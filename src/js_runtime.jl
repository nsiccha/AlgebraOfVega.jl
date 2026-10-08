# --- Output ---

"""
    to_json(spec; kwargs...) -> String

Convert a spec to a Vega-Lite JSON string. Non-finite floats (`NaN`, `±Inf`) are
written as `null`, which Vega-Lite renders as a gap; `kwargs` pass through to `JSON.json`.
"""
to_json(x; kwargs...) = _vl_json(to_vegalite(x); kwargs...)

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

Absolute path of the directory holding AoV's browser assets: the vendored
Vega/Vega-Lite/Vega-Embed builds (the exact-pinned trio `vega_head()` serves
from CDN by default) plus AoV's own runtime (`aov-runtime.js`) and stylesheet
(`aov.css`). Serve this directory from your app (e.g. mount it at `/vendor`
with a static route) and pass `vega_head(; source=:vendor, base="/vendor")` to
render plots with no CDN dependency — plus `runtime=:linked` to load AoV's
runtime and stylesheet from it too, instead of inlining them in every page.
"""
vega_vendor_dir() = normpath(joinpath(pkgdir(AlgebraOfVega), "vendor"))

# path => (mtime, bytes, version). Re-read when the file changes on disk, so
# an edited runtime is picked up without a restart; the version is a content
# hash, so a URL carrying it changes exactly when the bytes do.
const _VENDOR_CACHE = Dict{String,Tuple{Float64,String,String}}()
const _VENDOR_CACHE_LOCK = ReentrantLock()

function _vendor_asset(file)
    path = joinpath(vega_vendor_dir(), file)
    mt = mtime(path)
    lock(_VENDOR_CACHE_LOCK) do
        hit = get(_VENDOR_CACHE, path, nothing)
        !isnothing(hit) && hit[1] == mt && return hit
        bytes = read(path, String)
        _VENDOR_CACHE[path] = (mt, bytes, bytes2hex(sha256(bytes))[1:16])
    end
end

_vega_vendor_bytes(file) = _vendor_asset(file)[2]

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
`base`; `:inline` inlines the vendored bytes for fully self-contained pages.
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
            return [h.script(Raw(_vega_vendor_bytes(f)), data_aov_vendor=f) for f in _VEGA_VENDOR_FILES]
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
    [h.style(Raw(_vega_vendor_bytes(_AOV_STYLE_FILE))), vega_runtime()]
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

Return a vector of `h.script`/`h.style`/`h.link` nodes to include in `htmx(; extra_head=vega_head())`.

`source` selects where the Vega/Vega-Lite/Vega-Embed scripts come from:
`:cdn` (default) emits exact-pinned CDN tags with subresource integrity;
`:vendor` emits same-origin `<base>/vega.min.js?v=<content hash>` tags —
serve `vega_vendor_dir()` at `base` from your app; `:inline` inlines the
vendored bytes. Version overrides apply only to `:cdn`.

`runtime` selects how AoV's own runtime and stylesheet (~96 KB) reach the
page. `:inline` (default) inlines them. `:linked` — which needs
`source=:vendor` — references `<base>/aov-runtime.js` and `<base>/aov.css`
from the same mount instead, so the browser caches them rather than
receiving them in every full page. Every `:vendor` URL carries a `?v=`
content hash that changes exactly when the file's bytes do, so the mount may
serve them with a far-future `immutable` cache lifetime. The page settings
below (`zoom`, `max_width`, `actions`, `theme`) stay an inline per-page
script either way.

`zoom` uniformly scales all plots (chart area, fonts, axes, legend). Responsive plots
are sized to `containerWidth / zoom` so they don't overflow their container.

`max_width` caps plot width at `max_width` px: a plot in a wider container is
sized as if the container were `max_width` px (layered/faceted specs), or fills
at most `max_width` px of its container (single-view specs). A per-plot
`config(max_width=...)` overrides this page-level value for that plot.

`theme` selects how plots follow the page's light/dark choice. `:host` (the
default) draws axes, legends, facet headers, titles and unencoded text in the
CSS `color` each plot element inherits, on a transparent background, and
re-renders the plots when the page's colour scheme changes (a
`prefers-color-scheme` change, or a `class` / `data-theme` / `style` change on
`<html>` or `<body>`). Mark colours (palettes, `visual(...; color=...)`) are
unchanged, and a spec's own `config(config=Dict(...))` values still win. PNG/SVG
downloads of such a plot are painted on the page background behind it. `:none`
keeps Vega's own defaults (white background, black text). A per-plot
`config(theme=...)` overrides this page-level value for that plot.
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
        !isnothing(zoom) && push!(nodes, h.style(Raw(".vega-embed { zoom: $zoom; }")))
        push!(nodes, h.script(Raw("window.AoV = Object.assign(window.AoV || {}, $(_vl_json(settings)));")))
    end
    nodes
end

"""
    vega_controls(; zoom=true, actions=true)

Return an `h.div` node with client-side controls for Vega plots:
- **Zoom ±**: adjust CSS zoom on all `.vega-embed` elements (like Bruno's sidebar controls)
- **Actions**: toggle visibility of Vega-Embed's action menu (⋯ button) on all plots

Drop this into a sidebar, header, or anywhere on the page:

    nav_sidebar(items)(vega_controls())
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
        push!(children, h.script(Raw("""
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
        """)))
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
    data_vals = _as_vec(get(get(vl, "data", Dict()), "values", nothing))
    isnothing(data_vals) && return 1
    vals = Set()
    for row in data_vals
        _push_row_value!(vals, row, col_field)
    end
    n = length(vals)
    n <= 0 && return 1
    cols = get(vl, "columns", nothing)
    cols isa Number && cols >= 1 && (n = min(n, round(Int, cols)))
    return n
end

_push_row_value!(args...) = nothing
function _push_row_value!(vals, row::Dict, col_field)
    haskey(row, col_field) && push!(vals, row[col_field])
end

"""
Count the number of facet columns for ENCODING-level facets.

Covers the unit-spec form (`encoding.column`, emitted for single-layer `col=`):
Vega-Lite sizes top-level `width` PER CELL there (measured: 2 columns render
275px at width 100 and 875px at width 400), so the responsive JS must divide
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
    col = _as_dict(get(enc, "column", nothing))
    isnothing(col) && return nothing
    col_field = get(col, "field", nothing)
    (isnothing(col_field) || !(col_field isa AbstractString)) && return nothing
    data_vals = _as_vec(get(get(vl, "data", Dict()), "values", nothing))
    isnothing(data_vals) && return nothing
    vals = Set()
    for row in data_vals
        _push_row_value!(vals, row, col_field)
    end
    n = length(vals)
    n <= 0 ? nothing : n
end

"""
    vega_runtime()

Return a `h.script` node with the AlgebraOfVega JS runtime, inlined. Its
source is the file `aov-runtime.js` in `vega_vendor_dir()`, which
`vega_head(source=:vendor, runtime=:linked)` references by URL instead.
Manages Vega views by ID and provides helpers for HTMX integration.

Client-side API:
- `AoV.views[id]` — access Vega views by element ID
- `AoV.embed(id, spec, opts)` — embed and register a view; calling it again for the
  same `id` (e.g. with a spec that has more layers) replaces the view
- `AoV.whenReady(id, fn)` — call `fn(view)` now, or once the view has been embedded
- `AoV.updateData(id, data)` — swap a view's data without re-creating it
- `AoV.appendData(id, data, name, maxRows)` — insert rows into a view's data,
  optionally keeping only the most recent `maxRows`
- `AoV.replaceData(id, data, key, name)` — replace the rows of the groups `data`
  carries (rows whose `key` field values match a row of `data`), keeping the
  other groups' rows
- `AoV.removeData(id, values, key, name)` — remove one explicitly named keyed
  group without replacement rows.
- `data` is a row array or the columnar `{n, columns}` form `update_data` /
  `append_data` / `replace_data` send; `AoV.embed`/`AoV.updateSpec` expand
  inline datasets in that form too (`AoV._rowsFromColumns`)
- `AoV.onSignal(id, signal, callback)` — listen to a Vega signal
- Signal→HTMX wiring is set up automatically by `to_node(; signals=...)`
- `AoV.refreshTheme()` — re-render host-themed plots whose inherited text colour
  changed (automatic on `prefers-color-scheme` and `<html>`/`<body>` class,
  `data-theme` or `style` changes; call it after other theme switches)
- `AoV.hostThemeConfig(el)` / `AoV.hostBackground(el)` — the Vega-Lite config a
  host-themed plot in `el` embeds with, and the background its image downloads use
- `AoV.dispose(id)` — tear a plot down: finalize its Vega view and drop all
  per-plot runtime state (DOM untouched)
- `AoV.disposeWithin(root)` — dispose every plot whose element is `root` or
  inside it (works on detached subtrees too)

A Vega view registers `window`/`document` listeners (`width: "container"`
resize, zoom/pan drags, the actions menu) that keep it — its data, scenegraph
and canvas — reachable until it is finalized, so the runtime finalizes it. A
plot whose element leaves the document is disposed automatically: one
`MutationObserver` sweeps the registry after DOM removals, once the removing
script yields. A node removed and re-inserted synchronously stays live, and a
same-id re-render already embedded into its new element is untouched; a plot
detached and re-attached later is not revived (re-run its embed). `dispose`
finalizes through vega-embed's own `finalize`, as does
every re-embed (`View.finalize` alone leaves the actions menu's `document`
listener, which keeps the replaced view alive). Only the latest embed of a plot
registers: one superseded by a newer embed or by `dispose` is finalized when it
resolves, and resize/fit re-embeds scheduled by a superseded embed are inert.

Plots whose first render has an empty dataset (the incremental-plot pattern)
hide legends bound to empty scale domains until the first data change: Vega
renders an empty legend as a zero-item group whose inverted bounds collapse
the whole canvas to 0x0. The first `appendData`/`updateData` re-embeds once
with the accumulated rows, restoring the legend bound to the real domain.

A coloured `lineribbon`/`ribbon` draws each colour group as its own layers
(tagged `_lr_group`; an empty first render has `_lr_proto` template layers
instead), so the groups paint in order. A data change whose rows bring a group
without layers re-embeds once with layers for every group of the rows; rows of
groups that already have layers are swapped into the live view.

`AoV.embed` sizes the plot element of a `width: "container"` spec to its
container itself, so single-view plots fill their container on any page —
without it vega-embed's `display: inline-block` shrink-wraps the element and
the view measures 0px wide wherever no page stylesheet widens it.
"""
vega_runtime() = h.script(Raw(_vega_vendor_bytes(_AOV_RUNTIME_FILE)))
