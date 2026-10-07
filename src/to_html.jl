"""
    to_html(spec; id, width, height, source, base)

Return a standalone HTML string with embedded vega-embed. `source` selects the
script origin — `:cdn` (default), `:vendor`, or `:inline`, as in `vega_head`.
`source=:inline` inlines AoV's vendored Vega builds, so the returned page
renders with no network access at all.
"""
function to_html(spec; id=nothing, width=nothing, height=nothing,
        source::Symbol=:cdn, base::AbstractString="/vendor")
    vl = _as_vl_dict(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    id = _sanitize_id(something(id, "vega-" * string(abs(hash(_vl_json(vl))), base=16)))
    json = _vl_json(vl)
    scripts = join((sprint(show, MIME"text/html"(), n)
        for n in _vega_script_nodes(; source, base)), "\n")
    """
    <div id="$id"></div>
    $scripts
    <script>vegaEmbed('#$id', $json, {actions: false}).catch(console.error);</script>
    """
end

# Minimal HTML escaping for interpolated page metadata (titles). Fragment
# bodies are trusted HTMX nodes, rendered by HTMX itself.
_html_escape(s::AbstractString) =
    replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

"""
    to_html(node::HTMX.Node; title="AoV plot", head_extra="", source, base, runtime) -> String

Serialize a rendered plot node (e.g. `to_node`, `auto_remap_node`, or a
`with_plot_caption` fragment) as ONE standalone `.html` document string:
`<!DOCTYPE html>` + `<head>` + `<body>`.

The `<head>` is the exact `vega_head()` set — Vega/Vega-Lite/Vega-Embed
scripts plus the inlined `window.AoV.*` runtime — rendered by construction
from `vega_head()` itself, so versions can never drift. `source` selects the
script origin (`:cdn` default, `:vendor`, `:inline`) and `runtime` how AoV's
runtime is loaded (`:inline` default, `:linked`), as in `vega_head`;
`source=:inline` inlines the vendored builds, so the saved file renders with
no network at all. `head_extra` appends additional rendered head HTML (the
`with_plot_caption` methods use it for caption CSS + table sorting). The node
body carries picker controls, embed scripts, and inlined spec/data JSON, so
the saved file keeps working with no server: picker re-facets, CSV/PNG/SVG
download, caption/summary render. Only `signals=`-wired plots degrade (their
`htmx.ajax` callback has no server), and they do so silently — see
`signalToHtmx`.
"""
function to_html(node::HTMX.Node; title::AbstractString="AoV plot", head_extra::AbstractString="",
        source::Symbol=:cdn, base::AbstractString="/vendor", runtime::Symbol=:inline)
    head_io = IOBuffer()
    for n in vega_head(; source, base, runtime)
        show(head_io, MIME"text/html"(), n)
    end
    head_html = String(take!(head_io)) * head_extra
    body_html = sprint(show, MIME"text/html"(), node)
    _standalone_page(head_html, body_html; title=title)
end

function _standalone_page(head_html::AbstractString, body_html::AbstractString; title::AbstractString="AoV plot")
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>$(_html_escape(title))</title>
    <style>body{font-family:system-ui,sans-serif;margin:1rem}</style>
    $(head_html)
    </head>
    <body>
    $(body_html)
    </body>
    </html>
    """
end

"""
    vdraw(spec; kwargs...)

Render an AoG spec as a Vega-Lite HTML node. Convenience alias for `to_node(spec; kwargs...)`.
Named `vdraw` to avoid clashing with `AlgebraOfGraphics.draw` (Makie rendering).
"""
vdraw(spec; kwargs...) = to_node(spec; kwargs...)
vdraw(; kwargs...) = spec -> vdraw(spec; kwargs...)

"""
    vdraw(spec, scales; kwargs...)

Render an AoG spec with an AoG `Scales` override applied — the interactive mirror of
`AlgebraOfGraphics.draw(spec, scales(...))`. Equivalent to `vdraw(to_vegalite(spec, scales); kwargs...)`.
See `to_vegalite(spec, scales)` for the supported X/Y/Z axis scales and the `Color`
(palette / categories / colormap) override.
"""
vdraw(spec, sc::AlgebraOfGraphics.Scales; kwargs...) = to_node(to_vegalite(spec, sc); kwargs...)

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

"""
    vega_sri_hashes()

Subresource-integrity (sha384) hashes for the exact-pinned `vega_cdn_urls()`,
in the same order — for systems that declare script dependencies with
integrity checks.
"""
vega_sri_hashes() = [VEGA_SRI, VEGALITE_SRI, VEGA_EMBED_SRI]
