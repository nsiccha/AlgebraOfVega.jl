"""
    to_html(spec; id, width, height)

Return a standalone HTML string with embedded vega-embed that self-loads scripts from CDN.
"""
function to_html(spec; id=nothing, width=nothing, height=nothing)
    vl = _as_vl_dict(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    id = _sanitize_id(something(id, "vega-" * string(abs(hash(JSON.json(vl))), base=16)))
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
    vdraw(spec; kwargs...)

Render an AoG spec as a Vega-Lite HTML node. Convenience alias for `to_node(spec; kwargs...)`.
Named `vdraw` to avoid clashing with `AlgebraOfGraphics.draw` (Makie rendering).
"""
vdraw(spec; kwargs...) = to_node(spec; kwargs...)
vdraw(; kwargs...) = spec -> vdraw(spec; kwargs...)

# --- Renderer-agnostic dependency declaration ---

"""
    vega_cdn_urls(; vega=VEGA_VERSION, vegalite=VEGALITE_VERSION, embed=VEGA_EMBED_VERSION)

Return a vector of CDN URLs for the Vega libraries. Useful for VitePress config,
Quarto YAML, or any system that needs to declare script dependencies.
"""
vega_cdn_urls(; vega=VEGA_VERSION, vegalite=VEGALITE_VERSION, embed=VEGA_EMBED_VERSION) = [
    "https://cdn.jsdelivr.net/npm/vega@$vega",
    "https://cdn.jsdelivr.net/npm/vega-lite@$vegalite",
    "https://cdn.jsdelivr.net/npm/vega-embed@$embed",
]
