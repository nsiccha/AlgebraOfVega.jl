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

# Encoding-faceted? A spec faceted via `row=`/`col=` encoding channels carries
# `encoding.row` / `encoding.column` but has NO top-level `facet` operator and
# NO nested `spec`. `to_node` (fit_width sizing) and the auto-remap resolve
# scrubber must agree on this — a single source of truth so an encoding-faceted
# spec is never misclassified as a flat layered one by one site but not the other.
function _has_encoding_facet(vl::Dict)
    enc = _as_dict(get(vl, "encoding", nothing))
    !isnothing(enc) && (haskey(enc, "row") || haskey(enc, "column"))
end

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
"""
function config(; kwargs...)
    props = Dict{Symbol,Any}(pairs(kwargs)...)
    for key in _VL_OBJECT_PROPS
        haskey(props, key) && (props[key] = _lower_vl_object(key, props[key]))
    end
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

# Merge two `encoding` override dicts into a fresh, owned one: channel by channel,
# the later (`b`) wins on conflict, nested dicts merge key by key (as
# `_merge_encoding_config!` merges an override into a generated encoding).
_merge_encodings(::Nothing, b::Dict) = _owned_copy(b)
_merge_encodings(a::Dict, b::Dict) = _deep_merge_dict!(_owned_copy(a), _owned_copy(b))

# Merge two configs, later-wins on key conflict. Shared by `*` and `+` so config
# accumulates the same way under both. `encoding` dicts merge per channel instead
# of replacing each other: `spec * config(encoding=Dict(:tooltip => …)) *
# config(encoding=Dict("y" => Dict("sort" => …)))` keeps the tooltip.
function _merge_configs(a::Union{Config,Nothing}, b::Union{Config,Nothing})
    isnothing(a) && return b
    isnothing(b) && return a
    props = merge(a.properties, b.properties)
    ea = _as_dict(get(a.properties, :encoding, nothing))
    eb = _as_dict(get(b.properties, :encoding, nothing))
    !isnothing(ea) && !isnothing(eb) && (props[:encoding] = _merge_encodings(ea, eb))
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
    (Config(props), Any[_merge_encodings(e, scoped) for e in encs])
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
