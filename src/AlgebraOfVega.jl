module AlgebraOfVega

using AlgebraOfGraphics
import AlgebraOfGraphics: data, mapping, visual, dims,
    density, histogram, linear, smooth, expectation, frequency,
    Layer, Layers, ProcessedLayer, ProcessedLayers,
    renamer, sorter, nonnumeric, verbatim, presorted, direct,
    scale, scales, pregrouped
using Makie: Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, Hist, Density as MakieDensity, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot,
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
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot

# AlgebraOfVega exports
export config, vdraw, sdraw, sdraw_file, vlspec, vdata
export to_vegalite, to_json, to_html, to_node, vega_head
export vega_runtime, update_data, vega_cdn_urls
# Tidybayes-style analysis exports
export pointinterval, gradient_interval, lineribbon, ribbon, dotinterval
# High-level widget/recipe exports
export ecdf_grid, ppc_overlay
# Dataset exports
export sample_cars, sample_tips, sample_stocks, sample_temperatures,
    sample_population, melt_population, sample_monthly_sales, melt_sales,
    sample_posterior_draws, sample_regression_predictions,
    sample_grouped_regression_predictions, sample_faceted_regression_predictions,
    sample_faceted_observations,
    classify_columns, table_to_rows
# Explorer exports
export default_explorer_datasets, explorer_widget, write_explorer_assets,
    explorer_controls_html, explorer_js, explorer_data_init_js

"""
    vdata(args...; kwargs...)

Alias for `AlgebraOfGraphics.data`. Use when `data` clashes with a local variable
(e.g. an HTMXObjects struct field named `data`).
"""
vdata(args...; kwargs...) = data(args...; kwargs...)

include("datasets.jl")
include("explorer.jl")

# --- Vega-Lite constants and helpers ---

"""Vega-Lite v5 JSON schema URL, injected at top level of every spec."""
VL_SCHEMA = "https://vega.github.io/schema/vega-lite/v5.json"

"""Build a VL encoding channel dict. Filters out `nothing` values."""
function vl_enc(field; type=nothing, title=nothing, kwargs...)
    d = Dict{String,Any}("field" => string(field))
    !isnothing(type) && (d["type"] = type)
    !isnothing(title) && (d["title"] = title)
    for (k, v) in pairs(kwargs)
        !isnothing(v) && (d[string(k)] = v)
    end
    d
end

"""Build a VL mark dict. If no extra props, returns just the type string."""
function vl_mark(type; kwargs...)
    isempty(kwargs) && return type
    d = Dict{String,Any}("type" => type)
    for (k, v) in pairs(kwargs)
        d[string(k)] = v
    end
    d
end

"""Collect tooltip fields from an encoding dict (all channels that have a "field" key)."""
function vl_tooltips(encoding)
    tt = Dict{String,Any}[]
    for (ch, enc) in encoding
        enc isa Dict || continue
        haskey(enc, "field") || continue
        entry = Dict{String,Any}("field" => enc["field"])
        haskey(enc, "type") && (entry["type"] = enc["type"])
        push!(tt, entry)
    end
    tt
end

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
- `independent_scales` — sugar for VL `resolve`. `true` = both axes, `:x`/`:y` = one axis,
  `(:x, :y)` = explicit. Replaces `resolve=Dict("scale" => Dict("x" => "independent", ...))`.

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

# Combine VegaSpecs: unwrap drawables, merge configs
function _merge_configs(a::Union{Config,Nothing}, b::Union{Config,Nothing})
    isnothing(a) && return b
    isnothing(b) && return a
    Config(merge(a.properties, b.properties))
end
Base.:+(a::VegaSpec, b::VegaSpec) = VegaSpec(a.drawable + b.drawable, _merge_configs(a.config, b.config))
Base.:+(a::VegaSpec, b::AlgebraOfGraphics.AbstractAlgebraic) = VegaSpec(a.drawable + b, a.config)
Base.:+(a::AlgebraOfGraphics.AbstractAlgebraic, b::VegaSpec) = VegaSpec(a + b.drawable, b.config)

# --- Makie → Vega-Lite mark mapping ---

"""Makie plot type → VL mark string. Checked via `<:`, order matters for subtypes."""
_MARK_MAP = [
    Scatter => "point", Lines => "line", ScatterLines => "line",
    BarPlot => "bar", Heatmap => "rect", BoxPlot => "boxplot",
    Violin => "area", Band => "area", HLines => "rule", VLines => "rule",
    Hist => "bar", MakieDensity => "area", Errorbars => "errorbar",
    Stairs => "line", ECDFPlot => "line", Contour => "rect",
    Rangebars => "errorbar", CrossBar => "errorbar", Makie.Text => "text",
]

function plottype_to_mark(T::Type)
    for (PT, mark) in _MARK_MAP
        T <: PT && return mark
    end
    error("Unsupported plot type for Vega-Lite: $T")
end

"""Extra VL mark properties that depend on Makie plot type (e.g. ScatterLines → point=true)."""
_MARK_PROPS = [
    ScatterLines => Dict{String,Any}("point" => true),
    Stairs => Dict{String,Any}("interpolate" => "step-after"),
]

function plottype_to_mark_props(T::Type)
    for (PT, props) in _MARK_PROPS
        T <: PT && return props
    end
    Dict{String,Any}()
end

_COMPOSITE_MARKS = Set(["boxplot", "errorbar", "errorband"])

function _is_composite_mark(vl::Dict)
    m = get(vl, "mark", nothing)
    mark_type = m isa String ? m : m isa Dict ? get(m, "type", "") : ""
    mark_type in _COMPOSITE_MARKS
end

# --- AoG aesthetic name → Vega-Lite channel ---

"""AoG aesthetic name → VL encoding channel. Returns `nothing` for `:stack` (handled separately)."""
_CHANNEL_MAP = Dict{Symbol,Union{String,Nothing}}(
    :color => "color", :strokecolor => "stroke", :marker => "shape",
    :markersize => "size", :linewidth => "strokeWidth", :linestyle => "strokeDash",
    :dodge_x => "xOffset", :dodge_y => "yOffset",
    :col => "column", :row => "row", :layout => "facet",
    :group => "detail", :stack => nothing,
)

aog_named_to_vl_channel(name::Symbol) = get(_CHANNEL_MAP, name, string(name))

# --- Column selector → Vega-Lite field spec ---

selector_to_field(sel::Symbol) = Dict{String,Any}("field" => string(sel))
selector_to_field(sel::Int) = Dict{String,Any}("field" => "column_$sel")
function selector_to_field(sel::Pair)
    src, dst = sel
    field = selector_to_field(src)
    if dst isa AbstractString
        field["title"] = dst
    elseif dst isa Pair
        field["title"] = last(dst)
    end
    # dst isa Function → transform (best effort: just use the field)
    field
end
selector_to_field(sel) = Dict{String,Any}("value" => sel)  # DirectData, Presorted, etc.

_field_name(sel) = string(sel isa Pair ? first(sel) : sel)
_field_label(sel) = sel isa Pair && last(sel) isa AbstractString ? last(sel) : _field_name(sel)

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
    t isa AlgebraOfGraphics.Visual && return t
    t isa ComposedFunction && return _extract_from_composed(t, AlgebraOfGraphics.Visual)
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
                yval = y_arg[i][j]
                # Skip NaN/Inf values — they produce "infinite extent" VL warnings
                (yval isa Number && !isfinite(yval)) && continue
                row["y"] = yval
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
    tt = vl_tooltips(encoding)
    !isempty(tt) && (encoding["tooltip"] = tt)

    spec = Dict{String,Any}(
        "data" => Dict{String,Any}("values" => rows),
        "mark" => mark,
        "encoding" => encoding,
    )

    spec
end

_vl_safe(v) = v isa Number && !isfinite(v) ? nothing : v

function data_to_vl(table)
    isnothing(table) && return nothing
    rows = Tables.rowtable(table)
    Dict{String,Any}("values" => [
        Dict{String,Any}(string(k) => _vl_safe(v) for (k, v) in pairs(nt))
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
            props["color"] = string(v)
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

"""Extract a transformation of type `T` from a layer's transformation chain."""
function extract_transformation(layer::AlgebraOfGraphics.Layer, T::Type)
    t = layer.transformation
    t isa T && return t
    t isa ComposedFunction && return _extract_from_composed(t, T)
    nothing
end

"""
    _vl_prob_field(prefix, prob) -> String

Generate a Vega-Lite safe field name for a probability level.
Dots in VL field names are interpreted as nested property access,
so `0.95` becomes `0_95`: e.g. `_vl_prob_field("lo", 0.95)` → `"lo_0_95_"`.
"""
_vl_prob_field(prefix, prob) = "$(prefix)_$(replace(string(prob), "." => "_"))_"

# --- Facet helpers for TidybayesAnalysis ---

"""Extract `:col`/`:row` from a layer's named mappings, returning a VL facet dict and field name list."""
function _extract_facet_info(layer)
    col_field = haskey(layer.named, :col) ? _field_name(layer.named[:col]) : nothing
    col_label = haskey(layer.named, :col) ? _field_label(layer.named[:col]) : nothing
    row_field = haskey(layer.named, :row) ? _field_name(layer.named[:row]) : nothing
    row_label = haskey(layer.named, :row) ? _field_label(layer.named[:row]) : nothing
    facet = Dict{String,Any}()
    if !isnothing(col_field)
        col_enc = Dict{String,Any}("field" => col_field, "type" => "nominal")
        !isnothing(col_label) && col_label != col_field && (col_enc["title"] = col_label)
        facet["column"] = col_enc
    end
    if !isnothing(row_field)
        row_enc = Dict{String,Any}("field" => row_field, "type" => "nominal")
        !isnothing(row_label) && row_label != row_field && (row_enc["title"] = row_label)
        facet["row"] = row_enc
    end
    facet_fields = String[]
    !isnothing(col_field) && push!(facet_fields, col_field)
    !isnothing(row_field) && push!(facet_fields, row_field)
    facet, facet_fields
end

"""Wrap a VL spec with a `facet` operator, moving layer/mark/encoding into inner `spec`. Data stays at outer level."""
function _wrap_with_facet!(spec, facet)
    isempty(facet) && return spec
    inner = Dict{String,Any}()
    for k in keys(spec)
        k == "\$schema" && continue
        k == "data" && continue  # data stays at outer level for VL facet
        inner[k] = spec[k]
    end
    for k in keys(inner)
        delete!(spec, k)
    end
    spec["facet"] = facet
    spec["spec"] = inner
    spec
end

"""Add tooltip encoding to each sublayer in `layers`, built from the given fields."""
function _add_analysis_tooltips!(layers::Vector{Dict{String,Any}}, tooltip_fields::Vector{Dict{String,Any}})
    isempty(tooltip_fields) && return
    for sl in layers
        enc = get(sl, "encoding", nothing)
        isnothing(enc) && continue
        haskey(enc, "tooltip") && continue
        enc["tooltip"] = copy(tooltip_fields)
    end
end

# --- Interval summary computation ---

function compute_interval_summary(table, x_field::String, group_field::Union{String,Nothing}, probs::Vector{Float64}, point::Symbol; color_field::Union{String,Nothing}=nothing, facet_fields::Vector{String}=String[])
    vals = Tables.getcolumn(table, Symbol(x_field))
    groups = isnothing(group_field) ? nothing : Tables.getcolumn(table, Symbol(group_field))
    colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
    facet_data = [Tables.getcolumn(table, Symbol(f)) for f in facet_fields]
    facet_combos = isempty(facet_data) ? [()] : sort(unique(collect(zip(facet_data...))))

    group_keys = isnothing(groups) ? [nothing] : unique(groups)
    color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))
    rows = Dict{String,Any}[]
    for fk in facet_combos
        for gk in group_keys
            for ck in color_keys
                mask = trues(length(vals))
                if !isnothing(groups)
                    mask .&= [g == gk for g in groups]
                end
                if !isnothing(colors)
                    mask .&= [c == ck for c in colors]
                end
                for (j, fc) in enumerate(facet_data)
                    mask .&= [fci == fk[j] for fci in fc]
                end
                v = sort(vals[mask])
                n = length(v)
                n == 0 && continue
                q(f) = v[clamp(round(Int, f * n), 1, n)]
                pt = point === :mean ? sum(v) / n : q(0.5)
                row = Dict{String,Any}("__point__" => pt)
                if !isnothing(gk)
                    row[group_field] = gk
                end
                if !isnothing(ck)
                    row[color_field] = ck
                end
                for (j, ff) in enumerate(facet_fields)
                    row[ff] = fk[j]
                end
                for prob in probs
                    lo = (1 - prob) / 2
                    hi = 1 - lo
                    row[_vl_prob_field("lo", prob)] = q(lo)
                    row[_vl_prob_field("hi", prob)] = q(hi)
                end
                push!(rows, row)
            end
        end
    end
    rows
end

function compute_ribbon_summary(table, x_field::String, y_field::String, group_field::String, probs::Vector{Float64}; color_field::Union{String,Nothing}=nothing, facet_fields::Vector{String}=String[])
    xs = Tables.getcolumn(table, Symbol(x_field))
    ys = Tables.getcolumn(table, Symbol(y_field))
    draws = Tables.getcolumn(table, Symbol(group_field))
    colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
    facet_data = [Tables.getcolumn(table, Symbol(f)) for f in facet_fields]
    facet_combos = isempty(facet_data) ? [()] : sort(unique(collect(zip(facet_data...))))

    unique_xs = sort(unique(xs))
    color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

    rows = Dict{String,Any}[]
    for fk in facet_combos
        for ck in color_keys
            for x in unique_xs
                mask = if isnothing(colors)
                    [xi == x for xi in xs]
                else
                    [xi == x && ci == ck for (xi, ci) in zip(xs, colors)]
                end
                for (j, fc) in enumerate(facet_data)
                    mask .&= [fci == fk[j] for fci in fc]
                end
                v = sort(ys[mask])
                n = length(v)
                n == 0 && continue
                q(f) = v[clamp(round(Int, f * n), 1, n)]
                row = Dict{String,Any}(x_field => x, "__median__" => q(0.5))
                !isnothing(ck) && (row[color_field] = ck)
                for (j, ff) in enumerate(facet_fields)
                    row[ff] = fk[j]
                end
                for prob in probs
                    lo = (1 - prob) / 2
                    hi = 1 - lo
                    row[_vl_prob_field("lo", prob)] = q(lo)
                    row[_vl_prob_field("hi", prob)] = q(hi)
                end
                push!(rows, row)
            end
        end
    end
    rows
end

# --- Shared helpers for interval analysis → VL ---

function _extract_interval_fields(layer; default_x="value")
    table = extract_data(layer)
    x_sel = length(layer.positional) >= 1 ? layer.positional[1] : nothing
    x_field = isnothing(x_sel) ? default_x : _field_name(x_sel)
    x_label = isnothing(x_sel) ? default_x : _field_label(x_sel)
    y_field = haskey(layer.named, :y) ? _field_name(layer.named[:y]) : nothing
    y_label = haskey(layer.named, :y) ? _field_label(layer.named[:y]) : nothing
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)
    (; table, x_field, x_label, y_field, y_label, color_field, color_label, facet, facet_fields)
end

function _add_ycolor_encoding!(enc, y_field, color_field; y_label=nothing, color_label=nothing, y_axis=true)
    if !isnothing(y_field)
        y_enc = Dict{String,Any}("field" => y_field, "type" => "nominal")
        !y_axis && (y_enc["axis"] = Dict{String,Any}("title" => nothing))
        !isnothing(y_label) && y_label != y_field && (y_enc["title"] = y_label)
        enc["y"] = y_enc
    end
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        enc["color"] = color_enc
        !isnothing(y_field) && (enc["yOffset"] = Dict{String,Any}("field" => color_field, "type" => "nominal"))
    elseif !isnothing(y_field)
        enc["color"] = Dict{String,Any}("field" => y_field, "type" => "nominal", "legend" => nothing)
    end
    enc
end

function _interval_point_layer(y_field, color_field; y_label=nothing, color_label=nothing, mark_opts...)
    pt_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "__point__", "type" => "quantitative"),
    )
    if !isnothing(y_field)
        pt_enc["y"] = Dict{String,Any}("field" => y_field, "type" => "nominal")
    end
    if !isnothing(color_field) && !isnothing(y_field)
        pt_enc["yOffset"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    end
    mark = Dict{String,Any}("type" => "point", "filled" => true, (string(k) => v for (k,v) in pairs(mark_opts))...)
    Dict{String,Any}("mark" => mark, "encoding" => pt_enc)
end

function _interval_tooltips(x_label, y_field, color_field, probs)
    tt = Dict{String,Any}[Dict{String,Any}("field" => "__point__", "type" => "quantitative", "title" => "$x_label (estimate)")]
    !isnothing(y_field) && push!(tt, Dict{String,Any}("field" => y_field, "type" => "nominal"))
    !isnothing(color_field) && color_field != y_field && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    widest = maximum(probs)
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("lo", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% lo"))
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("hi", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% hi"))
    tt
end

# --- Analysis → Vega-Lite spec ---

function analysis_to_vl(a::PointIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, x_field, x_label, y_field, y_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer)
    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields)

    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = range(1.5, 8, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => x_label),
            "x2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        _add_ycolor_encoding!(enc, y_field, color_field; y_label, color_label, y_axis=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(y_field, color_field; y_label, color_label, size=80, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(x_label, y_field, color_field, a.probs))

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::GradientIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, x_field, x_label, y_field, y_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer)
    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.7, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => x_label),
            "x2" => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
            "opacity" => Dict{String,Any}("value" => opacities[i]),
        )
        _add_ycolor_encoding!(enc, y_field, color_field; y_label, color_label, y_axis=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => 14),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(y_field, color_field; y_label, color_label, size=50, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(x_label, y_field, color_field, a.probs))

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)

    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs; color_field, facet_fields)
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

    tt = Dict{String,Any}[
        Dict{String,Any}("field" => x_field, "type" => "quantitative"),
        Dict{String,Any}("field" => "__median__", "type" => "quantitative", "title" => "median"),
    ]
    !isnothing(color_field) && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    widest = sort(a.probs, rev=true)[1]
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("lo", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% lo"))
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("hi", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% hi"))
    _add_analysis_tooltips!(layers, tt)

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::DotIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, x_field, x_label, y_field, y_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer)

    vals = Tables.getcolumn(table, Symbol(x_field))
    groups = isnothing(y_field) ? nothing : Tables.getcolumn(table, Symbol(y_field))
    group_keys = isnothing(groups) ? [nothing] : unique(groups)
    colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
    color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))
    facet_data = [Tables.getcolumn(table, Symbol(f)) for f in facet_fields]
    facet_combos = isempty(facet_data) ? [()] : sort(unique(collect(zip(facet_data...))))

    # Quantile dots
    dot_rows = Dict{String,Any}[]
    for fk in facet_combos
        for gk in group_keys
            for ck in color_keys
                mask = trues(length(vals))
                if !isnothing(groups)
                    mask .&= [g == gk for g in groups]
                end
                if !isnothing(colors)
                    mask .&= [c == ck for c in colors]
                end
                for (j, fc) in enumerate(facet_data)
                    mask .&= [fci == fk[j] for fci in fc]
                end
                v = sort(vals[mask])
                n = length(v)
                for i in 1:a.n_dots
                    q = v[clamp(round(Int, (i - 0.5) / a.n_dots * n), 1, n)]
                    row = Dict{String,Any}("quantile" => q)
                    !isnothing(gk) && (row[y_field] = gk)
                    !isnothing(ck) && (row[color_field] = ck)
                    for (j, ff) in enumerate(facet_fields)
                        row[ff] = fk[j]
                    end
                    push!(dot_rows, row)
                end
            end
        end
    end

    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields)

    # Dot layer
    dot_enc = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "quantile", "type" => "quantitative", "title" => x_label,
                                  "bin" => Dict{String,Any}("maxbins" => 40)),
        "size" => Dict{String,Any}("aggregate" => "count", "legend" => nothing),
    )
    _add_ycolor_encoding!(dot_enc, y_field, color_field; y_label, color_label, y_axis=false)

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
        _add_ycolor_encoding!(enc, y_field, color_field; y_label, color_label)
        push!(interval_layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i], "color" => "#333"),
            "encoding" => enc,
        ))
    end

    push!(interval_layers, _interval_point_layer(y_field, color_field; y_label, color_label, size=50, color="white", stroke="#333", strokeWidth=1.5))
    _add_analysis_tooltips!(interval_layers, _interval_tooltips(x_label, y_field, color_field, a.probs))

    push!(layers, Dict{String,Any}(
        "data" => Dict{String,Any}("values" => summary),
        "layer" => interval_layers,
    ))

    spec = Dict{String,Any}("layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function density_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? _field_name(layer.named[:y]) : nothing

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
        color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
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
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    analysis = extract_transformation(layer, AlgebraOfGraphics.LinearAnalysis)
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
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    analysis = extract_transformation(layer, AlgebraOfGraphics.SmoothAnalysis)
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
    spec
end

"""
    histogram_to_vl(layer; is_sublayer=false)

Translate AoG's `histogram()` to Vega-Lite's bar mark with bin + count aggregation.
"""
function histogram_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"

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
    spec
end

"""
    frequency_to_vl(layer; is_sublayer=false)

Translate AoG's `frequency()` to a Vega-Lite bar chart with `aggregate: "count"`.
"""
function frequency_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"

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
    spec
end

"""
    expectation_to_vl(layer; is_sublayer=false)

Translate AoG's `expectation()` to a Vega-Lite bar chart with `aggregate: "mean"`.
"""
function expectation_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"

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
    spec
end

_is_ecdf(layer) = let vis = extract_visual(layer); !isnothing(vis) && vis.plottype <: ECDFPlot end

"""
    ecdf_to_vl(layer; is_sublayer=false)

Translate AoG's `visual(ECDFPlot)` to a Vega-Lite spec using window transforms
for cumulative distribution. Produces a step line of the empirical CDF.

Supports `color=` grouping via `groupby` on the window transforms.
"""
function ecdf_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    linestyle_field = haskey(layer.named, :linestyle) ? _field_name(layer.named[:linestyle]) : nothing

    # Window transforms for ECDF:
    # 1. Sort by x, count cumulative (per group)
    # 2. Count total (per group)
    # 3. Calculate ecdf = cumulative / total
    groupby_fields = String[]
    !isnothing(color_field) && push!(groupby_fields, color_field)
    !isnothing(linestyle_field) && push!(groupby_fields, linestyle_field)

    sort_spec = [Dict{String,Any}("field" => x_field)]

    window1 = Dict{String,Any}(
        "window" => [Dict{String,Any}("op" => "count", "as" => "__cumulative_count__")],
        "sort" => sort_spec,
    )
    window2 = Dict{String,Any}(
        "window" => [Dict{String,Any}("op" => "count", "as" => "__total_count__")],
        "frame" => [nothing, nothing],
    )
    if !isempty(groupby_fields)
        window1["groupby"] = groupby_fields
        window2["groupby"] = groupby_fields
    end

    calc = Dict{String,Any}(
        "calculate" => "datum.__cumulative_count__ / datum.__total_count__",
        "as" => "__ecdf__",
    )

    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative", "sort" => "ascending"),
        "y" => Dict{String,Any}("field" => "__ecdf__", "type" => "quantitative", "title" => "Cumulative Proportion"),
    )
    if !isnothing(color_field)
        encoding["color"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    end
    if !isnothing(linestyle_field)
        encoding["strokeDash"] = Dict{String,Any}("field" => linestyle_field, "type" => "nominal")
    end

    # Auto tooltip
    tt = vl_tooltips(encoding)
    !isempty(tt) && (encoding["tooltip"] = tt)

    vis = extract_visual(layer)
    mark = Dict{String,Any}("type" => "line", "interpolate" => "step-after")
    if !isnothing(vis)
        merge!(mark, visual_attrs_to_mark_props(vis))
    end

    spec = Dict{String,Any}(
        "mark" => mark,
        "transform" => [window1, window2, calc],
        "encoding" => encoding,
    )
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    if !isnothing(table)
        infer_types!(encoding, table)
    end
    spec
end

# --- Core translation: dispatch-based layer_to_vl ---

"""Analysis types to check in `_layer_handler`, in priority order."""
_ANALYSIS_TYPES = Type[
    TidybayesAnalysis,
    AlgebraOfGraphics.DensityAnalysis,
    AlgebraOfGraphics.FrequencyAnalysis,
    AlgebraOfGraphics.ExpectationAnalysis,
    AlgebraOfGraphics.LinearAnalysis,
    AlgebraOfGraphics.SmoothAnalysis,
    AlgebraOfGraphics.HistogramAnalysis,
]

"""Find the dispatch key for a layer: an analysis object, Val(:ecdf), or nothing (plain layer)."""
function _layer_handler(layer::AlgebraOfGraphics.Layer)
    for T in _ANALYSIS_TYPES
        a = extract_transformation(layer, T)
        !isnothing(a) && return a
    end
    _is_ecdf(layer) && return Val(:ecdf)
    nothing
end

# Dispatch: each handler type → its *_to_vl function
_layer_to_vl(a::TidybayesAnalysis, layer; kw...) = analysis_to_vl(a, layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.DensityAnalysis, layer; kw...) = density_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.FrequencyAnalysis, layer; kw...) = frequency_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.ExpectationAnalysis, layer; kw...) = expectation_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.LinearAnalysis, layer; kw...) = linear_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.SmoothAnalysis, layer; kw...) = smooth_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.HistogramAnalysis, layer; kw...) = histogram_to_vl(layer; kw...)
_layer_to_vl(::Val{:ecdf}, layer; kw...) = ecdf_to_vl(layer; kw...)
_layer_to_vl(::Nothing, layer; kw...) = _plain_layer_to_vl(layer; kw...)

function layer_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    if is_pregrouped(layer)
        spec = pregrouped_to_vl(layer; is_sublayer)
    else
        handler = _layer_handler(layer)
        spec = _layer_to_vl(handler, layer; is_sublayer)
    end
    !is_sublayer && (spec["\$schema"] = VL_SCHEMA)
    spec
end

"""Translate a plain (non-analysis, non-pregrouped) AoG layer to VL."""
function _plain_layer_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    spec = Dict{String,Any}()

    table = extract_data(layer)
    !isnothing(table) && (spec["data"] = data_to_vl(table))

    # Visual / mark (default to Scatter like AoG)
    vis = extract_visual(layer)
    if !isnothing(vis)
        mark_type = plottype_to_mark(vis.plottype)
        extra_props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
        spec["mark"] = isempty(extra_props) ? mark_type :
            merge(Dict{String,Any}("type" => mark_type), extra_props)
    else
        spec["mark"] = "point"
    end

    # Encoding from positional + named
    encoding = Dict{String,Any}()

    plot_type = !isnothing(vis) ? vis.plottype : Nothing
    positional_channels = if !isnothing(vis) && plot_type <: HLines
        ["y"]
    elseif !isnothing(vis) && plot_type <: VLines
        ["x"]
    elseif !isnothing(vis) && plot_type <: Union{Rangebars, Errorbars}
        ["x", "y", "y2"]
    else
        ["x", "y"]
    end
    for (i, sel) in enumerate(layer.positional)
        i <= length(positional_channels) || break
        encoding[positional_channels[i]] = selector_to_field(sel)
    end

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    !isnothing(table) && infer_types!(encoding, table)

    # Auto-tooltip
    if !isempty(encoding) && !haskey(encoding, "tooltip")
        tt = vl_tooltips(encoding)
        !isempty(tt) && (encoding["tooltip"] = tt)
    end

    !isempty(encoding) && (spec["encoding"] = encoding)
    spec
end

function layers_to_vl(layers::AlgebraOfGraphics.Layers)
    # Check if any layer is faceted density (density with y group) — needs special handling
    has_faceted_density = false
    facet_field = nothing
    shared_table = nothing
    shared_data = nothing

    for l in layers.layers
        is_pregrouped(l) && continue
        table = extract_data(l)
        if !isnothing(table) && isnothing(shared_table)
            shared_data = data_to_vl(table)
            shared_table = table
        end
        dens = extract_transformation(l, AlgebraOfGraphics.DensityAnalysis)
        if !isnothing(dens) && haskey(l.named, :y)
            has_faceted_density = true
            facet_field = string(l.named[:y])
        end
    end

    if has_faceted_density && !isnothing(facet_field)
        return _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    end

    # Check if any layer is an analysis type (produces own summarized data)
    has_analysis = any(l -> !isnothing(extract_transformation(l, TidybayesAnalysis)), layers.layers)

    spec = Dict{String,Any}("\$schema" => VL_SCHEMA)
    # Only share data at top level when no analysis layers are present
    if !has_analysis && !isnothing(shared_data)
        spec["data"] = shared_data
    end

    outer_facet = Dict{String,Any}()
    layer_specs = Dict{String,Any}[]

    for layer in layers.layers
        ls = layer_to_vl(layer; is_sublayer=true)

        if haskey(ls, "facet")
            # Faceted analysis spec — lift facet, flatten inner sublayers with their data
            merge!(outer_facet, ls["facet"])
            inner = ls["spec"]
            inner_data = get(ls, "data", get(inner, "data", nothing))
            for sl in get(inner, "layer", [inner])
                if !isnothing(inner_data) && !haskey(sl, "data")
                    sl["data"] = inner_data
                end
                push!(layer_specs, sl)
            end
        elseif haskey(ls, "layer")
            # Multi-layer (unfaceted analysis) — flatten sublayers with attached data
            sub_data = get(ls, "data", nothing)
            for sl in ls["layer"]
                if !isnothing(sub_data) && !haskey(sl, "data")
                    sl["data"] = sub_data
                end
                push!(layer_specs, sl)
            end
        else
            # Single layer
            if has_analysis && !haskey(ls, "data")
                # Mixed mode — ensure each layer carries its own data
                table = extract_data(layer)
                !isnothing(table) && (ls["data"] = data_to_vl(table))
            elseif !has_analysis
                table = extract_data(layer)
                if !isnothing(table) && table === shared_table
                    delete!(ls, "data")
                end
            end
            push!(layer_specs, ls)
        end
    end

    # Also collect facet from regular layer encodings (col=/row= → column/row channels)
    for ls in layer_specs
        enc = get(ls, "encoding", nothing)
        isnothing(enc) && continue
        haskey(enc, "column") && !haskey(outer_facet, "column") && (outer_facet["column"] = enc["column"])
        haskey(enc, "row") && !haskey(outer_facet, "row") && (outer_facet["row"] = enc["row"])
    end

    if !isempty(outer_facet)
        # VL facet only filters inherited (outer) data — per-sublayer data is NOT filtered.
        # Fix: merge all sublayer data into one outer dataset tagged with __source__,
        # then add filter transforms to each sublayer so they only see their own rows.
        merged_values = Dict{String,Any}[]
        src_id = 0
        seen_data = Dict{UInt,String}()  # objectid(values) → source tag

        # Re-include hoisted shared_data for sublayers that had their data removed
        hoisted_layers = filter(ls -> !haskey(ls, "data"), layer_specs)
        if !isnothing(shared_data) && !isempty(hoisted_layers)
            vals = get(shared_data, "values", nothing)
            if !isnothing(vals)
                src_id += 1
                tag = "_s$(src_id)"
                seen_data[objectid(vals)] = tag
                for row in vals
                    row["__src"] = tag
                end
                append!(merged_values, vals)
                for ls in hoisted_layers
                    existing = get(ls, "transform", Dict{String,Any}[])
                    pushfirst!(existing, Dict{String,Any}("filter" => "datum.__src === '$(tag)'"))
                    ls["transform"] = existing
                end
            end
        end

        for ls in layer_specs
            data = get(ls, "data", nothing)
            isnothing(data) && continue
            vals = get(data, "values", nothing)
            isnothing(vals) && continue
            oid = objectid(vals)
            tag = get(seen_data, oid, nothing)
            if isnothing(tag)
                src_id += 1
                tag = "_s$(src_id)"
                seen_data[oid] = tag
                for row in vals
                    row["__src"] = tag
                end
                append!(merged_values, vals)
            end
            # Replace per-sublayer data with a filter transform
            delete!(ls, "data")
            existing = get(ls, "transform", Dict{String,Any}[])
            pushfirst!(existing, Dict{String,Any}("filter" => "datum.__src === '$(tag)'"))
            ls["transform"] = existing
        end
        # Strip column/row from sublayer encodings — facet is at top level
        for ls in layer_specs
            enc = get(ls, "encoding", nothing)
            isnothing(enc) && continue
            delete!(enc, "column")
            delete!(enc, "row")
        end
        spec["data"] = Dict{String,Any}("values" => merged_values)
        spec["facet"] = outer_facet
        spec["spec"] = Dict{String,Any}("layer" => layer_specs)
    else
        spec["layer"] = layer_specs
    end

    spec
end

function _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    # For density + pointinterval combos: facet by group field, inner spec has layers
    inner_layers = Dict{String,Any}[]

    # Check if we have visual layers alongside density (raincloud-style) — need range scaling
    has_visual_layers = any(l -> begin
        isnothing(extract_transformation(l, AlgebraOfGraphics.DensityAnalysis)) && isnothing(extract_transformation(l, TidybayesAnalysis)) && !isnothing(extract_visual(l))
    end, layers.layers)

    for layer in layers.layers
        dens = extract_transformation(layer, AlgebraOfGraphics.DensityAnalysis)
        if !isnothing(dens)
            # Density sublayer (unfaceted version)
            x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
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
            analysis = extract_transformation(layer, TidybayesAnalysis)
            if !isnothing(analysis)
                # Compute interval summary per-group using VL transforms instead
                x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
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
                x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
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
        "\$schema" => VL_SCHEMA,
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

function _deep_merge_encoding!(target_enc::Dict, config_enc::Dict)
    for (ek, ev) in config_enc
        sek = string(ek)
        if ev isa Dict && haskey(target_enc, sek) && target_enc[sek] isa Dict
            merge!(target_enc[sek], Dict{String,Any}(string(k2) => v2 for (k2, v2) in ev))
        else
            target_enc[sek] = ev
        end
    end
end

function _merge_encoding_config!(spec::Dict, config_enc::Dict)
    if haskey(spec, "encoding")
        _deep_merge_encoding!(spec["encoding"], config_enc)
    end
    if haskey(spec, "layer")
        for sublayer in spec["layer"]
            sublayer isa Dict && _merge_encoding_config!(sublayer, config_enc)
        end
    end
    if haskey(spec, "spec")
        spec["spec"] isa Dict && _merge_encoding_config!(spec["spec"], config_enc)
    end
end

function to_vegalite(v::VegaSpec)
    spec = to_vegalite(v.drawable)
    select_fields = nothing
    if !isnothing(v.config)
        for (k, val) in v.config.properties
            sk = string(k)
            # Deep-merge encoding so config adds to (not overwrites) auto-generated channels
            if sk == "encoding" && val isa Dict
                _merge_encoding_config!(spec, val)
            elseif sk in ("width", "height") && haskey(spec, "spec")
                # For faceted specs, width/height go into the inner spec
                spec["spec"][sk] = val
            elseif sk == "independent_scales"
                # Sugar for VL resolve: independent_scales=true, =:x, =(:x,:y)
                axes = if val === true
                    ["x", "y"]
                elseif val isa Symbol
                    [string(val)]
                else
                    [string(v) for v in val]
                end
                resolve_scale = Dict{String,Any}(ax => "independent" for ax in axes)
                spec["resolve"] = Dict{String,Any}("scale" => resolve_scale)
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
    has_user_params = haskey(spec, "params")

    # For faceted specs, add zoom/pan inside "spec" (per-cell), not at facet level
    if haskey(spec, "facet")
        inner = get(spec, "spec", nothing)
        if !isnothing(inner) && !haskey(inner, "params")
            # Find quantitative axes in inner sublayers
            inner_layers = get(inner, "layer", nothing)
            inner_enc = get(inner, "encoding", nothing)
            zoom_ch = String[]
            for ch in ("x", "y")
                is_quant = false
                if !isnothing(inner_enc) && haskey(inner_enc, ch)
                    is_quant = get(inner_enc[ch], "type", "") == "quantitative"
                elseif !isnothing(inner_layers)
                    for sl in inner_layers
                        sl_enc = get(sl, "encoding", nothing)
                        isnothing(sl_enc) && continue
                        if haskey(sl_enc, ch) && get(sl_enc[ch], "type", "") == "quantitative"
                            is_quant = true
                            break
                        end
                    end
                end
                is_quant && push!(zoom_ch, ch)
            end
            if !isempty(zoom_ch)
                grid_param = Dict{String,Any}(
                    "name" => "grid",
                    "select" => Dict{String,Any}("type" => "interval", "encodings" => zoom_ch),
                    "bind" => "scales",
                )
                if !isnothing(inner_layers) && !isempty(inner_layers)
                    sl_params = get!(inner_layers[1], "params", Dict{String,Any}[])
                    push!(sl_params, grid_param)
                else
                    inner["params"] = [grid_param]
                end
            end
        end
        return spec
    end

    has_user_params && return spec

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

    # Zoom (scroll) + pan (drag) — only on quantitative axes to avoid duplicate signal errors
    zoom_encodings = String[]
    for ch in ("x", "y")
        is_quant = false
        if !isnothing(enc) && haskey(enc, ch)
            is_quant = get(enc[ch], "type", "") == "quantitative"
        elseif !isnothing(sublayers)
            for sl in sublayers
                sl_enc = get(sl, "encoding", nothing)
                isnothing(sl_enc) && continue
                if haskey(sl_enc, ch) && get(sl_enc[ch], "type", "") == "quantitative"
                    is_quant = true
                    break
                end
            end
        end
        is_quant && push!(zoom_encodings, ch)
    end
    if !isempty(zoom_encodings)
        grid_param = Dict{String,Any}(
            "name" => "grid",
            "select" => Dict{String,Any}("type" => "interval", "encodings" => zoom_encodings),
            "bind" => "scales",
        )
        if !isnothing(sublayers) && !isempty(sublayers)
            # For layered specs, put bind:scales on the first sublayer to avoid
            # VL duplicate signal error (grid_tuple created per view in layer array)
            sl_params = get!(sublayers[1], "params", Dict{String,Any}[])
            push!(sl_params, grid_param)
        else
            push!(params, grid_param)
        end
    end

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

    # Nearest-point tooltip for point/area marks (makes tooltip snap to data).
    # VL doesn't support "nearest" for line marks — skip those.
    if mark_type in ("point", "area") && !isnothing(enc) && haskey(enc, "tooltip")
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

"""Count the number of facet columns in a VL spec by inspecting the data."""
function _count_facet_cols(vl::Dict)
    facet = get(vl, "facet", nothing)
    isnothing(facet) && return 1
    col_field = nothing
    if haskey(facet, "column")
        col_field = get(facet["column"], "field", nothing)
    elseif haskey(facet, "field")
        col_field = facet["field"]
    end
    isnothing(col_field) && return 1
    data_vals = get(get(vl, "data", Dict()), "values", nothing)
    if !isnothing(data_vals) && data_vals isa Vector
        vals = Set()
        for row in data_vals
            row isa Dict && haskey(row, col_field) && push!(vals, row[col_field])
        end
        n = length(vals)
        return n > 0 ? n : 1
    end
    1
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

        _applyResponsiveWidth: function(id, spec) {
            var el = document.getElementById(id);
            if (!el) return spec;
            var containerWidth = el.parentElement ? el.parentElement.clientWidth : null;
            if (!containerWidth || containerWidth < 50) return spec;
            var padding = 30; // approximate VL padding

            // Faceted specs: set per-cell width from container / nCols
            if (spec._aov && spec._aov.nFacetCols && spec.spec) {
                var nCols = spec._aov.nFacetCols;
                var cellWidth = Math.floor((containerWidth - padding) / nCols) - padding;
                if (cellWidth > 50) {
                    spec.spec = Object.assign({}, spec.spec, {width: cellWidth});
                }
                return spec;
            }

            // Layered/composite specs: set top-level width
            if (spec.layer || spec._aov) {
                spec = Object.assign({}, spec, {width: containerWidth - padding});
                return spec;
            }

            return spec;
        },

        embed: function(id, spec, opts) {
            opts = opts || {};
            var self = this;
            // Store original spec for re-embed on resize
            var origSpec = JSON.parse(JSON.stringify(spec));
            var sized = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));

            var doEmbed = function() {
                var s = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));
                return vegaEmbed('#' + id, s, opts).then(function(result) {
                    self.views[id] = result.view;
                    if (self._pending[id]) {
                        self._pending[id].forEach(function(p) {
                            self.onSignal(id, p.signal, p.callback);
                        });
                        delete self._pending[id];
                    }
                    return result;
                }).catch(console.error);
            };

            // Set up resize observer for responsive re-embed
            if (spec.layer || spec._aov || (spec.spec && spec.facet)) {
                var el = document.getElementById(id);
                if (el && el.parentElement && window.ResizeObserver) {
                    var timer = null;
                    var lastWidth = el.parentElement.clientWidth;
                    var ro = new ResizeObserver(function() {
                        var newWidth = el.parentElement ? el.parentElement.clientWidth : 0;
                        if (newWidth === lastWidth || newWidth < 50) return;
                        lastWidth = newWidth;
                        clearTimeout(timer);
                        timer = setTimeout(function() { doEmbed(); }, 200);
                    });
                    ro.observe(el.parentElement);
                    // Clean up on element removal
                    self._observers = self._observers || {};
                    if (self._observers[id]) { self._observers[id].disconnect(); }
                    self._observers[id] = ro;
                }
            }

            return doEmbed();
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
    # Convert to VL dict
    vl = spec isa Dict ? copy(spec) : to_vegalite(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    # Only apply fit_width defaults if no explicit width was set (via config or kwarg)
    has_explicit_width = haskey(vl, "width") && vl["width"] isa Number
    has_explicit_inner_width = haskey(vl, "spec") && vl["spec"] isa Dict && haskey(vl["spec"], "width")
    if fit_width && !has_explicit_width && !has_explicit_inner_width && !haskey(vl, "hconcat") && !haskey(vl, "vconcat")
        is_faceted = haskey(vl, "facet") || haskey(vl, "spec")
        is_layered = haskey(vl, "layer") || is_faceted || haskey(vl, "concat")
        # VL composite marks (boxplot, errorbar, errorband) internally create layers —
        # "width: container" and "autosize: fit" don't work for them
        is_composite = _is_composite_mark(vl)
        if !is_layered && !is_composite
            # "width": "container" only works for true single-view specs
            vl["width"] = "container"
            vl["autosize"] = Dict("type" => "fit", "contains" => "padding")
        elseif is_faceted && haskey(vl, "spec")
            # Inject _aov hint for responsive JS resizing
            n_facet_cols = _count_facet_cols(vl)
            vl["_aov"] = Dict{String,Any}("nFacetCols" => n_facet_cols)
            inner = vl["spec"]
            if !haskey(inner, "width")
                inner["width"] = 400  # fallback, JS overrides
            end
        else
            # Layered/composite: mark for responsive JS resizing
            vl["_aov"] = Dict{String,Any}()
            if !haskey(vl, "width")
                vl["width"] = 400  # fallback, JS overrides
            end
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
    vdraw(spec; kwargs...)

Render an AoG spec as a Vega-Lite HTML node. Convenience alias for `to_node(spec; kwargs...)`.
Named `vdraw` to avoid clashing with `AlgebraOfGraphics.draw` (Makie rendering).
"""
vdraw(spec; kwargs...) = to_node(spec; kwargs...)
vdraw(; kwargs...) = spec -> vdraw(spec; kwargs...)

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

# --- High-level widgets and recipes ---

"""
    ecdf_grid(table, columns; group=nothing, width=250, height=180)

Render a grid of ECDF plots, one per column, colored by `group`.
Returns an HTMX `h.div` node with flex-wrap layout.

- `table`: any Tables.jl-compatible table (DataFrame, NamedTuple, etc.)
- `columns`: vector of column names (Symbols) to plot
- `group`: optional column name for color grouping (e.g. `:chain`, `:model`)
- `width`, `height`: per-plot dimensions

Example (posterior parameter ECDFs colored by chain):
```julia
ecdf_grid(draws_df, [:alpha, :beta, :sigma]; group=:chain)
```
"""
function ecdf_grid(table, columns; group=nothing, width=250, height=180)
    plots = map(columns) do col
        vals = Tables.getcolumn(table, col)
        if !isnothing(group)
            grp = string.(Tables.getcolumn(table, group))
            plot_tbl = (; value=vals, _group=grp)
            spec = data(plot_tbl) * mapping(:value; color=:_group) *
                visual(ECDFPlot) * config(width=width, height=height)
        else
            plot_tbl = (; value=vals)
            spec = data(plot_tbl) * mapping(:value) *
                visual(ECDFPlot) * config(width=width, height=height)
        end
        (string(col), vdraw(spec))
    end
    h.div(; style="display:flex; flex-wrap:wrap; gap:1rem;")(
        [h.div(h.h5(name), node) for (name, node) in plots]...
    )
end

"""
    ppc_overlay(obs, pred; x, y, col=nothing, row=nothing, group=nothing,
                color=nothing, truth=nothing, obs_mark=Scatter, obs_size=30,
                truth_color="red", truth_strokeWidth=2, truth_strokeDash=[4,4])

Build a posterior predictive check overlay: observations + prediction draws + optional truth.
Returns composable AoG layers — combine with `* config(...)` and pipe to `|> vdraw`.

- `obs`: observation data table
- `pred`: prediction draws table (one row per draw × observation)
- `x`, `y`: column names for the axes
- `col`, `row`: optional faceting columns
- `group`: draw identifier column (e.g. `:draw_id`) for prediction ribbons
- `color`: optional color column for predictions (e.g. `:model` for comparisons)
- `truth`: optional ground-truth data table (rendered as dashed lines)

Example:
```julia
ppc_overlay(obs_df, pred_df;
    x=:time_h, y=:value, col=:assay_name, row=:subject_name,
    group=:draw_id,
) * config(width=250, height=100, independent_scales=true) |> vdraw
```
"""
function ppc_overlay(obs, pred; x, y, col=nothing, row=nothing, group=nothing,
                     color=nothing, truth=nothing, obs_mark=Scatter, obs_size=30,
                     truth_color="red", truth_strokeWidth=2, truth_strokeDash=[4,4])
    facet_kw = Dict{Symbol,Any}()
    !isnothing(col) && (facet_kw[:col] = col)
    !isnothing(row) && (facet_kw[:row] = row)

    obs_layer = data(obs) * mapping(x, y; facet_kw...) * visual(obs_mark; size=obs_size)

    pred_kw = copy(facet_kw)
    !isnothing(group) && (pred_kw[:group] = group)
    !isnothing(color) && (pred_kw[:color] = color)
    pred_layer = data(pred) * mapping(x, y; pred_kw...) * lineribbon()

    layers = pred_layer + obs_layer

    if !isnothing(truth)
        truth_layer = data(truth) * mapping(x, y; facet_kw...) *
            visual(Lines; color=truth_color, strokeWidth=truth_strokeWidth, strokeDash=truth_strokeDash)
        layers = layers + truth_layer
    end

    layers
end

# --- Static (Makie) rendering ---

"""
    _extract_drawable(spec)

Extract the AoG drawable (Layer/Layers) from a spec. Returns `(drawable, config)`.
"""
_extract_drawable(layer::AlgebraOfGraphics.Layer) = (layer, nothing)
_extract_drawable(layers::AlgebraOfGraphics.Layers) = (layers, nothing)
_extract_drawable(v::VegaSpec) = (v.drawable, v.config)

"""
    _draw_kwargs(cfg::Union{Config,Nothing})

Translate AoV Config properties into keyword arguments for `AlgebraOfGraphics.draw`.
"""
function _is_faceted(drawable)
    if drawable isa AlgebraOfGraphics.Layer
        return haskey(drawable.named, :col) || haskey(drawable.named, :row) || haskey(drawable.named, :layout)
    elseif drawable isa AlgebraOfGraphics.Layers
        return any(_is_faceted, drawable.layers)
    end
    false
end

function _draw_kwargs(cfg::Union{Config,Nothing}; faceted=false)
    figure_kw = Dict{Symbol,Any}()
    facet_kw = Dict{Symbol,Any}()
    axis_kw = Dict{Symbol,Any}()
    isnothing(cfg) && return (; figure=NamedTuple(), facet=NamedTuple(), axis=NamedTuple())
    props = cfg.properties
    if !faceted
        w = get(props, :width, nothing)
        h_val = get(props, :height, nothing)
        if !isnothing(w) || !isnothing(h_val)
            figure_kw[:size] = (something(w, 400), something(h_val, 400))
        end
    end
    # Translate VL encoding scale overrides to Makie axis scales
    enc = get(props, :encoding, nothing)
    if !isnothing(enc) && enc isa Dict
        for (ch, ch_props) in enc
            ch_props isa Dict || continue
            scale_dict = get(ch_props, "scale", get(ch_props, :scale, nothing))
            isnothing(scale_dict) && continue
            scale_type = get(scale_dict, "type", get(scale_dict, :type, nothing))
            if scale_type == "log"
                if ch in (:y, "y")
                    axis_kw[:yscale] = log10
                elseif ch in (:x, "x")
                    axis_kw[:xscale] = log10
                end
            end
        end
    end
    for (k, v) in props
        if k in (:width, :height, :encoding)
            # handled above
        elseif k === :independent_scales
            axes = if v === true
                [:x, :y]
            elseif v isa Symbol
                [v]
            else
                [Symbol(a) for a in v]
            end
            :x in axes && (facet_kw[:linkxaxes] = :none)
            :y in axes && (facet_kw[:linkyaxes] = :none)
        end
    end
    (; figure=NamedTuple(figure_kw), facet=NamedTuple(facet_kw), axis=NamedTuple(axis_kw))
end

"""
    _has_aov_analysis(layer::AlgebraOfGraphics.Layer)

Check if a layer uses an AoV-specific transformation (tidybayes analyses).
"""
function _get_analysis(layer::AlgebraOfGraphics.Layer)
    t = layer.transformation
    t isa TidybayesAnalysis && return t
    if t isa ComposedFunction
        t.outer isa TidybayesAnalysis && return t.outer
        t.inner isa TidybayesAnalysis && return t.inner
    end
    nothing
end

"""
    _lineribbon_to_aog(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer)

Convert a LineRibbonAnalysis layer to pure AoG Band + Lines layers.
"""
function _lineribbon_to_aog(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)

    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs;
        color_field, facet_fields)

    # Build a columnar NamedTuple from the summary rows
    cols = collect(keys(summary[1]))
    col_syms = Tuple(Symbol.(cols))
    col_vals = Tuple([getindex.(summary, c) for c in cols])
    summary_nt = NamedTuple{col_syms}(col_vals)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.6, length=length(sorted_probs))

    facet_kw = Dict{Symbol,Any}()
    for ff in facet_fields
        sf = Symbol(ff)
        if haskey(layer.named, :col) && _field_name(layer.named[:col]) == ff
            facet_kw[:col] = sf
        elseif haskey(layer.named, :row) && _field_name(layer.named[:row]) == ff
            facet_kw[:row] = sf
        end
    end

    color_kw = isnothing(color_field) ? Dict{Symbol,Any}() :
        Dict{Symbol,Any}(:color => Symbol(color_field))

    x_sym = Symbol(x_field)
    result = nothing

    for (i, prob) in enumerate(sorted_probs)
        lo_sym = Symbol(_vl_prob_field("lo", prob))
        hi_sym = Symbol(_vl_prob_field("hi", prob))
        band_layer = data(summary_nt) *
            mapping(x_sym, lo_sym, hi_sym; color_kw..., facet_kw...) *
            visual(Band; alpha=opacities[i])
        result = isnothing(result) ? band_layer : result + band_layer
    end

    if a.show_line
        line_layer = data(summary_nt) *
            mapping(x_sym, Symbol("__median__"); color_kw..., facet_kw...) *
            visual(Lines)
        result = isnothing(result) ? line_layer : result + line_layer
    end

    result
end

"""
    _fix_visual_attrs(layer::AlgebraOfGraphics.Layer)

Remap VL-style visual attributes to Makie equivalents (e.g. size → markersize).
Returns the layer unchanged if no visual or no remapping needed.
"""
function _fix_visual_attrs(layer::AlgebraOfGraphics.Layer)
    vis = extract_visual(layer)
    isnothing(vis) && return layer
    attrs = Dict(pairs(vis.attributes))
    changed = false
    if haskey(attrs, :size) && !haskey(attrs, :markersize)
        attrs[:markersize] = pop!(attrs, :size)
        changed = true
    end
    if haskey(attrs, :strokeWidth) && !haskey(attrs, :linewidth)
        attrs[:linewidth] = pop!(attrs, :strokeWidth)
        changed = true
    end
    if haskey(attrs, :strokeDash) && !haskey(attrs, :linestyle)
        attrs[:linestyle] = pop!(attrs, :strokeDash)
        changed = true
    end
    if haskey(attrs, :opacity) && !haskey(attrs, :alpha)
        attrs[:alpha] = pop!(attrs, :opacity)
        changed = true
    end
    !changed && return layer
    new_vis = AlgebraOfGraphics.Visual(vis.plottype; attrs...)
    # Rebuild layer with new visual in the transformation
    t = layer.transformation
    new_t = if t isa AlgebraOfGraphics.Visual
        new_vis
    elseif t isa ComposedFunction
        t.outer isa AlgebraOfGraphics.Visual ? new_vis ∘ t.inner : t.outer ∘ new_vis
    else
        new_vis
    end
    AlgebraOfGraphics.Layer(new_t, layer.data, layer.positional, layer.named)
end

function _convert_single_layer(l::AlgebraOfGraphics.Layer)
    a = _get_analysis(l)
    if !isnothing(a)
        if a isa LineRibbonAnalysis
            return _lineribbon_to_aog(a, l)
        end
        error("sdraw does not yet support $(typeof(a)) — use vdraw for this plot type")
    end
    _fix_visual_attrs(l)
end

function _to_aog_drawable(layers::AlgebraOfGraphics.Layers)
    converted = map(_convert_single_layer, layers.layers)
    result = nothing
    for c in converted
        result = isnothing(result) ? c : result + c
    end
    result
end

"""
    sdraw(spec, path::AbstractString; kwargs...)

Render an AoG spec via AlgebraOfGraphics.draw → Makie → file.
Saves the figure to `path` (format inferred from extension) and returns
an `h.img` node pointing to `path`.

Requires a Makie backend (e.g. CairoMakie) to be loaded.

Extra `kwargs` are passed to `Makie.save` (e.g. `px_per_unit=2` for retina).
"""
function sdraw(spec, path::AbstractString; kwargs...)
    sdraw_file(spec, path; kwargs...)
    h.img(; src=path)
end

"""
    sdraw_file(spec, path::AbstractString; kwargs...)

Render an AoG spec to a file via AlgebraOfGraphics.draw → Makie.save.
Returns the path. Extra `kwargs` are passed to `Makie.save`.
"""
function sdraw_file(spec, path::AbstractString; kwargs...)
    drawable, cfg = _extract_drawable(spec)
    drawable = if drawable isa AlgebraOfGraphics.Layers
        _to_aog_drawable(drawable)
    elseif drawable isa AlgebraOfGraphics.Layer
        _convert_single_layer(drawable)
    else
        drawable
    end
    kw = _draw_kwargs(cfg; faceted=_is_faceted(drawable))
    fg = AlgebraOfGraphics.draw(drawable; figure=kw.figure, facet=kw.facet, axis=kw.axis)
    Makie.save(path, fg; kwargs...)
    path
end

# --- MIME show methods for notebook/Quarto support ---

Base.show(io::IO, ::MIME"text/html", spec::VegaSpec) = print(io, to_html(spec))
Base.show(io::IO, ::MIME"application/vnd.vegalite.v5+json", spec::VegaSpec) = print(io, to_json(spec))

# Also support raw Layer/Layers types
Base.show(io::IO, m::MIME"text/html", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"text/html", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))

end # module AlgebraOfVega
