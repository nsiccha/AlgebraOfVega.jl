module AlgebraOfVega

using AlgebraOfGraphics
import AlgebraOfGraphics: data, mapping, visual, dims,
    density, histogram, linear, smooth, expectation, frequency,
    Layer, Layers, ProcessedLayer, ProcessedLayers,
    renamer, sorter, nonnumeric, verbatim, presorted, direct,
    scale, scales, pregrouped
using Makie: Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, Hist, Density as MakieDensity, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar,
    Plot, plot
import Makie
using JSON, Tables
using HTMX
import HTMX: h

# Re-export AoG API
export data, mapping, visual, dims
export density, histogram, linear, smooth, expectation, frequency
export renamer, sorter, nonnumeric, verbatim, presorted, direct
export scale, scales, pregrouped
# Re-export Makie plot types users need
export Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, Hist, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar

# AlgebraOfVega exports
export config, draw, vlspec
export to_vegalite, to_json, to_html, to_node, vega_head
export vega_runtime, update_data, vega_cdn_urls
# Tidybayes-style analysis exports
export pointinterval, gradient_interval, lineribbon, ribbon, dotinterval
# Dataset exports
export sample_cars, sample_tips, sample_stocks, sample_temperatures,
    sample_population, melt_population, sample_monthly_sales, melt_sales,
    sample_posterior_draws, sample_regression_predictions,
    sample_grouped_regression_predictions,
    randn_bm, classify_columns, table_to_rows
# Explorer exports
export default_explorer_datasets, explorer_widget, write_explorer_assets,
    explorer_controls_html, explorer_js, explorer_data_init_js

include("datasets.jl")
include("explorer.jl")

# --- Vega-specific types ---

struct Config
    properties::Dict{Symbol, Any}
end

"""
    config(; kwargs...)

Create a `Config` with Vega-Lite properties. Common options:

- `width`, `height`, `title` — spec dimensions and title
- `encoding` — deep-merged with auto-generated encodings (add aggregate, scale, axis, etc.)
- `params`, `transform` — VL interactivity parameters and data transforms
- `select` — field(s) for client-side dropdown filtering (e.g. `select=:origin`)

Config is applied to a spec via `*`: `data(df) * mapping(:x, :y) * visual(Scatter) * config(width=500)`.
"""
config(; kwargs...) = Config(Dict{Symbol,Any}(pairs(kwargs)...))

struct VegaSpec
    drawable::Any  # AoG Layer, Layers, or AbstractAlgebraic
    config::Union{Config, Nothing}
end

"""
    vlspec(drawable; kwargs...)

Wrap an AoG drawable in a `VegaSpec` with optional config properties.
Equivalent to `drawable * config(; kwargs...)`.
"""
vlspec(drawable; kwargs...) = VegaSpec(drawable, isempty(kwargs) ? nothing : config(; kwargs...))

# Composition: AoG drawable * Config → VegaSpec
Base.:*(a::AlgebraOfGraphics.AbstractAlgebraic, c::Config) = VegaSpec(a, c)
Base.:*(c::Config, a::AlgebraOfGraphics.AbstractAlgebraic) = VegaSpec(a, c)
Base.:*(v::VegaSpec, c::Config) = VegaSpec(v.drawable, c)
Base.:*(c::Config, v::VegaSpec) = VegaSpec(v.drawable, c)

# --- Makie → Vega-Lite mark mapping ---

# Compare against the Plot{f} type aliases (e.g. Scatter = Plot{scatter})
function plottype_to_mark(T::Type)
    T <: Scatter && return "point"
    T <: Lines && return "line"
    T <: ScatterLines && return "line"
    T <: BarPlot && return "bar"
    T <: Heatmap && return "rect"
    T <: BoxPlot && return "boxplot"
    T <: Violin && return "area"
    T <: Band && return "area"
    T <: HLines && return "rule"
    T <: VLines && return "rule"
    T <: Hist && return "bar"
    T <: MakieDensity && return "area"
    T <: Errorbars && return "errorbar"
    T <: Stairs && return "line"
    T <: Contour && return "rect"
    T <: Rangebars && return "errorbar"
    T <: CrossBar && return "errorbar"
    T <: Makie.Text && return "text"
    error("Unsupported plot type for Vega-Lite: $T")
end

function plottype_to_mark_props(T::Type)
    props = Dict{String,Any}()
    if T <: ScatterLines
        props["point"] = true
    elseif T <: Stairs
        props["interpolate"] = "step-after"
    end
    props
end

# --- AoG aesthetic name → Vega-Lite channel ---

function aog_named_to_vl_channel(name::Symbol)
    name === :color && return "color"
    name === :strokecolor && return "stroke"
    name === :marker && return "shape"
    name === :markersize && return "size"
    name === :linewidth && return "strokeWidth"
    name === :linestyle && return "strokeDash"
    name === :dodge_x && return "xOffset"
    name === :dodge_y && return "yOffset"
    name === :col && return "column"
    name === :row && return "row"
    name === :layout && return "facet"
    name === :group && return "detail"
    name === :stack && return nothing  # handled via stack property
    return string(name)  # pass through unknown names
end

# --- Column selector → Vega-Lite field spec ---

function selector_to_field(sel)
    if sel isa Symbol
        return Dict{String,Any}("field" => string(sel))
    elseif sel isa Pair
        src, dst = sel
        if dst isa AbstractString
            # :col => "Label" — rename
            field = selector_to_field(src)
            field["title"] = dst
            return field
        elseif dst isa Pair
            # :col => func => "Label"
            field = selector_to_field(src)
            field["title"] = last(dst)
            return field
        elseif dst isa Function
            # :col => func — transform (best effort: just use the field)
            return selector_to_field(src)
        else
            return selector_to_field(src)
        end
    elseif sel isa Int
        # Column by index — can't resolve without data, use as-is
        return Dict{String,Any}("field" => "column_$sel")
    else
        # DirectData, Presorted, etc. — pass through as value
        return Dict{String,Any}("value" => sel)
    end
end

# --- Vega-Lite type inference ---

function vl_type(col)
    T = eltype(col)
    T = Base.nonmissingtype(T)
    if T <: Number
        "quantitative"
    elseif T <: AbstractString || T <: Symbol
        "nominal"
    else
        "nominal"
    end
end

function infer_types!(encoding::Dict, table)
    isnothing(table) && return encoding
    for (ch, enc) in encoding
        enc isa Dict || continue
        if haskey(enc, "field") && !haskey(enc, "type")
            field = Symbol(enc["field"])
            try
                col = Tables.getcolumn(table, field)
                enc["type"] = vl_type(col)
            catch
                # Field not found in data — leave untyped
            end
        end
    end
    encoding
end

# --- Extract components from AoG Layer ---

function extract_visual(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t === identity && return nothing
    if t isa AlgebraOfGraphics.Visual
        return t
    end
    # For composed transformations, try to find the Visual
    # AoG composes with ⨟ which creates ComposedFunction
    if t isa ComposedFunction
        # Walk the composition chain
        v = extract_visual_from_composed(t)
        !isnothing(v) && return v
    end
    nothing
end

function extract_visual_from_composed(f::ComposedFunction)
    for part in (f.outer, f.inner)
        if part isa AlgebraOfGraphics.Visual
            return part
        elseif part isa ComposedFunction
            v = extract_visual_from_composed(part)
            !isnothing(v) && return v
        end
    end
    nothing
end

function extract_data(layer::AlgebraOfGraphics.Layer)
    isnothing(layer.data) && return nothing
    cols = layer.data  # Columns{T} wrapper
    if cols isa AlgebraOfGraphics.Columns
        return cols.columns
    end
    cols
end

function is_pregrouped(layer::AlgebraOfGraphics.Layer)
    isnothing(layer.data) && return false
    d = layer.data
    inner = d isa AlgebraOfGraphics.Columns ? d.columns : d
    inner isa AlgebraOfGraphics.Pregrouped
end

"""
    pregrouped_to_vl(layer; is_sublayer=false)

Translate a pregrouped AoG layer to Vega-Lite. Flattens grouped vectors
into long-form inline data with "x" (nominal) and "y" (quantitative) columns.
Handles renamer labels on the x axis.
"""
function pregrouped_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    pos = layer.positional

    # Extract x and y grouped data from positional args
    x_arg = pos[1]
    y_arg = length(pos) >= 2 ? pos[2] : nothing

    # Unwrap x: may be Pair(data, renamer) or raw data
    x_data, x_rename = if x_arg isa Pair
        first(x_arg), last(x_arg)
    else
        x_arg, nothing
    end

    # Collect ordered labels from renamer for sort order
    x_sort = nothing
    if x_rename isa AlgebraOfGraphics.Renamer
        x_sort = [string(l) for l in x_rename.labels]
    end

    # Flatten grouped vectors into long-form rows
    rows = Dict{String,Any}[]
    n_groups = length(x_data)
    for i in 1:n_groups
        x_vals = x_data[i]
        for j in eachindex(x_vals)
            x_raw = x_vals[j]
            x_label = if x_rename isa AlgebraOfGraphics.Renamer
                string(x_rename(x_raw).value)
            elseif x_rename isa Function
                string(x_rename(x_raw))
            else
                string(x_raw)
            end
            row = Dict{String,Any}("x" => x_label)
            if !isnothing(y_arg)
                row["y"] = y_arg[i][j]
            end
            push!(rows, row)
        end
    end

    # Visual / mark
    vis = extract_visual(layer)
    mark_type = !isnothing(vis) ? plottype_to_mark(vis.plottype) : "boxplot"
    extra_props = !isnothing(vis) ? merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis)) : Dict{String,Any}()
    mark = if isempty(extra_props)
        mark_type
    else
        merge(Dict{String,Any}("type" => mark_type), extra_props)
    end

    # Encoding
    encoding = Dict{String,Any}()
    x_enc = Dict{String,Any}("field" => "x", "type" => "nominal")
    if !isnothing(x_sort)
        x_enc["sort"] = x_sort
    end
    encoding["x"] = x_enc
    if !isnothing(y_arg)
        encoding["y"] = Dict{String,Any}("field" => "y", "type" => "quantitative")
    end

    # Named mappings (color, etc.)
    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    # Auto tooltip
    tooltip_fields = Dict{String,Any}[]
    for (ch, enc) in encoding
        enc isa Dict || continue
        haskey(enc, "field") || continue
        entry = Dict{String,Any}("field" => enc["field"])
        haskey(enc, "type") && (entry["type"] = enc["type"])
        push!(tooltip_fields, entry)
    end
    if !isempty(tooltip_fields)
        encoding["tooltip"] = tooltip_fields
    end

    spec = Dict{String,Any}(
        "data" => Dict{String,Any}("values" => rows),
        "mark" => mark,
        "encoding" => encoding,
    )

    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

function data_to_vl(table)
    isnothing(table) && return nothing
    rows = Tables.rowtable(table)
    Dict{String,Any}("values" => [
        Dict{String,Any}(string(k) => v for (k, v) in pairs(nt))
        for nt in rows
    ])
end

function visual_attrs_to_mark_props(vis::AlgebraOfGraphics.Visual)
    props = Dict{String,Any}()
    for (k, v) in pairs(vis.attributes)
        sk = string(k)
        # Map Makie attribute names to Vega mark properties
        if k === :opacity || k === :fillOpacity
            props["opacity"] = v
        elseif k === :color
            props["color"] = v isa Symbol ? string(v) : string(v)
        elseif k === :strokeDash || k === :linestyle
            props["strokeDash"] = v
        elseif k === :markersize || k === :size
            props["size"] = v
        elseif k === :strokeWidth || k === :linewidth
            props["strokeWidth"] = v
        else
            props[sk] = v
        end
    end
    props
end

# --- Tidybayes-style analysis types ---

abstract type TidybayesAnalysis end

struct PointIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    point::Symbol
end

struct GradientIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    point::Symbol
end

struct LineRibbonAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    show_line::Bool
end

struct DotIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    n_dots::Int
    point::Symbol
end

"""
    pointinterval(; probs=[0.95, 0.8, 0.5], point=:median)

Nested credible intervals with varying stroke width + a point estimate.
Computes quantile summary in Julia, then generates layered rule + point marks.

    data(draws) * mapping(:value, y=:parameter) * pointinterval()
"""
pointinterval(; probs=[0.95, 0.8, 0.5], point=:median) =
    Layer(transformation=PointIntervalAnalysis(Float64.(probs), point))

"""
    gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median)

Nested credible intervals with uniform width and varying opacity + a point estimate.

    data(draws) * mapping(:value, y=:parameter) * gradient_interval()
"""
gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median) =
    Layer(transformation=GradientIntervalAnalysis(Float64.(probs), point))

"""
    lineribbon(; probs=[0.95, 0.8, 0.5])

Uncertainty ribbons (area marks) + median line, for draw-level predictions.
Groups by x, computes quantiles of y across draws. Supports `color=` for
multiple groups with separate ribbon bands per group.

    data(preds) * mapping(:x, :y, group=:draw) * lineribbon()
    data(preds) * mapping(:x, :y, group=:draw, color=:treatment) * lineribbon()
"""
lineribbon(; probs=[0.95, 0.8, 0.5]) =
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), true))

"""
    ribbon(; probs=[0.95, 0.8, 0.5])

Uncertainty ribbons (area marks) without a median line.
Same as `lineribbon` but omits the central line.

    data(preds) * mapping(:x, :y, group=:draw) * ribbon()
"""
ribbon(; probs=[0.95, 0.8, 0.5]) =
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), false))

"""
    dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median)

Quantile dotplot with nested interval overlay.

    data(draws) * mapping(:value, y=:parameter) * dotinterval()
"""
dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median) =
    Layer(transformation=DotIntervalAnalysis(Float64.(probs), n_dots, point))

# Extract analysis from transformation chain
function extract_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa TidybayesAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, TidybayesAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_density_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.DensityAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.DensityAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_linear_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.LinearAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.LinearAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_smooth_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.SmoothAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.SmoothAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_histogram_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.HistogramAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.HistogramAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_frequency_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.FrequencyAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.FrequencyAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function extract_expectation_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa AlgebraOfGraphics.ExpectationAnalysis && return t
    if t isa ComposedFunction
        a = _extract_from_composed(t, AlgebraOfGraphics.ExpectationAnalysis)
        !isnothing(a) && return a
    end
    nothing
end

function _extract_from_composed(f::ComposedFunction, T::Type)
    for part in (f.outer, f.inner)
        part isa T && return part
        if part isa ComposedFunction
            r = _extract_from_composed(part, T)
            !isnothing(r) && return r
        end
    end
    nothing
end

"""
    _vl_prob_field(prefix, prob) -> String

Generate a Vega-Lite safe field name for a probability level.
Dots in VL field names are interpreted as nested property access,
so `0.95` becomes `0_95`: e.g. `_vl_prob_field("lo", 0.95)` → `"lo_0_95_"`.
"""
_vl_prob_field(prefix, prob) = "$(prefix)_$(replace(string(prob), "." => "_"))_"

# --- Interval summary computation ---

function compute_interval_summary(table, x_field::String, group_field::Union{String,Nothing}, probs::Vector{Float64}, point::Symbol)
    vals = Tables.getcolumn(table, Symbol(x_field))
    groups = isnothing(group_field) ? nothing : Tables.getcolumn(table, Symbol(group_field))

    group_keys = isnothing(groups) ? [nothing] : unique(groups)
    rows = Dict{String,Any}[]
    for gk in group_keys
        mask = isnothing(groups) ? trues(length(vals)) : [g == gk for g in groups]
        v = sort(vals[mask])
        n = length(v)
        q(f) = v[clamp(round(Int, f * n), 1, n)]
        pt = point === :mean ? sum(v) / n : q(0.5)
        row = Dict{String,Any}("__point__" => pt)
        if !isnothing(gk)
            row[group_field] = gk
        end
        for prob in probs
            lo = (1 - prob) / 2
            hi = 1 - lo
            row[_vl_prob_field("lo", prob)] = q(lo)
            row[_vl_prob_field("hi", prob)] = q(hi)
        end
        push!(rows, row)
    end
    rows
end

function compute_ribbon_summary(table, x_field::String, y_field::String, group_field::String, probs::Vector{Float64}; color_field::Union{String,Nothing}=nothing)
    xs = Tables.getcolumn(table, Symbol(x_field))
    ys = Tables.getcolumn(table, Symbol(y_field))
    draws = Tables.getcolumn(table, Symbol(group_field))
    colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))

    unique_xs = sort(unique(xs))
    color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

    rows = Dict{String,Any}[]
    for ck in color_keys
        for x in unique_xs
            mask = if isnothing(colors)
                [xi == x for xi in xs]
            else
                [xi == x && ci == ck for (xi, ci) in zip(xs, colors)]
            end
            v = sort(ys[mask])
            n = length(v)
            n == 0 && continue
            q(f) = v[clamp(round(Int, f * n), 1, n)]
            row = Dict{String,Any}(x_field => x, "__median__" => q(0.5))
            !isnothing(ck) && (row[color_field] = ck)
            for prob in probs
                lo = (1 - prob) / 2
                hi = 1 - lo
                row[_vl_prob_field("lo", prob)] = q(lo)
                row[_vl_prob_field("hi", prob)] = q(hi)
            end
            push!(rows, row)
        end
    end
    rows
end

# --- Analysis → Vega-Lite spec ---

function analysis_to_vl(a::PointIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? string(layer.named[:y]) : nothing

    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point)
    summary_data = Dict{String,Any}("values" => summary)

    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = range(1.5, 8, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => x_field),
            "x2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        if !isnothing(y_field)
            enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "axis" => Dict{String,Any}("title" => nothing))
            enc["color"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "legend" => nothing)
        end
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    # Point layer
    pt_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "__point__", "type" => "quantitative"),
    )
    if !isnothing(y_field)
        pt_enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal")
    end
    push!(layers, Dict{String,Any}(
        "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 80, "color" => "white"),
        "encoding" => pt_enc,
    ))

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

function analysis_to_vl(a::GradientIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? string(layer.named[:y]) : nothing

    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point)
    summary_data = Dict{String,Any}("values" => summary)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.7, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => x_field),
            "x2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
            "opacity" => Dict{String,Any}("value" => opacities[i]),
        )
        if !isnothing(y_field)
            enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "axis" => Dict{String,Any}("title" => nothing))
            enc["color"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "legend" => nothing)
        end
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => 14),
            "encoding" => enc,
        ))
    end

    pt_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "__point__", "type" => "quantitative"),
    )
    if !isnothing(y_field)
        pt_enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal")
    end
    push!(layers, Dict{String,Any}(
        "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 50, "color" => "white"),
        "encoding" => pt_enc,
    ))

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

function analysis_to_vl(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? string(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? string(layer.named[:group]) : "draw"
    color_field = haskey(layer.named, :color) ? string(layer.named[:color]) : nothing

    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs; color_field)
    summary_data = Dict{String,Any}("values" => summary)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.6, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
            "y" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => y_field),
            "y2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        mark = Dict{String,Any}("type" => "area", "opacity" => opacities[i], "line" => false)
        if !isnothing(color_field)
            enc["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        else
            mark["fill"] = "#1f77b4"
        end
        push!(layers, Dict{String,Any}("mark" => mark, "encoding" => enc))
    end

    if a.show_line
        line_enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
            "y" => Dict{String,Any}("field" => "__median__", "type" => "quantitative"),
        )
        line_mark = Dict{String,Any}("type" => "line", "strokeWidth" => 2)
        if !isnothing(color_field)
            line_enc["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        else
            line_mark["color"] = "#1f77b4"
        end
        push!(layers, Dict{String,Any}("mark" => line_mark, "encoding" => line_enc))
    end

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

function analysis_to_vl(a::DotIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? string(layer.named[:y]) : nothing

    vals = Tables.getcolumn(table, Symbol(x_field))
    groups = isnothing(y_field) ? nothing : Tables.getcolumn(table, Symbol(y_field))
    group_keys = isnothing(groups) ? [nothing] : unique(groups)

    # Quantile dots
    dot_rows = Dict{String,Any}[]
    for gk in group_keys
        mask = isnothing(groups) ? trues(length(vals)) : [g == gk for g in groups]
        v = sort(vals[mask])
        n = length(v)
        for i in 1:a.n_dots
            q = v[clamp(round(Int, (i - 0.5) / a.n_dots * n), 1, n)]
            row = Dict{String,Any}("quantile" => q)
            !isnothing(gk) && (row[y_field] = gk)
            push!(dot_rows, row)
        end
    end

    # Interval summary
    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point)

    # Dot layer
    dot_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "quantile", "type" => "quantitative", "title" => x_field,
                                  "bin" => Dict{String,Any}("maxbins" => 40)),
        "size" => Dict{String,Any}("aggregate" => "count", "legend" => nothing),
    )
    if !isnothing(y_field)
        dot_enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "axis" => Dict{String,Any}("title" => nothing))
        dot_enc["color"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "legend" => nothing)
    end

    layers = Dict{String,Any}[
        Dict{String,Any}(
            "data" => Dict{String,Any}("values" => dot_rows),
            "mark" => Dict{String,Any}("type" => "circle", "opacity" => 0.6, "size" => 30),
            "encoding" => dot_enc,
        )
    ]

    # Interval sublayers
    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = range(1.5, 5, length=length(sorted_probs))
    interval_layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative"),
            "x2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        if !isnothing(y_field)
            enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal")
        end
        push!(interval_layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i], "color" => "#333"),
            "encoding" => enc,
        ))
    end

    # Point
    pt_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "__point__", "type" => "quantitative"),
    )
    if !isnothing(y_field)
        pt_enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal")
    end
    push!(interval_layers, Dict{String,Any}(
        "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 50, "color" => "white", "stroke" => "#333", "strokeWidth" => 1.5),
        "encoding" => pt_enc,
    ))

    push!(layers, Dict{String,Any}(
        "data" => Dict{String,Any}("values" => summary),
        "layer" => interval_layers,
    ))

    spec = Dict{String,Any}("layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

function density_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? string(layer.named[:y]) : nothing

    vis = extract_visual(layer)
    opacity = 0.4
    if !isnothing(vis)
        attrs = vis.attributes
        if haskey(attrs, :opacity)
            opacity = attrs[:opacity]
        end
    end

    if !isnothing(y_field)
        # Faceted density
        spec = Dict{String,Any}(
            "data" => data_to_vl(table),
            "facet" => Dict{String,Any}("field" => y_field, "type" => "nominal",
                                         "header" => Dict{String,Any}("title" => nothing, "labelFontSize" => 14)),
            "columns" => 1,
            "spec" => Dict{String,Any}(
                "width" => 500, "height" => 60,
                "layer" => [
                    Dict{String,Any}(
                        "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
                        "transform" => [Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])],
                        "encoding" => Dict{String,Any}(
                            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_field),
                            "y" => Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing),
                        ),
                    ),
                ],
            ),
        )
        if !is_sublayer
            spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
        end
        return spec
    else
        # Check for color grouping
        color_field = haskey(layer.named, :color) ? string(layer.named[:color]) : nothing
        density_transform = Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])
        if !isnothing(color_field)
            density_transform["groupby"] = [color_field]
        end

        encoding = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_field),
            "y" => Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing),
        )
        if !isnothing(color_field)
            encoding["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        end

        spec = Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
            "transform" => [density_transform],
            "encoding" => encoding,
        )
        if !isnothing(table)
            spec["data"] = data_to_vl(table)
        end
        if !is_sublayer
            spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
        end
        return spec
    end
end

"""
    compute_linear_ci(xs, ys, npoints=100, level=0.95)

Compute linear regression line + confidence interval band.
Returns a vector of Dicts with fields: x, y_hat, y_lo, y_hi.
Uses t-distribution approximation for CI of the mean response.
"""
function compute_linear_ci(xs::AbstractVector, ys::AbstractVector; npoints=100, level=0.95)
    n = length(xs)
    mx, my = sum(xs)/n, sum(ys)/n
    sxx = sum((xi - mx)^2 for xi in xs)
    sxy = sum((xi - mx)*(yi - my) for (xi,yi) in zip(xs, ys))
    b1 = sxy / sxx
    b0 = my - b1 * mx
    residuals = [yi - (b0 + b1*xi) for (xi,yi) in zip(xs, ys)]
    s2 = sum(r^2 for r in residuals) / (n - 2)
    s = sqrt(s2)
    # Approximate t critical value (for large n, close to z)
    alpha = 1 - level
    # Simple approximation: use 1.96 for 0.95, scale for other levels
    z = alpha < 0.01 ? 2.576 : alpha < 0.05 ? 1.96 : alpha < 0.10 ? 1.645 : 1.28
    xmin, xmax = minimum(xs), maximum(xs)
    xgrid = range(xmin, xmax, length=npoints)
    rows = Dict{String,Any}[]
    for xp in xgrid
        yhat = b0 + b1*xp
        se = s * sqrt(1/n + (xp - mx)^2 / sxx)
        push!(rows, Dict{String,Any}("x" => xp, "y_hat" => yhat, "y_lo" => yhat - z*se, "y_hi" => yhat + z*se))
    end
    rows
end

"""
    linear_to_vl(layer; is_sublayer=false)

Translate AoG's `linear()` to Vega-Lite's `regression` transform + line mark.
When `interval` is set, computes regression CI in Julia and renders as area+y2.
"""
function linear_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? string(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? string(layer.named[:color]) : nothing
    analysis = extract_linear_analysis(layer)
    has_band = !isnothing(analysis) && !isnothing(analysis.interval) && !(analysis.interval isa Makie.Automatic)

    reg_transform = Dict{String,Any}(
        "regression" => y_field,
        "on" => x_field,
        "method" => "linear",
    )
    if !isnothing(color_field)
        reg_transform["groupby"] = [color_field]
    end

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
        "y" => Dict{String,Any}("field" => y_field, "type" => "quantitative"),
    )
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        encoding["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    else
        line_mark["color"] = "firebrick"
    end

    line_layer = Dict{String,Any}(
        "mark" => line_mark,
        "transform" => [reg_transform],
        "encoding" => encoding,
    )

    if has_band && !isnothing(table)
        level = !isnothing(analysis) && hasproperty(analysis, :level) ? analysis.level : 0.95
        xs_all = Tables.getcolumn(table, Symbol(x_field))
        ys_all = Tables.getcolumn(table, Symbol(y_field))
        colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
        color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

        ci_rows = Dict{String,Any}[]
        for ck in color_keys
            mask = isnothing(colors) ? trues(length(xs_all)) : [c == ck for c in colors]
            ci = compute_linear_ci(xs_all[mask], ys_all[mask]; level)
            if !isnothing(ck)
                for row in ci
                    row[color_field] = ck
                end
            end
            append!(ci_rows, ci)
        end

        band_enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => "x", "type" => "quantitative"),
            "y" => Dict{String,Any}("field" => "y_lo", "type" => "quantitative"),
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            band_enc["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        end
        band_layer = Dict{String,Any}(
            "mark" => band_mark,
            "encoding" => band_enc,
            "data" => Dict{String,Any}("values" => ci_rows),
        )
        spec = Dict{String,Any}("layer" => [band_layer, line_layer])
    else
        spec = line_layer
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

"""
    compute_smooth_ci(xs, ys; bandwidth=0.75, npoints=100, level=0.95)

Compute a local smoothing confidence band using a moving-window approach.
At each grid point, uses a weighted local mean +/- t*SE within the bandwidth window.
"""
function compute_smooth_ci(xs::AbstractVector, ys::AbstractVector; bandwidth=0.75, npoints=100, level=0.95)
    n = length(xs)
    xmin, xmax = minimum(xs), maximum(xs)
    xrange = xmax - xmin
    half_w = bandwidth * xrange / 2
    xgrid = range(xmin, xmax, length=npoints)
    alpha = 1 - level
    z = alpha < 0.01 ? 2.576 : alpha < 0.05 ? 1.96 : alpha < 0.10 ? 1.645 : 1.28

    rows = Dict{String,Any}[]
    for xp in xgrid
        # Tricube weights
        weights = Float64[]
        vals = Float64[]
        for (xi, yi) in zip(xs, ys)
            u = abs(xi - xp) / half_w
            if u < 1
                w = (1 - u^3)^3
                push!(weights, w)
                push!(vals, yi)
            end
        end
        nw = length(vals)
        if nw < 3
            continue
        end
        tw = sum(weights)
        wmean = sum(w*v for (w,v) in zip(weights, vals)) / tw
        wvar = sum(w*(v - wmean)^2 for (w,v) in zip(weights, vals)) / tw
        se = sqrt(wvar / nw)
        push!(rows, Dict{String,Any}("x" => xp, "y_hat" => wmean, "y_lo" => wmean - z*se, "y_hi" => wmean + z*se))
    end
    rows
end

"""
    smooth_to_vl(layer; is_sublayer=false)

Translate AoG's `smooth()` to Vega-Lite's `loess` transform + line mark.
When `interval` is set, computes smooth CI in Julia and renders as area+y2.
"""
function smooth_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? string(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? string(layer.named[:color]) : nothing
    analysis = extract_smooth_analysis(layer)
    bandwidth = !isnothing(analysis) ? analysis.span : 0.75
    has_band = !isnothing(analysis) && !isnothing(analysis.interval) && !(analysis.interval isa Makie.Automatic)

    loess_transform = Dict{String,Any}(
        "loess" => y_field,
        "on" => x_field,
        "bandwidth" => bandwidth,
    )
    if !isnothing(color_field)
        loess_transform["groupby"] = [color_field]
    end

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
        "y" => Dict{String,Any}("field" => y_field, "type" => "quantitative"),
    )
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        encoding["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    else
        line_mark["color"] = "firebrick"
    end

    line_layer = Dict{String,Any}(
        "mark" => line_mark,
        "transform" => [loess_transform],
        "encoding" => encoding,
    )

    if has_band && !isnothing(table)
        level = !isnothing(analysis) && hasproperty(analysis, :level) ? analysis.level : 0.95
        xs_all = Tables.getcolumn(table, Symbol(x_field))
        ys_all = Tables.getcolumn(table, Symbol(y_field))
        colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
        color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

        ci_rows = Dict{String,Any}[]
        for ck in color_keys
            mask = isnothing(colors) ? trues(length(xs_all)) : [c == ck for c in colors]
            ci = compute_smooth_ci(xs_all[mask], ys_all[mask]; bandwidth, level)
            if !isnothing(ck)
                for row in ci
                    row[color_field] = ck
                end
            end
            append!(ci_rows, ci)
        end

        band_enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => "x", "type" => "quantitative"),
            "y" => Dict{String,Any}("field" => "y_lo", "type" => "quantitative"),
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            band_enc["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        end
        band_layer = Dict{String,Any}(
            "mark" => band_mark,
            "encoding" => band_enc,
            "data" => Dict{String,Any}("values" => ci_rows),
        )
        spec = Dict{String,Any}("layer" => [band_layer, line_layer])
    else
        spec = line_layer
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

"""
    histogram_to_vl(layer; is_sublayer=false)

Translate AoG's `histogram()` to Vega-Lite's bar mark with bin + count aggregation.
"""
function histogram_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative", "bin" => true),
        "y" => Dict{String,Any}("aggregate" => "count", "type" => "quantitative"),
    )

    # Handle color/stack from named mappings
    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    if !isnothing(table)
        infer_types!(encoding, table)
    end

    spec = Dict{String,Any}(
        "mark" => "bar",
        "encoding" => encoding,
    )
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

"""
    frequency_to_vl(layer; is_sublayer=false)

Translate AoG's `frequency()` to a Vega-Lite bar chart with `aggregate: "count"`.
"""
function frequency_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "nominal"),
        "y" => Dict{String,Any}("aggregate" => "count", "type" => "quantitative"),
    )

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    if !isnothing(table)
        infer_types!(encoding, table)
    end

    spec = Dict{String,Any}("mark" => "bar", "encoding" => encoding)
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

"""
    expectation_to_vl(layer; is_sublayer=false)

Translate AoG's `expectation()` to a Vega-Lite bar chart with `aggregate: "mean"`.
"""
function expectation_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? string(layer.positional[2]) : "y"

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "nominal"),
        "y" => Dict{String,Any}("field" => y_field, "aggregate" => "mean", "type" => "quantitative"),
    )

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    if !isnothing(table)
        infer_types!(encoding, table)
    end

    spec = Dict{String,Any}("mark" => "bar", "encoding" => encoding)
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    spec
end

# --- Core translation ---

function layer_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    # Check for pregrouped data first
    if is_pregrouped(layer)
        return pregrouped_to_vl(layer; is_sublayer)
    end

    # Check for tidybayes analysis types first
    analysis = extract_analysis(layer)
    if !isnothing(analysis)
        return analysis_to_vl(analysis, layer; is_sublayer)
    end

    # Check for density analysis
    dens = extract_density_analysis(layer)
    if !isnothing(dens)
        return density_to_vl(layer; is_sublayer)
    end

    # Check for frequency analysis
    if !isnothing(extract_frequency_analysis(layer))
        return frequency_to_vl(layer; is_sublayer)
    end

    # Check for expectation analysis
    if !isnothing(extract_expectation_analysis(layer))
        return expectation_to_vl(layer; is_sublayer)
    end

    # Check for linear regression
    if !isnothing(extract_linear_analysis(layer))
        return linear_to_vl(layer; is_sublayer)
    end

    # Check for smooth/loess
    if !isnothing(extract_smooth_analysis(layer))
        return smooth_to_vl(layer; is_sublayer)
    end

    # Check for histogram
    if !isnothing(extract_histogram_analysis(layer))
        return histogram_to_vl(layer; is_sublayer)
    end

    spec = Dict{String,Any}()

    # Data
    table = extract_data(layer)
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end

    # Visual / mark (default to Scatter like AoG)
    vis = extract_visual(layer)
    if !isnothing(vis)
        mark_type = plottype_to_mark(vis.plottype)
        extra_props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
        if isempty(extra_props)
            spec["mark"] = mark_type
        else
            spec["mark"] = merge(Dict{String,Any}("type" => mark_type), extra_props)
        end
    else
        spec["mark"] = "point"
    end

    # Encoding from positional + named
    encoding = Dict{String,Any}()

    # Choose positional channel mapping based on plot type
    plot_type = !isnothing(vis) ? vis.plottype : Nothing
    positional_channels = if !isnothing(vis) && plot_type <: HLines
        ["y"]  # HLines: pos[1] → y (horizontal rule)
    elseif !isnothing(vis) && plot_type <: VLines
        ["x"]  # VLines: pos[1] → x (vertical rule)
    elseif !isnothing(vis) && plot_type <: Union{Rangebars, Errorbars}
        ["x", "y", "y2"]  # Rangebars: pos[1] → x, pos[2] → y, pos[3] → y2
    else
        ["x", "y"]
    end
    for (i, sel) in enumerate(layer.positional)
        i <= length(positional_channels) || break
        encoding[positional_channels[i]] = selector_to_field(sel)
    end

    # Named: color=:origin → "color" channel
    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    # Infer types from data
    if !isnothing(table)
        infer_types!(encoding, table)
    end

    # Auto-generate tooltip from all field-based encodings
    if !isempty(encoding) && !haskey(encoding, "tooltip")
        tooltip_fields = Dict{String,Any}[]
        for (ch, enc) in encoding
            enc isa Dict || continue
            haskey(enc, "field") || continue
            entry = Dict{String,Any}("field" => enc["field"])
            haskey(enc, "type") && (entry["type"] = enc["type"])
            push!(tooltip_fields, entry)
        end
        if !isempty(tooltip_fields)
            encoding["tooltip"] = tooltip_fields
        end
    end

    if !isempty(encoding)
        spec["encoding"] = encoding
    end

    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end

    spec
end

function layers_to_vl(layers::AlgebraOfGraphics.Layers)
    # Check if any layer is faceted (density with y group) — needs special handling
    has_faceted = false
    facet_field = nothing
    shared_table = nothing
    shared_data = nothing

    for l in layers.layers
        if is_pregrouped(l)
            continue  # pregrouped layers carry their own inline data
        end
        table = extract_data(l)
        if !isnothing(table) && isnothing(shared_table)
            shared_data = data_to_vl(table)
            shared_table = table
        end
        dens = extract_density_analysis(l)
        if !isnothing(dens) && haskey(l.named, :y)
            has_faceted = true
            facet_field = string(l.named[:y])
        end
    end

    if has_faceted && !isnothing(facet_field)
        return _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    end

    spec = Dict{String,Any}()
    spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"

    if !isnothing(shared_data)
        spec["data"] = shared_data
    end

    layer_specs = Dict{String,Any}[]
    for layer in layers.layers
        ls = layer_to_vl(layer; is_sublayer=true)
        # A sublayer may itself contain "layer" (e.g. pointinterval) — flatten
        if haskey(ls, "layer") && !haskey(ls, "facet")
            sub_data = get(ls, "data", nothing)
            for sl in ls["layer"]
                if !isnothing(sub_data) && !haskey(sl, "data")
                    sl["data"] = sub_data
                end
                push!(layer_specs, sl)
            end
        else
            table = extract_data(layer)
            if !isnothing(table) && table === shared_table
                delete!(ls, "data")
            end
            push!(layer_specs, ls)
        end
    end

    spec["layer"] = layer_specs
    spec
end

function _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    # For density + pointinterval combos: facet by group field, inner spec has layers
    inner_layers = Dict{String,Any}[]

    # Check if we have visual layers alongside density (raincloud-style) — need range scaling
    has_visual_layers = any(l -> begin
        isnothing(extract_density_analysis(l)) && isnothing(extract_analysis(l)) && !isnothing(extract_visual(l))
    end, layers.layers)

    for layer in layers.layers
        dens = extract_density_analysis(layer)
        if !isnothing(dens)
            # Density sublayer (unfaceted version)
            x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
            vis = extract_visual(layer)
            opacity = 0.4
            if !isnothing(vis) && haskey(vis.attributes, :opacity)
                opacity = vis.attributes[:opacity]
            end
            y_enc = Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing)
            if has_visual_layers
                y_enc["scale"] = Dict{String,Any}("range" => [0, 40])
            end
            push!(inner_layers, Dict{String,Any}(
                "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
                "transform" => [Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])],
                "encoding" => Dict{String,Any}(
                    "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_field),
                    "y" => y_enc,
                ),
            ))
        else
            analysis = extract_analysis(layer)
            if !isnothing(analysis)
                # Compute interval summary per-group using VL transforms instead
                x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
                probs = analysis isa Union{PointIntervalAnalysis, GradientIntervalAnalysis} ? analysis.probs :
                         analysis isa DotIntervalAnalysis ? analysis.probs : [0.95, 0.5]
                point_sym = hasproperty(analysis, :point) ? analysis.point : :median

                # Use VL quantile transforms for intervals within facet
                sorted_probs = sort(probs, rev=true)
                is_gradient = analysis isa GradientIntervalAnalysis

                if is_gradient
                    opacities = collect(range(0.2, 0.7, length=length(sorted_probs)))
                else
                    stroke_widths = collect(range(1.5, 8, length=length(sorted_probs)))
                end

                for (i, prob) in enumerate(sorted_probs)
                    lo_p = (1 - prob) / 2
                    hi_p = 1 - lo_p
                    enc = Dict{String,Any}(
                        "x" => Dict{String,Any}("aggregate" => "min", "field" => "val", "type" => "quantitative"),
                        "x2" => Dict{String,Any}("aggregate" => "max", "field" => "val"),
                    )
                    if is_gradient
                        enc["opacity"] = Dict{String,Any}("value" => opacities[i])
                        mark = Dict{String,Any}("type" => "rule", "strokeWidth" => 14)
                    else
                        mark = Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i])
                    end
                    push!(inner_layers, Dict{String,Any}(
                        "mark" => mark,
                        "transform" => [
                            Dict{String,Any}("quantile" => x_field, "probs" => [lo_p, hi_p], "as" => ["prob", "val"]),
                            Dict{String,Any}("fold" => ["val"]),
                        ],
                        "encoding" => enc,
                    ))
                end

                # Median point
                push!(inner_layers, Dict{String,Any}(
                    "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 60, "color" => "white", "stroke" => "#333", "strokeWidth" => 1.5),
                    "transform" => [Dict{String,Any}("quantile" => x_field, "probs" => [0.5], "as" => ["prob", "val"])],
                    "encoding" => Dict{String,Any}(
                        "x" => Dict{String,Any}("field" => "val", "type" => "quantitative"),
                    ),
                ))
            else
                # Standard layer (e.g. visual(Scatter, BoxPlot)) inside facet
                # Strip the facet field from encoding — it's handled by facet, not y axis
                x_field = length(layer.positional) >= 1 ? string(layer.positional[1]) : "value"
                vis = extract_visual(layer)
                if !isnothing(vis)
                    mark_type = plottype_to_mark(vis.plottype)
                    mark_props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
                    mark = isempty(mark_props) ? mark_type : merge(Dict{String,Any}("type" => mark_type), mark_props)

                    enc = Dict{String,Any}(
                        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
                    )

                    if vis.plottype <: Scatter
                        # Add jitter for scatter inside facet (like original raincloud)
                        push!(inner_layers, Dict{String,Any}(
                            "mark" => mark,
                            "transform" => [Dict{String,Any}("calculate" => "-random() * 15 - 2", "as" => "jitter")],
                            "encoding" => merge(enc, Dict{String,Any}(
                                "y" => Dict{String,Any}("field" => "jitter", "type" => "quantitative",
                                                         "axis" => nothing, "scale" => Dict{String,Any}("range" => [0, 40])),
                            )),
                        ))
                    else
                        push!(inner_layers, Dict{String,Any}("mark" => mark, "encoding" => enc))
                    end
                end
            end
        end
    end

    spec = Dict{String,Any}(
        "\$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
        "data" => shared_data,
        "facet" => Dict{String,Any}("field" => facet_field, "type" => "nominal",
                                     "header" => Dict{String,Any}("title" => nothing, "labelFontSize" => 14)),
        "columns" => 1,
        "spec" => Dict{String,Any}(
            "width" => 500, "height" => (has_visual_layers ? 70 : 60),
            "layer" => inner_layers,
        ),
    )
    spec
end

# --- Public API: to_vegalite ---

"""
    to_vegalite(spec) -> Dict{String,Any}

Convert an AoG `Layer`, `Layers`, or `VegaSpec` to a Vega-Lite JSON dictionary.
Handles all translation: mark types, encodings, statistical transforms, config merging,
and auto-interactivity.
"""
function to_vegalite(layer::AlgebraOfGraphics.Layer)
    layer_to_vl(layer)
end

function to_vegalite(layers::AlgebraOfGraphics.Layers)
    layers_to_vl(layers)
end

function to_vegalite(v::VegaSpec)
    spec = to_vegalite(v.drawable)
    select_fields = nothing
    if !isnothing(v.config)
        for (k, val) in v.config.properties
            sk = string(k)
            # Deep-merge encoding so config adds to (not overwrites) auto-generated channels
            if sk == "encoding" && val isa Dict && haskey(spec, "encoding")
                for (ek, ev) in val
                    sek = string(ek)
                    if ev isa Dict && haskey(spec["encoding"], sek) && spec["encoding"][sek] isa Dict
                        # Deep-merge channel: keep auto-generated field/type, add config properties
                        merge!(spec["encoding"][sek], Dict{String,Any}(string(k2) => v2 for (k2, v2) in ev))
                    else
                        spec["encoding"][sek] = ev
                    end
                end
            elseif sk in ("width", "height") && haskey(spec, "spec")
                # For faceted specs, width/height go into the inner spec
                spec["spec"][sk] = val
            elseif sk == "select"
                # Collect select fields — processed after spec is built
                select_fields = val isa Symbol ? [val] : val
            else
                spec[sk] = val
            end
        end
    end
    if !isnothing(select_fields)
        add_select_filters!(spec, v.drawable, select_fields)
    end
    add_auto_interactivity!(spec)
    spec
end

"""
    add_select_filters!(spec, drawable, fields)

Add dropdown filter widgets for the given fields. Extracts unique values from
the data and injects VL `params` with `bind: {input: "select"}` + expression filters.

Usage via config: `config(select=:origin)` or `config(select=[:origin, :cylinders])`.
Each field gets a dropdown with "All" + sorted unique values.
"""
function add_select_filters!(spec::Dict{String,Any}, drawable, fields)
    # Extract data table from the drawable
    table = nothing
    if drawable isa AlgebraOfGraphics.Layer
        table = extract_data(drawable)
    elseif drawable isa AlgebraOfGraphics.Layers
        for l in drawable.layers
            t = extract_data(l)
            if !isnothing(t)
                table = t
                break
            end
        end
    end
    isnothing(table) && return spec

    params = get!(spec, "params", Dict{String,Any}[])
    transforms = get!(spec, "transform", Dict{String,Any}[])

    # For layered specs, transforms go at the top level (shared data)
    # For single-view specs, they also go at the top level
    for field in fields
        field_str = string(field)
        param_name = "select_$(field_str)"

        # Get unique values
        vals = try
            col = Tables.getcolumn(table, field)
            sort(unique(col))
        catch
            continue
        end

        # Add param with dropdown binding
        push!(params, Dict{String,Any}(
            "name" => param_name,
            "value" => nothing,  # null = show all
            "bind" => Dict{String,Any}(
                "input" => "select",
                "options" => [nothing; vals],
                "labels" => ["All"; [string(v) for v in vals]],
                "name" => "$(field_str): ",
            ),
        ))

        # Add filter transform
        push!(transforms, Dict{String,Any}(
            "filter" => "$(param_name) === null || datum.$(field_str) === $(param_name)",
        ))
    end

    spec
end

"""
    add_auto_interactivity!(spec)

Add automatic client-side interactivity to a Vega-Lite spec:
- **Legend click filtering**: For single-view specs with top-level `color` encoding,
  adds `bind: "legend"` selection so clicking legend items toggles group visibility.
  Uses `empty: true` so all data is visible by default.
- **Nearest-point tooltip**: For `line`/`area` marks with tooltip, adds `nearest: true`
  so the tooltip snaps to the closest data point.

Skipped when:
- User already defined `params` via `config()` (don't override explicit interactivity)
- Spec is faceted (`haskey(spec, "facet")`)
- Color encoding is only in sublayers, not top-level (VL `bind: "legend"` silently
  breaks layered specs where color is per-sublayer — renders empty)

Also skips adding opacity conditions to sublayers whose mark already has an intentional
`opacity` property (e.g. CI band areas with `mark.opacity: 0.2`).
"""
function add_auto_interactivity!(spec::Dict{String,Any})
    # Don't add interactivity if user already defined params (via config)
    haskey(spec, "params") && return spec
    # Don't add to faceted specs (params go in inner spec which is auto-generated)
    haskey(spec, "facet") && return spec

    # Find the encoding — may be top-level or in sublayers
    enc = get(spec, "encoding", nothing)
    sublayers = get(spec, "layer", nothing)
    mark = get(spec, "mark", nothing)
    mark_type = mark isa Dict ? get(mark, "type", "") : (mark isa String ? mark : "")

    # Find color field from top-level encoding only.
    # Legend binding doesn't work reliably for layered specs where color is only in sublayers.
    color_field = nothing
    if !isnothing(enc) && haskey(enc, "color") && enc["color"] isa Dict
        color_field = get(enc["color"], "field", nothing)
    end

    params = Dict{String,Any}[]

    if !isnothing(color_field)
        # Legend click selection: toggle group visibility + hover highlight
        push!(params, Dict{String,Any}(
            "name" => "legend_selection",
            "select" => Dict{String,Any}("type" => "point", "fields" => [color_field]),
            "bind" => "legend",
        ))

        opacity_condition = Dict{String,Any}(
            "condition" => Dict{String,Any}("param" => "legend_selection", "empty" => true, "value" => 1),
            "value" => 0.15,
        )

        if !isnothing(sublayers)
            for sl in sublayers
                sl_enc = get(sl, "encoding", nothing)
                # Skip layers that already have opacity in encoding or mark
                sl_mark = get(sl, "mark", nothing)
                mark_has_opacity = sl_mark isa Dict && haskey(sl_mark, "opacity")
                if !isnothing(sl_enc) && !haskey(sl_enc, "opacity") && !mark_has_opacity
                    sl_enc["opacity"] = opacity_condition
                end
            end
        elseif !isnothing(enc) && !haskey(enc, "opacity")
            enc["opacity"] = opacity_condition
        end
    end

    # Nearest-point tooltip for line/area marks (makes tooltip snap to data)
    if mark_type in ("line", "area") && !isnothing(enc) && haskey(enc, "tooltip")
        push!(params, Dict{String,Any}(
            "name" => "hover_nearest",
            "select" => Dict{String,Any}("type" => "point", "on" => "pointerover", "nearest" => true),
        ))
    end

    if !isempty(params)
        spec["params"] = params
    end

    spec
end

# Also accept raw Dicts (passthrough)
to_vegalite(d::Dict) = d

# --- Output ---

"""
    to_json(spec; kwargs...) -> String

Convert a spec to a Vega-Lite JSON string. Passes `kwargs` to `JSON.json`.
"""
to_json(x; kwargs...) = JSON.json(to_vegalite(x); kwargs...)

VEGA_VERSION = "5"
VEGALITE_VERSION = "5"
VEGA_EMBED_VERSION = "6"

"""
    vega_head(; vega_version, vegalite_version, vega_embed_version)

Return a vector of `h.script` nodes to include in `htmx(; extra_head=vega_head())`.
"""
function vega_head(;
    vega_version=VEGA_VERSION,
    vegalite_version=VEGALITE_VERSION,
    vega_embed_version=VEGA_EMBED_VERSION,
)
    [
        h.script(src="https://cdn.jsdelivr.net/npm/vega@$vega_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-embed@$vega_embed_version"),
        vega_runtime(),
    ]
end

"""
    vega_runtime()

Return a `h.script` node with the AlgebraOfVega JS runtime.
Manages Vega views by ID and provides helpers for HTMX integration.

Client-side API:
- `AoV.views[id]` — access Vega views by element ID
- `AoV.embed(id, spec, opts)` — embed and register a view
- `AoV.updateData(id, data)` — swap a view's data without re-creating it
- `AoV.onSignal(id, signal, callback)` — listen to a Vega signal
- Signal→HTMX wiring is set up automatically by `to_node(; signals=...)`
"""
function vega_runtime()
    h.script(raw"""
    window.AoV = window.AoV || {
        views: {},
        _pending: {},

        embed: function(id, spec, opts) {
            opts = opts || {};
            var self = this;
            return vegaEmbed('#' + id, spec, opts).then(function(result) {
                self.views[id] = result.view;
                // Wire up any pending signal listeners
                if (self._pending[id]) {
                    self._pending[id].forEach(function(p) {
                        self.onSignal(id, p.signal, p.callback);
                    });
                    delete self._pending[id];
                }
                return result;
            }).catch(console.error);
        },

        updateData: function(id, data, name) {
            var view = this.views[id];
            if (!view) { console.warn('AoV: no view for', id); return; }
            name = name || 'source_0';
            var changeset = vega.changeset().remove(function() { return true; }).insert(data);
            view.change(name, changeset).run();
        },

        onSignal: function(id, signal, callback) {
            var view = this.views[id];
            if (!view) {
                // View not ready yet — queue it
                this._pending[id] = this._pending[id] || [];
                this._pending[id].push({signal: signal, callback: callback});
                return;
            }
            view.addSignalListener(signal, function(name, value) {
                callback(name, value, view);
            });
        },

        // Wire a signal to an HTMX GET request
        signalToHtmx: function(id, signal, url, target, swap, debounceMs) {
            debounceMs = debounceMs || 300;
            var timer = null;
            this.onSignal(id, signal, function(name, value) {
                clearTimeout(timer);
                timer = setTimeout(function() {
                    var params = typeof value === 'object' ? value : {};
                    var qs = Object.keys(params).map(function(k) {
                        return encodeURIComponent(k) + '=' + encodeURIComponent(JSON.stringify(params[k]));
                    }).join('&');
                    var fullUrl = qs ? url + '?' + qs : url;
                    htmx.ajax('GET', fullUrl, {target: target, swap: swap || 'innerHTML'});
                }, debounceMs);
            });
        }
    };
    """)
end

"""
    to_node(spec; id, width, height, actions, signals)

Convert a spec to an HTMX `Node` containing a div + script that calls `vegaEmbed`.
Requires vega/vega-lite/vega-embed scripts to be loaded (use `vega_head()` in page head).

## Keyword arguments
- `id`: element ID (auto-generated if not provided)
- `width`, `height`: override spec dimensions
- `actions`: show Vega action links (default false)
- `signals`: vector of signal→HTMX wirings. Each entry is a NamedTuple or Dict:
  `(signal="brush", url="/on_brush", target="#detail")` or with optional `swap`, `debounce`.
"""
function to_node(spec; id=nothing, width=nothing, height=nothing, actions=false, signals=nothing, fit_width=true)
    vl = spec isa Dict ? copy(spec) : to_vegalite(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    if fit_width && !haskey(vl, "hconcat") && !haskey(vl, "vconcat")
        is_faceted = haskey(vl, "facet") || haskey(vl, "spec")
        is_layered = haskey(vl, "layer") || is_faceted || haskey(vl, "concat")
        if !is_layered
            # "width": "container" only works for single-view specs
            vl["width"] = "container"
        elseif is_faceted && haskey(vl, "spec")
            # For faceted specs, set per-cell width in the inner spec
            inner = vl["spec"]
            if !haskey(inner, "width")
                inner["width"] = 400
            end
        elseif !haskey(vl, "width")
            # For layered specs without explicit width, use a sensible default
            vl["width"] = 400
        end
        if !is_faceted
            vl["autosize"] = Dict("type" => "fit", "contains" => "padding")
        end
    end
    id = something(id, "vega-" * string(abs(hash(JSON.json(vl))), base=16))
    json = JSON.json(vl)

    # Queue embed for deferred execution (after layout is computed)
    embed_opts = "{actions: $actions}"
    signal_js = ""
    if !isnothing(signals)
        for sig in signals
            sname = sig isa NamedTuple ? sig.signal : sig["signal"]
            surl = sig isa NamedTuple ? sig.url : sig["url"]
            starget = sig isa NamedTuple ? get(sig, :target, "body") : get(sig, "target", "body")
            sswap = sig isa NamedTuple ? get(sig, :swap, "innerHTML") : get(sig, "swap", "innerHTML")
            sdebounce = sig isa NamedTuple ? get(sig, :debounce, 300) : get(sig, "debounce", 300)
            signal_js *= "AoV.signalToHtmx('$id', '$sname', '$surl', '$starget', '$sswap', $sdebounce);\n"
        end
    end

    h.div(; style="width:100%; min-width:0;")(
        h.div(; id=id, style="width:100%;"),
        h.script("AoV.embed('$id', $json, $embed_opts).then(function(){$signal_js});"),
    )
end

"""
    update_data(id, table; name="source_0")

Return an `h.script` node that updates an existing Vega view's dataset.
Useful for HTMX responses that should update a plot without re-rendering.
"""
function update_data(id, table; name="source_0")
    rows = Tables.rowtable(table)
    data = [Dict{String,Any}(string(k) => v for (k, v) in pairs(nt)) for nt in rows]
    json = JSON.json(data)
    h.script("AoV.updateData('$id', $json, '$name');")
end

"""
    to_html(spec; id, width, height)

Return a standalone HTML string with embedded vega-embed that self-loads scripts from CDN.
"""
function to_html(spec; id=nothing, width=nothing, height=nothing)
    vl = spec isa Dict ? copy(spec) : to_vegalite(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    id = something(id, "vega-" * string(abs(hash(JSON.json(vl))), base=16))
    json = JSON.json(vl)
    """
    <div id="$id"></div>
    <script src="https://cdn.jsdelivr.net/npm/vega@$VEGA_VERSION"></script>
    <script src="https://cdn.jsdelivr.net/npm/vega-lite@$VEGALITE_VERSION"></script>
    <script src="https://cdn.jsdelivr.net/npm/vega-embed@$VEGA_EMBED_VERSION"></script>
    <script>vegaEmbed('#$id', $json, {actions: false}).catch(console.error);</script>
    """
end

"""
    draw(spec; kwargs...)

Convenience alias for `to_node(spec; kwargs...)`.
"""
draw(spec; kwargs...) = to_node(spec; kwargs...)

# --- Renderer-agnostic dependency declaration ---

"""
    vega_cdn_urls(; vega=VEGA_VERSION, vegalite=VEGALITE_VERSION, embed=VEGA_EMBED_VERSION)

Return a vector of CDN URLs for the Vega libraries. Useful for VitePress config,
Quarto YAML, or any system that needs to declare script dependencies.
"""
vega_cdn_urls(; vega=VEGA_VERSION, vegalite=VEGALITE_VERSION, embed=VEGA_EMBED_VERSION) = [
    "https://cdn.jsdelivr.net/npm/vega@$vega",
    "https://cdn.jsdelivr.net/npm/vega-lite@$vegalite",
    "https://cdn.jsdelivr.net/npm/vega-embed@$embed",
]

# --- MIME show methods for notebook/Quarto support ---

Base.show(io::IO, ::MIME"text/html", spec::VegaSpec) = print(io, to_html(spec))
Base.show(io::IO, ::MIME"application/vnd.vegalite.v5+json", spec::VegaSpec) = print(io, to_json(spec))

# Also support raw Layer/Layers types
Base.show(io::IO, m::MIME"text/html", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"text/html", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))

end # module AlgebraOfVega
