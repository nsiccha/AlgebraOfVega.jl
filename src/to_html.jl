"""
    to_html(spec; id, width, height, source, base)

Return a standalone HTML string with embedded vega-embed. `source` selects the
script origin — `:cdn` (default), `:vendor`, or `:inline`, as in `vega_head`.
`source=:inline` inlines AoV's vendored Vega builds, so the returned page
renders with no network access at all. This is also the `text/html` `show` of a
spec, so it is what a notebook, or HTMXObjects' `SemanticPlot`, writes.

The fragment also draws when it is inserted into a page that has already
loaded, for example by an htmx swap into a page without `vega_head()`. There
the browser runs the embed script before the Vega scripts above it have
arrived, so the embed waits for them. If one of them fails to load, the plot's
container and the console say so, naming `vega_head()`.
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
    <script>$(_inline_text(_standalone_embed_js(id, json, _standalone_embed_opts(vl))))</script>
    """
end

# The bare embed's vega-embed options. A spec with a `visual(...; inspectable=false)`
# layer also gets the patch that makes its marks let the pointer through
# (`_AOV_PASSIVE`); any other spec's page is unchanged.
const _PASSIVE_PATCH_JS = "function (vg) { (function walk(marks) { (marks || []).forEach(function (m) { " *
    "var s = m.style; if (s === 'aov-passive' || (Array.isArray(s) && s.indexOf('aov-passive') !== -1)) m.interactive = false; " *
    "walk(m.marks); }); })(vg && vg.marks); return vg; }"
# A spec with AoV's automatic pan/zoom gets the patch that draws its marks whole
# until the reader zooms, then cuts them at the frame along the zoomed axes only
# (`_AOV_OWN_CLIP`). LOCKSTEP: `_panZoomClip` (vendor/aov-runtime.js).
const _PAN_ZOOM_CLIP_JS = "function (vg) { " *
    "if (!vg || !(vg.signals || []).some(function (s) { return s.name === 'grid'; })) return vg; " *
    "function size(v) { return v && typeof v.signal === 'string' ? '(' + v.signal + ')' : typeof v === 'number' ? String(v) : null; } " *
    "(function walk(group, w, h, fields) { " *
    "(group.signals || []).forEach(function (s) { if (s.name === 'grid_tuple_fields' && Array.isArray(s.value)) fields = s.value; }); " *
    "(group.marks || []).forEach(function (m) { " *
    "if (m.type === 'group') { var u = (m.encode && m.encode.update) || {}; walk(m, size(u.width), size(u.height), fields); return; } " *
    "if (m.clip !== true || !fields || !fields.length) return; " *
    "if ([].concat(m.style || []).indexOf('aov-own-clip') !== -1) return; " *
    "var channels = fields.map(function (f) { return f.channel; }); " *
    "var x = channels.indexOf('x') !== -1, y = channels.indexOf('y') !== -1; " *
    "var zoomed = fields.map(function (f) { return 'isValid(grid[' + JSON.stringify(f.field) + '])'; }).join(' || '); " *
    "var cut = x && !y && w ? \"pathShape('M0,-100000H' + \" + w + \" + 'V100000H0Z')\" : " *
    "y && !x && h ? \"pathShape('M-100000,0H100000V' + \" + h + \" + 'H-100000Z')\" : 'true'; " *
    "m.clip = {signal: '(' + zoomed + ') ? ' + cut + ' : false'}; }); " *
    "})(vg, 'width', 'height', null); return vg; }"
# Whether the spec carries AoV's automatic pan/zoom selection (`add_auto_interactivity!`).
_uses_pan_zoom(_) = false
_uses_pan_zoom(v::AbstractVector) = any(_uses_pan_zoom, v)
function _uses_pan_zoom(d::AbstractDict)
    ps = get(d, "params", nothing)
    ps isa AbstractVector && any(p -> p isa AbstractDict && get(p, "name", nothing) == "grid" &&
        get(p, "bind", nothing) == "scales", ps) && return true
    any(k -> haskey(d, k) && _uses_pan_zoom(d[k]), ("layer", "spec", "hconcat", "vconcat", "concat"))
end
function _standalone_embed_opts(vl)
    passive, pan_zoom = _uses_style(vl, _AOV_PASSIVE), _uses_pan_zoom(vl)
    patch = passive && pan_zoom ? "function (vg) { return ($_PAN_ZOOM_CLIP_JS)(($_PASSIVE_PATCH_JS)(vg)); }" :
        passive ? _PASSIVE_PATCH_JS : pan_zoom ? _PAN_ZOOM_CLIP_JS : nothing
    isnothing(patch) ? "{actions: false}" : "{actions: false, patch: $patch}"
end

# The embed script of `to_html(spec)`. A parsed page has run the Vega script
# tags before this one, so `vegaEmbed` exists and it draws at once. Inserted
# into a page that has already loaded (an htmx swap, `innerHTML` plus script
# re-creation), it runs at once while those tags are still downloading, so it
# draws once its own preceding `<script src>` siblings have loaded, and
# reports in the console and in the plot's container when one fails to load.
_standalone_embed_js(id, json, opts="{actions: false}") = """
    (function (current) {
      var id = '$id';
      function draw() { vegaEmbed('#$id', $json, $opts).catch(console.error); }
      if (window.vegaEmbed) return draw();
      var pending = [], settled = false;
      for (var n = current && current.previousElementSibling; n && n.tagName === 'SCRIPT'; n = n.previousElementSibling)
        if (n.src) pending.push(n);
      function settle(problem) {
        if (settled) return;
        settled = true;
        if (!problem && window.vegaEmbed) return draw();
        var message = 'AlgebraOfVega could not draw plot ' + id + ': ' + (problem || 'vegaEmbed is not defined') +
          '. Load Vega in the page head with vega_head().';
        console.error(message);
        var el = document.getElementById(id);
        if (el) { el.setAttribute('role', 'alert'); el.textContent = message; }
      }
      var left = pending.length;
      if (!left) return settle();
      pending.forEach(function (script) {
        script.addEventListener('load', function () { if (!--left) settle(); });
        script.addEventListener('error', function () { settle(script.src + ' did not load'); });
      });
    })(document.currentScript);"""

# Minimal HTML escaping for interpolated page metadata (titles). Fragment
# bodies are trusted HTMX nodes, rendered by HTMX itself.
_html_escape(s::AbstractString) =
    replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

"""
    to_html(node::HTMX.Node; texts=plot_texts(), title=texts.untitled, head_extra="", source, base, runtime) -> String

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

`texts` (a [`PlotTexts`](@ref)) sets the page's `<html lang>` and the title
used when `title` is not given; pass the same value as the node's own
`texts=` (`plot_texts(:de)` for a German page).
"""
function to_html(node::HTMX.Node; texts::PlotTexts=_EN_PLOT_TEXTS,
        title::AbstractString=texts.untitled, head_extra::AbstractString="",
        source::Symbol=:cdn, base::AbstractString="/vendor", runtime::Symbol=:inline)
    head_io = IOBuffer()
    for n in vega_head(; source, base, runtime)
        show(head_io, MIME"text/html"(), n)
    end
    head_html = String(take!(head_io)) * head_extra
    body_html = sprint(show, MIME"text/html"(), node)
    _standalone_page(head_html, body_html; title, lang=texts.lang)
end

function _standalone_page(head_html::AbstractString, body_html::AbstractString;
                          title::AbstractString, lang::AbstractString)
    """
    <!DOCTYPE html>
    <html lang="$(_html_escape(lang))">
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
