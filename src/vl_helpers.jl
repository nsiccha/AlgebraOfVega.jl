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

_vl_tooltip_entry!(args...) = nothing
function _vl_tooltip_entry!(tt, enc::Dict)
    haskey(enc, "field") || return
    entry = Dict{String,Any}("field" => enc["field"])
    haskey(enc, "type") && (entry["type"] = enc["type"])
    push!(tt, entry)
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

"""Collect tooltip fields from an encoding dict (all channels that have a "field" key), in channel order."""
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

Create a `Config` with Vega-Lite properties. Common options:

- `width`, `height`, `title` — spec dimensions and title
- `encoding` — deep-merged with auto-generated encodings (add aggregate, scale, axis, etc.).
  A `Dict` or the equivalent NamedTuple spelling: `encoding=(; x=(; scale=(; type="log")))`.
  On one summand of a `+` sum it applies to that summand's layers only
  (`a * config(encoding=E) + b`, e.g. a tooltip for `a`'s marks); apply it to the
  whole sum, `(a + b) * config(encoding=E)`, to reach every layer. `row`/`column`/`facet`
  overrides always configure the shared facet.
- `config` — raw Vega-Lite top-level `config` (a `Dict` or NamedTuple), deep-merged into
  AoV's defaults rather than replacing them
- `params`, `transform` — VL interactivity parameters and data transforms
- `select` — field(s) for client-side dropdown filtering (e.g. `select=:origin`)
- `frame` — animate the figure over a column's values, one frame at a time, with a
  play/pause button and a slider (e.g. `frame=:year`); the long form is
  `frame=(; field=:year, interval=0.5, loop=false, start=:first)`. Frames play in sorted
  order, or in a `sorter` order (`frame=:month => sorter("Jan", "Feb", …)`). Colour, size
  and x/y scales, and a map's projection, stay fixed across frames. Interactive path only.
- `link` — join a link group, e.g. `link=(; group="probes", key=:kenn)`: hovering one of this
  plot's marks highlights the item with the same `kenn` in every other member of group
  `probes` (other linked plots, HTMXObjects tables), and hovering an item there highlights
  this plot's marks with that `kenn` (the others dim, as for a legend selection). Interactive
  path only; a static figure ignores it.
- `scales` — an AoG `scales(...)` object, mirroring `draw(spec, scales(...))`. Currently
  translates X/Y/Z `scale=log`/`log2`/`log10`/`sqrt`/`symlog`/`identity` to VL scale types.
  Example: `config(scales=scales(Y=(; scale=log10)))`. Use `scale=symlog` for a symlog
  axis (linear near 0, log beyond — keeps genuine zeros a plain `log` axis cannot render),
  optionally with `constant=` to tune the linear-region half-width (VL default 1):
  `config(scales=scales(X=(; scale=symlog, constant=2)))`.
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

A configured spec still takes further algebra terms, which reach its layers as AoG
distributes `*` over `+`: `(a * config(encoding=E) + b) * visual(; clip=true)` is
`a * visual(; clip=true) * config(encoding=E) + b * visual(; clip=true)`, each summand
keeping its own override.

Successive terms accumulate: `spec * config(a...) * config(b...)` keeps every property of
both. `encoding`, `config`, `facet`, `axis` and `scales` merge key by key (`encoding` and
`config` recursively, `scales` scale by scale), with the later term winning on a
conflicting key; any other property (`width`, `title`, `params`, `transform`, …) takes the
later term's value.

Two configs compose the same way on their own: `a * b` is the `Config` that `spec * a * b`
applies, so `spec * (a * b) == spec * a * b`. A shared config extended with an app's own
settings, `SHARED * config(config=(; legend=(; orient="top")))`, stands in wherever
`SHARED` was used.
"""
function config(; kwargs...)
    props = Dict{Symbol,Any}(pairs(kwargs)...)
    for key in _VL_OBJECT_PROPS
        haskey(props, key) && (props[key] = _lower_vl_object(key, props[key]))
    end
    haskey(props, :frame) && (props[:frame] = _frame_options(props[:frame]))
    haskey(props, :link) && (props[:link] = _link_options(props[:link]))
    Config(props)
end

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
end
VegaSpec(drawable, config) = VegaSpec(drawable, config, Any[])

_spec_drawable(s::VegaSpec) = s.drawable
_spec_drawable(s) = s
_spec_layer_encodings(s::VegaSpec) = s.layer_encodings
_spec_layer_encodings(_) = Any[]

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
# raw Vega-Lite keys, …) takes the later term's value.
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
Base.:*(v::VegaSpec, c::Config) = VegaSpec(v.drawable, _merge_configs(v.config, c), v.layer_encodings)
Base.:*(c::Config, v::VegaSpec) = VegaSpec(v.drawable, _merge_configs(c, v.config), v.layer_encodings)
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

_summand_config(v::VegaSpec) = v.config
_summand_config(_) = nothing

"""
    _summand_parts(summand) -> (config, layer_encodings)

Split one summand of a `+` sum. `a * config(encoding=E) + b` scopes `E` to `a`:
`*` binds tighter than `+`, exactly as `a * visual(...) + b` styles only `a`.
The summand's `encoding` channels become per-layer overrides of ITS layers (on
top of any it already carried); facet channels and every other config property
(`width`, `title`, `scales`, `params`, …) describe the whole view and stay on the
sum's spec-level config. `(a + b) * config(encoding=E)` still applies `E` to
every layer.
"""
function _summand_parts(s)
    encs = _layer_encodings(s)
    cfg = _summand_config(s)
    isnothing(cfg) && return (cfg, encs)
    enc = _as_dict(get(cfg.properties, :encoding, nothing))
    isnothing(enc) && return (cfg, encs)
    scoped = Dict{String,Any}()
    shared = Dict{String,Any}()
    for (k, val) in enc
        ch = string(k)
        (_summand_scoped_channel(ch) ? scoped : shared)[ch] = val
    end
    isempty(scoped) && return (cfg, encs)
    props = copy(cfg.properties)
    isempty(shared) ? delete!(props, :encoding) : (props[:encoding] = shared)
    (Config(props), Any[_merge_vl_objects(e, scoped) for e in encs])
end

function _sum_specs(a, b)
    ca, ea = _summand_parts(a)
    cb, eb = _summand_parts(b)
    encs = vcat(ea, eb)
    VegaSpec(_spec_drawable(a) + _spec_drawable(b), _merge_configs(ca, cb),
        all(isnothing, encs) ? Any[] : encs)
end

# Combine VegaSpecs: unwrap drawables, merge view-level configs, keep each
# summand's encoding overrides on its own layers.
Base.:+(a::VegaSpec, b::VegaSpec) = _sum_specs(a, b)
Base.:+(a::VegaSpec, b::AlgebraOfGraphics.AbstractAlgebraic) = _sum_specs(a, b)
Base.:+(a::AlgebraOfGraphics.AbstractAlgebraic, b::VegaSpec) = _sum_specs(a, b)

# A further algebra term reaches a configured spec's layers as an unconfigured
# one's: AoG distributes `*` over `+`, so `(a * config(encoding=E) + b) * v`
# lowers like `a * v * config(encoding=E) + b * v`. Product layer (i, j) keeps
# the per-layer overrides of the left factor's layer i and then the right
# factor's layer j, in AoG's product order (the left factor's layers outer), and
# the view-level configs merge left to right. When the right factor carries
# per-layer overrides, the left factor's own encoding moves onto its layers
# first (`_summand_parts`), so a right-hand override still comes later and wins
# a conflicting key, as in the expanded expression.
function _mul_specs(a, b)
    ca, ea = isempty(_spec_layer_encodings(b)) ?
        (_summand_config(a), _layer_encodings(a)) : _summand_parts(a)
    eb = _layer_encodings(b)
    encs = Any[isnothing(e′) ? e : _merge_vl_objects(e, e′) for e in ea for e′ in eb]
    VegaSpec(_spec_drawable(a) * _spec_drawable(b), _merge_configs(ca, _summand_config(b)),
        all(isnothing, encs) ? Any[] : encs)
end

Base.:*(a::VegaSpec, b::VegaSpec) = _mul_specs(a, b)
Base.:*(a::VegaSpec, b::AlgebraOfGraphics.AbstractAlgebraic) = _mul_specs(a, b)
Base.:*(a::AlgebraOfGraphics.AbstractAlgebraic, b::VegaSpec) = _mul_specs(a, b)
