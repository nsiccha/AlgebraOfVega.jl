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

# Which view a coloured ribbon with few x values starts in (`intervals=`):
# `:auto` picks point-intervals when its colour groups' bands overlap by more
# than `threshold` of the y range; `:ribbons`/`:intervals` always start there.
struct RibbonIntervals
    start::Symbol
    threshold::Float64
end

# The `:auto` threshold (share of the y range), and the most distinct x values
# a ribbon may have to be offered as point-intervals.
const _RIBBON_OVERLAP_THRESHOLD = 0.1
const _RIBBON_INTERVAL_MAX_X = 12

_ribbon_intervals(start::Bool) = RibbonIntervals(start ? :intervals : :ribbons, _RIBBON_OVERLAP_THRESHOLD)
function _ribbon_intervals(threshold::Real)
    0 <= threshold <= 1 || throw(ArgumentError(
        "intervals=$threshold: a threshold is a share of the y range, between 0 and 1"))
    RibbonIntervals(:auto, Float64(threshold))
end
function _ribbon_intervals(start::Symbol)
    start === :auto || throw(ArgumentError(
        "intervals=:$start: pass :auto, a threshold between 0 and 1, or true/false"))
    RibbonIntervals(:auto, _RIBBON_OVERLAP_THRESHOLD)
end
_ribbon_intervals(x) = throw(ArgumentError(
    "intervals=$(repr(x)): pass :auto, a threshold between 0 and 1, or true/false"))

struct LineRibbonAnalysis <: TidybayesAnalysis
    probs::Vector{Float64}
    show_line::Bool
    detail_fields::Vector{Symbol}
    single_x_glyph::Bool
    intervals::RibbonIntervals
end

struct PrecomputedRibbonAnalysis <: TidybayesAnalysis
    bands::Vector{Pair{Symbol,Symbol}}
    show_line::Bool
    detail_fields::Vector{Symbol}
    single_x_glyph::Bool
    intervals::RibbonIntervals
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

When `color` identifies several intervals at the same category/facet position,
those intervals are dodged automatically. A one-to-one metadata color remains
centered. Map `dodge_y` explicitly for horizontal intervals, or `dodge_x` for
vertical intervals, to choose a dodge field directly:

    data(draws) * mapping(:value, y=:parameter, color=:dose, dodge_y=:model) *
        pointinterval()

A fixed colour colours every interval rule in place of the per-category palette
colour; the median point keeps its white fill and dark ring. `color=:ink`
follows the page's light/dark foreground. A `color=` mapping wins over it, as
for plain marks. Other `visual` attributes are not applied (the rules keep
their graduated widths) and are reported with a warning.

    data(draws) * mapping(:value, y=:parameter) * pointinterval() * visual(; color="black")
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
Color and `dodge_y`/`dodge_x` mappings, and a fixed `visual(; color=…)`, follow
`pointinterval` semantics.

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

`single_x_glyph` (default `true`): any group/facet whose data collapses to a
single x value (where an area/line would render nothing) is instead drawn as a
vertical pointinterval glyph (rule-bands + a stroked median point) so it stays
visible. Set `false` to opt out (single-x groups revert to invisible area/line).

A fixed colour colours every band, the median line and the single-x glyph
rules, on `vdraw` and `sdraw` alike; `color=:ink` follows the page's light/dark
foreground (the Makie theme's text colour under `sdraw`). A `color=` mapping
wins over it, as for plain marks. Other `visual` attributes are not applied
(the bands keep their graduated opacities) and are reported with a warning.

    data(summary) * mapping(:x, :median) *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75]) * visual(; color="black")

A ribbon coloured by `color=` with at most $(_RIBBON_INTERVAL_MAX_X) distinct
numeric x values (a dose ladder) can also be drawn as vertical point-intervals,
dodged by colour on evenly spaced x slots, and the reader switches between the
two with a "Ribbons | Intervals" control. `intervals` picks the view it starts
in: `:auto` (default) starts in point-intervals when the colour groups' outer
bands overlap by more than $(round(Int, 100 * _RIBBON_OVERLAP_THRESHOLD))% of
the y range on average, a number between 0 and 1 replaces that threshold, and
`true`/`false` always start in point-intervals/ribbons. `vsave` writes the
starting view; `sdraw` always draws the ribbon.
"""
function lineribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[], single_x_glyph=true,
                    intervals=:auto)
    iv = _ribbon_intervals(intervals)
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, true, Symbol.(detail), single_x_glyph, iv))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), true, Symbol.(detail), single_x_glyph, iv))
end

"""
    ribbon(; probs=[0.95, 0.8, 0.5])
    ribbon(; bands=[:q025 => :q975, :q25 => :q75])

Uncertainty ribbons (area marks) without a median line.
Same as `lineribbon` but omits the central line. Accepts the same `bands`
kwarg for pre-aggregated data, a fixed `visual(; color=…)` and `intervals` the
same way (its point-interval view keeps the median point).

    data(preds) * mapping(:x, :y, group=:draw) * ribbon()
    data(summary) * mapping(:x, :median) * ribbon(bands=[:q025 => :q975])
"""
function ribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[], single_x_glyph=true,
                intervals=:auto)
    iv = _ribbon_intervals(intervals)
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, false, Symbol.(detail), single_x_glyph, iv))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), false, Symbol.(detail), single_x_glyph, iv))
end

"""
    dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median, orientation=:horizontal)

Quantile dotplot with nested interval overlay.
Color and `dodge_y`/`dodge_x` mappings follow `pointinterval` semantics. A fixed
`visual(; color=…)` colours the dots as well as the rules (replacing the rules'
default ink).

    data(draws) * mapping(:value, y=:parameter) * dotinterval()
    data(draws) * mapping(:parameter, :value) * dotinterval(orientation=:vertical)
"""
dotinterval(; probs=[0.95, 0.5], n_dots=50, point=:median, detail=Symbol[], orientation::Symbol=:horizontal) =
    Layer(transformation=DotIntervalAnalysis(Float64.(probs), n_dots, point, Symbol.(detail), orientation))

# --- Geoshape / choropleth ---

struct GeoShapeAnalysis
    geometry::Any
    key::Any
    projection::Any
end

"""
    geoshape(geometry; key=nothing, projection=automatic)

Choropleth polygons: fill GeoJSON region shapes by a data column joined on a
shared key. The geometry source owns the polygons; the layer's `data(...)`
table owns the values; the emitted Vega-Lite spec looks up each table row's
feature with a `lookup` transform and draws the VL `geoshape` mark — there are
no x/y axes. A row whose key matches no feature, and a feature no row matches,
are not drawn.

`geometry` is a GeoJSON source in one of three forms: a URL string (fetched
by the browser), a parsed FeatureCollection `Dict`, or a vector of Feature
`Dict`s. Any ring winding draws: each polygon is the region its rings enclose,
whether the file winds exterior rings counter-clockwise (RFC 7946, as WFS
servers and most GIS tools write) or clockwise (d3's convention, and the
Shapefile one). AoV rewinds a parsed geometry when it lowers the layer, the AoV
browser runtime rewinds a URL's GeoJSON when it loads it, and [`vsave`](@ref)
rewinds what it reads into the file. A region larger than half the globe cannot
be drawn. `key` names the join field: a single name used on both sides
(`key=:AGS` — the geometry's feature property and the table column), a
`data_column => geo_property` pair when the two sides spell it differently,
or omitted, in which case the mapping's single positional is the key
(`mapping(:AGS; color=:effect)`). `projection` is a Vega-Lite projection:
a symbol/string type name (`:mercator`, `:albers`, …), a Dict/NamedTuple of
projection properties, or `nothing` to emit no projection. Left out, it is the
map's projection: the one another geoshape layer of the map sets, else
`:mercator`.

    data(effects) * mapping(:AGS; color=:effect) *
        geoshape("https://example.invalid/districts.geojson")

    data(effects) * mapping(:AGS; color=:effect => "Posterior effect") *
        geoshape(geojson_dict; projection=:mercator) |> vdraw

`mapping` supplies `color=` (and optionally `strokecolor=`); a fixed border
goes through `visual(; stroke="white", strokeWidth=0.5)`. Faceting with
`col=`/`row=`/`layout=` draws one small-multiple map per panel, each filled
from that panel's rows.

Sum other layers onto the map to draw on it, as on an AlgebraOfGraphics
`GeoAxis`: their two positionals are longitude then latitude (in degrees),
drawn through the map's projection, which is fitted to the polygons and the
marks together:

    data(effects) * mapping(:AGS; color=:effect) * geoshape(geojson) +
        data(sites) * mapping(:lon, :lat; color=:kind) * visual(Scatter)

Such a layer takes plain point-like marks (`Scatter`, `Lines`, `Text`) with
the usual named channels and tooltips; an analysis layer, an x/y channel, or a
mark that cannot stand at a point fail with an `ArgumentError`.

A map draws through one projection. Set `projection=` on one geoshape layer and
leave it out on the others, which then draw through it (an outline over a
fitted choropleth):

    data(effects) * mapping(:AGS; color=:effect) *
        geoshape(geojson; projection=(; type="mercator", fit=region)) +
    data(outline) * mapping(:AGS) * geoshape(outline_geo) *
        visual(; fill=nothing, stroke="red")

Two geoshape layers that set different projections fail with an
`ArgumentError` naming the properties they differ in. This is a Vega-Lite-only plot type: the static
`sdraw` path refuses it loudly, [`vsave`](@ref) writes it to a PDF/SVG/PNG file,
and a mounted map refreshes with `update_spec`. The channel picker keeps its x/y
channels disabled for a geoshape layer, as for the interval analyses.
"""
function geoshape(geometry; key=nothing, projection=Makie.automatic)
    _check_geoshape_geometry(geometry)
    _check_geoshape_key(key)
    _check_geoshape_projection(projection)
    Layer(transformation=GeoShapeAnalysis(geometry, key, projection))
end

_check_geoshape_geometry(g::AbstractString) =
    isempty(g) && throw(ArgumentError("geoshape: geometry URL must not be empty."))
function _check_geoshape_geometry(g::AbstractDict)
    (haskey(g, "features") || haskey(g, :features)) || throw(ArgumentError(
        "geoshape: a Dict geometry must be a GeoJSON FeatureCollection (no \"features\" key found)."))
end
function _check_geoshape_geometry(g::AbstractVector)
    isempty(g) && throw(ArgumentError("geoshape: geometry feature vector must not be empty."))
    all(f -> f isa AbstractDict, g) || throw(ArgumentError(
        "geoshape: a vector geometry must hold GeoJSON Feature Dicts."))
end
_check_geoshape_geometry(g) = throw(ArgumentError(
    "geoshape: geometry must be a GeoJSON URL string, a FeatureCollection Dict, or a vector of Feature Dicts; got $(typeof(g))."))

_check_geoshape_key(::Nothing) = nothing
_check_geoshape_key(::Union{Symbol,AbstractString}) = nothing
_check_geoshape_key(k::Pair) =
    (first(k) isa Union{Symbol,AbstractString} && last(k) isa Union{Symbol,AbstractString}) ||
    throw(ArgumentError("geoshape: a pair `key` must be `data_column => geo_property` with symbol/string sides."))
_check_geoshape_key(k) = throw(ArgumentError(
    "geoshape: `key` must be a column name, a `data_column => geo_property` pair, or omitted; got $(typeof(k))."))

_check_geoshape_projection(::Union{Nothing,Makie.Automatic}) = nothing
_check_geoshape_projection(::Union{Symbol,AbstractString,AbstractDict,NamedTuple}) = nothing
_check_geoshape_projection(p) = throw(ArgumentError(
    "geoshape: `projection` must be a projection type name, a Dict/NamedTuple of Vega-Lite projection properties, or `nothing`; got $(typeof(p))."))

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

# Resolve an analysis's interval into a Bool-friendly Maybe value: returns the
# interval if one is concretely set (e.g. `(0.025, 0.975)`), `nothing` if the
# interval is missing, `Automatic`, or the analysis itself is `nothing`.
# Replaces the old `_is_automatic` Bool predicate; callers compose via
# `isnothing(_resolved_band_interval(analysis))` instead of negating a Bool.
_resolved_band_interval(::Nothing) = nothing
_resolved_band_interval(analysis) = _resolved_interval_value(analysis.interval)
_resolved_interval_value(::Nothing) = nothing
_resolved_interval_value(::Makie.Automatic) = nothing
_resolved_interval_value(x) = x

_analysis_probs(a::Union{PointIntervalAnalysis,GradientIntervalAnalysis,DotIntervalAnalysis}) = a.probs
_analysis_probs(_) = [0.95, 0.5]

# Per-prob interval-style descriptors. Gradient analyses set an opacity ramp
# with fixed stroke width; non-gradient analyses ramp the stroke width with no
# opacity override. Replaces the old `_is_gradient` Bool predicate + paired
# if/else branches; the loop body just walks the precomputed styles.
_interval_styles(::GradientIntervalAnalysis, sorted_probs) =
    [(opacity=op, stroke_width=14) for op in range(0.2, 0.7, length=length(sorted_probs))]
_interval_styles(_, sorted_probs) =
    [(opacity=nothing, stroke_width=sw) for sw in range(1.5, 8, length=length(sorted_probs))]

_apply_opacity!(_enc, ::Nothing) = nothing
_apply_opacity!(enc, op) = (enc["opacity"] = Dict{String,Any}("value" => op); nothing)

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

"""Build the VL facet-channel encoding for one facet field
(`{field, type[, title][, sort]}`)."""
function _facet_channel_enc(field, label, sort=nothing)
    enc = Dict{String,Any}("field" => field, "type" => "nominal")
    !isnothing(label) && label != field && (enc["title"] = label)
    !isnothing(sort) && (enc["sort"] = sort)
    enc
end

"""
Extract `:col`/`:row`/`:layout` from a layer's named mappings, returning a VL facet dict
and the list of facet field names.

`:col`/`:row` lower to the 2-D grid form of the facet operator (`facet: {column, row}`).
`:layout` is AoG's *single-dimension wrap* facet and lowers to the wrap form
(`facet: {field, type}`) — the only form Vega-Lite's `columns: N` actually wraps; on the
`column`/`row` grid channels a sibling `columns` is ignored. When `:layout` is combined
with `:col`/`:row` (VL cannot mix the two operator forms) it takes the free grid channel,
`column` first then `row`.

An explicit `sorter`/`renamer` order on a facet selector is carried into the facet
channel's `sort`, just as it is on plain-mark channels; analyses rebuild their facet
encodings, so this thread must be explicit.

The returned `facet_fields` are the analysis grouping key: without the layout field in
here, preaggregation (`compute_ribbon_summary` / `compute_interval_summary`) pools across
panels and drops the column entirely.
"""
function _extract_facet_info(layer)
    col_field = haskey(layer.named, :col) ? _field_name(layer.named[:col]) : nothing
    col_label = haskey(layer.named, :col) ? _field_label(layer.named[:col]) : nothing
    col_sort = haskey(layer.named, :col) ? _selector_sort(layer.named[:col]) : nothing
    row_field = haskey(layer.named, :row) ? _field_name(layer.named[:row]) : nothing
    row_label = haskey(layer.named, :row) ? _field_label(layer.named[:row]) : nothing
    row_sort = haskey(layer.named, :row) ? _selector_sort(layer.named[:row]) : nothing
    layout_field = haskey(layer.named, :layout) ? _field_name(layer.named[:layout]) : nothing
    layout_label = haskey(layer.named, :layout) ? _field_label(layer.named[:layout]) : nothing
    layout_sort = haskey(layer.named, :layout) ? _selector_sort(layer.named[:layout]) : nothing
    facet = Dict{String,Any}()
    !isnothing(col_field) && (facet["column"] = _facet_channel_enc(col_field, col_label, col_sort))
    !isnothing(row_field) && (facet["row"] = _facet_channel_enc(row_field, row_label, row_sort))
    facet_fields = String[]
    !isnothing(col_field) && push!(facet_fields, col_field)
    !isnothing(row_field) && push!(facet_fields, row_field)
    if !isnothing(layout_field)
        lay_enc = _facet_channel_enc(layout_field, layout_label, layout_sort)
        if isempty(facet)
            merge!(facet, lay_enc)              # wrap form: facet: {field, type}
        elseif !haskey(facet, "column")
            facet["column"] = lay_enc
        elseif !haskey(facet, "row")
            facet["row"] = lay_enc
        else
            @warn "AlgebraOfVega: `layout=$layout_field` ignored — `col=` and `row=` already occupy both facet dimensions." maxlog=1
            layout_field = nothing
        end
        !isnothing(layout_field) && push!(facet_fields, layout_field)
    end
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
#
# With NO key columns the whole table is ONE group keyed by `()`. Returning an
# empty Dict here instead silently drops every row: the interval summaries then
# produce zero rows and the spec serializes as `data.values: []`, so an
# ungrouped `pointinterval()` renders a blank plot with no error anywhere.
function _group_indices(columns::Vector{<:AbstractVector}, nrows::Int)
    isempty(columns) && return Dict{Tuple{}, Vector{Int}}(() => collect(1:nrows))
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
    idx_groups = _group_indices(_key_columns(table; fields=key_fields), length(vals))

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
    idx_groups = _group_indices(kc, length(xs))

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

"""
    _kde_bandwidth(sorted) -> Float64

Gaussian-KDE bandwidth by the normal reference rule, byte-for-byte the formula
vega-statistics' `bandwidthNRD` uses (`1.06 · min(σ, IQR/1.34) · n^(-1/5)`, with
σ the *sample* standard deviation and the quartiles interpolated R-7 style —
Julia's `std` and `quantile` defaults on both counts). Matching it is the whole
point: `compute_density_summary` replaces a Vega `density` transform for faceted
specs only, so an unfaceted and a faceted density of the same column must not
draw visibly different curves.

`sorted` must already be sorted (the quantiles are taken with `sorted=true`).
Returns a non-positive or non-finite value for a degenerate group — `n < 2`, or
every value identical — which callers must treat as "no KDE exists here".
"""
function _kde_bandwidth(sorted::AbstractVector{<:Real})
    n = length(sorted)
    n < 2 && return NaN
    iqr = quantile(sorted, 0.75; sorted=true) - quantile(sorted, 0.25; sorted=true)
    1.06 * min(std(sorted), iqr / 1.34) * n^(-0.2)
end

"""
    compute_density_summary(table, x_field; group_fields=String[], npoints=200)

Per-group Gaussian KDE evaluated on a **per-group** grid, emitted as plain rows
`{"val", "dens", <each group field>}` — the `compute_ribbon_summary` pattern
applied to `density()`.

This exists because a Vega-Lite `density` transform computes ONE extent for the
whole dataset even when it carries a `groupby`. Measured (headless Vega, two
groups on `N(0,1)` and `N(1000,50)`): both panels' curves span the pooled
`[-2.62, 1136.16]`, so the tight group occupies a fraction of a percent of its
own panel, and `resolve.scale.x = independent` cannot fix it because the *data*
extent, not the scale, is what is shared. Computing the curves here gives each
group its own `[min, max]` and a full `npoints` grid inside it.

`npoints` is 200 to match both ends of the convention it replaces:
AlgebraOfGraphics' `DensityAnalysis` default and Vega's `maxsteps`. The extent is
the group's observed `[min, max]` — again the same convention as the transform's
default, just applied per group, so a KDE's tails stay truncated at the data
limits exactly as before.

A degenerate group (a single row, or every value identical) has no bandwidth and
contributes no rows; its panel renders empty and a warning names how many groups
were dropped. Cost is `O(npoints × nrows)` exponentials in total — the Gaussian
sum is not truncated, so the curve matches vega-statistics to floating point.
"""
function compute_density_summary(table, x_field::String; group_fields::Vector{String}=String[], npoints::Int=200)
    npoints >= 2 || throw(ArgumentError("compute_density_summary: npoints must be >= 2, got $npoints"))
    vals = Tables.getcolumn(table, Symbol(x_field))
    idx_groups = _group_indices(_key_columns(table; fields=group_fields), length(vals))

    rows = Dict{String,Any}[]
    sizehint!(rows, length(idx_groups) * npoints)
    buf = Float64[]
    degenerate = Any[]
    for (key, idxs) in idx_groups
        n = length(idxs)
        n == 0 && continue
        resize!(buf, n)
        @inbounds for k in 1:n
            buf[k] = float(vals[idxs[k]])
        end
        sort!(buf)
        lo, hi = first(buf), last(buf)
        h = _kde_bandwidth(buf)
        if !isfinite(h) || h <= 0 || !(hi > lo)
            push!(degenerate, key)
            continue
        end
        inv_h = 1 / h
        scale = inv_h / (n * sqrt(2 * pi))
        step = (hi - lo) / (npoints - 1)
        for j in 0:(npoints - 1)
            # Pin the last sample to `hi` exactly — `lo + (npoints-1)*step` can
            # land a rounding step short, which shows up as a sliver of missing
            # area at the right edge of every panel.
            x = j == npoints - 1 ? hi : lo + j * step
            acc = 0.0
            @inbounds for k in 1:n
                z = (x - buf[k]) * inv_h
                acc += exp(-0.5 * z * z)
            end
            row = Dict{String,Any}("val" => x, "dens" => acc * scale)
            for (ki, f) in enumerate(group_fields)
                row[f] = key[ki]
            end
            push!(rows, row)
        end
    end
    if !isempty(degenerate)
        # No `maxlog` here on purpose: this is one summary line per CALL, not per
        # dropped group, and it is data-dependent — a `maxlog=1` would silence it
        # for every later plot in the same session (and make it untestable once
        # any earlier test had tripped it).
        @warn "AlgebraOfVega: density() dropped $(length(degenerate)) group(s) with no computable KDE (a single row, or every value identical) — those panels render empty. First: $(first(degenerate))"
    end
    rows
end
