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
using JSON, Tables, Statistics
using HTMX
import HTMX: h

# === @tic timer (for profiling hot paths) =====================================
# `@tic "label"` inside a function body prints elapsed ms since the previous
# `@tic` call. `@tic expr` wraps an expression and prints its timing.
_TIC_VERSION = 7
mutable struct Tic
    label::String
    _ns::UInt64
end
macro tic(arg)
    v = esc(:_tic_)
    file = String(__source__.file)
    line = __source__.line
    if arg isa String || (arg isa Expr && arg.head === :string)
        label = esc(arg)
        quote
            if $(Expr(:isdefined, v))
                _el = (time_ns() - $v._ns) / 1e6
                @warn "[v$(_TIC_VERSION)] $($v.label) — $($label): $(round(_el; digits=1))ms" _file=$file _line=$line
                $v._ns = time_ns()
            else
                $v = Tic($label, time_ns())
            end
        end
    else
        label_str = string(arg)
        expr = esc(arg)
        val = gensym(:tic_val)
        t0 = gensym(:tic_t0)
        el = gensym(:tic_el)
        quote
            $t0 = time_ns()
            $val = $expr
            $el = (time_ns() - $t0) / 1e6
            if $(Expr(:isdefined, v))
                @warn "[v$(_TIC_VERSION)] $($v.label) — $($label_str): $(round($el; digits=1))ms" _file=$file _line=$line
            else
                @warn "[v$(_TIC_VERSION)] $($label_str): $(round($el; digits=1))ms" _file=$file _line=$line
            end
            $val
        end
    end
end
# === end @tic =================================================================

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
export to_vegalite, to_json, to_html, to_node, vega_head, vega_controls
export vega_runtime, update_data, vega_cdn_urls, mapping_controls, resolve_channels, refine_channels, remap_node, auto_remap_node
export with_plot_caption, draws_summary_table

"""
    with_plot_caption(plot_node, caption; plot_id, kwargs...)

Wrap an AoV plot node (built via `to_node` or `auto_remap_node`) in a `<figure>`
with a caption header that includes a CSV-download button (and optionally a
lazy "Show data" details). Implementation lives in the
`AlgebraOfVegaHTMXObjectsExt` extension and requires `using HTMXObjects` to be
loaded; see that extension's docstring for the full kwargs.
"""
function with_plot_caption end

"""
    draws_summary_table(table; value, outcome, group_cols=Symbol[], ci_level=0.95, digits=2, caption=nothing, kwargs...)

Build a "median [lo, hi]" summary table from long-format draws data. Implementation
lives in the `AlgebraOfVegaHTMXObjectsExt` extension (requires `using HTMXObjects`).
"""
function draws_summary_table end

# Sanitize a user-supplied id so it is safe both as an HTML id attribute and
# as a CSS selector (querySelector('#'+id)). Dots, brackets, colons, etc. are
# valid HTML id chars but break CSS selector parsing — replace anything outside
# [A-Za-z0-9_-] with '-'. Idempotent (sanitized ids pass through unchanged).
_sanitize_id(id) = replace(string(id), r"[^A-Za-z0-9_-]" => "-")

# Introspect a spec for a draws-shaped analysis (PointInterval / GradientInterval
# / DotIntervalAnalysis) and return args for `draws_summary_table`, or `nothing`
# if the spec isn't a suitable candidate. Used by the `::VegaSpec` dispatch of
# `with_plot_caption` to auto-build a pretty summary table. Implemented later in
# this file once the analysis types and helpers are defined.
function _auto_summary_args end
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
- `scales` — an AoG `scales(...)` object, mirroring `draw(spec, scales(...))`. Currently
  translates X/Y/Z `scale=log`/`log2`/`log10`/`sqrt`/`identity` to VL scale types.
  Example: `config(scales=scales(Y=(; scale=log10)))`.
- `facet` — an AoG-style NamedTuple passed to `draw(; facet=...)`. `linkxaxes=:none` /
  `linkyaxes=:none` translate to VL `resolve.scale.<axis>="independent"`.
  Example: `config(facet=(; linkxaxes=:none, linkyaxes=:none))`.
- `axis` — an AoG-style NamedTuple passed to `draw(; axis=...)`. `limits=((xlo, xhi),
  (ylo, yhi))` (each side may be `nothing`) translates to VL `encoding[x/y].scale.domain`;
  `clamp=true` additionally sets `scale.clamp=true` on the limited axes (VL-only extension,
  stripped on the Makie path).
  Example: `config(axis=(; limits=((1, 100), nothing), clamp=true))`.
- `independent_scales` — **deprecated**: use `facet=(; linkxaxes=:none, linkyaxes=:none)`.

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
    mark_type in _COMPOSITE_MARKS && return true
    # Check sublayers for composite marks (e.g. layered boxplots)
    for sl in get(vl, "layer", [])
        sl isa Dict || continue
        sm = get(sl, "mark", nothing)
        st = sm isa String ? sm : sm isa Dict ? get(sm, "type", "") : ""
        st in _COMPOSITE_MARKS && return true
    end
    false
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
    vals = [
        Dict{String,Any}(string(k) => _vl_safe(v) for (k, v) in pairs(nt))
        for nt in rows
    ]
    Dict{String,Any}("values" => vals)
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
    detail_fields::Vector{Symbol}
end

struct GradientIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    point::Symbol
    detail_fields::Vector{Symbol}
end

struct LineRibbonAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    show_line::Bool
    detail_fields::Vector{Symbol}
end

struct PrecomputedRibbonAnalysis <: TidybayesAnalysis
    bands::Vector{Pair{Symbol,Symbol}}
    show_line::Bool
    detail_fields::Vector{Symbol}
end

struct DotIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    n_dots::Int
    point::Symbol
    detail_fields::Vector{Symbol}
end

"""
    pointinterval(; probs=[0.95, 0.8, 0.5], point=:median)

Nested credible intervals with varying stroke width + a point estimate.
Computes quantile summary in Julia, then generates layered rule + point marks.

    data(draws) * mapping(:value, y=:parameter) * pointinterval()
"""
pointinterval(; probs=[0.95, 0.8, 0.5], point=:median, detail=Symbol[]) =
    Layer(transformation=PointIntervalAnalysis(Float64.(probs), point, Symbol.(detail)))

"""
    gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median)

Nested credible intervals with uniform width and varying opacity + a point estimate.

    data(draws) * mapping(:value, y=:parameter) * gradient_interval()
"""
gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median, detail=Symbol[]) =
    Layer(transformation=GradientIntervalAnalysis(Float64.(probs), point, Symbol.(detail)))

"""
    lineribbon(; probs=[0.95, 0.8, 0.5])
    lineribbon(; bands=[:q025 => :q975, :q25 => :q75])

Uncertainty ribbons (area marks) + median line.

With `probs` (default): expects draw-level data. Groups by x, computes quantiles
of y across draws. Requires `group=:draw` in mapping.

    data(preds) * mapping(:x, :y, group=:draw) * lineribbon()

With `bands`: expects pre-aggregated data with quantile columns. The second
positional in mapping is the median column. Each band is a `lo => hi` pair,
outermost first.

    data(summary) * mapping(:x, :median => "Response") *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75])
"""
function lineribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[])
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, true, Symbol.(detail)))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), true, Symbol.(detail)))
end

"""
    ribbon(; probs=[0.95, 0.8, 0.5])
    ribbon(; bands=[:q025 => :q975, :q25 => :q75])

Uncertainty ribbons (area marks) without a median line.
Same as `lineribbon` but omits the central line. Accepts the same `bands`
kwarg for pre-aggregated data.

    data(preds) * mapping(:x, :y, group=:draw) * ribbon()
    data(summary) * mapping(:x, :median) * ribbon(bands=[:q025 => :q975])
"""
function ribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[])
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, false, Symbol.(detail)))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), false, Symbol.(detail)))
end

"""
    dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median)

Quantile dotplot with nested interval overlay.

    data(draws) * mapping(:value, y=:parameter) * dotinterval()
"""
dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median, detail=Symbol[]) =
    Layer(transformation=DotIntervalAnalysis(Float64.(probs), n_dots, point, Symbol.(detail)))

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

# --- Grouping helper + summary computation ---

# Single-pass O(n) grouping by key columns → Dict{key => Vector{Int}}.
# Function barrier: `_group_indices_impl` sees a concrete `Tuple` of columns,
# so the key `map` and dict ops specialize on actual eltypes instead of `Any`.
function _group_indices(columns::Vector{<:AbstractVector})
    isempty(columns) && return Dict{Tuple{}, Vector{Int}}()
    _group_indices_impl(Tuple(columns))
end

function _group_indices_impl(tcols::Tuple)
    n = length(first(tcols))
    K = Tuple{map(eltype, tcols)...}
    groups = Dict{K, Vector{Int}}()
    n == 0 && return groups
    sizehint!(groups, min(n, 1 << 16))
    # Cache the last seen (key, vector) so contiguous runs of identical keys
    # (common in time-series / draw-indexed data) skip the dict lookup entirely.
    @inbounds begin
        last_key = map(c -> c[1], tcols)
        last_vec = Int[1]
        groups[last_key] = last_vec
        for i in 2:n
            key = map(c -> c[i], tcols)
            if key == last_key
                push!(last_vec, i)
            else
                vec = get(groups, key, nothing)
                if vec === nothing
                    vec = Int[]
                    groups[key] = vec
                end
                push!(vec, i)
                last_key = key
                last_vec = vec
            end
        end
    end
    groups
end

function _key_columns(table; fields::Vector{String})
    cols = AbstractVector[]
    for f in fields
        push!(cols, Tables.getcolumn(table, Symbol(f)))
    end
    cols
end

function compute_interval_summary(table, x_field::String, group_field::Union{String,Nothing}, probs::Vector{Float64}, point::Symbol; color_field::Union{String,Nothing}=nothing, facet_fields::Vector{String}=String[], detail_fields::Vector{String}=String[])
    vals = Tables.getcolumn(table, Symbol(x_field))
    key_fields = String[f for f in [group_field, color_field, facet_fields..., detail_fields...] if !isnothing(f)]
    idx_groups = _group_indices(_key_columns(table; fields=key_fields))

    rows = Dict{String,Any}[]
    sizehint!(rows, length(idx_groups))
    for (key, idxs) in idx_groups
        v = sort!(vals[idxs])
        n = length(v)
        n == 0 && continue
        pt = point === :mean ? sum(v) / n : quantile(v, 0.5; sorted=true)
        row = Dict{String,Any}("__point__" => pt)
        ki = 0
        !isnothing(group_field) && (row[group_field] = key[ki += 1])
        !isnothing(color_field) && (row[color_field] = key[ki += 1])
        for ff in facet_fields
            row[ff] = key[ki += 1]
        end
        for ff in detail_fields
            row[ff] = key[ki += 1]
        end
        for prob in probs
            lo = (1 - prob) / 2
            row[_vl_prob_field("lo", prob)] = quantile(v, lo; sorted=true)
            row[_vl_prob_field("hi", prob)] = quantile(v, 1 - lo; sorted=true)
        end
        push!(rows, row)
    end
    rows
end

function compute_ribbon_summary(table, x_field::String, y_field::String, group_field::String, probs::Vector{Float64}; color_field::Union{String,Nothing}=nothing, facet_fields::Vector{String}=String[], detail_fields::Vector{String}=String[])
    xs = Tables.getcolumn(table, Symbol(x_field))
    ys = Tables.getcolumn(table, Symbol(y_field))
    key_fields = String[f for f in [x_field, color_field, facet_fields..., detail_fields...] if !isnothing(f)]
    kc = _key_columns(table; fields=key_fields)
    idx_groups = _group_indices(kc)

    # Precompute per-prob quantile field names + lo/hi fractions — these are
    # called O(groups × probs) times so must not re-allocate strings inside.
    lo_keys = String[_vl_prob_field("lo", p) for p in probs]
    hi_keys = String[_vl_prob_field("hi", p) for p in probs]
    lo_fracs = Float64[(1 - p) / 2 for p in probs]
    row_size = 2 + (color_field === nothing ? 0 : 1) +
               length(facet_fields) + length(detail_fields) + 2 * length(probs)

    Y = eltype(ys)
    buf = Vector{Y}(undef, 0)

    rows = Dict{String,Any}[]
    sizehint!(rows, length(idx_groups))
    for (key, idxs) in idx_groups
        ng = length(idxs)
        ng == 0 && continue
        # Gather + sort into a reusable buffer (avoids allocating ys[idxs] per group).
        resize!(buf, ng)
        @inbounds for k in 1:ng
            buf[k] = ys[idxs[k]]
        end
        sort!(buf)

        row = Dict{String,Any}()
        sizehint!(row, row_size)
        ki = 1
        row[x_field] = key[ki]
        row["__median__"] = quantile(buf, 0.5; sorted=true)
        if color_field !== nothing
            ki += 1
            row[color_field] = key[ki]
        end
        for ff in facet_fields
            ki += 1
            row[ff] = key[ki]
        end
        for ff in detail_fields
            ki += 1
            row[ff] = key[ki]
        end
        for j in eachindex(probs)
            lo = lo_fracs[j]
            row[lo_keys[j]] = quantile(buf, lo; sorted=true)
            row[hi_keys[j]] = quantile(buf, 1 - lo; sorted=true)
        end
        push!(rows, row)
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
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

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
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

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

function _ribbon_to_vl(
    summary::Vector{<:Dict{String}},
    x_field::String, x_label::String, y_label::String,
    median_col::String,
    band_cols::Vector{Tuple{String,String}};
    color_field::Union{String,Nothing}=nothing,
    color_label::Union{String,Nothing}=nothing,
    detail_fields::Vector{String}=String[],
    facet=nothing, show_line::Bool=true, is_sublayer::Bool=false,
    band_labels::Union{Vector{String},Nothing}=nothing
)
    summary_data = Dict{String,Any}("values" => summary)
    opacities = range(0.2, 0.6, length=length(band_cols))

    detail_enc = if !isempty(detail_fields)
        length(detail_fields) == 1 ?
            Dict{String,Any}("field" => detail_fields[1], "type" => "nominal") :
            [Dict{String,Any}("field" => f, "type" => "nominal") for f in detail_fields]
    else
        nothing
    end

    template_layers = Dict{String,Any}[]
    for (i, (lo_col, hi_col)) in enumerate(band_cols)
        x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
        x_label != x_field && (x_enc["title"] = x_label)
        enc = Dict{String,Any}(
            "x" => x_enc,
            "y" => Dict{String,Any}("field" => lo_col, "type" => "quantitative", "title" => y_label),
            "y2" => Dict{String,Any}("field" => hi_col),
        )
        !isnothing(detail_enc) && (enc["detail"] = deepcopy(detail_enc))
        mark = Dict{String,Any}("type" => "area", "opacity" => opacities[i], "line" => false)
        push!(template_layers, Dict{String,Any}("mark" => mark, "encoding" => enc, "_lr_layer" => true))
    end
    if show_line
        line_x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
        x_label != x_field && (line_x_enc["title"] = x_label)
        line_enc = Dict{String,Any}(
            "x" => line_x_enc,
            "y" => Dict{String,Any}("field" => median_col, "type" => "quantitative", "title" => y_label),
        )
        !isnothing(detail_enc) && (line_enc["detail"] = deepcopy(detail_enc))
        line_mark = Dict{String,Any}("type" => "line", "strokeWidth" => 2)
        push!(template_layers, Dict{String,Any}("mark" => line_mark, "encoding" => line_enc, "_lr_layer" => true))
    end

    layers = Dict{String,Any}[]
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        color_vals = sort(unique(row[color_field] for row in summary if haskey(row, color_field)))
        for gval in color_vals
            filter_expr = "datum[$(JSON.json(color_field))] === $(JSON.json(gval))"
            for tl in template_layers
                gl = deepcopy(tl)
                gl["transform"] = [Dict{String,Any}("filter" => filter_expr)]
                gl["encoding"]["color"] = copy(color_enc)
                push!(layers, gl)
            end
        end
    else
        append!(layers, template_layers)
    end

    widest_lo, widest_hi = band_cols[1]
    widest_label = isnothing(band_labels) ? "" : band_labels[1]
    lo_title = widest_label == "" ? widest_lo : "$(widest_label) lo"
    hi_title = widest_label == "" ? widest_hi : "$(widest_label) hi"
    tt = Dict{String,Any}[
        Dict{String,Any}("field" => x_field, "type" => "quantitative", "title" => x_label),
        Dict{String,Any}("field" => median_col, "type" => "quantitative", "title" => "median"),
    ]
    !isnothing(color_field) && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    push!(tt, Dict{String,Any}("field" => widest_lo, "type" => "quantitative", "title" => lo_title))
    push!(tt, Dict{String,Any}("field" => widest_hi, "type" => "quantitative", "title" => hi_title))
    _add_analysis_tooltips!(layers, tt)

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !isnothing(color_field)
        aov = get!(Dict{String,Any}, spec, "_aov")
        aov["lineribbon"] = Dict{String,Any}("templateLayers" => template_layers)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)

    detail_strs = string.(a.detail_fields)
    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    band_cols = Tuple{String,String}[(_vl_prob_field("lo", p), _vl_prob_field("hi", p)) for p in sorted_probs]
    band_labels = String["$(round(Int, p*100))%" for p in sorted_probs]

    _ribbon_to_vl(summary, x_field, x_label, y_label, "__median__", band_cols;
        color_field, color_label, detail_fields=detail_strs,
        facet, show_line=a.show_line, is_sublayer, band_labels)
end

function analysis_to_vl(a::PrecomputedRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : error("Pre-aggregated lineribbon requires at least one positional mapping (x)")
    x_label = _field_label(layer.positional[1])
    length(layer.positional) >= 2 || error("Pre-aggregated lineribbon requires a second positional mapping (median column)")
    median_col = _field_name(layer.positional[2])
    y_label = _field_label(layer.positional[2])
    haskey(layer.named, :group) && error("Pre-aggregated lineribbon (bands=...) should not have group= in mapping — data is already aggregated")
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)
    detail_strs = string.(a.detail_fields)

    col_names = Set(string.(Tables.columnnames(table)))
    median_col in col_names || error("Pre-aggregated lineribbon: median column \"$median_col\" not found in table. Available: $(sort(collect(col_names)))")
    for (lo, hi) in a.bands
        los, his = string(lo), string(hi)
        los in col_names || error("Pre-aggregated lineribbon: band column \"$los\" not found in table. Available: $(sort(collect(col_names)))")
        his in col_names || error("Pre-aggregated lineribbon: band column \"$his\" not found in table. Available: $(sort(collect(col_names)))")
    end

    summary = table_to_rows(table)
    band_cols = Tuple{String,String}[(string(first(b)), string(last(b))) for b in a.bands]

    _ribbon_to_vl(summary, x_field, x_label, y_label, median_col, band_cols;
        color_field, color_label, detail_fields=detail_strs,
        facet, show_line=a.show_line, is_sublayer)
end

function analysis_to_vl(a::DotIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, x_field, x_label, y_field, y_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer)
    detail_strs = string.(a.detail_fields)

    vals = Tables.getcolumn(table, Symbol(x_field))
    key_fields = String[f for f in [y_field, color_field, facet_fields..., detail_strs...] if !isnothing(f)]
    idx_groups = _group_indices(_key_columns(table; fields=key_fields))

    # Quantile dots
    dot_rows = Dict{String,Any}[]
    for (key, idxs) in idx_groups
        v = sort!(vals[idxs])
        n = length(v)
        ki_base = 0
        gk = isnothing(y_field) ? nothing : key[ki_base += 1]
        ck = isnothing(color_field) ? nothing : key[ki_base += 1]
        for i in 1:a.n_dots
            q = quantile(v, (i - 0.5) / a.n_dots; sorted=true)
            row = Dict{String,Any}("quantile" => q)
            !isnothing(gk) && (row[y_field] = gk)
            !isnothing(ck) && (row[color_field] = ck)
            ki = ki_base
            for ff in facet_fields
                row[ff] = key[ki += 1]
            end
            for ff in detail_strs
                row[ff] = key[ki += 1]
            end
            push!(dot_rows, row)
        end
    end

    summary = compute_interval_summary(table, x_field, y_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "value"
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
                            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
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
        color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
        density_transform = Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])
        if !isnothing(color_field)
            density_transform["groupby"] = [color_field]
        end

        encoding = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
            "y" => Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing),
        )
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            encoding["color"] = color_enc
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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
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

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
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

        band_x_enc = Dict{String,Any}("field" => "x", "type" => "quantitative")
        x_label != x_field && (band_x_enc["title"] = x_label)
        band_y_enc = Dict{String,Any}("field" => "y_lo", "type" => "quantitative")
        y_label != y_field && (band_y_enc["title"] = y_label)
        band_enc = Dict{String,Any}(
            "x" => band_x_enc,
            "y" => band_y_enc,
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            band_enc["color"] = color_enc
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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
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

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
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

        band_x_enc = Dict{String,Any}("field" => "x", "type" => "quantitative")
        x_label != x_field && (band_x_enc["title"] = x_label)
        band_y_enc = Dict{String,Any}("field" => "y_lo", "type" => "quantitative")
        y_label != y_field && (band_y_enc["title"] = y_label)
        band_enc = Dict{String,Any}(
            "x" => band_x_enc,
            "y" => band_y_enc,
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            band_enc["color"] = color_enc
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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative", "bin" => true)
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"

    x_enc = Dict{String,Any}("field" => x_field, "type" => "nominal")
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"

    x_enc = Dict{String,Any}("field" => x_field, "type" => "nominal")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "aggregate" => "mean", "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)

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
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    linestyle_field = haskey(layer.named, :linestyle) ? _field_name(layer.named[:linestyle]) : nothing
    linestyle_label = haskey(layer.named, :linestyle) ? _field_label(layer.named[:linestyle]) : nothing

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

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative", "sort" => "ascending")
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
        "y" => Dict{String,Any}("field" => "__ecdf__", "type" => "quantitative", "title" => "Cumulative Proportion"),
    )
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
    end
    if !isnothing(linestyle_field)
        ls_enc = Dict{String,Any}("field" => linestyle_field, "type" => "nominal")
        !isnothing(linestyle_label) && linestyle_label != linestyle_field && (ls_enc["title"] = linestyle_label)
        encoding["strokeDash"] = ls_enc
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
            x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "value"
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
                    "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
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

# --- AoG scales / facet sugar (mirrors AlgebraOfGraphics.draw(spec, scales(...); facet=...)) ---

"""Translate an AoG scale transform function to a VL `scale` object, or `nothing` if unsupported."""
function _aog_scale_fn_to_vl(f)
    f === identity && return nothing
    f === log10 && return Dict{String,Any}("type" => "log")
    f === log2 && return Dict{String,Any}("type" => "log", "base" => 2)
    f === log && return Dict{String,Any}("type" => "log", "base" => ℯ)
    f === sqrt && return Dict{String,Any}("type" => "sqrt")
    @warn "AlgebraOfVega: cannot translate scale function `$f` to a Vega-Lite scale; leaving axis untransformed. Supported: identity, log, log2, log10, sqrt." maxlog=1
    nothing
end

_aog_axis_key_to_vl_channel(k::Symbol) =
    k === :X ? "x" : k === :Y ? "y" : k === :Z ? "z" : nothing

"""Translate an AoG `Scales` object into a VL encoding-override dict (X/Y/Z scales only)."""
function _scales_to_encoding_override(sc::AlgebraOfGraphics.Scales)
    override = Dict{String,Any}()
    for (axis_key, props) in pairs(sc.dict)
        ch = _aog_axis_key_to_vl_channel(axis_key)
        isnothing(ch) && continue
        scale_fn = get(props, :scale, nothing)
        isnothing(scale_fn) && continue
        vl_scale = _aog_scale_fn_to_vl(scale_fn)
        isnothing(vl_scale) && continue
        override[ch] = Dict{String,Any}("scale" => vl_scale)
    end
    override
end

"""Merge a VL `resolve.scale` dict into `spec`, preserving any existing entries."""
function _merge_resolve_scale!(spec::Dict, resolve_scale::Dict)
    isempty(resolve_scale) && return
    resolve = get!(spec, "resolve", Dict{String,Any}())
    existing = get!(resolve, "scale", Dict{String,Any}())
    merge!(existing, resolve_scale)
end

"""Translate an AoG-style `facet=(; linkxaxes, linkyaxes)` NamedTuple into a VL `resolve.scale` dict."""
function _facet_nt_to_resolve_scale(nt)
    out = Dict{String,Any}()
    linkx = get(nt, :linkxaxes, nothing)
    linky = get(nt, :linkyaxes, nothing)
    (linkx === :none || linkx === false) && (out["x"] = "independent")
    (linky === :none || linky === false) && (out["y"] = "independent")
    out
end

"""
Translate an AoG-style `axis=(; limits=((xlo, xhi), (ylo, yhi)))` NamedTuple into a
VL encoding-override dict. `limits` entries may be `nothing` to skip an axis.
`clamp=true` adds `clamp: true` to every axis that has explicit limits.
"""
function _axis_nt_to_encoding_override(nt)
    override = Dict{String,Any}()
    limits = get(nt, :limits, nothing)
    (limits isa Tuple && length(limits) == 2) || return override
    do_clamp = get(nt, :clamp, false) === true
    for (idx, ch) in enumerate(("x", "y"))
        lim = limits[idx]
        (lim isa Tuple && length(lim) == 2) || continue
        scale_dict = Dict{String,Any}("domain" => [lim[1], lim[2]])
        do_clamp && (scale_dict["clamp"] = true)
        override[ch] = Dict{String,Any}("scale" => scale_dict)
    end
    override
end

function to_vegalite(v::VegaSpec)
    spec = to_vegalite(v.drawable)
    select_fields = nothing
    if !isnothing(v.config)
        props = v.config.properties
        # First pass: apply AoG-style sugar (scales, facet) so user-supplied
        # `encoding=Dict(...)` in the second pass can still override on conflict.
        if haskey(props, :scales) && props[:scales] isa AlgebraOfGraphics.Scales
            override = _scales_to_encoding_override(props[:scales])
            isempty(override) || _merge_encoding_config!(spec, override)
        end
        if haskey(props, :facet) && props[:facet] isa NamedTuple
            _merge_resolve_scale!(spec, _facet_nt_to_resolve_scale(props[:facet]))
        end
        if haskey(props, :axis) && props[:axis] isa NamedTuple
            override = _axis_nt_to_encoding_override(props[:axis])
            isempty(override) || _merge_encoding_config!(spec, override)
        end
        for (k, val) in props
            sk = string(k)
            # Deep-merge encoding so config adds to (not overwrites) auto-generated channels
            if sk == "encoding" && val isa Dict
                _merge_encoding_config!(spec, val)
            elseif sk in ("width", "height") && haskey(spec, "spec")
                # For faceted specs, width/height go into the inner spec
                spec["spec"][sk] = val
            elseif sk == "scales" && val isa AlgebraOfGraphics.Scales
                # Handled in first pass
            elseif sk == "facet" && val isa NamedTuple
                # Handled in first pass
            elseif sk == "axis" && val isa NamedTuple
                # Handled in first pass
            elseif sk == "independent_scales"
                @warn "AlgebraOfVega: `config(independent_scales=$(repr(val)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
                # Sugar for VL resolve: independent_scales=true, =:x, =(:x,:y)
                axes = if val === true
                    ["x", "y"]
                elseif val isa Symbol
                    [string(val)]
                else
                    [string(v) for v in val]
                end
                _merge_resolve_scale!(spec, Dict{String,Any}(ax => "independent" for ax in axes))
            elseif sk == "font_scale"
                # Scale all default VL font sizes by val
                fs = Float64(val)
                cfg = get!(spec, "config", Dict{String,Any}())
                ax = get!(cfg, "axis", Dict{String,Any}())
                ax["labelFontSize"] = round(Int, 10 * fs)
                ax["titleFontSize"] = round(Int, 11 * fs)
                lg = get!(cfg, "legend", Dict{String,Any}())
                lg["labelFontSize"] = round(Int, 10 * fs)
                lg["titleFontSize"] = round(Int, 11 * fs)
                hd = get!(cfg, "header", Dict{String,Any}())
                hd["labelFontSize"] = round(Int, 10 * fs)
                hd["titleFontSize"] = round(Int, 11 * fs)
                tt = get!(cfg, "title", Dict{String,Any}())
                tt["fontSize"] = round(Int, 13 * fs)
            elseif sk == "max_width"
                # Store max width in _aov for JS to cap responsive sizing
                aov = get!(spec, "_aov", Dict{String,Any}())
                aov["maxWidth"] = val
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
    is_composite = _is_composite_mark(spec)

    # Skip all interactivity for composite marks (boxplot, errorbar, errorband)
    # — VL doesn't support selections on them
    is_composite && return spec

    # Check for aggregate encodings (count, mean, etc.) — zoom can't project on those
    function _has_aggregate(enc_dict, ch)
        !isnothing(enc_dict) && haskey(enc_dict, ch) && enc_dict[ch] isa Dict &&
            haskey(enc_dict[ch], "aggregate")
    end

    # Find color field from top-level encoding only.
    # Legend binding doesn't work reliably for layered specs where color is only in sublayers.
    color_field = nothing
    if !isnothing(enc) && haskey(enc, "color") && enc["color"] isa Dict
        color_field = get(enc["color"], "field", nothing)
    end

    params = Dict{String,Any}[]

    # Zoom (scroll) + pan (drag) — only on quantitative non-aggregate axes
    zoom_encodings = String[]
    for ch in ("x", "y")
        is_quant = false
        has_agg = false
        if !isnothing(enc) && haskey(enc, ch)
            is_quant = get(enc[ch], "type", "") == "quantitative"
            has_agg = _has_aggregate(enc, ch)
        elseif !isnothing(sublayers)
            for sl in sublayers
                sl_enc = get(sl, "encoding", nothing)
                isnothing(sl_enc) && continue
                if haskey(sl_enc, ch) && get(sl_enc[ch], "type", "") == "quantitative"
                    is_quant = true
                    has_agg = _has_aggregate(sl_enc, ch)
                    break
                end
            end
        end
        is_quant && !has_agg && push!(zoom_encodings, ch)
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

    # Nearest-point tooltip for point marks only.
    # VL doesn't support "nearest" for line or area marks.
    if mark_type == "point" && !isnothing(enc) && haskey(enc, "tooltip")
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
    vega_head(; vega_version, vegalite_version, vega_embed_version, zoom)

Return a vector of `h.script`/`h.style` nodes to include in `htmx(; extra_head=vega_head())`.

`zoom` uniformly scales all plots (chart area, fonts, axes, legend). Responsive plots
are sized to `containerWidth / zoom` so they don't overflow their container.
"""
function vega_head(;
    vega_version=VEGA_VERSION,
    vegalite_version=VEGALITE_VERSION,
    vega_embed_version=VEGA_EMBED_VERSION,
    zoom=nothing,
    max_width=nothing,
    actions=nothing,
)
    nodes = [
        h.script(src="https://cdn.jsdelivr.net/npm/vega@$vega_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-embed@$vega_embed_version"),
        # Fix vega-embed actions SVG sizing when CSS frameworks (Pico) override defaults
        h.style("""
            details[title] > summary > svg { width: 14px !important; height: 14px !important; }
            .chart-wrapper { height: auto !important; }
        """),
        vega_runtime(),
    ]
    settings = Dict{String,Any}()
    !isnothing(zoom) && (settings["zoom"] = zoom)
    !isnothing(max_width) && (settings["maxWidth"] = max_width)
    !isnothing(actions) && (settings["defaultActions"] = actions)
    if !isempty(settings)
        !isnothing(zoom) && push!(nodes, h.style(".vega-embed { zoom: $zoom; }"))
        push!(nodes, h.script("window.AoV = Object.assign(window.AoV || {}, $(JSON.json(settings)));"))
    end
    nodes
end

"""
    vega_controls(; zoom=true, actions=true)

Return an `h.div` node with client-side controls for Vega plots:
- **Zoom ±**: adjust CSS zoom on all `.vega-embed` elements (like Bruno's sidebar controls)
- **Actions**: toggle visibility of Vega-Embed's action menu (⋯ button) on all plots

Drop this into a sidebar, header, or anywhere on the page:

    nav_sidebar(items)(vega_controls())
"""
function vega_controls(; zoom=true, actions=true)
    children = []
    if zoom
        push!(children, h.span(
            "Zoom ",
            h.a("−"; href="#", onclick="document.querySelectorAll('.vega-embed').forEach(e => e.style.zoom = (parseFloat(e.style.zoom||getComputedStyle(e).zoom||1) - 0.1).toFixed(1)); return false;"),
            " ",
            h.a("+"; href="#", onclick="document.querySelectorAll('.vega-embed').forEach(e => e.style.zoom = (parseFloat(e.style.zoom||getComputedStyle(e).zoom||1) + 0.1).toFixed(1)); return false;"),
        ))
    end
    if actions
        push!(children, h.label(; style="cursor:pointer;")(
            h.input(; type="checkbox", class="aov-actions-toggle",
                style="vertical-align:middle; margin-right:0.3em;",
                onchange="""
                var show = this.checked;
                var sheet = document.getElementById('aov-actions-hide');
                if (show) { if (sheet) sheet.disabled = true; }
                else { if (sheet) sheet.disabled = false; }
                window.AoV = window.AoV || {};
                window.AoV.defaultActions = show;
                """),
            "Actions",
        ))
        # Use a stylesheet to hide .vega-actions — works even for elements created later.
        # When defaultActions is already true (from vega_head), start with checkbox checked and sheet disabled.
        push!(children, h.script("""
            (function() {
                if (!document.getElementById('aov-actions-hide')) {
                    var s = document.createElement('style');
                    s.id = 'aov-actions-hide';
                    s.textContent = '.vega-actions { display: none !important; }';
                    document.head.appendChild(s);
                }
                var show = window.AoV && window.AoV.defaultActions;
                var sheet = document.getElementById('aov-actions-hide');
                if (show && sheet) sheet.disabled = true;
                var cb = document.querySelector('.aov-actions-toggle');
                if (cb) cb.checked = !!show;
            })();
        """))
    end
    h.div(; style="padding:0.5rem 0; font-size:0.75em; opacity:0.6; display:flex; gap:1em; align-items:center;")(children...)
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
        _origSpecs: {},

        _applyResponsiveWidth: function(id, spec) {
            var el = document.getElementById(id);
            if (!el) return spec;
            var containerWidth = el.parentElement ? el.parentElement.clientWidth : null;
            if (!containerWidth || containerWidth < 50) return spec;
            var zoom = (window.AoV && window.AoV.zoom) ? window.AoV.zoom : 1;
            containerWidth = Math.floor(containerWidth / zoom);
            var maxWidth = (spec._aov && spec._aov.maxWidth) || (window.AoV && window.AoV.maxWidth) || Infinity;
            containerWidth = Math.min(containerWidth, maxWidth);
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

            // Faceted (row-only, no columns) or layered specs: set width responsively
            if (spec._aov && !spec._aov.nFacetCols) {
                var w = containerWidth - padding;
                if (spec.spec) {
                    // Row-only faceted: set width on inner spec
                    spec.spec = Object.assign({}, spec.spec, {width: w});
                } else {
                    spec = Object.assign({}, spec, {width: w});
                }
                return spec;
            }

            return spec;
        },

        // ggplot-style "broadcast across all facet panels" pass.
        // AoV merges layered data into a single spec.data.values with a __src
        // discriminator column when outer faceting is needed. When a facet field
        // is absent from some rows (e.g. dose VLines that have no health column),
        // Vega-Lite renders them in an "undefined" facet panel.
        // This pass replicates each missing-field row across the unique values
        // of that field. Layer-level __src filters still route rows correctly.
        // Idempotent: rows that already have the field are untouched.
        _broadcastCrossSource: function(spec) {
            if (!spec || typeof spec !== 'object') return spec;
            var inner = (spec.spec && typeof spec.spec === 'object') ? spec.spec : null;

            // Collect partition fields from facet config AND color encodings
            var fields = [];
            var pushField = function(f) {
                if (f && f.field && fields.indexOf(f.field) === -1) fields.push(f.field);
            };
            if (spec.facet) { pushField(spec.facet.row); pushField(spec.facet.column); }
            // Also broadcast for color fields (cross-source layers need them too)
            var layers = inner && inner.layer ? inner.layer : (spec.layer || null);
            if (layers) {
                layers.forEach(function(l) {
                    if (l && l.encoding && l.encoding.color) pushField(l.encoding.color);
                });
            }
            if (!fields.length) return spec;

            // Find the data object whose values carry the merged rows
            var dataObj = null;
            if (spec.data && spec.data.values) dataObj = spec.data;
            else if (inner && inner.data && inner.data.values) dataObj = inner.data;
            if (!dataObj) return spec;
            var vals = dataObj.values;

            fields.forEach(function(field) {
                var uniques = [];
                var seen = {};
                for (var i = 0; i < vals.length; i++) {
                    var v = vals[i];
                    if (v && Object.prototype.hasOwnProperty.call(v, field)) {
                        var k = String(v[field]);
                        if (!seen[k]) { seen[k] = true; uniques.push(v[field]); }
                    }
                }
                if (!uniques.length) return;

                var newVals = [];
                for (var i = 0; i < vals.length; i++) {
                    var v = vals[i];
                    if (!v || Object.prototype.hasOwnProperty.call(v, field)) {
                        newVals.push(v);
                    } else {
                        for (var j = 0; j < uniques.length; j++) {
                            var nv = Object.assign({}, v);
                            nv[field] = uniques[j];
                            newVals.push(nv);
                        }
                    }
                }
                vals = newVals;
            });
            dataObj.values = vals;

            return spec;
        },

        embed: function(id, spec, opts) {
            opts = opts || {};
            if (window.AoV && window.AoV.defaultActions !== undefined) {
                opts = Object.assign({}, opts, {actions: window.AoV.defaultActions});
            }
            var self = this;
            // Store original spec for re-embed on resize and remapEncoding
            var origSpec = JSON.parse(JSON.stringify(spec));
            self._broadcastCrossSource(origSpec);
            self._origSpecs[id] = origSpec;
            var sized = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));

            var doEmbed = function() {
                var s = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));
                // Tag VL warnings/errors with the plot ID for easier debugging
                var _warn = console.warn, _error = console.error;
                console.warn = function() { var a = Array.from(arguments); a[0] = '[' + id + '] ' + a[0]; _warn.apply(console, a); };
                console.error = function() { var a = Array.from(arguments); a[0] = '[' + id + '] ' + a[0]; _error.apply(console, a); };
                return vegaEmbed('#' + id, s, opts).then(function(result) {
                    console.warn = _warn; console.error = _error;
                    self.views[id] = result.view;
                    if (self._pending[id]) {
                        self._pending[id].forEach(function(p) {
                            self.onSignal(id, p.signal, p.callback);
                        });
                        delete self._pending[id];
                    }
                    return result;
                }).catch(function(err) { console.warn = _warn; console.error = _error; _error.call(console, '[' + id + ']', err); });
            };

            // Set up resize observer for responsive re-embed (only for _aov-marked specs)
            if (spec._aov) {
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

        // --- Plot data download / inline preview ---
        // Read inline data from a plot's view; returns array of objects.
        // Tries the named source first, falls back to common VL conventions.
        _plotData: function(id, name) {
            var view = this.views[id];
            if (!view) return null;
            name = name || 'source_0';
            try { return view.data(name); } catch (e) { /* fall through */ }
            // Fallback: enumerate runtime data, return first non-empty array
            try {
                var runtime = view._runtime && view._runtime.data;
                if (runtime) {
                    for (var k in runtime) {
                        try {
                            var d = view.data(k);
                            if (Array.isArray(d) && d.length) return d;
                        } catch (e) {}
                    }
                }
            } catch (e) {}
            return null;
        },

        // Split rows by a discriminator column (e.g. "__src" for multi-source layered specs).
        // Returns [{label, rows}, ...]. If no rows have the column, returns [{label: null, rows}].
        _splitBySource: function(rows, col) {
            col = col || '__src';
            if (!rows || !rows.length) return [{label: null, rows: rows || []}];
            var hasCol = rows.some(function(r) { return r && Object.prototype.hasOwnProperty.call(r, col); });
            if (!hasCol) return [{label: null, rows: rows}];
            var groups = {};
            var order = [];
            rows.forEach(function(r) {
                var v = r && r[col];
                var k = v === undefined ? '__none__' : String(v);
                if (!groups[k]) { groups[k] = []; order.push(k); }
                // Drop the discriminator from the exported row
                var clean = {};
                for (var f in r) { if (f !== col) clean[f] = r[f]; }
                groups[k].push(clean);
            });
            return order.map(function(k) {
                return {label: k === '__none__' ? null : k, rows: groups[k]};
            });
        },

        _csvEscape: function(s) {
            s = (s === null || s === undefined) ? '' : String(s);
            return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
        },

        _rowsToCsv: function(rows) {
            if (!rows || !rows.length) return '';
            var cols = Object.keys(rows[0]);
            var self = this;
            var header = cols.map(self._csvEscape).join(',');
            var body = rows.map(function(r) {
                return cols.map(function(c) { return self._csvEscape(r[c]); }).join(',');
            }).join('\n');
            return header + '\n' + body;
        },

        _triggerDownload: function(text, filename, mime) {
            var blob = new Blob([text], {type: (mime || 'text/csv') + ';charset=utf-8;'});
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url; a.download = filename;
            document.body.appendChild(a); a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        },

        // Public: download the plot's data as CSV. Splits by `__src` if present.
        // labels: optional {srcValue: humanLabel} override map.
        downloadPlotData: function(id, filenameBase, labels) {
            filenameBase = filenameBase || id;
            labels = labels || {};
            var rows = this._plotData(id);
            if (!rows) { console.warn('AoV.downloadPlotData: no data for', id); return; }
            var groups = this._splitBySource(rows);
            var self = this;
            groups.forEach(function(g) {
                var label = g.label === null ? '' : '_' + (labels[g.label] || g.label).replace(/[^A-Za-z0-9_-]+/g, '_');
                var fname = filenameBase + label + '.csv';
                self._triggerDownload(self._rowsToCsv(g.rows), fname);
            });
        },

        // Public: download the plot as a PNG/SVG image via vega view.toImageURL.
        downloadPlotImage: function(id, format, filenameBase) {
            filenameBase = filenameBase || id;
            format = (format || 'png').toLowerCase();
            var view = this.views[id];
            if (!view) { console.warn('AoV.downloadPlotImage: no view for', id); return; }
            view.toImageURL(format).then(function(url) {
                var a = document.createElement('a');
                a.href = url; a.download = filenameBase + '.' + format;
                document.body.appendChild(a); a.click();
                document.body.removeChild(a);
            }).catch(function(err) {
                console.warn('AoV.downloadPlotImage failed:', err);
            });
        },

        // Public: render the plot's data as sortable HTML table(s) into `container`.
        // Builds lazily — call from the <details> "toggle" event.
        showPlotData: function(id, container, labels) {
            labels = labels || {};
            if (container.dataset.aovRendered === '1') return;
            var rows = this._plotData(id);
            if (!rows) { container.textContent = '(no data available)'; container.dataset.aovRendered = '1'; return; }
            var groups = this._splitBySource(rows);
            container.innerHTML = '';
            var self = this;
            groups.forEach(function(g) {
                if (g.label !== null) {
                    var h = document.createElement('h6');
                    h.textContent = labels[g.label] || g.label;
                    h.style.margin = '0.5rem 0 0.25rem';
                    container.appendChild(h);
                }
                container.appendChild(self._buildSortableTable(g.rows));
            });
            container.dataset.aovRendered = '1';
        },

        _buildSortableTable: function(rows) {
            var table = document.createElement('table');
            table.className = 'striped';
            table.setAttribute('role', 'grid');
            if (!rows || !rows.length) {
                table.innerHTML = '<tbody><tr><td>(empty)</td></tr></tbody>';
                return table;
            }
            var rawCols = Object.keys(rows[0]);
            var stringCols = [], numericCols = [];
            rawCols.forEach(function(c) {
                var isNumeric = false;
                for (var i = 0; i < rows.length; i++) {
                    var v = rows[i][c];
                    if (v === null || v === undefined || v === '') continue;
                    isNumeric = (typeof v === 'number');
                    break;
                }
                (isNumeric ? numericCols : stringCols).push(c);
            });
            stringCols.sort();
            numericCols.sort();
            var cols = stringCols.concat(numericCols);
            var thead = document.createElement('thead');
            var trh = document.createElement('tr');
            cols.forEach(function(c, i) {
                var th = document.createElement('th');
                th.textContent = c;
                th.style.cursor = 'pointer';
                th.onclick = function() {
                    if (typeof window.sortTable === 'function') window.sortTable(i, th);
                };
                trh.appendChild(th);
            });
            thead.appendChild(trh);
            table.appendChild(thead);
            var tbody = document.createElement('tbody');
            rows.forEach(function(r) {
                var tr = document.createElement('tr');
                cols.forEach(function(c) {
                    var td = document.createElement('td');
                    var v = r[c];
                    td.textContent = (v === null || v === undefined) ? '' : String(v);
                    tr.appendChild(td);
                });
                tbody.appendChild(tr);
            });
            table.appendChild(tbody);
            return table;
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
        },

        // Client-side encoding remapping: swap color/row/column fields without server round-trip
        remapEncoding: function(id, mapping) {
            var orig = this._origSpecs[id];
            if (!orig) { console.warn('AoV.remapEncoding: no stored spec for', id); return; }
            var spec = JSON.parse(JSON.stringify(orig));

            // If combo data was pre-built by the caller (multi-select picker),
            // inject it into the cloned spec so combos are available to all channels
            if (mapping._comboData && mapping._comboData.values) {
                if (spec.data && spec.data.values) spec.data = mapping._comboData;
                else if (spec.spec && spec.spec.data) spec.spec.data = mapping._comboData;
            }

            // Find layers in either simple or faceted structure
            var isFaceted = !!(spec.facet || (spec.spec && spec.spec.layer));
            var layers = isFaceted ? (spec.spec && spec.spec.layer || []) : (spec.layer || [spec]);

            // Migrate encoding-based row/column to facet key structure
            // (encoding.row/column is VL inline faceting that conflicts with facet key)
            function _migrateEncodingFacets() {
                var enc = spec.encoding || (spec.spec && spec.spec.encoding);
                if (!enc) {
                    // Check sublayer encodings
                    layers.forEach(function(l) {
                        if (!l.encoding) return;
                        ['row', 'column'].forEach(function(ch) {
                            if (l.encoding[ch]) {
                                if (!isFaceted) { wrapFaceted(); }
                                spec.facet = spec.facet || {};
                                spec.facet[ch] = spec.facet[ch] || l.encoding[ch];
                                delete l.encoding[ch];
                            }
                        });
                    });
                    return;
                }
                ['row', 'column'].forEach(function(ch) {
                    if (enc[ch]) {
                        if (!isFaceted) { wrapFaceted(); }
                        spec.facet = spec.facet || {};
                        spec.facet[ch] = spec.facet[ch] || enc[ch];
                        delete enc[ch];
                    }
                });
            }
            _migrateEncodingFacets();

            // Resolve combo titles for human-readable legend/facet headers
            var _titles = mapping._comboTitles || {};
            function _fieldTitle(f) { return _titles[f] || f; }

            // Color remapping
            if ('color' in mapping) {
                var cf = mapping.color;
                var lrMeta = orig._aov && orig._aov.lineribbon;
                if (lrMeta && lrMeta.templateLayers) {
                    // Lineribbon per-group layering: rebuild layers from template
                    var tmpl = lrMeta.templateLayers;
                    var newLayers = [];
                    // When the spec uses merged data (with __src filters added by
                    // layers_to_vl), the rebuilt LR layers must inherit the same
                    // __src filter so they don't render rows from other sources.
                    var srcFilter = null;
                    for (var li = 0; li < layers.length; li++) {
                        var lll = layers[li];
                        if (lll && lll._lr_layer && Array.isArray(lll.transform)) {
                            for (var ti = 0; ti < lll.transform.length; ti++) {
                                var tf = lll.transform[ti];
                                if (tf && typeof tf.filter === 'string' && tf.filter.indexOf('__src') !== -1) {
                                    srcFilter = tf;
                                    break;
                                }
                            }
                            if (srcFilter) break;
                        }
                    }
                    if (cf) {
                        // Get unique values of the new color field from data
                        var vals = spec.data && spec.data.values || [];
                        var seen = {}; var groups = [];
                        vals.forEach(function(r) {
                            var v = r[cf];
                            if (v !== undefined && !seen[v]) { seen[v] = true; groups.push(v); }
                        });
                        groups.sort();
                        groups.forEach(function(gval) {
                            var filterExpr = 'datum[' + JSON.stringify(cf) + '] === ' + JSON.stringify(gval);
                            tmpl.forEach(function(tl) {
                                var gl = JSON.parse(JSON.stringify(tl));
                                gl.transform = srcFilter ? [srcFilter, {filter: filterExpr}] : [{filter: filterExpr}];
                                gl.encoding.color = {field: cf, type: 'nominal', title: _fieldTitle(cf)};
                                gl._lr_layer = true;
                                newLayers.push(gl);
                            });
                        });
                    } else {
                        // No color: use template layers as-is (with __src filter if any)
                        tmpl.forEach(function(tl) {
                            var gl = JSON.parse(JSON.stringify(tl));
                            if (srcFilter) gl.transform = [srcFilter];
                            gl._lr_layer = true;
                            newLayers.push(gl);
                        });
                    }
                    // Preserve non-lineribbon layers (e.g. cross-source dose VLines)
                    // and replace only the tagged lineribbon layers.
                    var preserved = layers.filter(function(l) { return !(l && l._lr_layer); });
                    var allLayers = preserved.concat(newLayers);
                    if (isFaceted) {
                        spec.spec.layer = allLayers;
                    } else {
                        spec.layer = allLayers;
                    }
                    layers = allLayers;
                } else {
                    // Non-lineribbon: standard color remapping. Skip layers
                    // whose mark statically sets `color` — those layers were
                    // intentionally given a fixed color (e.g. black observation
                    // scatters) and should not be data-driven by the picker.
                    layers.forEach(function(l) {
                        if (!l.encoding) return;
                        var staticColor = l.mark && typeof l.mark === 'object' && l.mark.color;
                        if (staticColor) return;
                        if (cf) {
                            l.encoding.color = {field: cf, type: 'nominal', title: _fieldTitle(cf)};
                        } else {
                            delete l.encoding.color;
                        }
                        // Sync tooltips: remove old color entries, add new
                        if (Array.isArray(l.encoding.tooltip)) {
                            l.encoding.tooltip = l.encoding.tooltip.filter(function(t) {
                                return t.type !== 'nominal' || t.field === (spec.facet && spec.facet.row && spec.facet.row.field) ||
                                       t.field === (spec.facet && spec.facet.column && spec.facet.column.field);
                            });
                            if (cf) l.encoding.tooltip.push({field: cf, type: 'nominal'});
                        }
                    });
                }
            }

            // Count unique values for a field in the data (for nFacetCols hint)
            function countUnique(field) {
                var vals = spec.data && spec.data.values;
                if (!vals) return 1;
                var seen = {};
                vals.forEach(function(r) { if (r[field] !== undefined) seen[r[field]] = true; });
                return Math.max(Object.keys(seen).length, 1);
            }

            // Helper: wrap a non-faceted spec into faceted structure
            function wrapFaceted() {
                if (isFaceted) return;
                if (spec.layer) {
                    spec.spec = {layer: spec.layer};
                    delete spec.layer;
                } else {
                    // Single-view spec: move mark+encoding into spec.spec
                    var inner = {};
                    ['mark', 'encoding', 'transform', 'selection', 'params'].forEach(function(k) {
                        if (spec[k] !== undefined) { inner[k] = spec[k]; delete spec[k]; }
                    });
                    spec.spec = inner;
                }
                spec.facet = {};
                // Remove single-view-only properties from outer spec
                delete spec.width;
                delete spec.autosize;
                // Add _aov hint for responsive faceted sizing
                spec._aov = spec._aov || {};
                isFaceted = true;
                layers = spec.spec.layer || [spec.spec];
            }

            // Helper: unwrap faceted spec back to flat
            function unwrapFaceted() {
                if (!spec.facet) return;
                if (spec.facet.column || spec.facet.row) return;
                var inner = spec.spec || {};
                if (inner.layer) {
                    spec.layer = inner.layer;
                } else {
                    // Restore single-view keys
                    Object.keys(inner).forEach(function(k) { spec[k] = inner[k]; });
                }
                delete spec.spec;
                delete spec.facet;
                if (!spec.layer) {
                    // Single-view: use VL native responsive width
                    spec.width = 'container';
                    spec.autosize = {type: 'fit', contains: 'padding'};
                    delete spec._aov;
                } else {
                    // Layered: use _aov marker for JS responsive sizing
                    spec._aov = {};
                }
                isFaceted = false;
                layers = spec.layer || [spec];
            }

            // Row facet remapping
            if ('row' in mapping) {
                var rf = mapping.row;
                if (rf) {
                    wrapFaceted();
                    spec.facet.row = {field: rf, type: 'nominal', title: _fieldTitle(rf)};
                } else if (spec.facet) {
                    delete spec.facet.row;
                    unwrapFaceted();
                }
            }

            // Column facet remapping
            if ('column' in mapping) {
                var clf = mapping.column;
                if (clf) {
                    wrapFaceted();
                    spec.facet.column = {field: clf, type: 'nominal', title: _fieldTitle(clf)};
                } else if (spec.facet) {
                    delete spec.facet.column;
                    unwrapFaceted();
                }
            }

            // Update _aov.nFacetCols for responsive sizing
            if (isFaceted && spec._aov && spec.facet) {
                if (spec.facet.column) {
                    spec._aov.nFacetCols = countUnique(spec.facet.column.field);
                } else {
                    delete spec._aov.nFacetCols;
                }
            }

            // Detail encoding: put explicitly-specified dimension fields into detail
            // so VL groups by them without assigning visual properties.
            // With the multi-select picker, _dimensions is the resolved detail
            // channel contents (no set subtraction needed).
            if (mapping._dimensions) {
                var detailFields = mapping._dimensions;
                layers.forEach(function(l) {
                    if (!l.encoding) return;
                    if (detailFields.length > 0) {
                        l.encoding.detail = detailFields.length === 1 ?
                            {field: detailFields[0], type: 'nominal'} :
                            detailFields.map(function(f) { return {field: f, type: 'nominal'}; });
                    } else {
                        delete l.encoding.detail;
                    }
                });
            }

            // Re-broadcast cross-source layers after row/column/color mutations
            this._broadcastCrossSource(spec);

            // Re-embed, but preserve the TRUE original spec
            var savedOrig = this._origSpecs[id];
            this.embed(id, spec);
            this._origSpecs[id] = savedOrig;
        }
    };
    """)
end

"""
    _layer_array(vl::Dict)

Return the mutable layer array of a (possibly faceted) Vega-Lite spec, or `nothing`
if the spec is single-view. Faceted specs nest layers under `spec.spec.layer`; flat
specs use `spec.layer`.
"""
function _layer_array(vl::Dict)
    if haskey(vl, "spec") && vl["spec"] isa Dict && haskey(vl["spec"], "layer")
        return vl["spec"]["layer"]
    elseif haskey(vl, "layer")
        return vl["layer"]
    end
    return nothing
end

"""
    _facet_fields(vl::Dict)

Return the list of partition field names declared on a Vega-Lite spec via
`facet.row/column`, top-level `encoding.row/column`, or sublayer `encoding.row/column`.
"""
function _facet_fields(vl::Dict)
    fields = String[]
    facet = get(vl, "facet", nothing)
    if facet isa Dict
        for ch in ("row", "column")
            f = get(facet, ch, nothing)
            if f isa Dict && haskey(f, "field")
                push!(fields, f["field"])
            end
        end
    end
    enc = get(vl, "encoding", nothing)
    if enc isa Dict
        for ch in ("row", "column")
            f = get(enc, ch, nothing)
            if f isa Dict && haskey(f, "field")
                push!(fields, f["field"])
            end
        end
    end
    layers = _layer_array(vl)
    if layers !== nothing
        for l in layers
            le = get(l, "encoding", nothing)
            le isa Dict || continue
            for ch in ("row", "column", "color")
                f = get(le, ch, nothing)
                if f isa Dict && haskey(f, "field")
                    push!(fields, f["field"])
                end
            end
        end
    end
    unique(fields)
end

"""
    _broadcast_cross_source_layers!(vl::Dict)

ggplot-style "broadcast across all facet panels". AoV merges layered data into a
single `spec.data.values` with a `__src` discriminator column when outer faceting
is needed (see `layers_to_vl`). When a facet field is absent from some rows
(typically annotation/overlay layers like dose VLines that have no health/vessel
columns), Vega-Lite renders them in an "undefined" facet panel.

This pass replicates each row that lacks the facet field across the unique values
of that field, so every cross-source row appears in every facet panel. Layer-level
`__src` filters still route rows to the correct mark, so replication is safe.

Idempotent: rows that already contain the field are untouched, so caller-side
replication keeps working unchanged.
"""
function _broadcast_cross_source_layers!(vl::Dict)
    fields = _facet_fields(vl)
    isempty(fields) && return vl

    # Find the data object whose `values` carry the merged rows. May be at the
    # outer spec or, for faceted layouts, at `spec.spec.data`.
    data_obj = nothing
    if haskey(vl, "data") && vl["data"] isa Dict && haskey(vl["data"], "values")
        data_obj = vl["data"]
    elseif haskey(vl, "spec") && vl["spec"] isa Dict
        inner = vl["spec"]
        if haskey(inner, "data") && inner["data"] isa Dict && haskey(inner["data"], "values")
            data_obj = inner["data"]
        end
    end
    data_obj === nothing && return vl
    vals = data_obj["values"]
    vals isa AbstractVector || return vl

    for field in fields
        # Collect unique values from rows that already have this field
        uniques = Any[]
        seen = Set{Any}()
        for v in vals
            if v isa Dict && haskey(v, field)
                u = v[field]
                if !(u in seen)
                    push!(seen, u)
                    push!(uniques, u)
                end
            end
        end
        isempty(uniques) && continue

        new_vals = Vector{Any}()
        for v in vals
            if !(v isa Dict) || haskey(v, field)
                push!(new_vals, v)
            else
                for u in uniques
                    nv = copy(v)
                    nv[field] = u
                    push!(new_vals, nv)
                end
            end
        end
        vals = new_vals
    end
    data_obj["values"] = vals
    vl
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
        # Detect faceting: explicit facet key, nested spec, or row/column encoding channels
        _enc = get(vl, "encoding", Dict())
        _enc = _enc isa Dict ? _enc : Dict()
        has_enc_facet = haskey(_enc, "row") || haskey(_enc, "column")
        is_faceted = haskey(vl, "facet") || haskey(vl, "spec") || has_enc_facet
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
    _broadcast_cross_source_layers!(vl)
    json = JSON.json(vl)
    id = _sanitize_id(something(id, "vega-" * string(abs(hash(json)), base=16)))

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
    id = _sanitize_id(id)
    rows = Tables.rowtable(table)
    data = [Dict{String,Any}(string(k) => v for (k, v) in pairs(nt)) for nt in rows]
    json = JSON.json(data)
    h.script("AoV.updateData('$id', $json, '$name');")
end

"""
    mapping_controls(id, dimensions; color_default="", row_default="", column_default="", channels=[:color, :row])

Client-side dropdowns that remap encoding channels on an already-rendered plot.
Calls `AoV.remapEncoding(id, {color: ..., row: ...})` — no server round-trip.

- `id`: must match the `id` kwarg passed to `to_node(spec; id=...)`
- `dimensions`: vector of `Pair{String,String}` (field => label) or bare strings/symbols
- `channels`: which encoding channels to show editable dropdowns for (default `[:color, :row, :column]`)
- `fixed`: `Dict` of channel => field that are always applied but not user-editable (e.g. `Dict(:column => :quantity)`)

## Example
```julia
id = "my-plot"
h.div()(
    mapping_controls(id, [:origin => "Origin", :cylinders => "Cylinders"];
        color_default="origin", fixed=Dict(:column => :cylinders)),
    to_node(data(df) * mapping(:x, :y, color=:origin, col=:cylinders) * visual(Scatter); id=id),
)
```
"""
const _CHANNEL_LABELS = Dict("color" => "Color", "row" => "Row", "column" => "Column", "detail" => "Ungrouped")

"""
    mapping_controls(id, dimensions; kwargs...)

Client-side multi-select mapping picker for Vega-Lite encoding channels.

Each channel (color, row, column, ungrouped/detail) is a multi-select. When 2+
fields are selected for one channel, a synthetic combo column is built on
`spec.data.values`. One channel is always "pinned" — the catch-all that
auto-absorbs any dims not in another channel. The pinned channel's select is
disabled; its contents are computed.

## Keyword arguments
- `id`: must match the `id` kwarg passed to `to_node(spec; id=...)`
- `dimensions`: vector of `Pair{String,String}` (field => label) or bare strings/symbols
- `color_default`, `row_default`, `column_default`, `detail_default`: initial selections (vector or single string)
- `channels`: which channels to show (default `[:color, :row, :column, :detail]`)
- `pinned`: which channel is the catch-all (default `:color`)
- `fixed`: `Dict` of channel => field(s) that are always applied but not user-editable
- `table`: optional table for field validation
- `spec`: optional AoG spec — if provided, validates that all dimension fields survive into the VL data (warns if a field was dropped during AoG summary)
"""

"""
    resolve_channels(dimensions; color_default, row_default, column_default, detail_default, pinned, fixed, channels)

Compute which dimension field maps to which visual channel, returning kwargs
ready to splice into `mapping()` and `lineribbon()`. This is the single source
of truth for channel resolution — both `mapping_controls` and server-side spec
construction should use this.

Returns a NamedTuple with:
- `color_kw`: NamedTuple to splat into `mapping(; color_kw...)`
- `row_kw`: NamedTuple to splat into `mapping(; row_kw...)`
- `column_kw`: NamedTuple to splat into `mapping(; column_kw...)`  (from non-fixed column defaults)
- `fixed_kw`: NamedTuple to splat into `mapping(; fixed_kw...)` (from fixed channels)
- `detail`: `Vector{Symbol}` for `lineribbon(; detail)`
- `color_fields`, `row_fields`, `column_fields`, `detail_fields`: raw field name vectors
- `dim_label_map`: `Dict{String,String}` field → human label
- `dims`: filtered dimension pairs
- `defaults`: `Dict{String,Vector{String}}` channel → field names (including pinned auto-fill)
"""
function resolve_channels(dimensions;
    color_default=String[], row_default=String[], column_default=String[], detail_default=String[],
    channels=[:color, :row, :column, :detail],
    pinned::Symbol=:color,
    fixed=Dict{Symbol,Any}())

    _norm(v) = v isa AbstractVector ? string.(v) : (v == "" || isnothing(v) ? String[] : [string(v)])
    color_default = _norm(color_default)
    row_default = _norm(row_default)
    column_default = _norm(column_default)
    detail_default = _norm(detail_default)
    defaults = Dict("color" => color_default, "row" => row_default,
                     "column" => column_default, "detail" => detail_default)

    dims = [(d isa Pair ? (string(first(d)) => string(last(d))) : (string(d) => string(d))) for d in dimensions]

    # Normalize fixed
    fixed_norm = Dict{String,Vector{String}}()
    for (k, v) in fixed
        fixed_norm[string(k)] = v isa AbstractVector ? string.(v) : [string(v)]
    end

    # Auto-add fixed fields to dims if not already present
    dim_fields = Set(first.(dims))
    for fs in values(fixed_norm)
        for f in fs
            if !(f in dim_fields)
                push!(dims, f => join(uppercasefirst.(split(f, "_")), " "))
                push!(dim_fields, f)
            end
        end
    end

    # Editable channels (not fixed)
    editable = [ch for ch in channels if !haskey(fixed_norm, string(ch))]

    # Label lookup
    dim_label_map = Dict(first(d) => last(d) for d in dims)
    _pretty(f) = get(dim_label_map, f, join(uppercasefirst.(split(f, "_")), " "))

    # Pinned channel absorbs all unassigned dims
    pinned_str = string(pinned)
    assigned_elsewhere = Set{String}()
    for ch in editable
        ch_str = string(ch)
        ch_str == pinned_str && continue
        for f in get(defaults, ch_str, String[])
            push!(assigned_elsewhere, f)
        end
    end
    for fs in values(fixed_norm)
        for f in fs; push!(assigned_elsewhere, f); end
    end
    defaults[pinned_str] = [first(d) for d in dims if !(first(d) in assigned_elsewhere)]

    # Build kwargs for a channel's field list.
    # AoG mapping() uses :col (not :column) for column faceting.
    _aog_key(ch) = ch == :column ? :col : ch
    function _channel_kw(ch_sym, fields)
        isempty(fields) && return (;)
        k = _aog_key(ch_sym)
        if length(fields) == 1
            return (; k => Symbol(fields[1]) => _pretty(fields[1]))
        end
        combo = Symbol("__aov_$(ch_sym)")
        combo_label = join([_pretty(f) for f in fields], " / ")
        return (; k => combo => combo_label)
    end

    color_fields = get(defaults, "color", String[])
    row_fields = get(defaults, "row", String[])
    column_fields = get(defaults, "column", String[])
    detail_fields = get(defaults, "detail", String[])

    color_kw = _channel_kw(:color, color_fields)
    row_kw = _channel_kw(:row, row_fields)
    column_kw = _channel_kw(:column, column_fields)
    detail = Symbol.(detail_fields)

    # When a channel uses a combo (2+ fields), the individual fields must also
    # appear in detail so they survive the AoG summary into the VL spec data.
    # (The combo column carries the visual encoding; detail preserves the components.)
    for fields in (color_fields, row_fields, column_fields)
        length(fields) > 1 && for f in fields
            s = Symbol(f)
            s in detail || push!(detail, s)
        end
    end

    # Fixed channels → kwargs
    fixed_kw_parts = NamedTuple[]
    for (ch_str, fs) in fixed_norm
        ch_sym = Symbol(ch_str)
        ch_sym in (:color, :row, :column) || continue  # detail handled differently
        kw = _channel_kw(ch_sym, fs)
        push!(fixed_kw_parts, kw)
    end
    # Also add fixed detail fields
    if haskey(fixed_norm, "detail")
        append!(detail, Symbol.(fixed_norm["detail"]))
    end
    fixed_kw = isempty(fixed_kw_parts) ? (;) : merge(fixed_kw_parts...)

    (; color_kw, row_kw, column_kw, fixed_kw, detail,
       color_fields, row_fields, column_fields, detail_fields,
       dim_label_map, dims, defaults, fixed=fixed_norm, pinned, channels)
end

"""
    apply_combo!(df, fields, combo_col=:__aov_combo)

Build a synthetic combo column on `df` by joining values of `fields` with " / ".
No-op if `length(fields) <= 1`. **Silently skips entirely if any field is
missing from `df`** — leaving the combo column unset on this layer so the
downstream cross-source broadcast pass can replicate the layer across every
unique combo value (this is how secondary layers like dose VLines or
observation scatters fan out across model facets). Returns `df`.
"""
function apply_combo!(df, fields, combo_col=:__aov_combo)
    length(fields) <= 1 && return df
    syms = Symbol.(fields)
    all(s -> hasproperty(df, s), syms) || return df
    df[!, combo_col] = [join([string(r[s]) for s in syms], " / ") for r in eachrow(df)]
    df
end

"""
    apply_combos!(df, resolved)

Build all synthetic combo columns (`__aov_color`, `__aov_row`, `__aov_column`)
on `df` for the channels in `resolved`. Per-layer: each channel's combo column
is built only if `df` has every component field; otherwise it's silently
skipped so the broadcast pass replicates the layer.

Returns `df`. **Does not refine `resolved`** — for global stripping of
absent / single-valued dims (which fixes static-render labels and the picker
catch-all), call `refine_channels(resolved, dfs...)` before building the
spec instead.
"""
function apply_combos!(df, resolved)
    apply_combo!(df, resolved.color_fields, :__aov_color)
    apply_combo!(df, resolved.row_fields, :__aov_row)
    apply_combo!(df, resolved.column_fields, :__aov_column)
    df
end

"""
    refine_channels(resolved, tables...)

Return a new `resolved` with dimensions stripped if they are absent from
**every** `table` or have ≤1 unique value in every table that has them.
Same treatment for fixed-channel assignments. Use this once before building
your spec so that:

- the static server-side render's auto-generated row/col/color labels only
  reference dims that actually vary,
- the pinned catch-all channel doesn't auto-absorb meaningless dims,
- `mapping_controls`' picker reflects the same set.

Per-layer combo construction is still done by `apply_combos!` against the
returned (refined) `resolved`. Layers that don't have every component of a
combo column will have it left unset, and the broadcast pass will replicate
them across the surviving facet panels.
"""
function refine_channels(resolved::NamedTuple, tables...)
    isempty(tables) && return resolved
    # A field is "useful" iff some table has it with >1 unique value.
    cols_per = [Set(Symbol.(Tables.columnnames(t))) for t in tables]
    _useful = function(field)
        sym = Symbol(field)
        for (i, t) in enumerate(tables)
            sym in cols_per[i] || continue
            length(unique(Tables.getcolumn(t, sym))) > 1 && return true
        end
        false
    end
    useful_dims = filter(d -> _useful(first(d)), resolved.dims)
    useful_fixed = Dict{String,Vector{String}}()
    for (ch, fs) in resolved.fixed
        kept = filter(_useful, fs)
        isempty(kept) || (useful_fixed[ch] = kept)
    end
    unchanged = length(useful_dims) == length(resolved.dims) &&
                length(useful_fixed) == length(resolved.fixed) &&
                all(length(useful_fixed[k]) == length(resolved.fixed[k]) for k in keys(resolved.fixed))
    unchanged && return resolved
    resolve_channels(useful_dims;
        color_default=get(resolved.defaults, "color", String[]),
        row_default=get(resolved.defaults, "row", String[]),
        column_default=get(resolved.defaults, "column", String[]),
        detail_default=resolved.detail_fields,
        channels=resolved.channels,
        pinned=resolved.pinned,
        fixed=useful_fixed)
end

"""
    _source_tables_from_spec(spec)

Return a `Vector` of all layer source tables in `spec`. Walks `VegaSpec` →
AoG drawable → layers and collects each layer's unwrapped `.data`. Skips
`nothing` and `Pregrouped` layers. Multi-layer specs (e.g. `dose_layer + spec`)
all contribute — uniqueness of a dim is taken across any layer that has it.
"""
function _source_tables_from_spec(spec)
    isnothing(spec) && return Any[]
    spec isa Dict && return Any[]
    drawable = spec isa VegaSpec ? spec.drawable : spec
    layers = if drawable isa AlgebraOfGraphics.Layers
        drawable.layers
    elseif drawable isa AlgebraOfGraphics.Layer
        (drawable,)
    else
        ()
    end
    out = Any[]
    for layer in layers
        t = extract_data(layer)
        isnothing(t) && continue
        t isa AlgebraOfGraphics.Pregrouped && continue
        push!(out, t)
    end
    out
end

function mapping_controls(id, dimensions::AbstractVector; table=nothing, spec=nothing, kwargs...)
    resolved = resolve_channels(dimensions; kwargs...)
    mapping_controls(id, resolved; table, spec)
end

"""
    remap_node(spec, dimensions; id, table=nothing, kwargs...)

Return a `h.div` bundling a `mapping_controls` picker above the rendered plot
for `spec`. `kwargs` are forwarded to `resolve_channels` (e.g. `color_default`,
`fixed`, `pinned`). Equivalent to:

```julia
h.div()(mapping_controls(id, dimensions; spec, table, kwargs...), to_node(spec; id))
```
"""
function remap_node(spec, dimensions; id, table=nothing, kwargs...)
    controls, plot = _remap_node_parts(spec, dimensions; id, table, kwargs...)
    h.div()(controls, plot)
end

# Expose the (controls, plot_node) pair so callers (e.g. `with_plot_caption`)
# can interleave them with other elements instead of having them pre-wrapped.
function _remap_node_parts(spec, dimensions; id, table=nothing, kwargs...)
    (mapping_controls(id, dimensions; spec, table, kwargs...), to_node(spec; id))
end

# === auto_remap_node ===========================================================
# `auto_remap_node(plot_id, spec; dims, fixed, pinned)` is the "fully
# automatic" form (distinct from the simpler `remap_node` above, which is
# a thin wrapper around `mapping_controls` + `to_node`). The user builds a
# regular AoG spec — including their normal `mapping(:x, :y; color=…,
# row=…, col=…)` channel encodings and any `* config(…)` — and
# auto_remap_node handles channel resolution, refinement against the
# spec's actual data, cartesian-product broadcast across missing facet
# dims, combo-column construction, layer rewriting, and picker assembly.

# --- helpers ---

# Walk a spec down to the list of AoG Layers it contains.
function _spec_layers(spec)
    drawable = spec isa VegaSpec ? spec.drawable : spec
    if drawable isa AlgebraOfGraphics.Layers
        collect(drawable.layers)
    elseif drawable isa AlgebraOfGraphics.Layer
        [drawable]
    else
        error("remap_node: unsupported spec drawable type $(typeof(drawable))")
    end
end

function _auto_summary_args(spec)
    layers = try
        _spec_layers(spec)
    catch
        return nothing
    end
    for layer in layers
        for T in (PointIntervalAnalysis, GradientIntervalAnalysis, DotIntervalAnalysis)
            a = extract_transformation(layer, T)
            isnothing(a) && continue
            table = extract_data(layer)
            (isnothing(table) || isempty(layer.positional) || !haskey(layer.named, :y)) && return nothing
            value = Symbol(_field_name(layer.positional[1]))
            outcome = Symbol(_field_name(layer.named[:y]))
            group_cols = Symbol[]
            for (k, v) in pairs(layer.named)
                k == :y && continue
                push!(group_cols, Symbol(_field_name(v)))
            end
            return (; table, value, outcome, group_cols)
        end
    end
    return nothing
end

# Read default channel assignments from layers' existing `.named` mappings.
# Returns a Dict("color"=>[...], "row"=>[...], "column"=>[...]).
function _layer_channel_defaults(layers)
    defaults = Dict("color"=>String[], "row"=>String[], "column"=>String[])
    for layer in layers
        for (k, v) in pairs(layer.named)
            ch = k === :col ? "column" : string(k)
            haskey(defaults, ch) || continue
            f = _field_name(v)
            f in defaults[ch] || push!(defaults[ch], f)
        end
    end
    defaults
end

# Append a new column to a column-table (NamedTuple of vectors).
_with_added_column(cols::NamedTuple, name::Symbol, vals) =
    merge(cols, NamedTuple{(name,)}((vals,)))

# Build the synthetic combo columns on a NamedTuple column-table per
# `resolved`. Non-mutating: returns a new NamedTuple with the combo columns
# appended where buildable. A combo column is built only if every component
# field is present (mirror of `apply_combo!`'s silent-skip semantics).
function _with_combos(cols::NamedTuple, resolved)
    cur = cols
    for (fields, combo_col) in ((resolved.color_fields,  :__aov_color),
                                 (resolved.row_fields,    :__aov_row),
                                 (resolved.column_fields, :__aov_column))
        length(fields) <= 1 && continue
        syms = Symbol.(fields)
        all(s -> haskey(cur, s), syms) || continue
        # Vectorized fold: `string.(acc, " / ", col)` per extra field.
        combo_vals = string.(cur[syms[1]])
        for s in @view syms[2:end]
            combo_vals = string.(combo_vals, " / ", cur[s])
        end
        cur = _with_added_column(cur, combo_col, combo_vals)
    end
    cur
end

# Precompute the union of unique values per field across all layers'
# column-tables. Walks each (layer, field) pair exactly once, instead of
# once per consuming layer — critical when one layer has millions of rows.
function _global_field_uniques(all_cols::Vector, fields)
    out = Dict{Symbol,Vector{Any}}()
    for field in fields
        sym = Symbol(field)
        per_layer = Vector{Any}[]
        for cols in all_cols
            haskey(cols, sym) || continue
            u = unique(cols[sym])
            isempty(u) || push!(per_layer, collect(Any, u))
        end
        isempty(per_layer) && continue
        merged = length(per_layer) == 1 ? per_layer[1] : unique(reduce(vcat, per_layer))
        out[sym] = merged
    end
    out
end

# Broadcast `cols` across every field in `fields` that's absent from it.
# Performs ONE cartesian-product expansion against the joint product of
# all missing fields. Unique-value lookup is done via a precomputed
# `field_uniques` dict so we don't re-walk other layers per call.
function _broadcast_missing_fields(cols::NamedTuple, fields, field_uniques::Dict{Symbol,Vector{Any}})
    # Gather missing fields and their unique values (skip empties).
    missing_syms = Symbol[]
    missing_vals = Vector{Vector{Any}}()
    for field in fields
        sym = Symbol(field)
        haskey(cols, sym) && continue
        haskey(field_uniques, sym) || continue
        push!(missing_syms, sym)
        push!(missing_vals, field_uniques[sym])
    end
    isempty(missing_syms) && return cols

    nrows = length(first(cols))
    sizes = length.(missing_vals)
    total_combos = prod(sizes)

    # Each original row is replicated `total_combos` times in a contiguous
    # block; one allocation per existing column.
    inflated = map(c -> repeat(c, inner=total_combos), cols)

    # Build each new field column so that within every block of size
    # `total_combos`, every cartesian combination appears exactly once.
    # `inner_sz` tracks how many positions a single value of the current
    # field spans before cycling.
    added = NamedTuple()
    inner_sz = 1
    for (sym, vals) in zip(missing_syms, missing_vals)
        n_vals = length(vals)
        outer_sz = total_combos ÷ (inner_sz * n_vals)
        cycle = repeat(repeat(vals, inner=inner_sz), outer=outer_sz)
        col = repeat(cycle, outer=nrows)
        added = merge(added, NamedTuple{(sym,)}((col,)))
        inner_sz *= n_vals
    end

    merge(inflated, added)
end

# Patch the `detail_fields` of any TidybayesAnalysis in a transformation
# chain to `new_detail`. Walks through `ComposedFunction` recursively.
_with_detail(t::PointIntervalAnalysis, d) = PointIntervalAnalysis(t.probs, t.point, d)
_with_detail(t::GradientIntervalAnalysis, d) = GradientIntervalAnalysis(t.probs, t.point, d)
_with_detail(t::LineRibbonAnalysis, d) = LineRibbonAnalysis(t.probs, t.show_line, d)
_with_detail(t::PrecomputedRibbonAnalysis, d) = PrecomputedRibbonAnalysis(t.bands, t.show_line, d)
_with_detail(t::DotIntervalAnalysis, d) = DotIntervalAnalysis(t.probs, t.n_dots, t.point, d)

function _patch_detail(t, new_detail)
    syms = Symbol.(new_detail)
    if t isa TidybayesAnalysis
        return _with_detail(t, syms)
    elseif t isa ComposedFunction
        return _patch_detail(t.outer, new_detail) ∘ _patch_detail(t.inner, new_detail)
    else
        return t
    end
end

# Collect channel keys (e.g. :color, :row, :col) that are statically set on
# any Visual in a transformation chain. These should NOT be overwritten by
# data-driven encodings from the resolved channel kws — e.g. a scatter
# layer with `visual(Scatter; color="black")` keeps its black points
# regardless of the picker's color channel.
function _visual_static_channels(t)
    if t isa AlgebraOfGraphics.Visual
        return Set{Symbol}(keys(t.attributes))
    elseif t isa ComposedFunction
        return union(_visual_static_channels(t.outer), _visual_static_channels(t.inner))
    else
        return Set{Symbol}()
    end
end

# Rebuild a layer with a new dataframe and resolved channel kws merged in.
# User-supplied entries on managed channels (color/row/col/column) are
# dropped first, then resolved kws are merged on top — except where the
# layer's Visual has already set the same channel statically. lineribbon
# detail is patched on the transformation.
function _rebuild_layer(layer, new_df, resolved)
    # Build merged named NamedTuple
    base = NamedTuple()
    for (k, v) in pairs(layer.named)
        k in (:color, :row, :col, :column) && continue
        base = merge(base, NamedTuple{(k,)}((v,)))
    end
    # If the visual statically sets a channel (typically :color), drop the
    # data-driven encoding for that channel from this layer's mapping.
    static = _visual_static_channels(layer.transformation)
    _drop = (nt, k) -> k in static ? Base.structdiff(nt, NamedTuple{(k,)}) : nt
    extra = merge(resolved.fixed_kw, resolved.row_kw, resolved.color_kw, resolved.column_kw)
    for k in (:color, :row, :col, :column)
        extra = _drop(extra, k)
    end
    new_named = merge(base, extra)
    # Patch detail on the transformation chain
    new_t = _patch_detail(layer.transformation, resolved.detail)
    # Compose a fresh layer using AoG operators (so .data, .positional, .named
    # are constructed in the AoG-native shapes), then swap in the patched
    # transformation.
    composed = AlgebraOfGraphics.data(new_df) *
        AlgebraOfGraphics.mapping(layer.positional...; new_named...)
    AlgebraOfGraphics.Layer(new_t, composed.data, composed.positional, composed.named)
end

"""
    auto_remap_node(plot_id, spec; dims, fixed=Dict(), pinned=:row)

Fully automatic interactive plot. Takes a "normal" AoG spec and produces an
`h.div(picker, plot_node)`. The user does not call `resolve_channels`,
`refine_channels`, `apply_combos!`, `mapping_controls`, or `to_node`; this
function does all of it.

# How channel info is sourced

- **Defaults** are read from each layer's existing `.named` mapping. If a
  layer says `mapping(:x, :y; color=:source, row=:study)`, then `color_default
  = "source"` and `row_default = "study"` automatically.
- **`dims`** is the user-supplied list of remappable dimensions, as
  `Vector{Pair{String,String}}` (field => human label). Labels here are the
  single source of truth for picker labels and combo titles.
- **`fixed`** assigns fields to channels that the picker shouldn't expose as
  remappable. Same shape as in `resolve_channels`. Labels for fixed fields
  are picked up from `dims` if present, otherwise snake_case → Title Case.
- **`pinned`** is the catch-all channel.

# What it does internally

1. Walks `spec` to enumerate layers and their dataframes.
2. Reads channel defaults from layers' existing mappings.
3. Calls `resolve_channels(dims; defaults..., fixed, pinned)`.
4. `refine_channels(resolved, dfs...)` — strips dims absent or single-valued
   across every layer.
5. For each layer's df: cartesian-product broadcasts the df across the
   union of unique values for every row/color/column field it doesn't have
   (so partial-overlap layers like observation scatters land in every
   relevant pred panel), then `apply_combos!` builds `__aov_row`/etc.
6. Rebuilds each layer with the new (broadcast) df and resolved channel
   kws merged into its mapping. lineribbon/pointinterval/etc. detail is
   patched on the transformation.
7. Reassembles layers via `+`, preserves the original `VegaSpec` config,
   and wraps with `mapping_controls` + `to_node` in an `h.div`.

# Example

```julia
spec = data(filtered_pred) * mapping(:dose_mg => "Dose (mg)", :qoi => "";
            group=:draw, color=:source, row=:study) * lineribbon() +
       data(obs_rows) * mapping(:dose_mg => "Dose (mg)", :qoi => "") *
            visual(Scatter; size=30, opacity=0.8)
spec *= config(height=300, facet=(; linkxaxes=:none, linkyaxes=:none))

remap_node("dose-response-plot", spec;
    dims=["source"=>"Source", "study"=>"Study", "outcome"=>"Outcome", "method"=>"Method"],
    fixed=Dict(:column => "assay"),
    pinned=:row)
```
"""
function auto_remap_node(plot_id, spec; kwargs...)
    controls, plot = _auto_remap_parts(plot_id, spec; kwargs...)
    h.div()(controls, plot)
end

# Same idea as `_remap_node_parts`: expose the (controls, plot_node) pair for
# composition with `with_plot_caption` et al.
function _auto_remap_parts(plot_id, spec; dims, fixed=Dict(), pinned::Symbol=:row)
    layers = _spec_layers(spec)
    raw_dfs = [extract_data(l) for l in layers]
    any(isnothing, raw_dfs) && error("auto_remap_node: every layer must have associated data (no Pregrouped layers supported here)")
    # Materialize each layer's data as a NamedTuple of vectors so the rest
    # of the pipeline can stay non-mutating and uniform across input types
    # (DataFrame / DataFrameColumns / NamedTuple / etc).
    dfs = NamedTuple[Tables.columntable(d) for d in raw_dfs]

    # Only fields the user listed in `dims` count as remappable defaults.
    # Layer-internal encodings on other fields (e.g. dose VLines coloring by
    # :vessel, or per-marker `color="black"`) are ignored.
    dim_fields = Set{String}(string(d isa Pair ? first(d) : d) for d in dims)
    defaults = _layer_channel_defaults(layers)
    defaults = Dict(ch => filter(f -> f in dim_fields, fs) for (ch, fs) in defaults)
    resolved = resolve_channels(dims;
        color_default=defaults["color"],
        row_default=defaults["row"],
        column_default=defaults["column"],
        pinned, fixed)
    resolved = refine_channels(resolved, dfs...)

    # Cartesian-product fill missing facet fields, then build combo columns.
    bcast_fields = unique(vcat(resolved.color_fields, resolved.row_fields, resolved.column_fields))
    field_uniques = _global_field_uniques(dfs, bcast_fields)
    bcasted = [_broadcast_missing_fields(df, bcast_fields, field_uniques) for df in dfs]
    new_dfs = [_with_combos(df, resolved) for df in bcasted]

    new_layers = [_rebuild_layer(layer, new_df, resolved) for (layer, new_df) in zip(layers, new_dfs)]
    new_drawable = reduce(+, new_layers)
    new_spec = spec isa VegaSpec ? VegaSpec(new_drawable, spec.config) : new_drawable

    controls = isempty(resolved.dims) ? "" : mapping_controls(plot_id, resolved; spec=new_spec)
    plot = to_node(new_spec; id=plot_id)
    (controls, plot)
end

function mapping_controls(id, resolved::NamedTuple; table=nothing, spec=nothing)
    id = _sanitize_id(id)
    dims = resolved.dims
    defaults = resolved.defaults
    fixed_js = resolved.fixed
    dim_label_map = resolved.dim_label_map
    _prettify(f) = get(dim_label_map, f, join(uppercasefirst.(split(f, "_")), " "))
    pinned_str = string(resolved.pinned)

    # Validate dimension fields exist in the table if provided
    if !isnothing(table)
        col_names = Set(string.(Tables.columnnames(table)))
        for (field, label) in dims
            field in col_names || error("mapping_controls: dimension field \"$field\" (label \"$label\") not found in table. Available columns: $(sort(collect(col_names)))")
        end
        for (ch_str, fs) in fixed_js
            for f in fs
                f in col_names || error("mapping_controls: fixed channel :$ch_str field \"$f\" not found in table. Available columns: $(sort(collect(col_names)))")
            end
        end
    end

    # Filter out dimensions with ≤1 unique value in the source DataFrame(s)
    # the AoG spec wraps. This is the authoritative source — walking the
    # post-AoG VL spec drops fields that get collapsed into combo columns
    # (e.g. row_fields = ["vessel","diet"] → __aov_row) even though `detail`
    # preserves them for rendering. Multi-layer specs contribute all layers:
    # a dim is kept iff *some* layer has it with >1 unique values.
    src_tables = !isnothing(table) ? Any[table] : _source_tables_from_spec(spec)
    if !isempty(src_tables)
        dims = filter(dims) do (field, _)
            sym = Symbol(field)
            for t in src_tables
                sym in Tables.columnnames(t) || continue
                length(unique(Tables.getcolumn(t, sym))) > 1 && return true
            end
            false  # no layer has the column, or every layer has ≤1 unique → drop
        end
    end

    js_id = replace(id, "-" => "_")
    channels = resolved.channels
    # Separate editable channels (for JS logic) from fixed
    editable_channels = [ch for ch in channels if !haskey(fixed_js, string(ch))]

    # Ensure :detail is always last in the channel order (for both editable and all)
    editable_channels = vcat(filter(!=(Symbol("detail")), editable_channels),
                    :detail in editable_channels ? [:detail] : Symbol[])
    all_ch_strs = [string(ch) for ch in editable_channels]

    # Build unified channel UI: all channels (editable + fixed) rendered identically.
    # Fixed channels have disabled select + disabled radio.
    all_ui_channels = vcat(filter(!=(Symbol("detail")), channels),
                           :detail in channels ? [:detail] : Symbol[])
    sel_size = string(clamp(length(dims), 2, 4))
    selects = map(all_ui_channels) do ch
        ch_str = string(ch)
        ch_label = get(_CHANNEL_LABELS, ch_str, uppercasefirst(ch_str))
        is_fixed = haskey(fixed_js, ch_str)
        is_pinned = !is_fixed && ch_str == pinned_str
        # Determine which fields are selected
        default_set = if is_fixed
            Set(fixed_js[ch_str])
        else
            Set(get(defaults, ch_str, String[]))
        end
        options = [let
            sel = field in default_set ? (; value=field, selected="selected") : (; value=field)
            h.option(; sel...)(label)
        end for (field, label) in dims]
        sel_attrs = (;
            id="aov-remap-$(ch_str)-$(id)",
            multiple="multiple",
            size=sel_size,
            onchange="_aovRemap_$(js_id)('$(ch_str)')",
        )
        if is_pinned || is_fixed
            sel_attrs = merge(sel_attrs, (; disabled="disabled"))
        end
        radio_attrs = (; type="radio", name="aov-pin-$(id)", value=ch_str,
            onchange="_aovPin_$(js_id)(this.value)")
        if is_pinned
            radio_attrs = merge(radio_attrs, (; checked="checked"))
        end
        if is_fixed
            radio_attrs = merge(radio_attrs, (; disabled="disabled"))
        end
        h.div()(
            h.label(; style="display:flex; align-items:center; gap:0.3rem;")(
                h.input(; radio_attrs...),
                ch_label * ": ",
            ),
            h.select(; sel_attrs...)(options...),
        )
    end

    dim_fields = JSON.json([first(d) for d in dims])
    dim_labels = JSON.json(Dict(first(d) => _prettify(first(d)) for d in dims))
    fixed_js_str = JSON.json(fixed_js)
    channels_json = JSON.json(all_ch_strs)

    js = h.script("""
    var _aovPin_$(js_id)_current = '$(pinned_str)';

    function _aovPin_$(js_id)(newPin) {
        var oldPin = _aovPin_$(js_id)_current;
        _aovPin_$(js_id)_current = newPin;
        // Enable old pinned, disable new pinned
        var oldSel = document.getElementById('aov-remap-' + oldPin + '-$(id)');
        var newSel = document.getElementById('aov-remap-' + newPin + '-$(id)');
        if (oldSel) oldSel.disabled = false;
        if (newSel) newSel.disabled = true;
        _aovRemap_$(js_id)('pin');
    }

    function _aovRemap_$(js_id)(changed) {
        var allDims = $(dim_fields);
        var labels = $(dim_labels);
        var channels = $(channels_json);
        var pinned = _aovPin_$(js_id)_current;

        // Read selections from each non-pinned channel
        function readChannel(ch) {
            var sel = document.getElementById('aov-remap-' + ch + '-$(id)');
            if (!sel) return [];
            return Array.from(sel.selectedOptions).map(function(o) { return o.value; });
        }

        var selections = {};
        channels.forEach(function(ch) {
            selections[ch] = (ch === pinned) ? [] : readChannel(ch);
        });

        // Pinned channel = all dims not in any other editable channel (or fixed)
        var fixed = $(fixed_js_str);
        var elsewhere = {};
        channels.forEach(function(ch) {
            if (ch === pinned) return;
            selections[ch].forEach(function(f) { elsewhere[f] = true; });
        });
        for (var k in fixed) { fixed[k].forEach(function(f) { elsewhere[f] = true; }); }
        selections[pinned] = allDims.filter(function(d) { return !elsewhere[d]; });

        // Update pinned select's visual state
        var pinnedSel = document.getElementById('aov-remap-' + pinned + '-$(id)');
        if (pinnedSel) {
            var pinnedSet = {};
            selections[pinned].forEach(function(f) { pinnedSet[f] = true; });
            Array.from(pinnedSel.options).forEach(function(o) {
                o.selected = !!pinnedSet[o.value];
            });
        }

        // Clone origSpec data for combo building
        var orig = AoV._origSpecs['$(id)'];
        if (!orig) return;
        var dataObj = orig.data || (orig.spec && orig.spec.data);
        var dataClone = dataObj ? JSON.parse(JSON.stringify(dataObj)) : null;

        // Validate: warn about dims not present in the spec data
        if (dataClone && dataClone.values && dataClone.values.length > 0) {
            var sampleRow = dataClone.values[0];
            var allSelected = [].concat(
                selections.color || [], selections.row || [],
                selections.column || [], selections.detail || []);
            allSelected.forEach(function(f) {
                if (!dataClone.values.some(function(r) { return Object.prototype.hasOwnProperty.call(r, f); })) {
                    console.warn('[AoV mapping_controls] dimension "' + f + '" (' + (labels[f] || f) +
                        ') is in the picker but not in the spec data — it was likely dropped during AoG summary. ' +
                        'Add it to the AoG mapping (e.g. color=:' + f + ' or lineribbon detail) so it survives into the VL spec.');
                }
            });
        }

        // Build synthetic combo field when 2+ fields selected for a channel.
        // Only sets the combo on rows that have ALL component fields — cross-source
        // rows (e.g. dose VLines) that lack them are left without the combo, so
        // _broadcastCrossSource can replicate them across all unique combo values.
        var comboTitles = {};
        function resolveChannel(fields, comboName) {
            if (fields.length === 0) return '';
            if (fields.length === 1) return fields[0];
            if (!dataClone || !dataClone.values) return fields[0];
            var title = fields.map(function(f) { return labels[f] || f; }).join(' / ');
            comboTitles[comboName] = title;
            dataClone.values.forEach(function(row) {
                var hasAll = fields.every(function(f) {
                    return Object.prototype.hasOwnProperty.call(row, f);
                });
                if (hasAll) {
                    row[comboName] = fields.map(function(f) {
                        return row[f] != null ? String(row[f]) : '';
                    }).join(' / ');
                }
            });
            return comboName;
        }

        var colorField  = resolveChannel(selections.color || [], '__aov_color');
        var rowField    = resolveChannel(selections.row || [], '__aov_row');
        var columnField = resolveChannel(selections.column || [], '__aov_column');
        var detailFields = selections.detail || [];

        // Merge dim labels into comboTitles so single fields also get pretty names
        for (var f in labels) { if (!comboTitles[f]) comboTitles[f] = labels[f]; }
        var mapping = {
            color: colorField,
            row: rowField,
            column: columnField,
            _dimensions: detailFields,
            _comboData: dataClone,
            _comboTitles: comboTitles
        };
        // Merge fixed channels (resolve combos for multi-field fixed)
        for (var k in fixed) {
            var fs = fixed[k];
            if (k === 'detail') {
                mapping._dimensions = mapping._dimensions.concat(fs);
            } else {
                mapping[k] = fs.length <= 1 ? (fs[0] || '') : resolveChannel(fs, '__aov_' + k);
            }
        }

        AoV.remapEncoding('$(id)', mapping);

        // URL persistence: comma-separated field lists + pin state
        var params = new URLSearchParams(window.location.search);
        channels.forEach(function(ch) {
            var key = 'aov_' + ch + '_$(id)';
            var fields = selections[ch];
            if (fields && fields.length > 0) params.set(key, fields.join(','));
            else params.delete(key);
        });
        params.set('aov_pin_$(id)', pinned);
        var qs = params.toString();
        history.replaceState(null, '', qs ? '?' + qs : window.location.pathname);
    }

    // Restore from URL params once the spec is embedded
    (function _aovRestore_$(js_id)() {
        if (!(typeof AoV !== 'undefined' && AoV._origSpecs && AoV._origSpecs['$(id)'])) {
            setTimeout(_aovRestore_$(js_id), 50);
            return;
        }
        var params = new URLSearchParams(window.location.search);
        var restored = false;
        var channels = $(channels_json);

        // Restore pin state first
        var pinVal = params.get('aov_pin_$(id)');
        if (pinVal && channels.indexOf(pinVal) !== -1 && pinVal !== _aovPin_$(js_id)_current) {
            var radio = document.querySelector('input[name="aov-pin-$(id)"][value="' + pinVal + '"]');
            if (radio) { radio.checked = true; _aovPin_$(js_id)(pinVal); }
        }
        var pinned = _aovPin_$(js_id)_current;

        // Restore channel selections (skip pinned — it's computed)
        channels.forEach(function(ch) {
            if (ch === pinned) return;
            var val = params.get('aov_' + ch + '_$(id)');
            if (val) {
                var fields = val.split(',');
                var sel = document.getElementById('aov-remap-' + ch + '-$(id)');
                if (sel) {
                    Array.from(sel.options).forEach(function(o) {
                        o.selected = fields.indexOf(o.value) !== -1;
                    });
                    restored = true;
                }
            }
        });
        if (restored) _aovRemap_$(js_id)('');
    })();
    """)

    hint = h.small(; style="display:block; color:var(--pico-muted-color, #666); margin-bottom:0.3rem;")(
        "Assign dimensions to channels (multi-select). ",
        "The pinned channel (", h.strong("●"), ") auto-fills with unassigned dimensions. ",
        "Selecting 2+ dimensions in one channel combines them.",
    )

    h.div()(
        hint,
        h.div(; style="display:flex; gap:1rem; align-items:end; flex-wrap:wrap; margin-bottom:0.5rem;")(
            selects..., js,
        ),
    )
end

"""
    to_html(spec; id, width, height)

Return a standalone HTML string with embedded vega-embed that self-loads scripts from CDN.
"""
function to_html(spec; id=nothing, width=nothing, height=nothing)
    vl = spec isa Dict ? copy(spec) : to_vegalite(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    id = _sanitize_id(something(id, "vega-" * string(abs(hash(JSON.json(vl))), base=16)))
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
) * config(width=250, height=100, facet=(; linkxaxes=:none, linkyaxes=:none)) |> vdraw
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
    scales_obj = nothing
    isnothing(cfg) && return (; figure=NamedTuple(), facet=NamedTuple(), axis=NamedTuple(), scales=nothing)
    props = cfg.properties
    if !faceted
        w = get(props, :width, nothing)
        h_val = get(props, :height, nothing)
        if !isnothing(w) || !isnothing(h_val)
            figure_kw[:size] = (something(w, 400), something(h_val, 400))
        end
    end
    # Translate VL encoding scale overrides to Makie axis scales (backwards compat)
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
        elseif k === :scales && v isa AlgebraOfGraphics.Scales
            scales_obj = v
        elseif k === :facet && v isa NamedTuple
            for (fk, fv) in pairs(v)
                facet_kw[fk] = fv
            end
        elseif k === :axis && v isa NamedTuple
            for (ak, av) in pairs(v)
                ak === :clamp && continue  # VL-only, no Makie analogue
                axis_kw[ak] = av
            end
        elseif k === :independent_scales
            @warn "AlgebraOfVega: `config(independent_scales=$(repr(v)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
            axes = if v === true
                [:x, :y]
            elseif v isa Symbol
                [v]
            else
                [Symbol(a) for a in v]
            end
            :x in axes && get!(facet_kw, :linkxaxes, :none)
            :y in axes && get!(facet_kw, :linkyaxes, :none)
        end
    end
    (; figure=NamedTuple(figure_kw), facet=NamedTuple(facet_kw), axis=NamedTuple(axis_kw), scales=scales_obj)
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

function _rows_to_columntable(rows::Vector{Dict{String,Any}})
    cols = collect(keys(rows[1]))
    col_syms = Tuple(Symbol.(cols))
    col_vals = Tuple([getindex.(rows, c) for c in cols])
    NamedTuple{col_syms}(col_vals)
end

function _ribbon_to_aog(summary_nt::NamedTuple, x_sym::Symbol, median_sym::Symbol,
    band_syms::Vector{Tuple{Symbol,Symbol}};
    show_line::Bool=true, color_kw=Dict{Symbol,Any}(), facet_kw=Dict{Symbol,Any}())
    opacities = range(0.2, 0.6, length=length(band_syms))
    result = nothing
    for (i, (lo_sym, hi_sym)) in enumerate(band_syms)
        band_layer = data(summary_nt) *
            mapping(x_sym, lo_sym, hi_sym; color_kw..., facet_kw...) *
            visual(Band; alpha=opacities[i])
        result = isnothing(result) ? band_layer : result + band_layer
    end
    if show_line
        line_layer = data(summary_nt) *
            mapping(x_sym, median_sym; color_kw..., facet_kw...) *
            visual(Lines)
        result = isnothing(result) ? line_layer : result + line_layer
    end
    result
end

function _extract_aog_facet_color_kw(layer)
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    _, facet_fields = _extract_facet_info(layer)
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
    (; color_field, facet_fields, facet_kw, color_kw)
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
    (; color_field, facet_fields, facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    detail_strs = string.(a.detail_fields)
    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs;
        color_field, facet_fields, detail_fields=detail_strs)
    summary_nt = _rows_to_columntable(summary)

    sorted_probs = sort(a.probs, rev=true)
    band_syms = Tuple{Symbol,Symbol}[(Symbol(_vl_prob_field("lo", p)), Symbol(_vl_prob_field("hi", p))) for p in sorted_probs]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol("__median__"), band_syms;
        show_line=a.show_line, color_kw, facet_kw)
end

function _precomputed_ribbon_to_aog(a::PrecomputedRibbonAnalysis, layer::AlgebraOfGraphics.Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    median_col = _field_name(layer.positional[2])
    (; facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    summary_nt = Tables.columntable(table)
    band_syms = Tuple{Symbol,Symbol}[(first(b), last(b)) for b in a.bands]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol(median_col), band_syms;
        show_line=a.show_line, color_kw, facet_kw)
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
        elseif a isa PrecomputedRibbonAnalysis
            return _precomputed_ribbon_to_aog(a, l)
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
    fg = isnothing(kw.scales) ?
        AlgebraOfGraphics.draw(drawable; figure=kw.figure, facet=kw.facet, axis=kw.axis) :
        AlgebraOfGraphics.draw(drawable, kw.scales; figure=kw.figure, facet=kw.facet, axis=kw.axis)
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
