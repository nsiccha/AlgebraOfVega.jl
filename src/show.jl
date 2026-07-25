# --- MIME show methods for notebook/Quarto support ---

Base.show(io::IO, ::MIME"text/html", spec::VegaSpec) = print(io, to_html(spec))
Base.show(io::IO, ::MIME"application/vnd.vegalite.v5+json", spec::VegaSpec) = print(io, to_json(spec))

# Also support raw Layer/Layers types
Base.show(io::IO, m::MIME"text/html", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"text/html", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"application/vnd.vegalite.v5+json", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))

# text/markdown — the `?plain` view. A spec returned directly from a route would
# otherwise fall to HTMX's `print(io, string(val))` catch-all and serialize the
# whole struct; emit the same bounded structural summary a plot node carries.
Base.show(io::IO, ::MIME"text/markdown", spec::VegaSpec) = print(io, plot_summary_md(spec))
Base.show(io::IO, m::MIME"text/markdown", layer::AlgebraOfGraphics.Layer) = show(io, m, VegaSpec(layer, nothing))
Base.show(io::IO, m::MIME"text/markdown", layers::AlgebraOfGraphics.Layers) = show(io, m, VegaSpec(layers, nothing))

