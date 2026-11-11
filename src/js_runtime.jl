# --- Output ---

"""
    to_json(spec; interactive=true, auto_remap=nothing, kwargs...) -> String

Convert a spec to a Vega-Lite JSON string. Non-finite floats (`NaN`, `±Inf`) are
written as `null`, which Vega-Lite renders as a gap. `interactive` and
`auto_remap` select the lowering exactly as in [`to_vegalite`](@ref); the other
`kwargs` pass through to `JSON.json`.
"""
to_json(x; interactive::Bool=true, auto_remap::Union{Nothing,NamedTuple}=nothing, kwargs...) =
    _vl_json(to_vegalite(x; interactive, auto_remap); kwargs...)

# Exact pins, not major-only: a CDN-side release inside the major line used to
# change rendering with zero repo diff. These are the latest in each major
# line as of 2026-09-28 — i.e. what the floating tags already served — so the
# freeze is behavior-preserving. The same builds are vendored under `vendor/`.
VEGA_VERSION = "5.33.1"
VEGALITE_VERSION = "5.23.0"
VEGA_EMBED_VERSION = "6.29.0"

# Subresource-integrity (sha384) hashes of the exact-pinned jsDelivr builds,
# byte-identical to `vendor/`. Recompute on every trio bump (vendor/README.md).
VEGA_SRI = "sha384-NMXhl2TbCXxcN7o4ROC56Funm78m4AylL8gMg/7Kn4YU+wrm23K9l7cY8lDRXQ9d"
VEGALITE_SRI = "sha384-D9LYH0esGjcxQJsBuxOuXtCDJGXRWW1+KhluzWPqi0rLJmiR/ygPChefaD+rFFDQ"
VEGA_EMBED_SRI = "sha384-M+Ax7e/WFJpxSOF09HzI+Sj4wg9ottVd/uxmV2ItGGh02fLH28t2FAOJx3TJBap5"

const _VEGA_VENDOR_FILES = ("vega.min.js", "vega-lite.min.js", "vega-embed.min.js")

# AoV's own browser assets, next to the trio: the `window.AoV.*` runtime and
# the head stylesheet. These files are the single source of both forms — the
# inline `<script>`/`<style>` (`runtime=:inline`) and the same-origin URLs
# (`runtime=:linked`).
const _AOV_RUNTIME_FILE = "aov-runtime.js"
const _AOV_STYLE_FILE = "aov.css"

"""
    vega_vendor_dir() -> String

Return the directory containing the vendored Vega, Vega-Lite, and Vega-Embed
libraries together with AoV's browser runtime and stylesheet. Serve the whole
directory from `base` when using `vega_head(source=:vendor)`.
"""
vega_vendor_dir() = normpath(joinpath(pkgdir(AlgebraOfVega), "vendor"))

# path => (mtime, bytes, version, inline). Re-read when the file changes on
# disk, so an edited runtime is picked up without a restart; the version is a
# content hash, so a URL carrying it changes exactly when the bytes do; `inline`
# is the text an inline element carries (`_inline_text`), computed once per read.
const _VENDOR_CACHE = Dict{String,Tuple{Float64,String,String,String}}()
const _VENDOR_CACHE_LOCK = ReentrantLock()

function _vendor_asset(file)
    path = joinpath(vega_vendor_dir(), file)
    mt = mtime(path)
    lock(_VENDOR_CACHE_LOCK) do
        hit = get(_VENDOR_CACHE, path, nothing)
        !isnothing(hit) && hit[1] == mt && return hit
        bytes = read(path, String)
        _VENDOR_CACHE[path] = (mt, bytes, bytes2hex(sha256(bytes))[1:16], _inline_text(bytes))
    end
end

# A vendored file as an inline `<script>`/`<style>` body. AoV's own runtime and
# stylesheet never spell a closing tag, so theirs are the file's bytes; the
# pinned vega-embed build spells `</head>`, `</body>`, `</html>` in template
# literals, which this rewrites (the vendored-trio testitem pins those sites).
_vega_vendor_inline(file) = _vendor_asset(file)[4]

# The same-origin URL of a vendored file, versioned by its content hash so an
# app can serve `vega_vendor_dir()` with a far-future (`immutable`) cache
# lifetime: the bytes behind one URL never change.
_vendor_url(base, file) = "$(rstrip(base, '/'))/$file?v=$(_vendor_asset(file)[3])"

_cdn_script(url, sri) =
    isnothing(sri) ? h.script(src=url) : h.script(src=url, integrity=sri, crossorigin="anonymous")

"""
    _vega_script_nodes(; source, base, vega_version, vegalite_version, vega_embed_version)

The three Vega/Vega-Lite/Vega-Embed `<script>` nodes shared by `vega_head()`
and `to_html`: `:cdn` (default) emits exact-pinned CDN tags with
subresource integrity; `:vendor` emits same-origin, content-versioned
`<base>/<file>?v=<hash>` tags for an app serving `vega_vendor_dir()` at
`base`; `:inline` inlines the vendored bytes for fully self-contained pages,
closing tags written as `<\\/` (`_inline_text`).
Version overrides apply only to `:cdn` — the vendored bytes are fixed at the
pinned trio. Vendored tags (`:vendor` and `:inline`) carry `data-aov-vendor`,
which tells `AoV.downloadPlotHtml` to carry their bytes into the saved file.
"""
function _vega_script_nodes(; source::Symbol=:cdn, base::AbstractString="/vendor",
        vega_version=VEGA_VERSION, vegalite_version=VEGALITE_VERSION,
        vega_embed_version=VEGA_EMBED_VERSION)
    if source === :cdn
        return [
            _cdn_script("https://cdn.jsdelivr.net/npm/vega@$vega_version",
                vega_version == VEGA_VERSION ? VEGA_SRI : nothing),
            _cdn_script("https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version",
                vegalite_version == VEGALITE_VERSION ? VEGALITE_SRI : nothing),
            _cdn_script("https://cdn.jsdelivr.net/npm/vega-embed@$vega_embed_version",
                vega_embed_version == VEGA_EMBED_VERSION ? VEGA_EMBED_SRI : nothing),
        ]
    elseif source === :vendor || source === :inline
        if vega_version != VEGA_VERSION || vegalite_version != VEGALITE_VERSION ||
                vega_embed_version != VEGA_EMBED_VERSION
            throw(ArgumentError("source=$source serves AoV's vendored trio " *
                "(vega@$VEGA_VERSION, vega-lite@$VEGALITE_VERSION, vega-embed@$VEGA_EMBED_VERSION); " *
                "version overrides apply only to source=:cdn"))
        end
        if source === :vendor
            return [h.script(src=_vendor_url(base, f), data_aov_vendor=f) for f in _VEGA_VENDOR_FILES]
        else
            return [h.script(Raw(_vega_vendor_inline(f)), data_aov_vendor=f) for f in _VEGA_VENDOR_FILES]
        end
    else
        throw(ArgumentError("source must be :cdn, :vendor, or :inline, got $source"))
    end
end

# AoV's own stylesheet + runtime nodes. AoV has no CDN of its own, so they
# are inlined by default; `runtime=:linked` references the same files from the
# vendor mount instead, so a page carries a few hundred bytes of tags rather
# than ~96 KB that the browser can cache. `source` is validated by
# `_vega_script_nodes`.
_aov_asset_nodes(::Val{:inline}, source::Symbol, base::AbstractString) =
    [h.style(Raw(_vega_vendor_inline(_AOV_STYLE_FILE))), vega_runtime()]
function _aov_asset_nodes(::Val{:linked}, source::Symbol, base::AbstractString)
    source === :vendor || throw(ArgumentError("runtime=:linked loads AoV's runtime from the " *
        "vendor mount, so it needs source=:vendor (serve vega_vendor_dir() at base); got source=:$source"))
    [h.link(rel="stylesheet", href=_vendor_url(base, _AOV_STYLE_FILE), data_aov_vendor=_AOV_STYLE_FILE),
        h.script(src=_vendor_url(base, _AOV_RUNTIME_FILE), data_aov_vendor=_AOV_RUNTIME_FILE)]
end
_aov_asset_nodes(::Val{R}, source::Symbol, base::AbstractString) where {R} =
    throw(ArgumentError("runtime must be :inline or :linked, got $(repr(R))"))

const _THEMES = (:host, :none)
_check_theme(theme::Symbol) = theme in _THEMES ||
    throw(ArgumentError("theme must be one of $(join(repr.(_THEMES), ", ")), got $(repr(theme))"))
_check_theme(theme) = throw(ArgumentError("theme must be a Symbol (:host or :none), got $(repr(theme))"))

"""
    vega_head(; vega_version, vegalite_version, vega_embed_version, source, base, runtime, zoom, max_width, actions, theme)

Return HTML head nodes for the plotting libraries and AoV browser runtime.
Include them once in a host page. `source=:cdn` uses pinned URLs and integrity
hashes; `:vendor` loads from `base`; `:inline` embeds the vendored bytes.
`runtime=:linked` requires `source=:vendor` and links the runtime and stylesheet.

The default `theme=:host` follows the plot element's inherited foreground and
font. `theme=:none` keeps Vega's own appearance. `zoom`, `max_width`, and
`actions` set page defaults. Author-specified mark palettes remain unchanged
when the host theme switches.

CSS properties on the plot or an ancestor can set the host appearance:

| Property | Meaning |
| --- | --- |
| `--aov-font` | Font-family list. |
| `--aov-category` | Default categorical colors, separated by commas. |
| `--aov-axis-label-color`, `--aov-axis-title-color` | Axis text colors. |
| `--aov-grid-color`, `--aov-tick-color`, `--aov-domain-color` | Grid, ticks, and axis lines; `none` removes them. |
| `--aov-view-color` | Plot frame color; `none` removes it. |
| `--aov-legend-label-color`, `--aov-legend-title-color` | Legend text colors. |
| `--aov-header-label-color`, `--aov-header-title-color` | Facet header colors. |

These defaults leave explicit mark colors and scale palettes intact. Class,
`data-theme`, or style changes on the document root or body refresh the plots.
After other stylesheet changes, call `AoV.refreshTheme()` in the browser.
"""
function vega_head(;
    vega_version=VEGA_VERSION,
    vegalite_version=VEGALITE_VERSION,
    vega_embed_version=VEGA_EMBED_VERSION,
    source::Symbol=:cdn,
    base::AbstractString="/vendor",
    runtime::Symbol=:inline,
    zoom=nothing,
    max_width=nothing,
    actions=nothing,
    theme=:host,
)
    _check_theme(theme)
    nodes = [
        _vega_script_nodes(; source, base, vega_version, vegalite_version, vega_embed_version)...,
        _aov_asset_nodes(Val(runtime), source, base)...,
    ]
    settings = Dict{String,Any}()
    !isnothing(zoom) && (settings["zoom"] = zoom)
    !isnothing(max_width) && (settings["maxWidth"] = max_width)
    !isnothing(actions) && (settings["defaultActions"] = actions)
    theme === :host || (settings["theme"] = string(theme))
    if !isempty(settings)
        !isnothing(zoom) && push!(nodes, _inline_style(".vega-embed { zoom: $zoom; }"))
        push!(nodes, _inline_script("window.AoV = Object.assign(window.AoV || {}, $(_vl_json(settings)));"))
    end
    nodes
end

"""
    vega_controls(; zoom=true, actions=true)

Return optional controls for CSS plot zoom and the Vega action menu.
These are page controls; plot selections and legend interactions belong to the
figure specification.
"""
function vega_controls(; zoom=true, actions=true)
    children = []
    if zoom
        push!(children, h.span(
            "Zoom ",
            h.a("−"; href="#", onclick="document.querySelectorAll('.vega-embed').forEach(e => e.style.zoom = (parseFloat(e.style.zoom||getComputedStyle(e).zoom||1) - 0.1).toFixed(1)); return false;"),
            " ",
            h.a("+"; href="#", onclick="document.querySelectorAll('.vega-embed').forEach(e => e.style.zoom = (parseFloat(e.style.zoom||getComputedStyle(e).zoom||1) + 0.1).toFixed(1)); return false;"),
        ))
    end
    if actions
        push!(children, h.label(; class="u-pointer")(
            h.input(; type="checkbox", class="aov-actions-toggle aov-cb-mid",
                onchange="""
                var show = this.checked;
                var sheet = document.getElementById('aov-actions-hide');
                if (show) { if (sheet) sheet.disabled = true; }
                else { if (sheet) sheet.disabled = false; }
                window.AoV = window.AoV || {};
                window.AoV.defaultActions = show;
                """),
            "Actions",
        ))
        # Use a stylesheet to hide .vega-actions — works even for elements created later.
        # When defaultActions is already true (from vega_head), start with checkbox checked and sheet disabled.
        push!(children, _inline_script("""
            (function() {
                if (!document.getElementById('aov-actions-hide')) {
                    var s = document.createElement('style');
                    s.id = 'aov-actions-hide';
                    s.textContent = '.vega-actions { display: none !important; }';
                    document.head.appendChild(s);
                }
                var show = window.AoV && window.AoV.defaultActions;
                var sheet = document.getElementById('aov-actions-hide');
                if (show && sheet) sheet.disabled = true;
                var cb = document.querySelector('.aov-actions-toggle');
                if (cb) cb.checked = !!show;
            })();
        """))
    end
    h.div(; class="aov-context-bar")(children...)
end

"""
Count the number of facet columns in a VL spec by inspecting the data.

Covers both operator forms: the 2-D grid (`facet: {column}`) and the single-field
wrap (`facet: {field}`, emitted for `layout=`). A wrap facet with a sibling
`columns: N` lays out at most `N` panels per row regardless of cardinality, so the
count is clamped by it — otherwise the responsive-resize hint sizes the view for
more columns than Vega actually renders.
"""
function _count_facet_cols(vl::Dict)
    facet = get(vl, "facet", nothing)
    isnothing(facet) && return 1
    col_field = nothing
    if haskey(facet, "column")
        col_field = get(facet["column"], "field", nothing)
    elseif haskey(facet, "field")
        col_field = facet["field"]
    end
    isnothing(col_field) && return 1
    n = _facet_levels(vl, col_field)
    n <= 0 && return 1
    cols = _wrap_columns(vl, facet)
    isnothing(cols) || (n = min(n, cols))
    return n
end

"""
Count the number of facet columns for ENCODING-level facets.

Covers the unit-spec forms: `encoding.column` (single-layer `col=`) and the wrap
channel `encoding.facet` (single-layer `layout=`, clamped by its `columns` like the
operator wrap). Vega-Lite sizes top-level `width` PER CELL there (measured: 2 columns
render 275px at width 100 and 875px at width 400), so the responsive JS must divide
by this count just like for operator facets. Returns `nothing` for every
other shape: operator facets (counted by `_count_facet_cols`), row-only
encoding facets (full-width cells), non-faceted specs — and layered specs,
whose shared top-level `encoding.column` Vega-Lite silently ignores
(measured: 2-level column on a 2-layer spec renders one 100px cell).
"""
function _count_encoding_facet_cols(vl::Dict)
    (haskey(vl, "facet") || haskey(vl, "spec") || haskey(vl, "layer")) && return nothing
    enc = _as_dict(get(vl, "encoding", nothing))
    isnothing(enc) && return nothing
    wrap = _wrap_facet(vl)
    col = isnothing(wrap) ? _as_dict(get(enc, "column", nothing)) : wrap
    isnothing(col) && return nothing
    col_field = get(col, "field", nothing)
    (isnothing(col_field) || !(col_field isa AbstractString)) && return nothing
    n = _facet_levels(vl, col_field)
    n <= 0 && return nothing
    cols = isnothing(wrap) ? nothing : _wrap_columns(vl, wrap)
    isnothing(cols) ? n : min(n, cols)
end

"""
    vega_runtime()

Return AoV's browser runtime as an inline script node. Prefer `vega_head()`
to install the complete library, stylesheet, and runtime set.
"""
vega_runtime() = h.script(Raw(_vega_vendor_inline(_AOV_RUNTIME_FILE)))
