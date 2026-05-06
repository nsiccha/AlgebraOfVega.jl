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
_is_string_label(::String) = true
_is_string_label(e::Expr) = e.head === :string
_is_string_label(_) = false

macro tic(arg)
    v = esc(:_tic_)
    file = String(__source__.file)
    line = __source__.line
    if _is_string_label(arg)
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
export vega_runtime, update_data, vega_cdn_urls, mapping_controls, resolve_channels, refine_channels, auto_remap_node
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

# Type-narrowing helpers — return the value as the requested type or `nothing`.
# Used by Vega-Lite spec walkers that previously tested `x isa Dict` / `x isa AbstractString`.
_as_dict(d::Dict) = d
_as_dict(_) = nothing
_as_str(s::AbstractString) = s
_as_str(_) = nothing

_vl_tooltip_entry!(args...) = nothing
function _vl_tooltip_entry!(tt, enc::Dict)
    haskey(enc, "field") || return
    entry = Dict{String,Any}("field" => enc["field"])
    haskey(enc, "type") && (entry["type"] = enc["type"])
    push!(tt, entry)
end

"""Collect tooltip fields from an encoding dict (all channels that have a "field" key)."""
function vl_tooltips(encoding)
    tt = Dict{String,Any}[]
    for (_, enc) in encoding
        _vl_tooltip_entry!(tt, enc)
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
    Scatter => Dict{String,Any}("filled" => true),
    ScatterLines => Dict{String,Any}("point" => true, "filled" => true),
    Stairs => Dict{String,Any}("interpolate" => "step-after"),
]

function plottype_to_mark_props(T::Type)
    for (PT, props) in _MARK_PROPS
        T <: PT && return props
    end
    Dict{String,Any}()
end

_COMPOSITE_MARKS = Set(["boxplot", "errorbar", "errorband"])

_mark_type(m::String) = m
_mark_type(m::Dict) = get(m, "type", "")
_mark_type(_) = ""

_layer_mark_type(sl::Dict) = _mark_type(get(sl, "mark", nothing))
_layer_mark_type(_) = ""

function _is_composite_mark(vl::Dict)
    _mark_type(get(vl, "mark", nothing)) in _COMPOSITE_MARKS && return true
    # Check sublayers for composite marks (e.g. layered boxplots)
    for sl in get(vl, "layer", [])
        _layer_mark_type(sl) in _COMPOSITE_MARKS && return true
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
    _apply_selector_modifier!(field, dst)
    field
end
selector_to_field(sel) = Dict{String,Any}("value" => sel)  # DirectData, Presorted, etc.

# Apply one Pair-destination modifier to a field dict. Handles string labels,
# nested labels (`=> :fn => "Label"`), and AoG scale-type modifiers like
# `nonnumeric` that must force the VL encoding `type` so downstream
# infer_types! doesn't re-derive from the column eltype.
_apply_selector_modifier!(field::Dict{String,Any}, _) = field
_apply_selector_modifier!(field::Dict{String,Any}, dst::AbstractString) = (field["title"] = dst; field)
# nonnumeric: force categorical. Without this, an Int column used for
# color ends up as quantitative, which won't merge with sibling layers
# (e.g. ECDFPlot) that hardcode nominal → dual color legends.
_apply_selector_modifier!(field::Dict{String,Any}, ::typeof(AlgebraOfGraphics.nonnumeric)) = (field["type"] = "nominal"; field)
function _apply_selector_modifier!(field::Dict{String,Any}, dst::Pair)
    _apply_selector_modifier!(field, first(dst))
    _apply_selector_modifier!(field, last(dst))
    field
end

_field_name(sel) = string(sel)
_field_name(sel::Pair) = string(first(sel))
_field_label(sel) = _field_name(sel)
_field_label(sel::Pair{<:Any,<:AbstractString}) = last(sel)

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

_infer_enc_type!(args...) = nothing
function _infer_enc_type!(enc::Dict, table)
    haskey(enc, "field") && !haskey(enc, "type") || return
    field = Symbol(enc["field"])
    if field in Tables.columnnames(table)
        enc["type"] = vl_type(Tables.getcolumn(table, field))
    end
end

function infer_types!(encoding::Dict, table)
    isnothing(table) && return encoding
    for (_, enc) in encoding
        _infer_enc_type!(enc, table)
    end
    encoding
end

# --- Extract components from AoG Layer ---

extract_visual(layer::AlgebraOfGraphics.Layer) =
    extract_transformation(layer, AlgebraOfGraphics.Visual)

_unwrap_columns(cols::AlgebraOfGraphics.Columns) = cols.columns
_unwrap_columns(cols) = cols

function extract_data(layer::AlgebraOfGraphics.Layer)
    isnothing(layer.data) && return nothing
    _unwrap_columns(layer.data)
end

_is_pregrouped(::AlgebraOfGraphics.Pregrouped) = true
_is_pregrouped(_) = false

function is_pregrouped(layer::AlgebraOfGraphics.Layer)
    isnothing(layer.data) && return false
    _is_pregrouped(_unwrap_columns(layer.data))
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
    x_data, x_rename = _unwrap_x_arg(x_arg)

    # Collect ordered labels from renamer for sort order
    x_sort = _renamer_sort(x_rename)

    # Flatten grouped vectors into long-form rows
    rows = Dict{String,Any}[]
    n_groups = length(x_data)
    for i in 1:n_groups
        x_vals = x_data[i]
        for j in eachindex(x_vals)
            x_raw = x_vals[j]
            x_label = _apply_rename(x_rename, x_raw)
            row = Dict{String,Any}("x" => x_label)
            if !isnothing(y_arg)
                yval = y_arg[i][j]
                # Skip NaN/Inf values — they produce "infinite extent" VL warnings
                isnothing(_vl_safe(yval)) && continue
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

_vl_safe(v) = v
_vl_safe(v::Number) = isfinite(v) ? v : nothing

# Pregrouped x-arg may arrive as `data => renamer` or as raw data
_unwrap_x_arg(x) = (x, nothing)
_unwrap_x_arg(x::Pair) = (first(x), last(x))

# Sort labels from a renamer (only AoG.Renamer carries an explicit order)
_renamer_sort(_) = nothing
_renamer_sort(r::AlgebraOfGraphics.Renamer) = [string(l) for l in r.labels]

# Map a raw x-tick value through the optional renamer before stringifying
_apply_rename(::Nothing, x_raw) = string(x_raw)
_apply_rename(r::AlgebraOfGraphics.Renamer, x_raw) = string(r(x_raw).value)
_apply_rename(f::Function, x_raw) = string(f(x_raw))

# Histogram bin spec: integer → maxbins; vector of edges → step + extent
_apply_bins!(_, _) = nothing
_apply_bins!(bp::Dict{String,Any}, n::Integer) = (bp["maxbins"] = Int(n); nothing)
function _apply_bins!(bp::Dict{String,Any}, edges::AbstractVector)
    length(edges) >= 2 || return nothing
    e = collect(float.(edges))
    bp["step"] = e[2] - e[1]
    bp["extent"] = [first(e), last(e)]
    nothing
end

# datalimits: only 2-tuple of Reals is meaningful
_apply_datalimits!(args...) = nothing
function _apply_datalimits!(bp::Dict{String,Any}, dl::Tuple{<:Real,<:Real})
    bp["extent"] = [float(dl[1]), float(dl[2])]
    nothing
end

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
    orientation::Symbol
end

struct GradientIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    point::Symbol
    detail_fields::Vector{Symbol}
    orientation::Symbol
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

struct PrecomputedIntervalAnalysis <: TidybayesAnalysis
    bands::Vector{Pair{Symbol,Symbol}}
    detail_fields::Vector{Symbol}
    orientation::Symbol
end

struct DotIntervalAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    n_dots::Int
    point::Symbol
    detail_fields::Vector{Symbol}
    orientation::Symbol
end

"""
    pointinterval(; probs=[0.95, 0.8, 0.5], point=:median, orientation=:horizontal)
    pointinterval(; bands=[:q025 => :q975, :q25 => :q75], orientation=:horizontal)

Nested credible intervals with varying stroke width + a point estimate.

With `probs` (default): expects draw-level data. Computes quantiles in Julia,
then generates layered rule + point marks.

    data(draws) * mapping(:value, y=:parameter) * pointinterval()

With `bands`: expects pre-aggregated data with interval columns. The first
positional is the point/median column. Each band is a `lo => hi` pair,
outermost first. Skips Julia-side quantile computation.

    data(summary) * mapping(:median, y=:parameter) *
        pointinterval(bands=[:q025 => :q975, :q25 => :q75])

With `orientation=:vertical`: value column on y-axis, category on x-axis.
Requires two positional mappings `(category, value)`:

    data(draws) * mapping(:parameter, :value) * pointinterval(orientation=:vertical)
"""
function pointinterval(; probs=[0.95, 0.8, 0.5], point=:median, bands=nothing,
                        detail=Symbol[], orientation::Symbol=:horizontal)
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedIntervalAnalysis(parsed, Symbol.(detail), orientation))
    end
    Layer(transformation=PointIntervalAnalysis(Float64.(probs), point, Symbol.(detail), orientation))
end

"""
    gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median, orientation=:horizontal)

Nested credible intervals with uniform width and varying opacity + a point estimate.

    data(draws) * mapping(:value, y=:parameter) * gradient_interval()
    data(draws) * mapping(:parameter, :value) * gradient_interval(orientation=:vertical)
"""
gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median, detail=Symbol[], orientation::Symbol=:horizontal) =
    Layer(transformation=GradientIntervalAnalysis(Float64.(probs), point, Symbol.(detail), orientation))

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
    dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median, orientation=:horizontal)

Quantile dotplot with nested interval overlay.

    data(draws) * mapping(:value, y=:parameter) * dotinterval()
    data(draws) * mapping(:parameter, :value) * dotinterval(orientation=:vertical)
"""
dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median, detail=Symbol[], orientation::Symbol=:horizontal) =
    Layer(transformation=DotIntervalAnalysis(Float64.(probs), n_dots, point, Symbol.(detail), orientation))

# Direct hit on `T` — dispatches over the value's type rather than `isa`.
_find_part(::Type, _) = nothing
_find_part(::Type{T}, t::T) where {T} = t

# Recurse through ComposedFunction halves looking for a `T`. Non-ComposedFunction
# values fall to the `Any` fallback and return nothing.
_walk_chain(args...) = nothing
function _walk_chain(::Type{T}, f::ComposedFunction) where {T}
    for part in (f.outer, f.inner)
        r = _find_part(T, part)
        isnothing(r) || return r
        r = _walk_chain(T, part)
        isnothing(r) || return r
    end
    nothing
end

_is_automatic(::Makie.Automatic) = true
_is_automatic(_) = false

_analysis_probs(a::Union{PointIntervalAnalysis,GradientIntervalAnalysis,DotIntervalAnalysis}) = a.probs
_analysis_probs(_) = [0.95, 0.5]

_is_gradient(::GradientIntervalAnalysis) = true
_is_gradient(_) = false

"""Extract a transformation of type `T` from a layer's transformation chain."""
function extract_transformation(layer::AlgebraOfGraphics.Layer, T::Type)
    t = layer.transformation
    t === identity && return nothing
    r = _find_part(T, t)
    isnothing(r) || return r
    _walk_chain(T, t)
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

function _extract_interval_fields(layer, orientation::Symbol=:horizontal; default_value="value")
    table = extract_data(layer)
    if orientation === :horizontal
        value_sel = length(layer.positional) >= 1 ? layer.positional[1] : nothing
        value_field = isnothing(value_sel) ? default_value : _field_name(value_sel)
        value_label = isnothing(value_sel) ? default_value : _field_label(value_sel)
        group_field = haskey(layer.named, :y) ? _field_name(layer.named[:y]) : nothing
        group_label = haskey(layer.named, :y) ? _field_label(layer.named[:y]) : nothing
    elseif orientation === :vertical
        length(layer.positional) >= 2 || error("interval analysis with orientation=:vertical expects `mapping(category, value)` — two positional mappings; got $(length(layer.positional))")
        group_field = _field_name(layer.positional[1])
        group_label = _field_label(layer.positional[1])
        value_field = _field_name(layer.positional[2])
        value_label = _field_label(layer.positional[2])
    else
        error("orientation must be :horizontal or :vertical, got :$orientation")
    end
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)
    (; table, value_field, value_label, group_field, group_label,
       color_field, color_label, facet, facet_fields, orientation)
end

_interval_axes(orientation::Symbol) = orientation === :vertical ?
    (value_axis="y", value2_axis="y2", group_axis="x", offset_key="xOffset") :
    (value_axis="x", value2_axis="x2", group_axis="y", offset_key="yOffset")

function _add_group_color_encoding!(enc, group_field, color_field, group_axis::String, offset_key::String;
                                      group_label=nothing, color_label=nothing, show_axis_title=true)
    if !isnothing(group_field)
        g_enc = Dict{String,Any}("field" => group_field, "type" => "nominal")
        !show_axis_title && (g_enc["axis"] = Dict{String,Any}("title" => nothing))
        !isnothing(group_label) && group_label != group_field && (g_enc["title"] = group_label)
        enc[group_axis] = g_enc
    end
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        enc["color"] = color_enc
        !isnothing(group_field) && (enc[offset_key] = Dict{String,Any}("field" => color_field, "type" => "nominal"))
    elseif !isnothing(group_field)
        enc["color"] = Dict{String,Any}("field" => group_field, "type" => "nominal", "legend" => nothing)
    end
    enc
end

function _interval_point_layer(group_field, color_field, group_axis::String, offset_key::String;
                                 point_field::String="__point__", value_axis::String="x",
                                 mark_opts...)
    pt_enc = Dict{String,Any}(
        value_axis => Dict{String,Any}("field" => point_field, "type" => "quantitative"),
    )
    if !isnothing(group_field)
        pt_enc[group_axis] = Dict{String,Any}("field" => group_field, "type" => "nominal")
    end
    if !isnothing(color_field) && !isnothing(group_field)
        pt_enc[offset_key] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    end
    mark = Dict{String,Any}("type" => "point", "filled" => true, (string(k) => v for (k,v) in pairs(mark_opts))...)
    Dict{String,Any}("mark" => mark, "encoding" => pt_enc)
end

function _interval_tooltips(value_label, group_field, color_field, probs;
                              point_field::String="__point__")
    tt = Dict{String,Any}[Dict{String,Any}("field" => point_field, "type" => "quantitative", "title" => "$value_label (estimate)")]
    !isnothing(group_field) && push!(tt, Dict{String,Any}("field" => group_field, "type" => "nominal"))
    !isnothing(color_field) && color_field != group_field && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    widest = maximum(probs)
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("lo", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% lo"))
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("hi", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% hi"))
    tt
end

# --- Analysis → Vega-Lite spec ---

function analysis_to_vl(a::PointIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = length(sorted_probs) == 1 ? [8.0] : range(1.5, 8, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         value_axis=ax.value_axis, size=80, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::PrecomputedIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)

    col_names = Set(string.(Tables.columnnames(table)))
    value_field in col_names || error("Pre-aggregated pointinterval: point column \"$value_field\" not found in table. Available: $(sort(collect(col_names)))")
    for (lo, hi) in a.bands
        los, his = string(lo), string(hi)
        los in col_names || error("Pre-aggregated pointinterval: band column \"$los\" not found in table. Available: $(sort(collect(col_names)))")
        his in col_names || error("Pre-aggregated pointinterval: band column \"$his\" not found in table. Available: $(sort(collect(col_names)))")
    end

    summary = table_to_rows(table)
    stroke_widths = length(a.bands) == 1 ? [8.0] : range(1.5, 8, length=length(a.bands))

    layers = Dict{String,Any}[]
    for (i, (lo, hi)) in enumerate(a.bands)
        lo_col, hi_col = string(lo), string(hi)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => lo_col, "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => hi_col),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         point_field=value_field, value_axis=ax.value_axis,
                                         size=80, color="white"))

    widest_lo = string(first(a.bands[1]))
    widest_hi = string(last(a.bands[1]))
    tt = Dict{String,Any}[
        Dict{String,Any}("field" => value_field, "type" => "quantitative", "title" => "$value_label (estimate)"),
    ]
    !isnothing(group_field) && push!(tt, Dict{String,Any}("field" => group_field, "type" => "nominal"))
    !isnothing(color_field) && color_field != group_field && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    push!(tt, Dict{String,Any}("field" => widest_lo, "type" => "quantitative", "title" => widest_lo))
    push!(tt, Dict{String,Any}("field" => widest_hi, "type" => "quantitative", "title" => widest_hi))
    _add_analysis_tooltips!(layers, tt)

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::GradientIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.7, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
            "opacity" => Dict{String,Any}("value" => opacities[i]),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => 14),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         value_axis=ax.value_axis, size=50, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

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
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)

    vals = Tables.getcolumn(table, Symbol(value_field))
    key_fields = String[f for f in [group_field, color_field, facet_fields..., detail_strs...] if !isnothing(f)]
    idx_groups = _group_indices(_key_columns(table; fields=key_fields))

    # Quantile dots
    dot_rows = Dict{String,Any}[]
    for (key, idxs) in idx_groups
        v = sort!(vals[idxs])
        n = length(v)
        ki_base = 0
        gk = isnothing(group_field) ? nothing : key[ki_base += 1]
        ck = isnothing(color_field) ? nothing : key[ki_base += 1]
        for i in 1:a.n_dots
            q = quantile(v, (i - 0.5) / a.n_dots; sorted=true)
            row = Dict{String,Any}("quantile" => q)
            !isnothing(gk) && (row[group_field] = gk)
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

    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    # Dot layer
    dot_enc = Dict{String,Any}(
        ax.value_axis => Dict{String,Any}("field" => "quantile", "type" => "quantitative", "title" => value_label,
                                           "bin" => Dict{String,Any}("maxbins" => 40)),
        "size" => Dict{String,Any}("aggregate" => "count", "legend" => nothing),
    )
    _add_group_color_encoding!(dot_enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                group_label, color_label, show_axis_title=false)

    layers = Dict{String,Any}[
        Dict{String,Any}(
            "data" => Dict{String,Any}("values" => dot_rows),
            "mark" => Dict{String,Any}("type" => "circle", "opacity" => 0.6, "size" => 30),
            "encoding" => dot_enc,
        )
    ]

    # Interval sublayers
    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = length(sorted_probs) == 1 ? [5.0] : range(1.5, 5, length=length(sorted_probs))
    interval_layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative"),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label)
        push!(interval_layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i], "color" => "#333"),
            "encoding" => enc,
        ))
    end

    push!(interval_layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                                   value_axis=ax.value_axis,
                                                   size=50, color="white", stroke="#333", strokeWidth=1.5))
    _add_analysis_tooltips!(interval_layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

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
    has_band = !isnothing(analysis) && !isnothing(analysis.interval) && !_is_automatic(analysis.interval)

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
    has_band = !isnothing(analysis) && !isnothing(analysis.interval) && !_is_automatic(analysis.interval)

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

    # Read the HistogramAnalysis struct so bins / datalimits / normalization
    # from `histogram(; bins=N, datalimits=…, normalization=…)` actually
    # reach the emitted VL spec.
    ha = extract_transformation(layer, AlgebraOfGraphics.HistogramAnalysis)
    bin_params, count_op = _histogram_bin_config(ha)

    # Collect facet (row/col) and other named channels separately. Row/col
    # land in a `facet` dict that is hoisted via _wrap_with_facet! so
    # `config(facet=(; linkxaxes=:none))`'s `resolve.scale.<axis>` lands in
    # scope.
    facet = Dict{String,Any}()
    other_named = Dict{Symbol,Any}()
    for (name, sel) in pairs(layer.named)
        if name === :row || name === :col
            facet_ch = name === :col ? "column" : "row"
            facet[facet_ch] = selector_to_field(sel)
            haskey(facet[facet_ch], "type") || (facet[facet_ch]["type"] = "nominal")
            continue
        end
        other_named[name] = sel
    end

    # When facet is present, emit bin + aggregate as transforms inside the
    # inner spec. VL runs those per-facet-cell, so each facet row/column
    # gets its own bin extents (matches AoG/Makie behavior under
    # linkxaxes=:none). Without facet, keep the simple encoding.x.bin=true
    # path since there's only one scale.
    color_sel = get(other_named, :color, nothing)
    color_field = isnothing(color_sel) ? nothing : _field_name(color_sel)

    if !isempty(facet)
        groupby = String["__bin_lo__", "__bin_hi__"]
        isnothing(color_field) || push!(groupby, color_field)
        transforms = Dict{String,Any}[
            Dict{String,Any}("bin" => bin_params, "field" => x_field,
                             "as" => ["__bin_lo__", "__bin_hi__"]),
            Dict{String,Any}("aggregate" => [Dict{String,Any}("op" => count_op, "as" => "__count__")],
                             "groupby" => groupby),
        ]
        x_enc = Dict{String,Any}("field" => "__bin_lo__", "bin" => "binned", "type" => "quantitative")
        x_label != x_field && (x_enc["title"] = x_label)
        encoding = Dict{String,Any}(
            "x" => x_enc,
            "x2" => Dict{String,Any}("field" => "__bin_hi__"),
            "y" => Dict{String,Any}("field" => "__count__", "type" => "quantitative"),
        )
        for (name, sel) in other_named
            ch = aog_named_to_vl_channel(name)
            isnothing(ch) && continue
            encoding[ch] = selector_to_field(sel)
        end
        !isnothing(table) && infer_types!(encoding, table)
        spec = Dict{String,Any}(
            "transform" => transforms,
            "mark" => "bar",
            "encoding" => encoding,
        )
        !isnothing(table) && (spec["data"] = data_to_vl(table))
        _wrap_with_facet!(spec, facet)
        return spec
    end

    # Non-faceted path: single global bin scale. Use encoding-level bin
    # when possible; fall back to a transform when bin_params carries
    # structured config (since `encoding.x.bin` also accepts a Dict).
    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative", "bin" => bin_params)
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
        "y" => Dict{String,Any}("aggregate" => count_op, "type" => "quantitative"),
    )
    for (name, sel) in other_named
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end
    !isnothing(table) && infer_types!(encoding, table)

    spec = Dict{String,Any}(
        "mark" => "bar",
        "encoding" => encoding,
    )
    !isnothing(table) && (spec["data"] = data_to_vl(table))
    spec
end

# Translate a HistogramAnalysis's struct config into (bin_params, count_op)
# for use in the VL bin transform / encoding.
#
# - `bins::Integer` → `{"maxbins": N}`
# - `bins::AbstractVector` → `{"step": step, "extent": [first, last]}` —
#   only handles uniformly-spaced vectors; non-uniform bins aren't expressible
#   declaratively in VL, so we fall back to step=first-diff.
# - `datalimits::Tuple{<:Real,<:Real}` → adds `"extent": [lo, hi]` (a
#   function like `extrema` stays automatic — the inner-spec per-facet
#   transform handles per-group extents already).
# - `normalization ∈ (:probability, :pdf, :density, :none)` → maps to the
#   VL aggregate operator (`count` vs VL's built-in `sum` with weights is
#   not sufficient for true density / pdf; emit a warning for those).
function _histogram_bin_config(ha)
    bp = Dict{String,Any}()
    count_op = "count"
    isnothing(ha) && return (true, count_op)

    # bins
    _apply_bins!(bp, ha.bins)

    # datalimits
    _apply_datalimits!(bp, ha.datalimits)

    # normalization: VL's aggregate only supports count/sum natively.
    # Non-count normalizations need a post-aggregate calculate transform;
    # not implemented yet. Emit a one-shot warning so the user knows the
    # y-axis is raw counts instead of the requested normalization.
    norm = hasproperty(ha, :normalization) ? ha.normalization : :none
    if norm !== :none && norm !== :count
        @warn "AlgebraOfVega: histogram(; normalization=$(repr(norm))) not yet wired into VL — rendering as raw counts. Open an issue if you need this." maxlog=1
    end

    bin_params = isempty(bp) ? true : bp
    (bin_params, count_op)
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

Supports `color=`, `linestyle=`, `group=`, and `detail=` grouping via
`groupby` on the window transforms (so each group gets its own ECDF
curve). `group=`/`detail=` produce a `detail` encoding so Vega draws
separate lines without coloring them differently -- useful when
overlaying many posterior-draw ECDFs and a per-draw color legend would
just be noise.
"""
function ecdf_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    linestyle_field = haskey(layer.named, :linestyle) ? _field_name(layer.named[:linestyle]) : nothing
    linestyle_label = haskey(layer.named, :linestyle) ? _field_label(layer.named[:linestyle]) : nothing
    # `group` and `detail` both partition without a visual channel; treat
    # them interchangeably (AoG accepts `group`, Vega-Lite uses `detail`).
    detail_key = haskey(layer.named, :detail) ? :detail :
                 haskey(layer.named, :group)  ? :group  : nothing
    detail_field = isnothing(detail_key) ? nothing : _field_name(layer.named[detail_key])
    detail_label = isnothing(detail_key) ? nothing : _field_label(layer.named[detail_key])

    # Window transforms for ECDF:
    # 1. Sort by x, count cumulative (per group)
    # 2. Count total (per group)
    # 3. Calculate ecdf = cumulative / total
    groupby_fields = String[]
    !isnothing(color_field) && push!(groupby_fields, color_field)
    !isnothing(linestyle_field) && push!(groupby_fields, linestyle_field)
    !isnothing(detail_field) && push!(groupby_fields, detail_field)

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
    if !isnothing(detail_field)
        d_enc = Dict{String,Any}("field" => detail_field, "type" => "nominal")
        !isnothing(detail_label) && detail_label != detail_field && (d_enc["title"] = detail_label)
        encoding["detail"] = d_enc
    end

    # Auto tooltip
    tt = vl_tooltips(encoding)
    !isempty(tt) && (encoding["tooltip"] = tt)

    vis = extract_visual(layer)
    mark = Dict{String,Any}("type" => "line", "interpolate" => "step-after")
    if !isnothing(vis)
        merge!(mark, visual_attrs_to_mark_props(vis))
    end

    # Detect per-group x cardinality. A group with only 1 unique x is a
    # point-mass distribution -- the empirical CDF is a vertical jump
    # from 0 to 1 at that x. Vega-Lite's `line` mark with all rows at
    # the same x renders to nothing visible (zero horizontal extent),
    # even with `step-after` interpolation. So for such groups we emit
    # a `rule` mark (true 1D vertical from y=0 to y=1) instead. Bypasses
    # the window transforms entirely -- duplicate rows in the data are
    # harmless because the rule paints the same pixels.
    degen_keys, normal_keys = _ecdf_partition_groups(table, x_field, groupby_fields)
    all_degen   = !isempty(degen_keys) && isempty(normal_keys)
    has_normal  = !isempty(normal_keys)
    has_degen   = !isempty(degen_keys)

    rule_layer = nothing
    if has_degen
        rule_enc = copy(encoding)
        rule_enc["y"]  = Dict{String,Any}("datum" => 0,
                                          "type"  => "quantitative",
                                          "title" => "Cumulative Proportion")
        rule_enc["y2"] = Dict{String,Any}("datum" => 1)
        delete!(rule_enc, "tooltip")  # __ecdf__ doesn't exist on this layer
        # rebuild tooltip from x + groupby only
        rt = vl_tooltips(rule_enc)
        !isempty(rt) && (rule_enc["tooltip"] = rt)
        rule_mark = Dict{String,Any}("type" => "rule")
        !isnothing(vis) && merge!(rule_mark, visual_attrs_to_mark_props(vis))
        rule_layer = Dict{String,Any}(
            "mark"     => rule_mark,
            "encoding" => rule_enc,
        )
        # Filter to degenerate groups only (single-field groupby case);
        # multi-field groupby falls back to no filter when mixed (rare;
        # current BRM use cases only ever group by `:draw`).
        if has_normal && length(groupby_fields) == 1
            rule_layer["transform"] = [Dict{String,Any}(
                "filter" => Dict{String,Any}(
                    "field"  => groupby_fields[1],
                    "oneOf"  => collect(degen_keys),
                ),
            )]
        end
    end

    line_layer = nothing
    if has_normal || !has_degen  # no-data case still gets the line spec
        line_enc = encoding
        line_layer = Dict{String,Any}(
            "mark"      => mark,
            "transform" => [window1, window2, calc],
            "encoding"  => line_enc,
        )
        if has_degen && length(groupby_fields) == 1
            pushfirst!(line_layer["transform"], Dict{String,Any}(
                "filter" => Dict{String,Any}(
                    "field"  => groupby_fields[1],
                    "oneOf"  => collect(normal_keys),
                ),
            ))
        end
    end

    spec = if all_degen
        rule_layer
    elseif !has_degen
        line_layer
    else
        Dict{String,Any}("layer" => [rule_layer, line_layer])
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
        # Infer types on every encoding actually present in the final
        # spec -- when `all_degen`, `encoding` belongs to the discarded
        # line layer and inferring types on it would be a no-op for the
        # rule spec.
        for enc in (haskey(spec, "layer") ?
                    [l["encoding"] for l in spec["layer"]] :
                    [spec["encoding"]])
            infer_types!(enc, table)
        end
    end
    spec
end

# Inspect `table` and return (degenerate_keys, normal_keys) where the
# keys are the unique values of the single-field groupby case (or
# tuples for multi-field). "Degenerate" means the group has only 1
# unique x value -- visually a point-mass and broken for line marks.
# When `groupby_fields` is empty, treats the entire table as one group
# and returns ([nothing], []) if degenerate, ([], [nothing]) if not.
function _ecdf_partition_groups(table, x_field::AbstractString,
                                groupby_fields::Vector{String})
    isnothing(table) && return (Any[], Any[])
    rows = Tables.rows(table)
    xs_per_group = Dict{Any,Set{Any}}()
    if isempty(groupby_fields)
        xs = Set{Any}()
        for r in rows
            push!(xs, getproperty(r, Symbol(x_field)))
        end
        return length(xs) == 1 ? (Any[nothing], Any[]) :
                                 (Any[], Any[nothing])
    end
    one_field = length(groupby_fields) == 1
    f1 = Symbol(groupby_fields[1])
    for r in rows
        key = one_field ? getproperty(r, f1) :
              Tuple(getproperty(r, Symbol(f)) for f in groupby_fields)
        bucket = get!(xs_per_group, key) do; Set{Any}() end
        push!(bucket, getproperty(r, Symbol(x_field)))
    end
    degen, normal = Any[], Any[]
    for (k, xs) in xs_per_group
        push!(length(xs) == 1 ? degen : normal, k)
    end
    degen, normal
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
        _harmonize_axis_types!(layer_specs)
        spec["data"] = Dict{String,Any}("values" => merged_values)
        spec["facet"] = outer_facet
        spec["spec"] = Dict{String,Any}("layer" => layer_specs)
    else
        _harmonize_axis_types!(layer_specs)
        spec["layer"] = layer_specs
    end

    spec
end

# For sibling sublayers that encode the same `field` on the same axis
# (x / y) but disagree on `type`, coerce all to the most conservative
# (nominal) type. Fixes the "Unrecognized scale name: child_layer_N_x"
# compile failure when e.g. a vertical pointinterval (group axis hardcoded
# nominal) is overlaid with a `visual(Scatter)` whose Int-column positional
# gets inferred as quantitative: VL emits per-layer band+linear scales that
# don't cross-reference.
#
# Nominal is the safe coercion: any value can be treated as a category,
# while quantitative requires numeric values — string categories can't be
# widened without data loss.
# Get `ls.encoding[axis]` as a Dict, or nothing if any step doesn't fit.
_axis_enc(ls::Dict, axis) = let enc = _as_dict(get(ls, "encoding", nothing))
    isnothing(enc) ? nothing : _as_dict(get(enc, axis, nothing))
end
_axis_enc(_, _) = nothing

function _harmonize_axis_types!(layer_specs::Vector{Dict{String,Any}})
    for axis in ("x", "y")
        # field → any sublayer has `type=nominal` for it
        nominal_fields = Set{String}()
        for ls in layer_specs
            ae = _axis_enc(ls, axis)
            isnothing(ae) && continue
            f = _as_str(get(ae, "field", nothing))
            isnothing(f) && continue
            get(ae, "type", nothing) == "nominal" && push!(nominal_fields, f)
        end
        isempty(nominal_fields) && continue
        for ls in layer_specs
            ae = _axis_enc(ls, axis)
            isnothing(ae) && continue
            f = _as_str(get(ae, "field", nothing))
            (!isnothing(f) && f in nominal_fields) || continue
            get(ae, "type", nothing) == "nominal" && continue
            ae["type"] = "nominal"
            # Drop scale config that's meaningless for nominal axes
            sc = _as_dict(get(ae, "scale", nothing))
            if !isnothing(sc)
                st = _as_str(get(sc, "type", nothing))
                if !isnothing(st) && st in ("log", "sqrt", "pow", "symlog")
                    delete!(sc, "type")
                end
                isempty(sc) && delete!(ae, "scale")
            end
        end
    end
    layer_specs
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
                probs = _analysis_probs(analysis)
                point_sym = hasproperty(analysis, :point) ? analysis.point : :median

                # Use VL quantile transforms for intervals within facet
                sorted_probs = sort(probs, rev=true)
                is_gradient = _is_gradient(analysis)

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
        ev_dict = _as_dict(ev)
        target_dict = _as_dict(get(target_enc, sek, nothing))
        if !isnothing(ev_dict) && !isnothing(target_dict)
            merge!(target_dict, Dict{String,Any}(string(k2) => v2 for (k2, v2) in ev_dict))
        else
            target_enc[sek] = ev
        end
    end
end

# Recurse the merge into a child spec only when it's actually a Dict.
_merge_into_child!(args...) = nothing
_merge_into_child!(child::Dict, config_enc::Dict) = _merge_encoding_config!(child, config_enc)

function _merge_encoding_config!(spec::Dict, config_enc::Dict)
    if haskey(spec, "encoding")
        _deep_merge_encoding!(spec["encoding"], config_enc)
    end
    if haskey(spec, "layer")
        for sublayer in spec["layer"]
            _merge_into_child!(sublayer, config_enc)
        end
    end
    if haskey(spec, "spec")
        _merge_into_child!(spec["spec"], config_enc)
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
_as_pair(t::Tuple{Any,Any}) = t
_as_pair(_) = nothing

function _axis_nt_to_encoding_override(nt)
    override = Dict{String,Any}()
    limits = _as_pair(get(nt, :limits, nothing))
    isnothing(limits) && return override
    do_clamp = get(nt, :clamp, false) === true
    for (idx, ch) in enumerate(("x", "y"))
        lim = _as_pair(limits[idx])
        isnothing(lim) && continue
        scale_dict = Dict{String,Any}("domain" => [lim[1], lim[2]])
        do_clamp && (scale_dict["clamp"] = true)
        override[ch] = Dict{String,Any}("scale" => scale_dict)
    end
    override
end

# Narrow a config-prop to the type our sugar handlers expect, or `nothing`.
_as_scales(s::AlgebraOfGraphics.Scales) = s
_as_scales(_) = nothing
_as_nt(nt::NamedTuple) = nt
_as_nt(_) = nothing

# Sugar appliers — dispatch the work over the `val` type. The Any fallback is
# what fires when the prop key exists but the value isn't of the expected shape.
_apply_scales_sugar!(args...) = nothing
_apply_scales_sugar!(spec, s::AlgebraOfGraphics.Scales) =
    let override = _scales_to_encoding_override(s)
        isempty(override) || _merge_encoding_config!(spec, override)
    end

_apply_facet_sugar!(args...) = nothing
_apply_facet_sugar!(spec, nt::NamedTuple) =
    _merge_resolve_scale!(spec, _facet_nt_to_resolve_scale(nt))

_apply_axis_sugar!(args...) = nothing
_apply_axis_sugar!(spec, nt::NamedTuple) =
    let override = _axis_nt_to_encoding_override(nt)
        isempty(override) || _merge_encoding_config!(spec, override)
    end

# Sugar for VL resolve: independent_scales=true, =:x, =(:x,:y)
_independent_axes(val::Bool) = val === true ? ["x", "y"] : String[]
_independent_axes(val::Symbol) = [string(val)]
_independent_axes(val) = [string(v) for v in val]

_select_field_list(s::Symbol) = [s]
_select_field_list(v) = v

# `mark` in a VL spec can be a Dict (with `type` key) or a String shorthand.
_mark_type(d::Dict) = get(d, "type", "")
_mark_type(s::String) = s
_mark_type(_) = ""

function to_vegalite(v::VegaSpec)
    spec = to_vegalite(v.drawable)
    select_fields = nothing
    if !isnothing(v.config)
        props = v.config.properties
        # First pass: apply AoG-style sugar (scales, facet) so user-supplied
        # `encoding=Dict(...)` in the second pass can still override on conflict.
        haskey(props, :scales) && _apply_scales_sugar!(spec, props[:scales])
        haskey(props, :facet) && _apply_facet_sugar!(spec, props[:facet])
        haskey(props, :axis) && _apply_axis_sugar!(spec, props[:axis])
        for (k, val) in props
            sk = string(k)
            # Deep-merge encoding so config adds to (not overwrites) auto-generated channels
            if sk == "encoding" && !isnothing(_as_dict(val))
                _merge_encoding_config!(spec, val)
            elseif sk in ("width", "height") && haskey(spec, "spec")
                # For faceted specs, width/height go into the inner spec
                spec["spec"][sk] = val
            elseif sk == "scales" && !isnothing(_as_scales(val))
                # Handled in first pass
            elseif sk == "facet" && !isnothing(_as_nt(val))
                # Handled in first pass
            elseif sk == "axis" && !isnothing(_as_nt(val))
                # Handled in first pass
            elseif sk == "independent_scales"
                @warn "AlgebraOfVega: `config(independent_scales=$(repr(val)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
                axes = _independent_axes(val)
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
                select_fields = _select_field_list(val)
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
_drawable_table(l::AlgebraOfGraphics.Layer) = extract_data(l)
function _drawable_table(ls::AlgebraOfGraphics.Layers)
    for l in ls.layers
        t = extract_data(l)
        isnothing(t) || return t
    end
    nothing
end
_drawable_table(_) = nothing

function add_select_filters!(spec::Dict{String,Any}, drawable, fields)
    table = _drawable_table(drawable)
    isnothing(table) && return spec

    params = get!(spec, "params", Dict{String,Any}[])
    transforms = get!(spec, "transform", Dict{String,Any}[])

    # For layered specs, transforms go at the top level (shared data)
    # For single-view specs, they also go at the top level
    for field in fields
        field_str = string(field)
        param_name = "select_$(field_str)"

        # Get unique values
        field in Tables.columnnames(table) || continue
        vals = sort(unique(Tables.getcolumn(table, field)))

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
    mark_type = _mark_type(mark)
    is_composite = _is_composite_mark(spec)

    # Skip all interactivity for composite marks (boxplot, errorbar, errorband)
    # — VL doesn't support selections on them
    is_composite && return spec

    # Check for aggregate encodings (count, mean, etc.) — zoom can't project on those
    function _has_aggregate(enc_dict, ch)
        isnothing(enc_dict) && return false
        d = _as_dict(get(enc_dict, ch, nothing))
        !isnothing(d) && haskey(d, "aggregate")
    end

    # Find color field from top-level encoding only.
    # Legend binding doesn't work reliably for layered specs where color is only in sublayers.
    color_field = nothing
    if !isnothing(enc)
        color_enc = _as_dict(get(enc, "color", nothing))
        isnothing(color_enc) || (color_field = get(color_enc, "field", nothing))
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
                sl_mark = _as_dict(get(sl, "mark", nothing))
                mark_has_opacity = !isnothing(sl_mark) && haskey(sl_mark, "opacity")
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

            /* AoV utility classes (domain-specific; generic ones use HTMXObjects u-* utilities) */
            .aov-plot-area { width: 100%; min-width: 0; }
            .aov-w-8 { width: 8rem; }
            .aov-w-50 { width: 50%; }
            .aov-w-60 { width: 60%; }
            .aov-img-fluid { max-width: 100%; }
            .aov-flex-1 { flex: 1; }
            .aov-grid-cell { border: 1px solid var(--pico-muted-border-color); border-radius: 0.2rem; padding: 0.2rem; overflow: hidden; min-width: 0; }
            .aov-grid-cell-failed { opacity: 0.4; }
            .aov-grid-cell-title { font-weight: bold; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-bottom: 0.1rem; }
            .aov-grid-page { width: 100vw; padding: 0.5rem; font-size: 0.5em; }
            .aov-grid-16 { display: grid; grid-template-columns: repeat(16, 1fr); gap: 0.25rem; }
            .aov-grid-4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.5rem; }
            .aov-card { margin: 0; padding: 0.5rem; min-width: 0; overflow: hidden; }
            .aov-card-header { padding: 0 0 0.25rem; margin: 0; display: flex; align-items: center; flex-wrap: wrap; }
            .aov-card-title-link { font-size: 0.9em; font-weight: bold; text-decoration: none; }
            .aov-card-title { font-size: 0.9em; font-weight: bold; }
            .aov-mr-auto { margin-right: auto; }
            .aov-cb-mid { vertical-align: middle; margin-right: 0.3em; }
            .aov-context-bar { padding: 0.5rem 0; font-size: 0.75em; opacity: 0.6; display: flex; gap: 1em; align-items: center; }
            .aov-plot-nav { display: flex; flex-wrap: wrap; gap: 0.25rem; margin-bottom: 1rem; align-items: center; }
            .aov-back-link { font-size: 0.9em; }
            .aov-plot-row { display: flex; gap: 1rem; }
            .aov-plot-row-tight { display: flex; gap: 0.5rem; margin-top: 1rem; }
            .aov-plot-nav-btn { margin: 0.1rem; font-size: 0.85em; padding: 0.3rem 0.6rem; }
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
        push!(children, h.label(; class="u-pointer")(
            h.input(; type="checkbox", class="aov-actions-toggle aov-cb-mid",
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
    h.div(; class="aov-context-bar")(children...)
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
    data_vals = _as_vec(get(get(vl, "data", Dict()), "values", nothing))
    isnothing(data_vals) && return 1
    vals = Set()
    for row in data_vals
        _push_row_value!(vals, row, col_field)
    end
    n = length(vals)
    return n > 0 ? n : 1
end

_push_row_value!(args...) = nothing
function _push_row_value!(vals, row::Dict, col_field)
    haskey(row, col_field) && push!(vals, row[col_field])
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

        _buildSortableTable: function(rows, cols) {
            var table = document.createElement('table');
            table.className = 'striped';
            table.setAttribute('role', 'grid');
            if (!rows || !rows.length) {
                table.innerHTML = '<tbody><tr><td>(empty)</td></tr></tbody>';
                return table;
            }
            if (!cols) {
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
                cols = stringCols.concat(numericCols);
            }
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

        // Public: toggle between Pretty and Raw views inside a captioned plot's
        // <details>. Lazily renders the chosen view on first switch.
        toggleDataView: function(btn, view) {
            var details = btn.closest('details');
            if (!details) return;
            details.querySelectorAll('.aov-toggle-btn').forEach(function(b) {
                var on = b.dataset.view === view;
                b.classList.toggle('aov-toggle-active', on);
                if (on) b.setAttribute('aria-pressed', 'true');
                else b.removeAttribute('aria-pressed');
            });
            var pretty = details.querySelector('.aov-data-pretty');
            var raw = details.querySelector('.aov-data-raw');
            if (pretty) pretty.hidden = view !== 'pretty';
            if (raw) raw.hidden = view !== 'raw';
            this._lazyRenderDataView(details, view);
        },

        _lazyRenderDataView: function(details, view) {
            if (view === 'raw') {
                var body = details.querySelector('.aov-data-raw-body');
                if (body && body.dataset.aovRendered !== '1') {
                    var pid = body.dataset.aovPlotId;
                    var labels = body.dataset.aovLabels ? JSON.parse(body.dataset.aovLabels) : {};
                    if (pid) this.showPlotData(pid, body, labels);
                }
            } else if (view === 'pretty') {
                var body = details.querySelector('.aov-data-pretty-body');
                if (body && body.dataset.aovRendered !== '1') {
                    var pid = body.dataset.aovPlotId;
                    var opts = body.dataset.aovSummaryOpts ? JSON.parse(body.dataset.aovSummaryOpts) : {};
                    if (pid) this.renderPrettySummary(pid, body, opts);
                }
            }
        },

        // Public: render a "point [lo, hi]" pretty summary table from the live
        // Vega view's source_0, which already holds the aggregated columns
        // produced by Julia. Two modes:
        //   1. Auto-detect: looks for __point__ or __median__ as the central col,
        //      and lo_<prob>_ / hi_<prob>_ pairs for the intervals (used by
        //      pointinterval/gradient/dot/lineribbon).
        //   2. Explicit (opts.bands): caller passes [[loCol, hiCol, label], ...]
        //      and opts.point_col (used by lineribbon(bands=...) precomputed).
        //
        //   opts.ci: 'outer' (default, widest band) | 'inner' | Number (closest prob)
        //   opts.sigfigs: significant figures for numeric formatting (default 2)
        //   opts.value_label: header for the formatted value column (default 'value')
        //   opts.point_label: 'Median' (default) | 'Mean' | custom — used in caption
        renderPrettySummary: function(id, container, opts) {
            opts = opts || {};
            if (container.dataset.aovRendered === '1') return;
            var rows = this._plotData(id);
            if (!rows || !rows.length) {
                container.textContent = '(no summary data available)';
                container.dataset.aovRendered = '1';
                return;
            }
            var groups = this._splitBySource(rows);
            container.innerHTML = '';
            var labels = opts.labels || {};
            var self = this;
            groups.forEach(function(g) {
                if (g.label !== null) {
                    var heading = document.createElement('h6');
                    heading.textContent = labels[g.label] || g.label;
                    heading.style.margin = '0.5rem 0 0.25rem';
                    container.appendChild(heading);
                }
                var built = self._buildPrettyRows(g.rows, opts);
                if (!built) {
                    container.appendChild(self._buildSortableTable(g.rows));
                    return;
                }
                if (built.caption) {
                    var cap = document.createElement('figcaption');
                    cap.textContent = built.caption;
                    cap.style.cssText = 'font-size:0.85em;opacity:0.75;margin:0 0 0.25rem';
                    container.appendChild(cap);
                }
                container.appendChild(self._buildSortableTable(built.rows, built.cols));
            });
            container.dataset.aovRendered = '1';
        },

        _buildPrettyRows: function(rows, opts) {
            if (!rows || !rows.length) return null;
            var first = rows[0];
            var pointCol = opts.point_col ||
                ('__point__' in first ? '__point__' :
                 ('__median__' in first ? '__median__' : null));
            if (!pointCol || !(pointCol in first)) return null;

            var bands; // [{lo, hi, label}, ...] sorted inner→outer
            if (opts.bands && opts.bands.length) {
                // AoV passes explicit bands outermost-first (lineribbon convention);
                // internal representation is inner→outer to match the auto-detect path.
                bands = opts.bands.slice().reverse().map(function(b) {
                    return {lo: b[0], hi: b[1], label: b[2] || (b[0] + ' / ' + b[1])};
                });
            } else {
                var probMap = {};
                Object.keys(first).forEach(function(c) {
                    var m = /^lo_(\d+(?:_\d+)?)_$/.exec(c);
                    if (m && ('hi_' + m[1] + '_') in first) {
                        probMap[m[1]] = parseFloat(m[1].replace('_', '.'));
                    }
                });
                var probKeys = Object.keys(probMap);
                if (!probKeys.length) return null;
                probKeys.sort(function(a, b) { return probMap[a] - probMap[b]; });
                bands = probKeys.map(function(k) {
                    return {
                        lo: 'lo_' + k + '_',
                        hi: 'hi_' + k + '_',
                        label: Math.round(probMap[k] * 100) + '%',
                        prob: probMap[k]
                    };
                });
            }

            var pick;
            var ci = opts.ci;
            if (typeof ci === 'number' && bands[0].prob !== undefined) {
                pick = bands[0]; var bestDiff = Math.abs(pick.prob - ci);
                bands.forEach(function(b) {
                    var d = Math.abs(b.prob - ci);
                    if (d < bestDiff) { pick = b; bestDiff = d; }
                });
            } else if (ci === 'inner') {
                pick = bands[0];
            } else {
                pick = bands[bands.length - 1];
            }

            var sigfigs = (opts.sigfigs === undefined) ? 2 : opts.sigfigs;
            var fmt = function(x) {
                if (x === null || x === undefined || (typeof x === 'number' && isNaN(x))) return '';
                if (typeof x !== 'number') return String(x);
                return parseFloat(x.toPrecision(sigfigs)).toString();
            };
            var label = opts.value_label || 'value';
            var pointLabel = opts.point_label || 'Median';

            var hidden = {};
            hidden[pointCol] = 1;
            bands.forEach(function(b) { hidden[b.lo] = 1; hidden[b.hi] = 1; });

            var visibleSourceCols = Object.keys(first).filter(function(c) {
                if (hidden[c]) return false;
                if (c.indexOf('__') === 0) return false;
                return true;
            });
            // Categorical first (alpha), then numeric (alpha), then the value col.
            var stringCols = [], numericCols = [];
            visibleSourceCols.forEach(function(c) {
                var isNumeric = false;
                for (var i = 0; i < rows.length; i++) {
                    var v = rows[i][c];
                    if (v === null || v === undefined || v === '') continue;
                    isNumeric = (typeof v === 'number');
                    break;
                }
                (isNumeric ? numericCols : stringCols).push(c);
            });
            stringCols.sort(); numericCols.sort();
            var orderedCols = stringCols.concat(numericCols).concat([label]);

            var roundNum = function(v) {
                if (typeof v !== 'number' || isNaN(v)) return v;
                return parseFloat(v.toPrecision(sigfigs));
            };
            var built = rows.map(function(r) {
                var out = {};
                visibleSourceCols.forEach(function(c) { out[c] = roundNum(r[c]); });
                out[label] = fmt(r[pointCol]) + ' [' + fmt(r[pick.lo]) + ', ' + fmt(r[pick.hi]) + ']';
                return out;
            });

            var caption = pointLabel + ' [' + pick.label + (pick.prob !== undefined ? ' credible interval' : '') + ']';
            return {rows: built, cols: orderedCols, caption: caption};
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
                        if (l._keep_color) return;  // layer-fixed color (field outside remappable dims)
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

            // x/y axis remapping. Each swap: rewrite encoding.<axis>.field, re-infer
            // the type from a sample value in the data, refresh axis title and any
            // tooltip entry referencing the old field. Layers tagged `_no_axis_remap`
            // (planned: analysis layers with value axes bound to computed columns)
            // are skipped.
            function _inferType(v) {
                if (typeof v === 'number') return 'quantitative';
                if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return 'temporal';
                return 'nominal';
            }
            function _sampleVals() {
                if (spec.data && Array.isArray(spec.data.values)) return spec.data.values;
                if (spec.spec && spec.spec.data && Array.isArray(spec.spec.data.values)) return spec.spec.data.values;
                return null;
            }
            function _remapAxis(axis) {
                if (!(axis in mapping)) return;
                var newField = mapping[axis];
                if (!newField) return;  // empty = don't change (defensive: avoids breaking mandatory axes)
                var vals = _sampleVals();
                var sample = null;
                if (vals) {
                    for (var i = 0; i < vals.length; i++) {
                        if (vals[i] && vals[i][newField] !== undefined && vals[i][newField] !== null) {
                            sample = vals[i][newField]; break;
                        }
                    }
                }
                var newType = sample !== null ? _inferType(sample) : null;
                layers.forEach(function(l) {
                    if (!l || l._no_axis_remap) return;
                    var enc = l.encoding;
                    if (!enc || !enc[axis] || typeof enc[axis] !== 'object') return;
                    var oldField = enc[axis].field;
                    if (oldField === undefined) return;
                    enc[axis].field = newField;
                    if (newType) {
                        enc[axis].type = newType;
                        // When the axis type flips from quantitative to nominal, a log/sqrt
                        // scale no longer makes sense — drop it rather than leave VL with
                        // an invalid scale it will ignore with warnings.
                        if (newType !== 'quantitative' && enc[axis].scale && enc[axis].scale.type) {
                            var st = enc[axis].scale.type;
                            if (st === 'log' || st === 'sqrt' || st === 'pow') {
                                delete enc[axis].scale.type;
                            }
                        }
                    }
                    enc[axis].title = _fieldTitle(newField);
                    var tt = enc.tooltip;
                    if (Array.isArray(tt)) {
                        tt.forEach(function(t) {
                            if (t && t.field === oldField) {
                                t.field = newField;
                                t.title = _fieldTitle(newField);
                                if (newType) t.type = newType;
                            }
                        });
                    }
                });
            }
            _remapAxis('x');
            _remapAxis('y');

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
    inner = _as_dict(get(vl, "spec", nothing))
    if !isnothing(inner) && haskey(inner, "layer")
        return inner["layer"]
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
# Push the `field` key from a Dict-shaped channel encoding, if present.
_push_field!(args...) = nothing
function _push_field!(fields, ch_enc::Dict)
    haskey(ch_enc, "field") && push!(fields, ch_enc["field"])
end

function _push_channel_fields!(fields, container, channels)
    d = _as_dict(container)
    isnothing(d) && return
    for ch in channels
        _push_field!(fields, _as_dict(get(d, ch, nothing)))
    end
end

function _facet_fields(vl::Dict)
    fields = String[]
    _push_channel_fields!(fields, get(vl, "facet", nothing), ("row", "column"))
    _push_channel_fields!(fields, get(vl, "encoding", nothing), ("row", "column"))
    layers = _layer_array(vl)
    if layers !== nothing
        for l in layers
            _push_channel_fields!(fields, get(l, "encoding", nothing), ("row", "column", "color"))
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
    data_obj = _data_with_values(_as_dict(get(vl, "data", nothing)))
    if isnothing(data_obj)
        inner = _as_dict(get(vl, "spec", nothing))
        isnothing(inner) || (data_obj = _data_with_values(_as_dict(get(inner, "data", nothing))))
    end
    isnothing(data_obj) && return vl
    vals = _as_vec(data_obj["values"])
    isnothing(vals) && return vl

    for field in fields
        # Collect unique values from rows that already have this field
        uniques = Any[]
        seen = Set{Any}()
        for v in vals
            _collect_field_value!(uniques, seen, v, field)
        end
        isempty(uniques) && continue

        new_vals = Vector{Any}()
        for v in vals
            _replicate_or_keep!(new_vals, v, field, uniques)
        end
        vals = new_vals
    end
    data_obj["values"] = vals
    vl
end

_data_with_values(d::Dict) = haskey(d, "values") ? d : nothing
_data_with_values(_) = nothing

_as_vec(v::AbstractVector) = v
_as_vec(_) = nothing

_norm_string_list(v::AbstractVector) = string.(v)
_norm_string_list(::Nothing) = String[]
_norm_string_list(s::AbstractString) = isempty(s) ? String[] : [string(s)]
_norm_string_list(v) = [string(v)]

_to_string_vec(v::AbstractVector) = string.(v)
_to_string_vec(v) = [string(v)]

_dim_pair(d::Pair) = string(first(d)) => string(last(d))
_dim_pair(d) = string(d) => string(d)

_dim_first(d::Pair) = string(first(d))
_dim_first(d) = string(d)

_collect_field_value!(args...) = nothing
function _collect_field_value!(uniques, seen, v::Dict, field)
    haskey(v, field) || return
    u = v[field]
    if !(u in seen)
        push!(seen, u)
        push!(uniques, u)
    end
end

# When `v` lacks the facet field, replicate it across `uniques`. Otherwise keep as-is.
_replicate_or_keep!(new_vals, v, args...) = (push!(new_vals, v); nothing)
function _replicate_or_keep!(new_vals, v::Dict, field, uniques)
    if haskey(v, field)
        push!(new_vals, v)
    else
        for u in uniques
            nv = copy(v)
            nv[field] = u
            push!(new_vals, nv)
        end
    end
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
_as_vl_dict(d::Dict) = copy(d)
_as_vl_dict(s) = to_vegalite(s)

_as_number(n::Number) = n
_as_number(_) = nothing

# Look up a key in a per-signal entry. NamedTuple uses Symbol keys, Dict uses String.
_sig_get(sig::NamedTuple, key::Symbol) = getproperty(sig, key)
_sig_get(sig, key::Symbol) = sig[string(key)]
_sig_get(sig::NamedTuple, key::Symbol, default) = get(sig, key, default)
_sig_get(sig, key::Symbol, default) = get(sig, string(key), default)

function to_node(spec; id=nothing, width=nothing, height=nothing, actions=false, signals=nothing, fit_width=true)
    vl = _as_vl_dict(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    # Only apply fit_width defaults if no explicit width was set (via config or kwarg)
    has_explicit_width = !isnothing(_as_number(get(vl, "width", nothing)))
    inner_spec = _as_dict(get(vl, "spec", nothing))
    has_explicit_inner_width = !isnothing(inner_spec) && haskey(inner_spec, "width")
    if fit_width && !has_explicit_width && !has_explicit_inner_width && !haskey(vl, "hconcat") && !haskey(vl, "vconcat")
        # Detect faceting: explicit facet key, nested spec, or row/column encoding channels
        _enc = something(_as_dict(get(vl, "encoding", nothing)), Dict())
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
            sname = _sig_get(sig, :signal)
            surl = _sig_get(sig, :url)
            starget = _sig_get(sig, :target, "body")
            sswap = _sig_get(sig, :swap, "innerHTML")
            sdebounce = _sig_get(sig, :debounce, 300)
            signal_js *= "AoV.signalToHtmx('$id', '$sname', '$surl', '$starget', '$sswap', $sdebounce);\n"
        end
    end

    h.div(; class="aov-plot-area")(
        h.div(; id=id, class="u-w-full"),
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
    x_default=String[], y_default=String[],
    channels=[:color, :row, :column, :detail],
    pinned::Symbol=:color,
    fixed=Dict{Symbol,Any}(),
    extra_assigned::AbstractVector=String[])

    color_default = _norm_string_list(color_default)
    row_default = _norm_string_list(row_default)
    column_default = _norm_string_list(column_default)
    detail_default = _norm_string_list(detail_default)
    x_default = _norm_string_list(x_default)
    y_default = _norm_string_list(y_default)
    # x/y are single-select; keep only the first field if multiple are passed.
    length(x_default) > 1 && (x_default = x_default[1:1])
    length(y_default) > 1 && (y_default = y_default[1:1])
    defaults = Dict("color" => color_default, "row" => row_default,
                     "column" => column_default, "detail" => detail_default,
                     "x" => x_default, "y" => y_default)
    extra_assigned_norm = String[string(f) for f in extra_assigned]

    dims = [_dim_pair(d) for d in dimensions]

    # Normalize fixed
    fixed_norm = Dict{String,Vector{String}}()
    for (k, v) in fixed
        fixed_norm[string(k)] = _to_string_vec(v)
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
    # Positional (x/y) and any other fields the caller flags as "already used"
    # elsewhere in the plot. Even when :x/:y are not picker channels, their
    # positional fields should not get absorbed into the pinned catch-all.
    for f in extra_assigned_norm
        push!(assigned_elsewhere, f)
    end
    defaults[pinned_str] = [first(d) for d in dims if !(first(d) in assigned_elsewhere)]

    # Build kwargs for a channel's field list.
    # AoG mapping() uses :col (not :column) for column faceting.
    # x/y are positional in AoG — they aren't re-composed here; the JS
    # remapEncoding path rewrites encoding.x.field / encoding.y.field on
    # the VL spec directly when the user swaps them via the picker.
    _aog_key(ch) = ch == :column ? :col : ch
    function _channel_kw(ch_sym, fields)
        isempty(fields) && return (;)
        ch_sym in (:x, :y) && return (;)
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
    x_fields = get(defaults, "x", String[])
    y_fields = get(defaults, "y", String[])

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
       x_fields, y_fields,
       dim_label_map, dims, defaults, fixed=fixed_norm, pinned, channels,
       extra_assigned=extra_assigned_norm)
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
        x_default=get(resolved.defaults, "x", String[]),
        y_default=get(resolved.defaults, "y", String[]),
        channels=resolved.channels,
        pinned=resolved.pinned,
        fixed=useful_fixed,
        extra_assigned=get(resolved, :extra_assigned, String[]))
end

"""
    _source_tables_from_spec(spec)

Return a `Vector` of all layer source tables in `spec`. Walks `VegaSpec` →
AoG drawable → layers and collects each layer's unwrapped `.data`. Skips
`nothing` and `Pregrouped` layers. Multi-layer specs (e.g. `dose_layer + spec`)
all contribute — uniqueness of a dim is taken across any layer that has it.
"""
_spec_drawable(s::VegaSpec) = s.drawable
_spec_drawable(s) = s

_wrap_with_config(spec::VegaSpec, drawable) = VegaSpec(drawable, spec.config)
_wrap_with_config(_, drawable) = drawable

_layer_iter(d::AlgebraOfGraphics.Layers) = d.layers
_layer_iter(d::AlgebraOfGraphics.Layer) = (d,)
_layer_iter(_) = ()

_drop_pregrouped(::AlgebraOfGraphics.Pregrouped) = nothing
_drop_pregrouped(t) = t

_source_tables_from_spec(::Nothing) = Any[]
_source_tables_from_spec(::Dict) = Any[]
function _source_tables_from_spec(spec)
    out = Any[]
    for layer in _layer_iter(_spec_drawable(spec))
        t = _drop_pregrouped(extract_data(layer))
        isnothing(t) || push!(out, t)
    end
    out
end

function mapping_controls(id, dimensions::AbstractVector; table=nothing, spec=nothing, kwargs...)
    resolved = resolve_channels(dimensions; kwargs...)
    mapping_controls(id, resolved; table, spec)
end

# === auto_remap_node ===========================================================
# `auto_remap_node(plot_id, spec; dims, fixed, pinned)` is the "fully
# automatic" remap entry point. The user builds a regular AoG spec —
# including their normal `mapping(:x, :y; color=…, row=…, col=…)` channel
# encodings and any `* config(…)` — and auto_remap_node handles channel
# resolution, refinement against the spec's actual data, cartesian-product
# broadcast across missing facet dims, combo-column construction, layer
# rewriting, and picker assembly.

# --- helpers ---

# Walk a spec down to the list of AoG Layers it contains.
_spec_layers_or_nothing(d::AlgebraOfGraphics.Layers) = collect(d.layers)
_spec_layers_or_nothing(d::AlgebraOfGraphics.Layer) = [d]
_spec_layers_or_nothing(_) = nothing

function _spec_layers(spec)
    drawable = _spec_drawable(spec)
    layers = _spec_layers_or_nothing(drawable)
    isnothing(layers) && error("auto_remap_node: unsupported spec drawable type $(typeof(drawable))")
    layers
end

function _auto_summary_args(spec)
    layers = _spec_layers_or_nothing(_spec_drawable(spec))
    isnothing(layers) && return nothing
    for layer in layers
        for T in (PointIntervalAnalysis, GradientIntervalAnalysis, DotIntervalAnalysis)
            a = extract_transformation(layer, T)
            isnothing(a) && continue
            table = extract_data(layer)
            isnothing(table) && return nothing
            if a.orientation === :vertical
                length(layer.positional) >= 2 || return nothing
                outcome = Symbol(_field_name(layer.positional[1]))
                value = Symbol(_field_name(layer.positional[2]))
                group_cols = Symbol[]
                for (k, v) in pairs(layer.named)
                    push!(group_cols, Symbol(_field_name(v)))
                end
            else
                (isempty(layer.positional) || !haskey(layer.named, :y)) && return nothing
                value = Symbol(_field_name(layer.positional[1]))
                outcome = Symbol(_field_name(layer.named[:y]))
                group_cols = Symbol[]
                for (k, v) in pairs(layer.named)
                    k == :y && continue
                    push!(group_cols, Symbol(_field_name(v)))
                end
            end
            return (; kind=:pointinterval, table, value, outcome, group_cols)
        end
        a = extract_transformation(layer, LineRibbonAnalysis)
        if !isnothing(a)
            table = extract_data(layer)
            (isnothing(table) || length(layer.positional) < 2) && return nothing
            x = Symbol(_field_name(layer.positional[1]))
            value = Symbol(_field_name(layer.positional[2]))
            group_cols = Symbol[x]
            for (k, v) in pairs(layer.named)
                k === :group && continue
                push!(group_cols, Symbol(_field_name(v)))
            end
            return (; kind=:lineribbon, table, value, group_cols)
        end
        a = extract_transformation(layer, PrecomputedRibbonAnalysis)
        if !isnothing(a)
            length(layer.positional) < 2 && return nothing
            value = Symbol(_field_name(layer.positional[2]))
            point_col = string(value)
            # bands as [(lo, hi, label)]: outermost first per AoV convention
            bands = Tuple{String,String,String}[
                (string(lo), string(hi), "$(string(lo))/$(string(hi))")
                for (lo, hi) in a.bands
            ]
            return (; kind=:precomputed_ribbon, value, point_col, bands)
        end
        a = extract_transformation(layer, PrecomputedIntervalAnalysis)
        if !isnothing(a)
            point_idx = a.orientation === :vertical ? 2 : 1
            length(layer.positional) >= point_idx || return nothing
            value = Symbol(_field_name(layer.positional[point_idx]))
            point_col = string(value)
            bands = Tuple{String,String,String}[
                (string(lo), string(hi), "$(string(lo))/$(string(hi))")
                for (lo, hi) in a.bands
            ]
            return (; kind=:precomputed_ribbon, value, point_col, bands)
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

# Union of positional field names across all layers. Used by the pinned
# catch-all in `resolve_channels` so positionally-assigned dims aren't
# absorbed by the combo even when :x/:y aren't picker-exposed channels.
function _layer_positional_fields(layers)
    out = String[]
    for layer in layers
        for v in layer.positional
            f = _field_name(v)
            (isnothing(f) || isempty(f)) && continue
            f in out || push!(out, f)
        end
    end
    out
end

# Per-axis defaults derived from positional mappings: positional[1] → x,
# positional[2] → y. Returns (x=String[], y=String[]) — each at most one
# field (single-select), unioned across layers.
function _layer_axis_defaults(layers)
    xs = String[]; ys = String[]
    for layer in layers
        if length(layer.positional) >= 1
            f = _field_name(layer.positional[1])
            !isnothing(f) && !isempty(f) && !(f in xs) && push!(xs, f)
        end
        if length(layer.positional) >= 2
            f = _field_name(layer.positional[2])
            !isnothing(f) && !isempty(f) && !(f in ys) && push!(ys, f)
        end
    end
    (; x=xs, y=ys)
end

# True if any layer carries a TidybayesAnalysis — for those, x/y picker
# channels are disabled because at least one axis is bound to computed
# summary columns (lo_*/hi_*/__point__/__median__). Per-axis refuse-tagging
# is a planned follow-up (see TODO in Claude/algebraofvega.md).
function _has_axis_blocker(layers)
    for layer in layers
        !isnothing(extract_transformation(layer, TidybayesAnalysis)) && return true
    end
    false
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
_with_detail(t::PointIntervalAnalysis, d) = PointIntervalAnalysis(t.probs, t.point, d, t.orientation)
_with_detail(t::GradientIntervalAnalysis, d) = GradientIntervalAnalysis(t.probs, t.point, d, t.orientation)
_with_detail(t::LineRibbonAnalysis, d) = LineRibbonAnalysis(t.probs, t.show_line, d)
_with_detail(t::PrecomputedRibbonAnalysis, d) = PrecomputedRibbonAnalysis(t.bands, t.show_line, d)
_with_detail(t::PrecomputedIntervalAnalysis, d) = PrecomputedIntervalAnalysis(t.bands, d, t.orientation)
_with_detail(t::DotIntervalAnalysis, d) = DotIntervalAnalysis(t.probs, t.n_dots, t.point, d, t.orientation)

_patch_detail(t::TidybayesAnalysis, new_detail) = _with_detail(t, Symbol.(new_detail))
_patch_detail(t::ComposedFunction, new_detail) =
    _patch_detail(t.outer, new_detail) ∘ _patch_detail(t.inner, new_detail)
_patch_detail(t, _) = t

# Collect channel keys (e.g. :color, :row, :col) that are statically set on
# any Visual in a transformation chain. These should NOT be overwritten by
# data-driven encodings from the resolved channel kws — e.g. a scatter
# layer with `visual(Scatter; color="black")` keeps its black points
# regardless of the picker's color channel.
_visual_static_channels(t::AlgebraOfGraphics.Visual) = Set{Symbol}(keys(t.attributes))
_visual_static_channels(t::ComposedFunction) =
    union(_visual_static_channels(t.outer), _visual_static_channels(t.inner))
_visual_static_channels(_) = Set{Symbol}()

# Rebuild a layer with a new dataframe and resolved channel kws merged in.
# User-supplied entries on managed channels (color/row/col/column) are
# dropped first, then resolved kws are merged on top — except where the
# layer's Visual has already set the same channel statically. lineribbon
# detail is patched on the transformation.
#
# Layer-fixed color preservation: if the layer has `color=<field>` on a field
# outside `dim_fields` (the set of remappable dims), the layer's own color
# encoding is preserved verbatim and the resolved color kw is NOT applied to
# this layer. Returns `(new_layer, keep_color_field)` where `keep_color_field`
# is `nothing` unless the layer has a preserved, non-remappable color field.
function _rebuild_layer(layer, new_df, resolved, dim_fields::Set{String})
    # Detect layer-fixed color: `color=` on a field outside `dim_fields`.
    # Such layers keep their original color encoding and skip resolved.color_kw.
    keep_color_field = nothing
    if haskey(layer.named, :color)
        cf = _field_name(layer.named[:color])
        if !(cf in dim_fields)
            keep_color_field = cf
        end
    end
    # Build merged named NamedTuple
    base = NamedTuple()
    for (k, v) in pairs(layer.named)
        # Keep the original :color if it's layer-fixed (outside dim_fields).
        if k === :color && !isnothing(keep_color_field)
            base = merge(base, NamedTuple{(:color,)}((v,)))
            continue
        end
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
    # For layer-fixed-color layers, strip resolved.color_kw so it doesn't
    # override the preserved original color.
    if !isnothing(keep_color_field) && haskey(extra, :color)
        extra = Base.structdiff(extra, NamedTuple{(:color,)})
    end
    # Preserve AoG scale-type modifiers (e.g. `nonnumeric`) from the user's
    # original named mapping on the resolved channel kw. Without this, a
    # layer built from `mapping(color=:flag => nonnumeric)` loses the
    # modifier when auto_remap rewrites the color channel, and the rebuilt
    # spec falls back to eltype-inferred type (Int → quantitative),
    # diverging from the direct-render path.
    extra = _preserve_selector_modifiers(extra, layer.named, keep_color_field)
    new_named = merge(base, extra)
    # Patch detail on the transformation chain
    new_t = _patch_detail(layer.transformation, resolved.detail)
    # Compose a fresh layer using AoG operators (so .data, .positional, .named
    # are constructed in the AoG-native shapes), then swap in the patched
    # transformation.
    composed = AlgebraOfGraphics.data(new_df) *
        AlgebraOfGraphics.mapping(layer.positional...; new_named...)
    new_layer = AlgebraOfGraphics.Layer(new_t, composed.data, composed.positional, composed.named)
    (new_layer, keep_color_field)
end

# Extract the scale-type modifier Function (e.g. `nonnumeric`) from a
# selector like `:field => nonnumeric` or `:field => nonnumeric => "Label"`.
# Returns `nothing` if none is present.
_selector_scale_modifier(_) = nothing
function _selector_scale_modifier(sel::Pair)
    _selector_scale_modifier_dst(first(sel), last(sel))
end
_selector_scale_modifier_dst(src, dst::Function) = dst
_selector_scale_modifier_dst(src, dst::Pair) = _selector_scale_modifier(Pair(src, first(dst)))
_selector_scale_modifier_dst(args...) = nothing

# Splice a scale-type modifier into a resolved channel kw value. Resolved
# values come out of `_channel_kw` as `Symbol`, `:field => "Label"`, or
# `:field => :combo => "Label"` (for combos — but we skip combos as the
# combo column is a fresh string and carries the modifier implicitly).
_attach_modifier(v, ::Nothing) = v
_attach_modifier(v::Symbol, modifier) = Pair(v, modifier)
_attach_modifier(v::Pair, modifier) = _attach_modifier_pair(first(v), last(v), modifier)
_attach_modifier(v, modifier) = v

_attach_modifier_pair(src, dst::AbstractString, modifier) = Pair(src, Pair(modifier, dst))
_attach_modifier_pair(src, dst, modifier) = Pair(src, dst)

# For each managed channel (:color, :row, :column, :col) in `extra`, look
# up the user's original selector in `orig_named`; if it carried a scale
# modifier (`nonnumeric` etc.), splice it onto the resolved value so the
# VL-level type-inference sees it and emits the right encoding type.
function _preserve_selector_modifiers(extra::NamedTuple, orig_named, keep_color_field)
    isempty(extra) && return extra
    keys_in = keys(extra)
    updates = NamedTuple()
    for ch in keys_in
        ch in (:color, :row, :column, :col) || continue
        # keep_color_field layers already re-use the original selector verbatim,
        # so modifier propagation there is a no-op (extra.color was stripped).
        ch === :color && !isnothing(keep_color_field) && continue
        # Look up the user's original selector for this channel.
        orig_key = ch === :column ? :col : ch
        haskey(orig_named, orig_key) || continue
        mod = _selector_scale_modifier(orig_named[orig_key])
        isnothing(mod) && continue
        new_v = _attach_modifier(extra[ch], mod)
        new_v === extra[ch] && continue
        updates = merge(updates, NamedTuple{(ch,)}((new_v,)))
    end
    isempty(updates) ? extra : merge(extra, updates)
end

"""
    auto_remap_node(plot_id, spec; dims, fixed=Dict(), pinned=:row, axes=false)

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
- **`axes=true`** opts in to X/Y axis channels in the picker. The layer's
  positional fields (`mapping(x, y, …)`) are automatically added to the
  picker's dim set — they become X/Y defaults AND are selectable on the
  other channels. Off by default because X/Y are single-select (no combo
  semantics) and usually the positional fields are not meant to be
  re-routed. When any layer carries a `TidybayesAnalysis`, X/Y stay
  hidden regardless of `axes` — analyses bind axes to computed columns.

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

auto_remap_node("dose-response-plot", spec;
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
function _auto_remap_parts(plot_id, spec; dims, fixed=Dict(), pinned::Symbol=:row,
                            axes::Bool=false)
    layers = _spec_layers(spec)
    raw_dfs = [extract_data(l) for l in layers]
    any(isnothing, raw_dfs) && error("auto_remap_node: every layer must have associated data (no Pregrouped layers supported here)")
    # Materialize each layer's data as a NamedTuple of vectors so the rest
    # of the pipeline can stay non-mutating and uniform across input types
    # (DataFrame / DataFrameColumns / NamedTuple / etc).
    dfs = NamedTuple[Tables.columntable(d) for d in raw_dfs]

    # Positional fields — always feed into `extra_assigned` so the pinned
    # catch-all doesn't absorb them. When `axes=true` they also become
    # picker channel defaults + extra options on all channels.
    pos_all = _layer_positional_fields(layers)
    axis_defs = _layer_axis_defaults(layers)
    enable_axes = axes && !_has_axis_blocker(layers)

    # Build the effective dims list. When axes=true, any positional field
    # not already in `dims` is auto-added so x/y can have defaults AND the
    # same fields are pickable on color/row/column.
    effective_dims = if enable_axes
        dims_vec = Any[d for d in dims]
        listed = Set{String}(_dim_first(d) for d in dims_vec)
        for f in pos_all
            f in listed && continue
            push!(dims_vec, f => join(uppercasefirst.(split(f, "_")), " "))
            push!(listed, f)
        end
        dims_vec
    else
        dims
    end
    dim_fields = Set{String}(_dim_first(d) for d in effective_dims)
    defaults = _layer_channel_defaults(layers)
    defaults = Dict(ch => filter(f -> f in dim_fields, fs) for (ch, fs) in defaults)
    extra_assigned = filter(f -> f in dim_fields, pos_all)
    x_default = enable_axes ? filter(f -> f in dim_fields, axis_defs.x) : String[]
    y_default = enable_axes ? filter(f -> f in dim_fields, axis_defs.y) : String[]
    channels = enable_axes ? [:x, :y, :color, :row, :column, :detail] :
                             [:color, :row, :column, :detail]
    resolved = resolve_channels(effective_dims;
        color_default=defaults["color"],
        row_default=defaults["row"],
        column_default=defaults["column"],
        x_default, y_default,
        channels, pinned, fixed,
        extra_assigned)
    resolved = refine_channels(resolved, dfs...)

    # Cartesian-product fill missing facet fields, then build combo columns.
    bcast_fields = unique(vcat(resolved.color_fields, resolved.row_fields, resolved.column_fields))
    field_uniques = _global_field_uniques(dfs, bcast_fields)
    bcasted = [_broadcast_missing_fields(df, bcast_fields, field_uniques) for df in dfs]
    new_dfs = [_with_combos(df, resolved) for df in bcasted]

    rebuilt = [_rebuild_layer(layer, new_df, resolved, dim_fields) for (layer, new_df) in zip(layers, new_dfs)]
    new_layers = [r[1] for r in rebuilt]
    keep_color_fields = Set{String}(r[2] for r in rebuilt if !isnothing(r[2]))
    new_drawable = reduce(+, new_layers)
    new_spec = _wrap_with_config(spec, new_drawable)

    # Build VL, tag layers whose color field is layer-fixed so JS remapEncoding skips them.
    vl = to_vegalite(new_spec)
    isempty(keep_color_fields) || _tag_keep_color_layers!(vl, keep_color_fields)
    # If the resolved spec is non-faceted (e.g. `:basename` had a single unique
    # value and got refined out of `dims`), strip top-level
    # `resolve.scale.{x,y} == "independent"` entries inherited from the user's
    # config — they were authored to mean "independent across facet rows", but
    # on a flat layered spec VL would interpret them as "independent across
    # layers", which gives each band/point sublayer its own x/y axis (top-axes
    # stack-up bug).
    _scrub_independent_resolve_if_unfaceted!(vl)

    controls = isempty(resolved.dims) ? "" : mapping_controls(plot_id, resolved; spec=new_spec)
    plot = to_node(vl; id=plot_id)
    (controls, plot)
end

# Drop `resolve.scale.x|y == "independent"` entries when the spec is not
# faceted. Those entries are only meaningful for the facet operator; on a
# plain layered spec VL applies them per-layer, giving each sublayer its own
# x/y scale + axis (axes stack at the top of the chart).
function _scrub_independent_resolve_if_unfaceted!(vl::Dict)
    haskey(vl, "facet") && return
    haskey(vl, "spec") && !isnothing(_as_dict(vl["spec"])) && return
    resolve = _as_dict(get(vl, "resolve", nothing))
    isnothing(resolve) && return
    scale = _as_dict(get(resolve, "scale", nothing))
    isnothing(scale) && return
    for ax in ("x", "y")
        get(scale, ax, nothing) == "independent" && delete!(scale, ax)
    end
    isempty(scale) && delete!(resolve, "scale")
    isempty(resolve) && delete!(vl, "resolve")
    return
end

# Walk a VL dict and mark any layer with `encoding.color.field ∈ keep_color_fields`
# with `_keep_color = true`, so the JS remapEncoding loop leaves it alone.
_tag_keep_color_layer!(args...) = nothing
function _tag_keep_color_layer!(l::Dict, keep_color_fields::Set{String})
    enc = _as_dict(get(l, "encoding", nothing)); isnothing(enc) && return
    color = _as_dict(get(enc, "color", nothing)); isnothing(color) && return
    f = _as_str(get(color, "field", nothing))
    !isnothing(f) && f in keep_color_fields && (l["_keep_color"] = true)
    return
end

function _tag_keep_color_layers!(vl::Dict, keep_color_fields::Set{String})
    # Faceted specs nest layers under "spec"; plain layered specs use top-level "layer".
    nested = haskey(vl, "spec") ? _as_dict(vl["spec"]) : nothing
    container = isnothing(nested) ? vl : nested
    layers = _as_vec(get(container, "layer", nothing))
    isnothing(layers) && return
    for l in layers
        _tag_keep_color_layer!(l, keep_color_fields)
    end
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
        # x/y are single-select axis channels — no combo, no pin radio.
        is_axis = ch_str == "x" || ch_str == "y"
        # Determine which fields are selected
        default_set = if is_fixed
            Set(fixed_js[ch_str])
        else
            Set(get(defaults, ch_str, String[]))
        end
        options = if is_axis
            # Prepend an empty option so users can clear the axis (JS will
            # leave the layer untouched when the selected value is empty).
            vcat(
                h.option(; value="")(""),
                [let
                    sel = field in default_set ? (; value=field, selected="selected") : (; value=field)
                    h.option(; sel...)(label)
                end for (field, label) in dims],
            )
        else
            [let
                sel = field in default_set ? (; value=field, selected="selected") : (; value=field)
                h.option(; sel...)(label)
            end for (field, label) in dims]
        end
        sel_attrs = if is_axis
            # Single-select listbox (no `multiple`) sized to match the other
            # channels' multi-select listboxes so the row of channels lines up.
            (;
                id="aov-remap-$(ch_str)-$(id)",
                size=sel_size,
                onchange="_aovRemap_$(js_id)('$(ch_str)')",
            )
        else
            (;
                id="aov-remap-$(ch_str)-$(id)",
                multiple="multiple",
                size=sel_size,
                onchange="_aovRemap_$(js_id)('$(ch_str)')",
            )
        end
        if (!is_axis && is_pinned) || is_fixed
            sel_attrs = merge(sel_attrs, (; disabled="disabled"))
        end
        radio_attrs = (; type="radio", name="aov-pin-$(id)", value=ch_str,
            onchange="_aovPin_$(js_id)(this.value)")
        if is_pinned
            radio_attrs = merge(radio_attrs, (; checked="checked"))
        end
        if is_fixed || is_axis
            radio_attrs = merge(radio_attrs, (; disabled="disabled"))
        end
        # x/y render the radio disabled (they can't be pinned — catch-all
        # makes no sense on a single-select axis channel) so the column layout
        # stays consistent with color/row/column/detail.
        h.div()(
            h.label(; class="u-flex-tight")(
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
        // x/y are single-select: pick the one field (or empty string).
        var xField = (selections.x && selections.x[0]) || '';
        var yField = (selections.y && selections.y[0]) || '';

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
        if (channels.indexOf('x') !== -1) mapping.x = xField;
        if (channels.indexOf('y') !== -1) mapping.y = yField;
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

    hint = h.small(; class="u-text-muted u-mb-1")(
        "Assign dimensions to channels (multi-select). ",
        "The pinned channel (", h.strong("●"), ") auto-fills with unassigned dimensions. ",
        "Selecting 2+ dimensions in one channel combines them.",
    )

    h.div()(
        hint,
        h.div(; class="u-flex-wide u-flex-wrap u-mb-2")(
            selects..., js,
        ),
    )
end

"""
    to_html(spec; id, width, height)

Return a standalone HTML string with embedded vega-embed that self-loads scripts from CDN.
"""
function to_html(spec; id=nothing, width=nothing, height=nothing)
    vl = _as_vl_dict(spec)
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
    h.div(; class="u-flex-wide u-flex-wrap")(
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
_merge_nt!(_, ::Nothing) = nothing
function _merge_nt!(kw, nt::NamedTuple)
    for (k, v) in pairs(nt)
        kw[k] = v
    end
end

_merge_axis_nt!(_, ::Nothing) = nothing
function _merge_axis_nt!(axis_kw, nt::NamedTuple)
    for (ak, av) in pairs(nt)
        ak === :clamp && continue  # VL-only, no Makie analogue
        axis_kw[ak] = av
    end
end

_independent_axes_syms(b::Bool) = b ? (:x, :y) : ()
_independent_axes_syms(s::Symbol) = (s,)
_independent_axes_syms(v) = (Symbol(a) for a in v)

_apply_log_scales!(axis_kw, ::Nothing) = nothing
function _apply_log_scales!(axis_kw, enc::Dict)
    for (ch, ch_props) in enc
        d = _as_dict(ch_props); isnothing(d) && continue
        scale_dict = get(d, "scale", get(d, :scale, nothing))
        isnothing(scale_dict) && continue
        scale_type = get(scale_dict, "type", get(scale_dict, :type, nothing))
        scale_type == "log" || continue
        if ch in (:y, "y")
            axis_kw[:yscale] = log10
        elseif ch in (:x, "x")
            axis_kw[:xscale] = log10
        end
    end
end

_is_faceted(drawable::AlgebraOfGraphics.Layer) =
    haskey(drawable.named, :col) || haskey(drawable.named, :row) || haskey(drawable.named, :layout)
_is_faceted(drawable::AlgebraOfGraphics.Layers) = any(_is_faceted, drawable.layers)
_is_faceted(_) = false

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
    _apply_log_scales!(axis_kw, _as_dict(get(props, :encoding, nothing)))
    for (k, v) in props
        k in (:width, :height, :encoding) && continue  # handled above
        if k === :scales
            s = _as_scales(v); isnothing(s) || (scales_obj = s)
        elseif k === :facet
            _merge_nt!(facet_kw, _as_nt(v))
        elseif k === :axis
            _merge_axis_nt!(axis_kw, _as_nt(v))
        elseif k === :independent_scales
            @warn "AlgebraOfVega: `config(independent_scales=$(repr(v)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
            for ax in _independent_axes_syms(v)
                ax === :x && get!(facet_kw, :linkxaxes, :none)
                ax === :y && get!(facet_kw, :linkyaxes, :none)
            end
        end
    end
    (; figure=NamedTuple(figure_kw), facet=NamedTuple(facet_kw), axis=NamedTuple(axis_kw), scales=scales_obj)
end

"""
    _has_aov_analysis(layer::AlgebraOfGraphics.Layer)

Check if a layer uses an AoV-specific transformation (tidybayes analyses).
"""
_tidybayes_or_nothing(t::TidybayesAnalysis) = t
_tidybayes_or_nothing(_) = nothing

_analysis_in(t::TidybayesAnalysis) = t
function _analysis_in(t::ComposedFunction)
    a = _tidybayes_or_nothing(t.outer); isnothing(a) || return a
    _tidybayes_or_nothing(t.inner)
end
_analysis_in(_) = nothing

_get_analysis(layer::AlgebraOfGraphics.Layer) = _analysis_in(layer.transformation)

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
        v = pop!(attrs, :strokeDash)
        attrs[:linestyle] = v isa AbstractVector{<:Real} ? Makie.Linestyle(collect(Float64, v)) : v
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
