module AlgebraOfVega

using JSON, Tables
using HTMX
import HTMX: h, Node

export data, mapping, visual, config, draw
export to_vegalite, to_json, to_html, to_node, vega_head

# --- Core Types ---

struct Data
    values::Any
end

struct Mapping
    positional::Vector{Symbol}
    named::Dict{Symbol, Any}
end

struct Visual
    mark::Symbol
    properties::Dict{Symbol, Any}
end

struct Config
    properties::Dict{Symbol, Any}
end

struct Layer
    data::Union{Data, Nothing}
    mappings::Vector{Mapping}
    visual::Union{Visual, Nothing}
    config::Union{Config, Nothing}
end

struct Layers
    layers::Vector{Layer}
    config::Union{Config, Nothing}
end

const Spec = Union{Layer, Layers}

# --- Constructors ---

data(table) = Data(table)
data(; url) = Data((; url))

mapping(args::Symbol...; kwargs...) = Mapping(collect(args), Dict{Symbol,Any}(pairs(kwargs)...))

visual(mark::Symbol; kwargs...) = Visual(mark, Dict{Symbol,Any}(pairs(kwargs)...))

config(; kwargs...) = Config(Dict{Symbol,Any}(pairs(kwargs)...))

# --- Composition with * ---

_layer(; data=nothing, mappings=Mapping[], visual=nothing, config=nothing) =
    Layer(data, mappings isa Vector ? mappings : [mappings], visual, config)

Base.:*(d::Data, m::Mapping) = _layer(data=d, mappings=[m])
Base.:*(m::Mapping, v::Visual) = _layer(mappings=[m], visual=v)
Base.:*(d::Data, v::Visual) = _layer(data=d, visual=v)
Base.:*(l::Layer, v::Visual) = Layer(l.data, l.mappings, v, l.config)
Base.:*(l::Layer, m::Mapping) = Layer(l.data, vcat(l.mappings, m), l.visual, l.config)
Base.:*(l::Layer, d::Data) = Layer(d, l.mappings, l.visual, l.config)
Base.:*(d::Data, l::Layer) = Layer(d, l.mappings, l.visual, l.config)
Base.:*(l::Layer, c::Config) = Layer(l.data, l.mappings, l.visual, c)
Base.:*(c::Config, l::Layer) = Layer(l.data, l.mappings, l.visual, c)
Base.:*(d::Data, m::Layers) = Layers([Layer(d, l.mappings, l.visual, l.config) for l in m.layers], m.config)

# Layering with +
Base.:+(a::Layer, b::Layer) = Layers([a, b], nothing)
Base.:+(a::Layers, b::Layer) = Layers(vcat(a.layers, [b]), a.config)
Base.:+(a::Layer, b::Layers) = Layers(vcat([a], b.layers), b.config)
Base.:+(a::Layers, b::Layers) = Layers(vcat(a.layers, b.layers), a.config)

# Config with Layers
Base.:*(l::Layers, c::Config) = Layers(l.layers, c)
Base.:*(c::Config, l::Layers) = Layers(l.layers, c)

# --- Vega-Lite Type Inference ---

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

const POSITIONAL_CHANNELS = [:x, :y, :color, :size, :shape]

# --- Encoding Conversion ---

function mapping_to_encoding(m::Mapping)
    encoding = Dict{String, Any}()
    for (i, field) in enumerate(m.positional)
        i <= length(POSITIONAL_CHANNELS) || break
        channel = string(POSITIONAL_CHANNELS[i])
        encoding[channel] = Dict{String,Any}("field" => string(field))
    end
    for (channel, value) in m.named
        ch = string(channel)
        if value isa Symbol
            encoding[ch] = Dict{String,Any}("field" => string(value))
        elseif value isa Pair
            encoding[ch] = Dict{String,Any}("field" => string(first(value)), "type" => last(value))
        elseif value isa Dict
            encoding[ch] = value
        else
            encoding[ch] = Dict{String,Any}("value" => value)
        end
    end
    encoding
end

function infer_types!(encoding::Dict, table)
    isnothing(table) && return encoding
    Tables.istable(table) || return encoding
    cols = Tables.columns(table)
    colnames = Tables.columnnames(cols)
    for (ch, enc) in encoding
        enc isa Dict || continue
        if haskey(enc, "field") && !haskey(enc, "type")
            field = Symbol(enc["field"])
            if field in colnames
                enc["type"] = vl_type(Tables.getcolumn(cols, field))
            end
        end
    end
    encoding
end

# --- Data Conversion ---

function data_to_vl(d::Data)
    values = d.values
    if values isa NamedTuple && haskey(values, :url)
        return Dict{String,Any}("url" => values.url)
    end
    rows = Tables.rowtable(values)
    Dict{String,Any}("values" => [
        Dict{String,Any}(string(k) => v for (k, v) in pairs(nt))
        for nt in rows
    ])
end

function mark_to_vl(v::Visual)
    if isempty(v.properties)
        string(v.mark)
    else
        merge(
            Dict{String,Any}("type" => string(v.mark)),
            Dict{String,Any}(string(k) => val for (k, val) in v.properties)
        )
    end
end

# --- to_vegalite ---

function to_vegalite(layer::Layer)
    spec = Dict{String,Any}()
    spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"

    table = nothing
    if !isnothing(layer.data)
        spec["data"] = data_to_vl(layer.data)
        table = layer.data.values
    end

    if !isnothing(layer.visual)
        spec["mark"] = mark_to_vl(layer.visual)
    end

    if !isempty(layer.mappings)
        encoding = Dict{String,Any}()
        for m in layer.mappings
            merge!(encoding, mapping_to_encoding(m))
        end
        infer_types!(encoding, table)
        spec["encoding"] = encoding
    end

    if !isnothing(layer.config)
        for (k, v) in layer.config.properties
            spec[string(k)] = v
        end
    end

    spec
end

function to_vegalite(layers::Layers)
    spec = Dict{String,Any}()
    spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"

    # Extract shared data from first layer
    shared_data = nothing
    for l in layers.layers
        if !isnothing(l.data)
            shared_data = l.data
            break
        end
    end

    if !isnothing(shared_data)
        spec["data"] = data_to_vl(shared_data)
    end

    layer_specs = Dict{String,Any}[]
    for layer in layers.layers
        ls = Dict{String,Any}()

        # Only include data if different from shared
        if !isnothing(layer.data) && layer.data !== shared_data
            ls["data"] = data_to_vl(layer.data)
        end

        if !isnothing(layer.visual)
            ls["mark"] = mark_to_vl(layer.visual)
        end

        if !isempty(layer.mappings)
            encoding = Dict{String,Any}()
            for m in layer.mappings
                merge!(encoding, mapping_to_encoding(m))
            end
            table = !isnothing(layer.data) ? layer.data.values :
                    !isnothing(shared_data) ? shared_data.values : nothing
            infer_types!(encoding, table)
            ls["encoding"] = encoding
        end

        push!(layer_specs, ls)
    end

    spec["layer"] = layer_specs

    if !isnothing(layers.config)
        for (k, v) in layers.config.properties
            spec[string(k)] = v
        end
    end

    spec
end

# --- Output ---

to_json(x; kwargs...) = JSON.json(to_vegalite(x))

const VEGA_VERSION = "5"
const VEGALITE_VERSION = "5"
const VEGA_EMBED_VERSION = "6"

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
    ]
end

"""
    to_node(spec; id, width, height, actions)

Convert a spec to an HTMX `Node` containing a div + script that calls `vegaEmbed`.
Requires vega/vega-lite/vega-embed scripts to be loaded (use `vega_head()` in page head).
"""
function to_node(spec; id=nothing, width=nothing, height=nothing, actions=false)
    vl = spec isa Dict ? copy(spec) : to_vegalite(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    id = something(id, "vega-" * string(abs(hash(JSON.json(vl))), base=16))
    json = JSON.json(vl)
    h.div(
        h.div(id=id),
        h.script("vegaEmbed('#$id', $json, {actions: $actions}).catch(console.error);"),
    )
end

"""
    to_html(spec; id, width, height)

Return a standalone HTML string with embedded vega-embed that self-loads scripts from CDN.
Useful outside of HTMXObjects (e.g. saving to file).
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
    draw(spec; kwargs...)

Convenience alias for `to_node(spec; kwargs...)`.
"""
draw(spec; kwargs...) = to_node(spec; kwargs...)

end # module AlgebraOfVega
