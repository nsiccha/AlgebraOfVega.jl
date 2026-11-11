# --- Vega-Lite constants and helpers ---

"""Vega-Lite v5 JSON schema URL, injected at top level of every spec."""
VL_SCHEMA = "https://vega.github.io/schema/vega-lite/v5.json"

"""
    _vl_json(x; kwargs...) -> String

AoV's single JSON writer for everything it hands to the browser. Every non-finite
float (`NaN`, `Inf`, `-Inf`) is written as `null`, which Vega-Lite reads as a
missing value — a line/area gap or a dropped point/rule — instead of the
`ArgumentError` JSON.jl ≥ 1 raises by default. `kwargs` pass through to `JSON.json`.
"""
_vl_json(x; kwargs...) = JSON.json(x; allownan=true, nan="null", inf="null", ninf="null", kwargs...)

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

# Encoding-faceted? A single view faceted through its encoding — `encoding.row` /
# `encoding.column` (single-layer `row=`/`col=`) or the wrap channel
# `encoding.facet` (single-layer `layout=`) — has NO top-level `facet` operator
# and NO nested `spec`. `to_node` (fit_width sizing), `plot_size` and the
# auto-remap resolve scrubber must agree on this — a single source of truth so an
# encoding-faceted spec is never misclassified as a flat single view by one site
# but not the other.
function _has_encoding_facet(vl::Dict)
    enc = _as_dict(get(vl, "encoding", nothing))
    !isnothing(enc) && (haskey(enc, "row") || haskey(enc, "column") || haskey(enc, "facet"))
end

# Faceted? The facet operator (`facet` + nested `spec`) or an encoding-faceted single
# view. Only there does `resolve.scale.<axis> = "independent"` mean "per facet panel":
# beside a plain `layer` Vega-Lite gives every layer its own scale and axis instead.
# The AoG-drawable methods (`row`/`col`/`layout` mappings) are in src/sdraw.jl.
_is_faceted(vl::Dict) = haskey(vl, "facet") || !isnothing(_as_dict(get(vl, "spec", nothing))) ||
    _has_encoding_facet(vl)

# The wrap facet of a spec (`layout=`): the facet operator's single-field form
# (`facet: {field}`, analysis and multi-layer figures) or a single view's
# `encoding.facet` channel. Returns that field def, or `nothing` for any other spec
# (a `row`/`column` grid does not wrap).
_wrap_facet(_) = nothing
function _wrap_facet(vl::Dict)
    facet = _as_dict(get(vl, "facet", nothing))
    isnothing(facet) || return haskey(facet, "field") ? facet : nothing
    enc = _as_dict(get(vl, "encoding", nothing))
    f = isnothing(enc) ? nothing : _as_dict(get(enc, "facet", nothing))
    (!isnothing(f) && haskey(f, "field")) ? f : nothing
end

# The column count a wrap facet already carries: the spec's top-level `columns`, or
# the facet channel's own `columns`. Vega-Lite reads either; `nothing` when neither
# is set (Vega-Lite then lays every panel out in one row).
function _wrap_columns(vl::Dict, facet::Dict)
    n = _as_number(get(vl, "columns", nothing))
    isnothing(n) && (n = _as_number(get(facet, "columns", nothing)))
    isnothing(n) ? nothing : max(1, round(Int, n))
end

# How many distinct values `field` takes in the spec's inline `data.values`:
# the number of facet panels. 0 when the spec carries no inline rows.
function _facet_levels(vl::Dict, field)
    vals = _as_vec(get(something(_as_dict(get(vl, "data", nothing)), Dict()), "values", nothing))
    isnothing(vals) ? 0 : _size_field_cardinality(vals, field)
end

# A generated tooltip names each mapped column by the mapping's label, the
# name its axis, legend or facet header shows, so the tooltip agrees with the
# figure it sits on (`mapping(:east => "East (km)")` reads "East (km)", not
# "east"). An unlabelled column keeps its own name, and so does one labelled
# "": a header hidden with `row=:time => ""` would otherwise give a tooltip row
# with no name. Before this, every generated tooltip listed raw column names
# (snag `hover-a-cell-of-a723ea83`).
_is_tooltip_label(label, field) = label isa AbstractString && !isempty(label) && label != string(field)

"""A generated tooltip row for `field`, titled with `label` when that is a label (`_is_tooltip_label`)."""
function _tooltip_entry(field, type=nothing, label=nothing)
    entry = Dict{String,Any}("field" => field)
    isnothing(type) || (entry["type"] = type)
    _is_tooltip_label(label, field) && (entry["title"] = label)
    entry
end

_vl_tooltip_entry!(args...) = nothing
function _vl_tooltip_entry!(tt, enc::Dict)
    haskey(enc, "field") || return
    # One row per column: `color=:g, strokecolor=:g` maps one column twice.
    any(t -> t["field"] == enc["field"], tt) && return
    push!(tt, _tooltip_entry(enc["field"], get(enc, "type", nothing), get(enc, "title", nothing)))
end

# Channels are listed in this order when present; anything else follows
# alphabetically. Generated tooltips and plot summaries sort by it rather than
# iterating an encoding `Dict`, whose order is its hash order and differs
# between Julia versions (1.10 lists `x` before `y`, 1.13 `y` before `x`).
const _CHANNEL_ORDER = ("x", "y", "x2", "y2", "longitude", "latitude",
    "longitude2", "latitude2", "xOffset", "yOffset",
    "theta", "theta2", "radius", "radius2", "color", "fill", "stroke",
    "opacity", "fillOpacity", "strokeOpacity", "strokeWidth", "strokeDash",
    "size", "shape", "angle", "detail", "order", "row", "column", "facet",
    "text", "tooltip", "href", "key", "url")

_channel_sort_key(ch) = let name = string(ch)
    (something(findfirst(==(name), _CHANNEL_ORDER), length(_CHANNEL_ORDER) + 1), name)
end

"""Collect tooltip fields from an encoding dict (all channels that have a "field" key), in channel order,
each column once and titled with its channel's label."""
function vl_tooltips(encoding)
    tt = Dict{String,Any}[]
    for ch in sort!(collect(keys(encoding)); by=_channel_sort_key)
        _vl_tooltip_entry!(tt, encoding[ch])
    end
    tt
end

# --- Vega-specific types ---

struct Config
    properties::Dict{Symbol, Any}
end

"""
    config(; kwargs...)

Attach Vega-Lite configuration to a drawable with `spec * config(...)`.
Use `width`, `height`, and `title` for the figure; `axis=(; ...)` for labels and
limits; and `scales=scales(...)` for scale configuration using AlgebraOfGraphics
names. The same `scales(...)` object can be the second argument to `vdraw` or
`to_vegalite`.

`params`, `transform`, and other Vega-Lite properties provide an escape hatch.
`select` adds filter controls; `frame` selects an animation coordinate; `link`
connects hover identity across figures. Per-layer configuration stays with its
layer. Configuration applied to a combined figure applies to the combined result.

Use a configured drawable with `vdraw` for a browser or `sdraw` for Makie.
Browser-only settings need not have a static-rendering equivalent.
"""
function config(; kwargs...)
    props = Dict{Symbol,Any}(pairs(kwargs)...)
    for key in _VL_OBJECT_PROPS
        haskey(props, key) && (props[key] = _lower_vl_object(key, props[key]))
    end
    haskey(props, :transform) && (props[:transform] = _transform_list(props[:transform]))
    haskey(props, :frame) && (props[:frame] = _frame_options(props[:frame]))
    haskey(props, :link) && (props[:link] = _link_options(props[:link]))
    Config(props)
end

# `config(transform=…)` lowered to an owned list. Vega-Lite takes only a list, and
# every transform AoV adds later (a dropdown's filter) extends this one in place.
_transform_list(::Nothing) = Any[]
_transform_list(t::AbstractVector) = _owned_copy(t)
_transform_list(t::Union{AbstractDict,NamedTuple}) = Any[_owned_copy(t)]
_transform_list(t) = throw(ArgumentError(
    "AlgebraOfVega: `config(transform=…)` takes a list of Vega-Lite transforms, got $(typeof(t))."))

# The config properties AoV deep-merges into the Vega-Lite object it generated.
# Each is lowered once, here, to an owned `Dict{String,Any}`, so the `*`/`+`
# config merges, summand scoping, `to_vegalite` and `sdraw` all see one shape
# whether the caller wrote a Dict or a NamedTuple. Anything else would replace
# the generated object wholesale, so it fails here instead.
const _VL_OBJECT_PROPS = (:encoding, :config)
_lower_vl_object(_, obj::Union{AbstractDict,NamedTuple}) = _owned_copy(obj)
_lower_vl_object(key, obj) = throw(ArgumentError(
    "AlgebraOfVega: `config($key=…)` takes a Dict or NamedTuple of Vega-Lite properties, got $(typeof(obj))."))

struct VegaSpec
    drawable::Any  # AoG Layer, Layers, or AbstractAlgebraic
    config::Union{Config, Nothing}
    # Per-layer `config(encoding=…)` overrides that summands carried into a `+`
    # sum, aligned with the drawable's layers (`nothing` = no override for that
    # layer). Empty when no summand carried one. See `_summand_parts`.
    layer_encodings::Vector{Any}
    # Per-layer `config(transform=…)` lists, aligned the same way. See `_summand_parts`.
    layer_transforms::Vector{Any}
end
VegaSpec(drawable, config) = VegaSpec(drawable, config, Any[], Any[])

_spec_drawable(s::VegaSpec) = s.drawable
_spec_drawable(s) = s
_spec_layer_encodings(s::VegaSpec) = s.layer_encodings
_spec_layer_encodings(_) = Any[]
_spec_layer_transforms(s::VegaSpec) = s.layer_transforms
_spec_layer_transforms(_) = Any[]

"""
    vlspec(drawable; kwargs...)

Wrap an AoG drawable in a `VegaSpec` with optional config properties.
Equivalent to `drawable * config(; kwargs...)`.
"""
vlspec(drawable; kwargs...) = VegaSpec(drawable, isempty(kwargs) ? nothing : config(; kwargs...))

# A copy of a caller's override that AoV owns and may extend in place: every
# nested dict or NamedTuple becomes a fresh `Dict{String,Any}`, every vector a
# fresh `Vector{Any}`, and every Symbol the string JSON writes for it. A
# concretely typed caller dict (`Dict("type" => "log")` is a `Dict{String,String}`)
# could not take the `zero=false` a later pass adds, and the caller's own values
# are never aliased.
_owned_copy(d::Union{AbstractDict,NamedTuple}) =
    Dict{String,Any}(string(k) => _owned_copy(v) for (k, v) in pairs(d))
_owned_copy(v::AbstractVector) = Any[_owned_copy(x) for x in v]
_owned_copy(s::Symbol) = string(s)
_owned_copy(x) = deepcopy(x)

# Merge two Vega-Lite object overrides (`encoding`, raw `config`) into a fresh,
# owned one: key by key, the later (`b`) wins on conflict, nested dicts merge key
# by key (as `_merge_encoding_config!` merges an override into a generated encoding).
_merge_vl_objects(::Nothing, b::Dict) = _owned_copy(b)
_merge_vl_objects(a::Dict, b::Dict) = _deep_merge_dict!(_owned_copy(a), _owned_copy(b))

# The config properties that hold an object, which successive config terms MERGE
# rather than the later replacing the earlier wholesale: the Vega-Lite objects
# (recursively), the AoG `draw(; facet, axis)` keyword NamedTuples (key by key) and
# the AoG `scales(...)` (scale by scale, then key by key). The later term wins on a
# conflicting key. Every other property (`width`, `title`, `params`, `transform`,
# raw Vega-Lite keys, …) takes the later term's value on one view; a `+` moves a
# summand's `transform` onto its own layers first (`_summand_parts`).
const _MERGED_CONFIG_PROPS = (_VL_OBJECT_PROPS..., :facet, :axis, :scales)
_merge_config_value(_, b) = b  # not two objects of one kind: the later term wins
_merge_config_value(a::Dict, b::Dict) = _merge_vl_objects(a, b)
_merge_config_value(a::NamedTuple, b::NamedTuple) = merge(a, b)
function _merge_config_value(a::AlgebraOfGraphics.Scales, b::AlgebraOfGraphics.Scales)
    scale_props(s, id) = haskey(s.dict, id) ? NamedTuple(pairs(s.dict[id])) : (;)
    ids = unique!(Symbol[keys(a.dict)..., keys(b.dict)...])
    AlgebraOfGraphics.scales(; (id => merge(scale_props(a, id), scale_props(b, id)) for id in ids)...)
end

# Merge two configs, later-wins on key conflict. Shared by `*` and `+` so config
# accumulates the same way under both. Object-valued properties merge instead of
# replacing each other: `spec * config(encoding=Dict(:tooltip => …)) *
# config(encoding=Dict("y" => Dict("sort" => …)))` keeps the tooltip, and
# `spec * config(config=Dict("legend" => …)) * config(config=Dict("locale" => …))`
# keeps the legend settings.
function _merge_configs(a::Union{Config,Nothing}, b::Union{Config,Nothing})
    isnothing(a) && return b
    isnothing(b) && return a
    props = merge(a.properties, b.properties)
    for k in _MERGED_CONFIG_PROPS
        haskey(a.properties, k) && haskey(b.properties, k) &&
            (props[k] = _merge_config_value(a.properties[k], b.properties[k]))
    end
    Config(props)
end

# Composition: AoG drawable * Config → VegaSpec
Base.:*(a::AlgebraOfGraphics.AbstractAlgebraic, c::Config) = VegaSpec(a, c)
Base.:*(c::Config, a::AlgebraOfGraphics.AbstractAlgebraic) = VegaSpec(a, c)
# A second `* config(...)` MERGES into the config already on the spec rather than
# replacing it — an app helper appending e.g. `config(width=…, height=…)` after a
# caller's `config(facet=…, title=…)` used to silently drop every earlier prop,
# with no warning and no error (the deprecation warning for `independent_scales`
# didn't fire either, because the clobbered props never reached `to_vegalite`).
# Later-wins, matching `+`/`merge`. Left operand comes first in the expression,
# so the right one takes precedence.
Base.:*(v::VegaSpec, c::Config) = VegaSpec(v.drawable, _merge_configs(v.config, c), v.layer_encodings, v.layer_transforms)
Base.:*(c::Config, v::VegaSpec) = VegaSpec(v.drawable, _merge_configs(c, v.config), v.layer_encodings, v.layer_transforms)
# Two configs compose into the one config `spec * a * b` applies, so
# `spec * (a * b) == spec * a * b`: an app extends a shared config with its own
# settings once (`const GERMAN = SHARED * config(config=…)`) and uses the result
# wherever it used the shared one, instead of copying it or changing every call site.
Base.:*(a::Config, b::Config) = _merge_configs(a, b)

# Facet channels configure the one facet operator every layer shares, so a
# summand's override of them stays spec-level.
const _FACET_ENCODING_CHANNELS = ("row", "column", "facet")
_summand_scoped_channel(ch::AbstractString) = !(ch in _FACET_ENCODING_CHANNELS)

_n_layers(::AlgebraOfGraphics.Layer) = 1
_n_layers(l::AlgebraOfGraphics.Layers) = length(l.layers)

_layer_encodings(v::VegaSpec) = isempty(v.layer_encodings) ?
    Any[nothing for _ in 1:_n_layers(v.drawable)] : copy(v.layer_encodings)
_layer_encodings(a) = Any[nothing for _ in 1:_n_layers(a)]
_layer_transforms(v::VegaSpec) = isempty(v.layer_transforms) ?
    Any[nothing for _ in 1:_n_layers(v.drawable)] : copy(v.layer_transforms)
_layer_transforms(a) = Any[nothing for _ in 1:_n_layers(a)]

_summand_config(v::VegaSpec) = v.config
_summand_config(_) = nothing

"""
    _summand_parts(summand) -> (config, layer_encodings, layer_transforms)

Split one summand of a `+` sum. `a * config(encoding=E, transform=T) + b` scopes `E`
and `T` to `a`: `*` binds tighter than `+`, exactly as `a * visual(...) + b` styles
only `a`. The summand's `encoding` channels become per-layer overrides of ITS layers
(on top of any it already carried), and its `transform` runs before any its layers
already carried, as a figure's transform runs before a layer's. Facet channels and
every other config property (`width`, `title`, `scales`, `params`, …) describe the
whole view and stay on the sum's spec-level config. `(a + b) * config(encoding=E,
transform=T)` still applies `E` and `T` to every layer.
"""
function _summand_parts(s)
    encs = _layer_encodings(s)
    transforms = _layer_transforms(s)
    cfg = _summand_config(s)
    isnothing(cfg) && return (cfg, encs, transforms)
    props = copy(cfg.properties)
    transform = pop!(props, :transform, nothing)
    if !isnothing(transform) && !isempty(transform)
        transforms = Any[isnothing(t) ? transform : vcat(transform, t) for t in transforms]
    end
    enc = _as_dict(get(props, :encoding, nothing))
    if !isnothing(enc)
        scoped = Dict{String,Any}()
        shared = Dict{String,Any}()
        for (k, val) in enc
            ch = string(k)
            (_summand_scoped_channel(ch) ? scoped : shared)[ch] = val
        end
        if !isempty(scoped)
            isempty(shared) ? delete!(props, :encoding) : (props[:encoding] = shared)
            encs = Any[_merge_vl_objects(e, scoped) for e in encs]
        end
    end
    (Config(props), encs, transforms)
end

# The per-layer overrides of a sum or product, or none when no layer has one.
_layer_overrides(xs) = all(isnothing, xs) ? Any[] : xs

function _sum_specs(a, b)
    ca, ea, ta = _summand_parts(a)
    cb, eb, tb = _summand_parts(b)
    VegaSpec(_spec_drawable(a) + _spec_drawable(b), _merge_configs(ca, cb),
        _layer_overrides(vcat(ea, eb)), _layer_overrides(vcat(ta, tb)))
end

# Combine VegaSpecs: unwrap drawables, merge view-level configs, keep each
# summand's encoding and transform overrides on its own layers.
Base.:+(a::VegaSpec, b::VegaSpec) = _sum_specs(a, b)
Base.:+(a::VegaSpec, b::AlgebraOfGraphics.AbstractAlgebraic) = _sum_specs(a, b)
Base.:+(a::AlgebraOfGraphics.AbstractAlgebraic, b::VegaSpec) = _sum_specs(a, b)

# A further algebra term reaches a configured spec's layers as an unconfigured
# one's: AoG distributes `*` over `+`, so `(a * config(encoding=E) + b) * v`
# lowers like `a * v * config(encoding=E) + b * v`. Product layer (i, j) keeps
# the per-layer overrides of the left factor's layer i and then the right
# factor's layer j, in AoG's product order (the left factor's layers outer), and
# the view-level configs merge left to right. When the right factor carries
# per-layer overrides, the left factor's own encoding and transform move onto its
# layers first (`_summand_parts`), so a right-hand override still comes later and
# wins a conflicting key, as in the expanded expression; a right-hand transform
# takes the place of a left-hand one, as `spec * config(transform=T)` does.
function _mul_specs(a, b)
    ca, ea, ta = isempty(_spec_layer_encodings(b)) && isempty(_spec_layer_transforms(b)) ?
        (_summand_config(a), _layer_encodings(a), _layer_transforms(a)) : _summand_parts(a)
    eb = _layer_encodings(b)
    tb = _layer_transforms(b)
    encs = Any[isnothing(e′) ? e : _merge_vl_objects(e, e′) for e in ea for e′ in eb]
    transforms = Any[isnothing(t′) ? t : t′ for t in ta for t′ in tb]
    VegaSpec(_spec_drawable(a) * _spec_drawable(b), _merge_configs(ca, _summand_config(b)),
        _layer_overrides(encs), _layer_overrides(transforms))
end

Base.:*(a::VegaSpec, b::VegaSpec) = _mul_specs(a, b)
Base.:*(a::VegaSpec, b::AlgebraOfGraphics.AbstractAlgebraic) = _mul_specs(a, b)
Base.:*(a::AlgebraOfGraphics.AbstractAlgebraic, b::VegaSpec) = _mul_specs(a, b)
