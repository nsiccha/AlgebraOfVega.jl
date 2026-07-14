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
    single_x_glyph::Bool
end

struct PrecomputedRibbonAnalysis <: TidybayesAnalysis
    bands::Vector{Pair{Symbol,Symbol}}
    show_line::Bool
    detail_fields::Vector{Symbol}
    single_x_glyph::Bool
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

`single_x_glyph` (default `true`): any group/facet whose data collapses to a
single x value (where an area/line would render nothing) is instead drawn as a
vertical pointinterval glyph (rule-bands + a stroked median point) so it stays
visible. Set `false` to opt out (single-x groups revert to invisible area/line).
"""
function lineribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[], single_x_glyph=true)
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, true, Symbol.(detail), single_x_glyph))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), true, Symbol.(detail), single_x_glyph))
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
function ribbon(; probs=[0.95, 0.8, 0.5], bands=nothing, detail=Symbol[], single_x_glyph=true)
    if !isnothing(bands)
        parsed = Pair{Symbol,Symbol}[Symbol(first(b)) => Symbol(last(b)) for b in bands]
        return Layer(transformation=PrecomputedRibbonAnalysis(parsed, false, Symbol.(detail), single_x_glyph))
    end
    Layer(transformation=LineRibbonAnalysis(Float64.(probs), false, Symbol.(detail), single_x_glyph))
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
