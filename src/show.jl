# --- MIME show methods for notebook/Quarto support ---

Base.show(io::IO, ::MIME"text/html", spec::VegaSpec) = print(io, to_html(spec))
Base.show(io::IO, ::MIME"application/vnd.vegalite.v5+json", spec::VegaSpec) = print(io, to_json(spec))

# Also support raw Layer/Layers types
Base.show(io::IO, m::MIME"text/html", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"text/html", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))

