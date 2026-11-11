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

# Which view a ribbon with few x values starts in (`intervals=`): `:auto`
# picks point-intervals when its colour groups' bands overlap by more than
# `threshold` of the y range (one group, as without a colour mapping, overlaps
# nothing); `:ribbons`/`:intervals` always start there.
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

Draw nested empirical intervals and a central point. With `probs`, summarize
raw values using quantiles in Julia. With `bands`, read precomputed lower/upper
column pairs, widest first; the first positional mapping is the center column.

The default horizontal orientation maps values to x and categories through
`y`. Vertical orientation requires positional mappings `(category, value)`.
Color groups at the same category are dodged automatically; `dodge_y` or
`dodge_x` selects the dodge field explicitly. `detail` preserves extra grouping
columns. A fixed `visual(; color=...)` colors interval rules; `color=:ink`
follows the page foreground. Other visual attributes are not applied.

Intervals describe the supplied distribution. They are credible intervals only
when that distribution consists of appropriate posterior draws.
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

Draw nested quantile intervals with uniform stroke width and varying opacity,
plus a central point. Orientation, grouping, color, and dodge mappings follow
`pointinterval`. Supply raw values; `probs` specifies central interval masses.
"""
gradient_interval(; probs=[0.95, 0.8, 0.5], point=:median, detail=Symbol[], orientation::Symbol=:horizontal) =
    Layer(transformation=GradientIntervalAnalysis(Float64.(probs), point, Symbol.(detail), orientation))

"""
    lineribbon(; probs=[0.95, 0.8, 0.5])
    lineribbon(; bands=[:q025 => :q975, :q25 => :q75])

Summarize y at each x with a median line and nested quantile ribbons.
Use raw values with `probs` and a `group` mapping for draw identity, or
precomputed lower/upper column pairs with `bands`. The two positional mappings
are x and the value or median. `detail` preserves grouping columns. A color mapping identifies
separate series; fixed `visual(; color=...)` colors a series without grouping.

At a single x position, `single_x_glyph=true` uses an interval glyph.
Over at most 12 numeric x values (a dose ladder), coloured or not, the figure
can also be drawn as point-intervals, and the `intervals` option picks the
drawing it starts in. Use `ribbon_view` to inspect that choice before rendering.
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

Draw nested quantile bands without the median line. Inputs, grouping, and
precomputed `bands` follow `lineribbon`. `single_x_glyph` controls the display
when a series has only one x coordinate.
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

Represent a distribution with quantile dots, nested intervals, and a point.
`n_dots` sets the quantile-dot count; `probs` chooses interval masses.
Orientation, grouping, and fixed colors follow `pointinterval`. The dots are
a distribution summary, not individual source observations.
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

Join mapped table values to GeoJSON geometry and draw geographic shapes.
`geometry` accepts a GeoJSON URL, a FeatureCollection dictionary, or a vector
of Feature dictionaries. `key` is a shared column/property name or a
`data_column => geo_property` pair; when omitted, the positional mapping
supplies the shared name. Unmatched rows and features are not drawn.
Use the `color` mapping for a numeric or categorical attribute and `projection`
for the geographic projection. All layers in a map share one projection;
the default is Mercator when no layer specifies another. Added point and line
layers map longitude and latitude in degrees. Regions larger than half the
globe are not supported.

This is a browser/Vega-Lite analysis. `vsave` can export it; the Makie `sdraw`
path does not implement it. Use `visual(; fill=nothing, stroke=:ink)` when
only a theme-aware boundary should be drawn.
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
