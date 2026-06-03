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
