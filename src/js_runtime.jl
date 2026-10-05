# --- Output ---

"""
    to_json(spec; kwargs...) -> String

Convert a spec to a Vega-Lite JSON string. Passes `kwargs` to `JSON.json`.
"""
to_json(x; kwargs...) = JSON.json(to_vegalite(x); kwargs...)

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

"""
    vega_vendor_dir() -> String

Absolute path of the directory holding AoV's vendored Vega/Vega-Lite/Vega-Embed
builds — the exact-pinned trio `vega_head()` serves from CDN by default.
Serve this directory from your app (e.g. mount it at `/vendor` with a static
route) and pass `vega_head(; source=:vendor, base="/vendor")` to render plots
with no CDN dependency.
"""
vega_vendor_dir() = normpath(joinpath(pkgdir(AlgebraOfVega), "vendor"))

_vega_vendor_bytes(file) = read(joinpath(vega_vendor_dir(), file), String)

_cdn_script(url, sri) =
    isnothing(sri) ? h.script(src=url) : h.script(src=url, integrity=sri, crossorigin="anonymous")

"""
    _vega_script_nodes(; source, base, vega_version, vegalite_version, vega_embed_version)

The three Vega/Vega-Lite/Vega-Embed `<script>` nodes shared by `vega_head()`
and `to_html`: `:cdn` (default) emits exact-pinned CDN tags with
subresource integrity; `:vendor` emits same-origin `<base>/<file>` tags for an
app serving `vega_vendor_dir()` at `base`; `:inline` inlines the vendored
bytes for fully self-contained pages. Version overrides apply only to `:cdn` —
the vendored bytes are fixed at the pinned trio.
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
            root = rstrip(base, '/')
            return [h.script(src="$root/$f") for f in _VEGA_VENDOR_FILES]
        else
            return [h.script(Raw(_vega_vendor_bytes(f))) for f in _VEGA_VENDOR_FILES]
        end
    else
        throw(ArgumentError("source must be :cdn, :vendor, or :inline, got $source"))
    end
end

"""
    vega_head(; vega_version, vegalite_version, vega_embed_version, source, base, zoom, max_width, actions)

Return a vector of `h.script`/`h.style` nodes to include in `htmx(; extra_head=vega_head())`.

`source` selects where the Vega/Vega-Lite/Vega-Embed scripts come from:
`:cdn` (default) emits exact-pinned CDN tags with subresource integrity;
`:vendor` emits same-origin `<base>/vega.min.js` tags — serve
`vega_vendor_dir()` at `base` from your app; `:inline` inlines the vendored
bytes. Version overrides apply only to `:cdn`.

`zoom` uniformly scales all plots (chart area, fonts, axes, legend). Responsive plots
are sized to `containerWidth / zoom` so they don't overflow their container.

`max_width` caps plot width at `max_width` px: a plot in a wider container is
sized as if the container were `max_width` px (layered/faceted specs), or fills
at most `max_width` px of its container (single-view specs). A per-plot
`config(max_width=...)` overrides this page-level value for that plot.
"""
function vega_head(;
    vega_version=VEGA_VERSION,
    vegalite_version=VEGALITE_VERSION,
    vega_embed_version=VEGA_EMBED_VERSION,
    source::Symbol=:cdn,
    base::AbstractString="/vendor",
    zoom=nothing,
    max_width=nothing,
    actions=nothing,
)
    nodes = [
        _vega_script_nodes(; source, base, vega_version, vegalite_version, vega_embed_version)...,
        # Fix vega-embed actions SVG sizing when CSS frameworks (Pico) override defaults
        h.style(Raw("""
            details[title] > summary > svg { width: 14px !important; height: 14px !important; }
            .chart-wrapper { height: auto !important; }

            /* AoV-specific role classes. Generic concepts (gallery
               grid, sortable table, status badges, …) live upstream in
               HTMXObjects; this block only carries roles peculiar to
               the AoV gallery shell. */
            .aov-plot-area { width: 100%; min-width: 0; max-width: 100%; overflow-x: auto; }
            .aov-grid-page { width: 100vw; padding: 0.5rem; font-size: 0.5em; }
            /* Dense compact grid (16 cols) and gallery static grid (4 cols).
               Both compose with upstream `.htmxo-grid`, supplying only the
               column-count + gap variables; child styling stays scoped here. */
            .aov-grid-dense  { --htmxo-grid-cols: 16; --htmxo-grid-gap: 0.25rem; }
            .aov-grid-static { --htmxo-grid-cols: 4;  --htmxo-grid-gap: 0.5rem; }
            /* Compact gallery cells: <figure> in a grid container; <figcaption> is the title. */
            .aov-grid-dense > figure, .aov-grid-static > figure {
                margin: 0; border: 1px solid var(--pico-muted-border-color);
                border-radius: 0.2rem; padding: 0.2rem;
                overflow: hidden; min-width: 0;
            }
            .aov-grid-dense > figure > figcaption, .aov-grid-static > figure > figcaption {
                font-weight: bold; white-space: nowrap; overflow: hidden;
                text-overflow: ellipsis; margin-bottom: 0.1rem;
            }
            /* Static gallery cards: <article><header><a/><button/></header><img/></article>. */
            .aov-grid-static > article {
                margin: 0; padding: 0.5rem; min-width: 0; overflow: hidden;
            }
            .aov-grid-static > article > header {
                padding: 0 0 0.25rem; margin: 0;
                display: flex; align-items: center; flex-wrap: wrap;
            }
            .aov-grid-static > article > header > a {
                font-size: 0.9em; font-weight: bold; text-decoration: none;
            }
            .aov-grid-dense > figure img, .aov-grid-static > figure img,
            .aov-grid-static > article img { width: 100%; }
            .aov-cb-mid { vertical-align: middle; margin-right: 0.3em; }
            .aov-context-bar { padding: 0.5rem 0; font-size: 0.75em; opacity: 0.6; display: flex; gap: 1em; align-items: center; }
            /* Plot nav: a strip of role=button anchors. The first one
               ("← Gallery") pushes everything after it to the right. */
            .aov-plot-nav { display: flex; flex-wrap: wrap; gap: 0.25rem; margin-bottom: 1rem; align-items: center; }
            .aov-plot-nav > a:first-child { margin-right: auto; }
            .aov-plot-nav > a { margin: 0.1rem; font-size: 0.85em; padding: 0.3rem 0.6rem; }

            /* Responsive demo cells. The demo's whole point is to
               showcase widths, so the cell width is the cell's *role*
               and lives on a `data-cell` attribute. */
            .aov-demo-page > [data-cell="half"]          { width: 50%; }
            .aov-demo-page > [data-cell="three-fifths"]  { width: 60%; }
            .aov-demo-page > [data-cell="row"]           { display: flex; gap: 1rem; }
            .aov-demo-page > [data-cell="row"] > div     { flex: 1; }

            /* Semantic roles. Bare <pre> and <small> rely on Pico defaults. */
            .aov-code-scroll { max-height: 25rem; overflow-y: auto; }
            .aov-static-section { margin-bottom: 2rem; }
            .aov-static-section h3 { margin-bottom: 0.5rem; }
            .aov-detail h4, .aov-demo-page h4 { margin-top: 1.5rem; }
            .aov-detail .aov-json-details { margin-top: 1rem; }
            .aov-card-with-specs > details { margin-top: 0.5rem; }
            .aov-card-with-specs > details + details { margin-top: 0.25rem; }
            .aov-brush-stats { margin-top: 1rem; }

            /* Captioned-plot data preview: <details data-mode="pretty|raw">
               wraps a role=group toggle and two [data-view] body divs. The
               mode attribute drives visibility; aria-pressed drives the
               button state. */
            .aov-data-preview[data-mode="pretty"] > [data-view="raw"] { display: none; }
            .aov-data-preview[data-mode="raw"]    > [data-view="pretty"] { display: none; }
        """)),
        vega_runtime(),
    ]
    settings = Dict{String,Any}()
    !isnothing(zoom) && (settings["zoom"] = zoom)
    !isnothing(max_width) && (settings["maxWidth"] = max_width)
    !isnothing(actions) && (settings["defaultActions"] = actions)
    if !isempty(settings)
        !isnothing(zoom) && push!(nodes, h.style(Raw(".vega-embed { zoom: $zoom; }")))
        push!(nodes, h.script(Raw("window.AoV = Object.assign(window.AoV || {}, $(JSON.json(settings)));")))
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

Return a `h.script` node with the AlgebraOfVega JS runtime.
Manages Vega views by ID and provides helpers for HTMX integration.

Client-side API:
- `AoV.views[id]` — access Vega views by element ID
- `AoV.embed(id, spec, opts)` — embed and register a view; calling it again for the
  same `id` (e.g. with a spec that has more layers) replaces the view
- `AoV.whenReady(id, fn)` — call `fn(view)` now, or once the view has been embedded
- `AoV.updateData(id, data)` — swap a view's data without re-creating it
- `AoV.appendData(id, data, name, maxRows)` — insert rows into a view's data,
  optionally keeping only the most recent `maxRows`
- `AoV.onSignal(id, signal, callback)` — listen to a Vega signal
- Signal→HTMX wiring is set up automatically by `to_node(; signals=...)`
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

`AoV.embed` sizes the plot element of a `width: "container"` spec to its
container itself, so single-view plots fill their container on any page —
without it vega-embed's `display: inline-block` shrink-wraps the element and
the view measures 0px wide wherever no page stylesheet widens it.
"""
function vega_runtime()
    h.script(Raw(raw"""
    window.AoV = window.AoV || {
        views: {},
        _pending: {},
        _signals: {},
        _liveRows: {},
        _specRows: {},
        _origSpecs: {},
        _droppedLegends: {},
        _embedOpts: {},
        _results: {},
        _els: {},
        _embedTok: {},
        _gens: {},
        _genSeq: 0,

        // Every map keyed by plot id; dispose() clears each. A new per-plot
        // map belongs in this list.
        _perPlotState: ['views', '_results', '_els', '_embedTok', '_gens', '_pending',
            '_signals', '_liveRows', '_specRows', '_origSpecs', '_droppedLegends',
            '_embedOpts', '_observers', '_computedWidths', '_corrections', '_correctedRegime'],

        _applyResponsiveWidth: function(id, spec) {
            var el = document.getElementById(id);
            if (!el) return spec;
            var containerWidth = el.parentElement ? el.parentElement.clientWidth : null;
            if (!containerWidth || containerWidth < 50) return spec;
            var zoom = (window.AoV && window.AoV.zoom) ? window.AoV.zoom : 1;
            containerWidth = Math.floor(containerWidth / zoom);
            var maxWidth = (spec._aov && spec._aov.maxWidth) || (window.AoV && window.AoV.maxWidth) || Infinity;
            containerWidth = Math.min(containerWidth, maxWidth);
            var padding = 30; // approximate VL padding
            var minCell = 100; // readable-minimum panel width; narrower viewports scroll in-frame (see .aov-plot-area)

            // Classify the shape. Only _aov-marked composite specs are JS-sized
            // (single views use VL-native width:"container").
            var kind = null, nCols = 0, computed = 0;
            if (spec._aov && spec._aov.nFacetCols && spec.hconcat) {
                // hconcat of per-column facet views (per-column Y scales):
                // per-child width from container / nCols, written into every
                // child's inner spec.
                kind = 'hconcat'; nCols = spec._aov.nFacetCols;
                computed = Math.max(minCell, Math.floor((containerWidth - padding) / nCols) - padding);
            } else if (spec._aov && spec._aov.nFacetCols && spec.spec) {
                // Operator-faceted specs: per-cell width from container / nCols
                kind = 'facet'; nCols = spec._aov.nFacetCols;
                computed = Math.max(minCell, Math.floor((containerWidth - padding) / nCols) - padding);
            } else if (spec._aov && spec._aov.nFacetCols && !spec.spec) {
                // Encoding-faceted unit specs: VL sizes top-level width PER
                // CELL here, so divide the same way but write it top-level.
                kind = 'encfacet'; nCols = spec._aov.nFacetCols;
                computed = Math.max(minCell, Math.floor((containerWidth - padding) / nCols) - padding);
            } else if (spec._aov && !spec._aov.nFacetCols) {
                // Row-only faceted (width lives on the inner spec) or layered
                // specs: one panel spans the container.
                computed = Math.max(minCell, containerWidth - padding);
                kind = spec.spec ? 'inner' : 'top';
            } else {
                return spec;
            }
            var colField = spec.facet && spec.facet.column && spec.facet.column.field;
            var rowField = spec.facet && spec.facet.row && spec.facet.row.field;
            var regime = [containerWidth, kind, nCols, colField, rowField].join('|');

            // A post-embed correction (_fitCorrection) overrides the computed
            // width while its regime still matches; a resize/remap starts a
            // fresh regime and recomputes from the container.
            var self = window.AoV || {};
            var corr = (self._corrections || {})[id];
            var width = (corr && corr.regime === regime) ? corr.width : computed;

            if (kind === 'hconcat') {
                spec.hconcat.forEach(function(child) {
                    if (child && child.spec) child.spec = Object.assign({}, child.spec, {width: width});
                });
            } else if (kind === 'facet' || kind === 'inner') {
                spec.spec = Object.assign({}, spec.spec, {width: width});
            } else {
                // 'top' and 'encfacet' both write top-level width: total span
                // for plain/layered specs, per-cell width for encoding facets.
                spec = Object.assign({}, spec, {width: width});
            }
            self._computedWidths = self._computedWidths || {};
            self._computedWidths[id] = {kind: kind, width: width, nCols: nCols, budget: containerWidth, regime: regime};
            return spec;
        },

        // Post-embed correction for JS-sized specs. The computed cell width
        // reserves only approximate padding, while real facet chrome (row
        // headers, per-panel axes, spacing, legends) varies per spec — so the
        // first paint can overshoot the budget it was sized for. Measure the
        // rendered canvas; if it overshoots, shrink the cells by the excess
        // and re-embed once via reembed(). Bounded: at most one correction
        // per regime (budget/kind/columns/fields); a resize/remap opens a new
        // regime. When cells already sit at the readable minimum there is
        // nothing to shrink — the frame's in-frame scroll takes over.
        _fitCorrection: function(id, reembed) {
            var self = window.AoV || {};
            var info = (self._computedWidths || {})[id];
            if (!info) return;
            if (self._correctedRegime && self._correctedRegime[id] === info.regime) return;
            var el = document.getElementById(id);
            var canvas = el && el.querySelector('canvas.marks');
            if (!canvas) return;
            // Layout px (pre-zoom): CSS zoom scales the canvas and the budget's
            // container alike, so the factor cancels in the difference.
            var over = canvas.clientWidth - info.budget;
            if (over <= 2) return;
            var minCell = 100;
            var perCell = (info.kind === 'facet' || info.kind === 'encfacet' || info.kind === 'hconcat') && info.nCols > 0;
            var shrink = perCell ? Math.ceil(over / info.nCols) : Math.ceil(over);
            var newWidth = info.width - shrink;
            if (newWidth >= info.width || newWidth < minCell) return;
            self._correctedRegime = self._correctedRegime || {};
            self._correctedRegime[id] = info.regime;
            self._corrections = self._corrections || {};
            self._corrections[id] = {regime: info.regime, width: newWidth};
            reembed();
        },

        // ggplot-style "broadcast across all facet panels" pass.
        // AoV merges layered data into a single spec.data.values with a __src
        // discriminator column when outer faceting is needed. When a facet field
        // is absent from some rows (e.g. dose VLines that have no health column),
        // Vega-Lite renders them in an "undefined" facet panel.
        // This pass replicates each missing-field row across the unique values
        // of that field. Layer-level __src filters still route rows correctly.
        // Idempotent: rows that already have the field are untouched.
        _broadcastCrossSource: function(spec) {
            if (!spec || typeof spec !== 'object') return spec;
            var inner = (spec.spec && typeof spec.spec === 'object') ? spec.spec : null;

            // Collect partition fields from facet config AND sublayer
            // row/column encodings. Deliberately NOT color: a missing color
            // value renders as one null group, never an "undefined" panel,
            // so replicating rows across color values only overpaints
            // identical geometry.
            var fields = [];
            var pushField = function(f) {
                if (f && f.field && fields.indexOf(f.field) === -1) fields.push(f.field);
            };
            if (spec.facet) { pushField(spec.facet.row); pushField(spec.facet.column); }
            if (spec.hconcat) {
                spec.hconcat.forEach(function(child) {
                    if (!child) return;
                    if (child.facet) { pushField(child.facet.row); pushField(child.facet.column); }
                    var cl = child.spec && child.spec.layer ? child.spec.layer : null;
                    if (cl) cl.forEach(function(l) {
                        if (l && l.encoding) { pushField(l.encoding.row); pushField(l.encoding.column); }
                    });
                });
            }
            var layers = inner && inner.layer ? inner.layer : (spec.layer || null);
            if (layers) {
                layers.forEach(function(l) {
                    if (l && l.encoding) { pushField(l.encoding.row); pushField(l.encoding.column); }
                });
            }
            if (!fields.length) return spec;

            // Find the data object whose values carry the merged rows
            var dataObj = null;
            if (spec.data && spec.data.values) dataObj = spec.data;
            else if (inner && inner.data && inner.data.values) dataObj = inner.data;
            if (!dataObj) return spec;
            var vals = dataObj.values;

            fields.forEach(function(field) {
                var uniques = [];
                var seen = {};
                for (var i = 0; i < vals.length; i++) {
                    var v = vals[i];
                    if (v && Object.prototype.hasOwnProperty.call(v, field)) {
                        var k = String(v[field]);
                        if (!seen[k]) { seen[k] = true; uniques.push(v[field]); }
                    }
                }
                if (!uniques.length) return;

                var newVals = [];
                for (var i = 0; i < vals.length; i++) {
                    var v = vals[i];
                    if (!v || Object.prototype.hasOwnProperty.call(v, field)) {
                        newVals.push(v);
                    } else {
                        for (var j = 0; j < uniques.length; j++) {
                            var nv = Object.assign({}, v);
                            nv[field] = uniques[j];
                            newVals.push(nv);
                        }
                    }
                }
                vals = newVals;
            });
            dataObj.values = vals;

            return spec;
        },

        embed: function(id, spec, opts) {
            return this._embed(id, spec, opts, false);
        },

        // A plot whose element leaves the document is disposed. One
        // MutationObserver (installed on the first embed) sweeps the registry
        // after any batch of DOM removals. Its callback runs at the next
        // microtask checkpoint, so a node removed and re-inserted synchronously
        // stays live; it compares element identity, so a same-id re-render
        // already embedded into its new element is untouched.
        _sweepDetached: function() {
            var self = this;
            Object.keys(self._els).forEach(function(id) {
                var el = self._els[id];
                if (el && !el.isConnected) self.dispose(id);
            });
        },
        _watchRemovals: function() {
            if (this._removalObserver || typeof MutationObserver === 'undefined' || !document.documentElement) return;
            var self = this;
            this._removalObserver = new MutationObserver(function(records) {
                for (var i = 0; i < records.length; i++) {
                    if (records[i].removedNodes.length) { self._sweepDetached(); return; }
                }
            });
            this._removalObserver.observe(document.documentElement, {childList: true, subtree: true});
        },

        // Refresh ONLY AoV-generated legend selections after channel remapping.
        // Units may have been cloned by ribbon reconstruction or facet/concat
        // lowering. Restore their recorded opacity/filter before electing one
        // owner per field; explicit user params and encodings survive unchanged.
        _refreshLegendSelections: function(spec) {
            var mode = spec._aov && spec._aov.legendInteraction;
            if (!mode) return;
            var units = [];
            function visit(node, data, encoding) {
                if (!node) return;
                data = node.data || data;
                encoding = Object.assign({}, encoding, node.encoding || {});
                var children = node.spec ? [node.spec] : [];
                ['layer', 'hconcat', 'vconcat', 'concat'].forEach(function(k) {
                    children = children.concat(node[k] || []);
                });
                if (children.length) children.forEach(function(c) { visit(c, data, encoding); });
                else if (node.mark) units.push({unit:node, data:data, encoding:encoding});
            }
            visit(spec, null, {});
            units.forEach(function(info) {
                var u = info.unit, meta = u._aovLegend;
                if (!meta) return;
                if (u.params) {
                    u.params = u.params.filter(function(p) { return meta.params.indexOf(p.name) === -1; });
                    if (!u.params.length) delete u.params;
                }
                if (meta.dimmed) {
                    if (meta.opacity === null) delete u.encoding.opacity;
                    else u.encoding.opacity = meta.opacity;
                }
                if (meta.domain && u.encoding.color && u.encoding.color.scale &&
                    JSON.stringify(u.encoding.color.scale.domain) === JSON.stringify(meta.domain)) {
                    delete u.encoding.color.scale.domain;
                    if (!Object.keys(u.encoding.color.scale).length) delete u.encoding.color.scale;
                }
                if (meta.filtered) {
                    if (meta.transform.length) u.transform = meta.transform;
                    else delete u.transform;
                }
                delete u._aovLegend;
            });
            units = [];
            visit(spec, null, {});
            var owners = Object.create(null), fields = [];
            function composite(u) {
                var m = typeof u.mark === 'string' ? u.mark : u.mark.type;
                return ['boxplot', 'errorbar', 'errorband'].indexOf(m) !== -1;
            }
            units.forEach(function(info) {
                var c = info.encoding.color;
                if (composite(info.unit) || !c || !c.field ||
                    ['nominal', 'ordinal'].indexOf(c.type) === -1 || c.legend === null || c.scale === null ||
                    c.aggregate || c.bin || c.timeUnit) return;
                if (!owners[c.field]) { owners[c.field] = info.unit; fields.push(c.field); }
            });
            function hasField(v, field) {
                return v && typeof v === 'object' && (v.field === field ||
                    Object.keys(v).some(function(k) { return hasField(v[k], field); }));
            }
            units.forEach(function(info) {
                var u = info.unit;
                if (composite(u)) return;
                var rows = info.data && info.data.values || [];
                var member = fields.filter(function(f) {
                    return hasField(info.encoding, f) || rows.some(function(r) {
                        return Object.prototype.hasOwnProperty.call(r, f);
                    });
                });
                if (!member.length) return;
                var enc = Object.assign({}, info.encoding);
                u.encoding = enc;
                var meta = {params:[], dimmed:false, filtered:false,
                    opacity:enc.opacity === undefined ? null : enc.opacity,
                    transform:u.transform || []};
                u._aovLegend = meta;
                var color = enc.color;
                if (mode === 'filter' && color && color.field && color.scale !== null &&
                    !(color.scale && 'domain' in color.scale)) {
                    var domain = [];
                    units.forEach(function(peer) {
                        (peer.data && peer.data.values || []).forEach(function(row) {
                            var value = row[color.field];
                            if (value !== undefined && value !== null && domain.indexOf(value) === -1) domain.push(value);
                        });
                    });
                    if (domain.length) {
                        enc.color = Object.assign({}, color, {scale:Object.assign({}, color.scale, {domain:{unionWith:domain}})});
                        meta.domain = {unionWith:domain};
                    }
                }
                var predicate = {and:member.map(function(f) {
                    var i = fields.indexOf(f), name = i ? 'legend_selection_' + (i+1) : 'legend_selection';
                    if (owners[f] === u) {
                        u.params = (u.params || []).concat([{name:name, select:{type:'point', fields:[f]}, bind:'legend'}]);
                        meta.params.push(name);
                    }
                    return {or:['!isValid(datum[' + JSON.stringify(f) + '])', {param:name, empty:true}]};
                })};
                if (mode === 'filter') {
                    meta.filtered = true;
                    u.transform = meta.transform.concat([{filter:predicate}]);
                } else {
                    var base = enc.opacity === undefined ?
                        (typeof u.mark === 'object' && u.mark.opacity !== undefined ? u.mark.opacity : 1) :
                        enc.opacity && enc.opacity.value;
                    if (typeof base === 'number' && !(enc.opacity && enc.opacity.condition)) {
                        meta.dimmed = true;
                        enc.opacity = {condition:{test:predicate, value:base}, value:0.15*base};
                    }
                }
            });
        },

        // `keepData` retains rows added via updateData/appendData on re-embed.
        _embed: function(id, spec, opts, keepData) {
            opts = opts || {};
            if (window.AoV && window.AoV.defaultActions !== undefined) {
                opts = Object.assign({}, opts, {actions: window.AoV.defaultActions});
            }
            var self = this;
            self._watchRemovals();
            // Live state (rows added via updateData/appendData, onSignal listeners) belongs
            // to the plot element: a new element with this ID (e.g. after an HTMX swap)
            // starts fresh, a new spec for the same element keeps the listeners.
            var prev = self.views[id], el = document.getElementById(id);
            if (!(prev && el && el.contains(prev.container()))) {
                delete self._signals[id];
                delete self._liveRows[id];
                delete self._droppedLegends[id];
            } else if (!keepData) {
                delete self._liveRows[id];
            }
            // The element this plot lives in (disposeWithin matches on it) and
            // this embed's ownership token: resize/fit re-embeds scheduled by an
            // earlier embed of the id check it and do nothing once superseded.
            var tok = {};
            self._els[id] = el;
            self._embedTok[id] = tok;
            // Remember the embed options so the restore re-embed below (and any
            // legend-restore re-embed from appendData/updateData) can preserve
            // them (e.g. actions:false) instead of falling back to defaults.
            self._embedOpts[id] = opts;
            // Store original spec for re-embed on resize and remapEncoding
            var origSpec = JSON.parse(JSON.stringify(spec));
            self._refreshLegendSelections(origSpec);
            spec = origSpec;
            self._broadcastCrossSource(origSpec);
            self._origSpecs[id] = origSpec;

            // width:"container" sizes the view from the embed element's own
            // width, and vega-embed makes that element display:inline-block,
            // which shrink-wraps its (not yet rendered) content: unless a page
            // stylesheet happens to widen it, the container measures 0 and the
            // plot renders 0px wide. Size the element here, where the runtime
            // runs, so single-view plots fill their container on any page
            // (vega_head pages, to_html files, runtime-only docs embeds).
            if (spec.width === 'container' && el) el.style.width = '100%';

            // Width cap for VL-native single-view specs: width:"container" has
            // no max, so bound the embed element itself and the plot fills
            // min(container, cap). (JS-sized layered/faceted specs are capped
            // through the sizing budget in _applyResponsiveWidth instead.)
            var _cap = (spec._aov && spec._aov.maxWidth) || (window.AoV && window.AoV.maxWidth);
            if (_cap !== undefined && _cap !== null && isFinite(_cap) && spec.width === 'container') {
                var _capEl = document.getElementById(id);
                if (_capEl) _capEl.style.maxWidth = _cap + 'px';
            }

            var doEmbed = function() {
                // Superseded by a newer embed of this id, or disposed: a resize or
                // fit re-embed scheduled earlier must not resurrect the old spec.
                if (self._embedTok[id] !== tok) return Promise.resolve();
                var s = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));
                // Replace (not leak) the previous view
                self._finalizeView(id);
                // Only the latest embed registers its view; one that resolves after
                // a newer embed (or a dispose) started is finalized instead.
                var gen = self._gens[id] = ++self._genSeq;
                // Tag VL warnings/errors with the plot ID for easier debugging
                self._tagConsole();
                self._inFlight[id] = (self._inFlight[id] || 0) + 1;
                var settled = false;
                var settle = function() {
                    if (settled) return;
                    settled = true;
                    if (--self._inFlight[id] <= 0) delete self._inFlight[id];
                };
                return vegaEmbed('#' + id, s, self._withLiveRows(id, opts, gen)).then(function(result) {
                    settle();
                    if (self._gens[id] !== gen) { result.finalize(); return result; }
                    self._results[id] = result;
                    var view = self.views[id] = result.view;
                    (self._signals[id] || []).forEach(function(sig) {
                        self._attachSignal(view, sig.signal, sig.callback);
                    });
                    // Run anything queued before the view was ready (e.g. appendData)
                    var pending = self._pending[id] || [];
                    delete self._pending[id];
                    pending.forEach(function(fn) { fn(view); });
                    // One bounded correction pass for JS-sized specs whose
                    // rendered chrome overshoots the computed budget.
                    self._fitCorrection(id, function() { doEmbed(); });
                    return result;
                }).catch(function(err) { settle(); self._console.error.call(console, '[' + id + ']', err); });
            };

            // Set up resize observer for responsive re-embed (only for _aov-marked specs)
            if (spec._aov) {
                var el = document.getElementById(id);
                if (el && el.parentElement && window.ResizeObserver) {
                    var timer = null;
                    var lastWidth = el.parentElement.clientWidth;
                    var ro = new ResizeObserver(function() {
                        var newWidth = el.parentElement ? el.parentElement.clientWidth : 0;
                        if (newWidth === lastWidth || newWidth < 50) return;
                        lastWidth = newWidth;
                        clearTimeout(timer);
                        timer = setTimeout(function() { doEmbed(); }, 200);
                    });
                    ro.observe(el.parentElement);
                    // Clean up on element removal
                    self._observers = self._observers || {};
                    if (self._observers[id]) { self._observers[id].disconnect(); }
                    self._observers[id] = ro;
                }
            }

            return doEmbed();
        },

        // Vega-Lite compiles inside vegaEmbed with no per-embed logger, so its
        // warnings carry no plot id. One permanent wrapper tags them while
        // exactly one embed is in flight (with several in flight the source is
        // ambiguous). Per-embed save/restore of console.warn interleaves across
        // concurrent embeds and leaves a growing chain of wrappers installed,
        // each keeping its plot reachable after dispose().
        _inFlight: {},
        _tagConsole: function() {
            if (this._console) return;
            var self = this, orig = this._console = {warn: console.warn, error: console.error};
            ['warn', 'error'].forEach(function(level) {
                console[level] = function() {
                    var a = Array.prototype.slice.call(arguments), ids = Object.keys(self._inFlight);
                    if (ids.length === 1) a[0] = '[' + ids[0] + '] ' + a[0];
                    return orig[level].apply(console, a);
                };
            });
        },

        // Finalize a plot's current view through vega-embed's own finalize:
        // View.finalize() alone leaves the actions menu's document click
        // listener, which keeps the whole replaced view reachable.
        _finalizeView: function(id) {
            var r = this._results[id], v = this.views[id];
            if (r) r.finalize(); else if (v) v.finalize();
            delete this._results[id];
            delete this.views[id];
        },

        // Tear a plot down: finalize its view (removing the window/document
        // listeners that otherwise keep its data, scenegraph and canvas alive)
        // and drop every piece of per-plot state. The DOM is left alone; an
        // embed still in flight is finalized when it resolves.
        dispose: function(id) {
            var self = this;
            self._finalizeView(id);
            if (self._observers && self._observers[id]) self._observers[id].disconnect();
            self._perPlotState.forEach(function(k) { if (self[k]) delete self[k][id]; });
        },

        // Dispose every plot whose element is `root` or inside it. Walks the
        // registry rather than the DOM, so it also works on a detached subtree.
        disposeWithin: function(root) {
            var self = this;
            if (!root) return;
            Object.keys(self._els).forEach(function(id) {
                var el = self._els[id];
                if (el && (el === root || root.contains(el))) self.dispose(id);
            });
        },

        whenReady: function(id, fn) {
            var view = this.views[id];
            if (view) { fn(view); return; }
            this._pending[id] = this._pending[id] || [];
            this._pending[id].push(fn);
        },

        updateData: function(id, data, name) {
            name = name || 'source_0';
            var self = this;
            this.whenReady(id, function(view) {
                self._liveRows[id] = self._liveRows[id] || {};
                self._liveRows[id][name] = data;
                var changeset = vega.changeset().remove(function() { return true; }).insert(data);
                view.change(name, changeset).run();
                self._maybeRestoreLegends(id);
            });
        },

        appendData: function(id, data, name, maxRows) {
            name = name || 'source_0';
            var self = this;
            this.whenReady(id, function(view) {
                var live = self._liveRows[id] = self._liveRows[id] || {};
                var rows = (live[name] || (self._specRows[id] || {})[name] || []).concat(data);
                var trimmed = maxRows && rows.length > maxRows;
                if (trimmed) rows = rows.slice(rows.length - maxRows);
                live[name] = rows;
                var changeset = trimmed ?
                    vega.changeset().remove(function() { return true; }).insert(rows) :
                    vega.changeset().insert(data);
                view.change(name, changeset).run();
                self._maybeRestoreLegends(id);
            });
        },

        // Vega renders a legend whose scale domain is empty as a zero-item
        // legend group with inverted bounds; the legend layout folds those
        // bounds into the view origin, collapsing the whole canvas to 0x0
        // (observed on vega 5.33.1 / vega-lite 5.23.0). The incremental-plot
        // pattern starts from a typed-empty table, so this is the normal first
        // paint for any colored plot whose data streams in later. _withLiveRows
        // drops such legends at the compiled-spec boundary (an empty legend has
        // nothing to label), records the drop per plot, and the first data
        // change re-embeds once with live rows to restore the legend.
        _legendDomainEmpty: function(vg, domainSpec) {
            var self = this;
            if (Array.isArray(domainSpec)) return domainSpec.length === 0;
            if (domainSpec && domainSpec.fields) {
                // Multi-layer union domain: empty only when every field's
                // source dataset resolves empty.
                return (domainSpec.fields || []).every(function(f) {
                    return self._legendDomainEmpty(vg, f);
                });
            }
            if (domainSpec && domainSpec.data) {
                var ds = (vg.data || []).find(function(d) { return d.name === domainSpec.data; });
                if (ds) return self._datasetEmpty(vg, ds);
            }
            return false;
        },
        _datasetEmpty: function(vg, ds) {
            if (ds.values) return ds.values.length === 0;
            if (ds.source) {
                var src = (vg.data || []).find(function(d) { return d.name === ds.source; });
                return src ? this._datasetEmpty(vg, src) : false;
            }
            return false;
        },
        _dropEmptyLegends: function(id, vg) {
            var self = this;
            var scales = {};
            (vg.scales || []).forEach(function(s) { scales[s.name] = s; });
            var dropped = 0, kept = [];
            (vg.legends || []).forEach(function(L) {
                var empty = false;
                ['fill', 'stroke', 'shape', 'size', 'opacity', 'fontWeight'].forEach(function(prop) {
                    var sc = L[prop] && scales[L[prop]];
                    if (sc && self._legendDomainEmpty(vg, sc.domain)) empty = true;
                });
                if (empty) { dropped++; return; }
                kept.push(L);
            });
            vg.legends = kept;
            if (dropped > 0) self._droppedLegends[id] = dropped;
            else delete self._droppedLegends[id];
        },
        _maybeRestoreLegends: function(id) {
            var self = this;
            if (!self._droppedLegends[id]) return;
            delete self._droppedLegends[id];
            // keepData re-embed: the patched patch substitutes the appended
            // rows, so the legend comes back bound to the real domain. Signal
            // listeners re-attach in _embed; the view swap is invisible at
            // 60 fps (single bounded re-embed after the first data change).
            self._embed(id, self._origSpecs[id], self._embedOpts[id], true);
        },

        // The raw rows of datasets changed via updateData/appendData are kept per plot, and
        // re-embeds (resize, remapEncoding) compile the spec with them in place of its own.
        _withLiveRows: function(id, opts, gen) {
            var self = this, patch = opts.patch;
            return Object.assign({}, opts, {patch: function(vg) {
                if (typeof patch === 'function') vg = patch(vg);
                // An embed superseded or disposed while compiling still compiles;
                // it must not re-create the plot's state.
                if (self._gens[id] !== gen) return vg;
                var live = self._liveRows[id] || {}, specRows = self._specRows[id] = {};
                (vg.data || []).forEach(function(d) {
                    if (Array.isArray(d.values)) specRows[d.name] = d.values;
                    if (live[d.name]) d.values = live[d.name];
                });
                self._dropEmptyLegends(id, vg);
                return vg;
            }});
        },

        onSignal: function(id, signal, callback) {
            // A plot disposed before its embed resolved (to_node wires signals
            // in the embed's .then) has nothing to listen to. Listeners added
            // before a plot's first embed were already dropped by that embed.
            if (!(id in this._els)) return;
            // Kept per plot so re-embeds (resize, new layers) re-attach it
            this._signals[id] = this._signals[id] || [];
            this._signals[id].push({signal: signal, callback: callback});
            var view = this.views[id];
            if (view) this._attachSignal(view, signal, callback);
        },

        _attachSignal: function(view, signal, callback) {
            try {
                view.addSignalListener(signal, function(name, value) {
                    callback(name, value, view);
                });
            } catch (e) { console.warn('AoV: cannot listen to signal', signal, e); }
        },

        // --- Plot data download / inline preview ---
        // Read inline data from a plot's view; returns array of objects.
        // Tries the named source first, falls back to common VL conventions.
        _plotData: function(id, name) {
            var view = this.views[id];
            if (!view) return null;
            name = name || 'source_0';
            try { return view.data(name); } catch (e) { /* fall through */ }
            // Fallback: enumerate runtime data, return first non-empty array
            try {
                var runtime = view._runtime && view._runtime.data;
                if (runtime) {
                    for (var k in runtime) {
                        try {
                            var d = view.data(k);
                            if (Array.isArray(d) && d.length) return d;
                        } catch (e) {}
                    }
                }
            } catch (e) {}
            return null;
        },

        // Split rows by a discriminator column (e.g. "__src" for multi-source layered specs).
        // Returns [{label, rows}, ...]. If no rows have the column, returns [{label: null, rows}].
        _splitBySource: function(rows, col) {
            col = col || '__src';
            if (!rows || !rows.length) return [{label: null, rows: rows || []}];
            var hasCol = rows.some(function(r) { return r && Object.prototype.hasOwnProperty.call(r, col); });
            if (!hasCol) return [{label: null, rows: rows}];
            var groups = {};
            var order = [];
            rows.forEach(function(r) {
                var v = r && r[col];
                var k = v === undefined ? '__none__' : String(v);
                if (!groups[k]) { groups[k] = []; order.push(k); }
                // Drop the discriminator from the exported row
                var clean = {};
                for (var f in r) { if (f !== col) clean[f] = r[f]; }
                groups[k].push(clean);
            });
            return order.map(function(k) {
                return {label: k === '__none__' ? null : k, rows: groups[k]};
            });
        },

        _csvEscape: function(s) {
            s = (s === null || s === undefined) ? '' : String(s);
            return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
        },

        _rowsToCsv: function(rows) {
            if (!rows || !rows.length) return '';
            var cols = Object.keys(rows[0]);
            var self = this;
            var header = cols.map(self._csvEscape).join(',');
            var body = rows.map(function(r) {
                return cols.map(function(c) { return self._csvEscape(r[c]); }).join(',');
            }).join('\n');
            return header + '\n' + body;
        },

        _triggerDownload: function(text, filename, mime) {
            var blob = new Blob([text], {type: (mime || 'text/csv') + ';charset=utf-8;'});
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url; a.download = filename;
            document.body.appendChild(a); a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        },

        // Public: download the plot's data as CSV. Splits by `__src` if present.
        // labels: optional {srcValue: humanLabel} override map.
        downloadPlotData: function(id, filenameBase, labels) {
            filenameBase = filenameBase || id;
            labels = labels || {};
            var rows = this._plotData(id);
            if (!rows) { console.warn('AoV.downloadPlotData: no data for', id); return; }
            var groups = this._splitBySource(rows);
            var self = this;
            groups.forEach(function(g) {
                var label = g.label === null ? '' : '_' + (labels[g.label] || g.label).replace(/[^A-Za-z0-9_-]+/g, '_');
                var fname = filenameBase + label + '.csv';
                self._triggerDownload(self._rowsToCsv(g.rows), fname);
            });
        },

        // Public: download the plot as a PNG/SVG image via vega view.toImageURL.
        downloadPlotImage: function(id, format, filenameBase) {
            filenameBase = filenameBase || id;
            format = (format || 'png').toLowerCase();
            var view = this.views[id];
            if (!view) { console.warn('AoV.downloadPlotImage: no view for', id); return; }
            view.toImageURL(format).then(function(url) {
                var a = document.createElement('a');
                a.href = url; a.download = filenameBase + '.' + format;
                document.body.appendChild(a); a.click();
                document.body.removeChild(a);
            }).catch(function(err) {
                console.warn('AoV.downloadPlotImage failed:', err);
            });
        },

        // Public: download THIS card as a standalone .html file — no server
        // round-trip. Clones the card's live DOM (picker + plot + caption +
        // lazy shells), resets live-only UI state on the clone, and prepends
        // a <head> scraped from the live document (Vega CDN scripts + AoV
        // runtime + caption CSS), mirroring `to_html(::HTMX.Node)`.
        downloadPlotHtml: function(id, filenameBase) {
            filenameBase = filenameBase || id;
            var anchor = document.getElementById(id);
            if (!anchor) { console.warn('AoV.downloadPlotHtml: no element for', id); return; }
            var root = anchor.closest('[data-aov-fragment]') || anchor.closest('figure');
            if (!root) { console.warn('AoV.downloadPlotHtml: no card root for', id); return; }
            var clone = root.cloneNode(true);

            // Live-rendered view output: the fresh page re-embeds from the spec.
            var plotEl = clone.querySelector('#' + id);
            if (plotEl) plotEl.innerHTML = '';
            // Lazy data shells: drop rendered bodies; the fresh page re-renders lazily.
            clone.querySelectorAll('.aov-data-raw-body[data-aov-plot-id], .aov-data-pretty-body[data-aov-plot-id]').forEach(function(b) {
                b.innerHTML = '';
            });
            clone.querySelectorAll('[data-aov-rendered]').forEach(function(el) {
                el.removeAttribute('data-aov-rendered');
            });
            // Pretty/Raw toggle: back to the initial Pretty mode.
            clone.querySelectorAll('details.aov-data-preview[data-mode]').forEach(function(d) {
                d.dataset.mode = 'pretty';
                d.querySelectorAll('button[data-view]').forEach(function(btn) {
                    if (btn.dataset.view === 'pretty') btn.setAttribute('aria-pressed', 'true');
                    else btn.removeAttribute('aria-pressed');
                });
            });
            // Picker: restore the INITIAL pin/disabled/checked state. Pin changes
            // (and URL restore) flip select.disabled, a reflecting IDL attribute,
            // so the clone's attributes may disagree with the authored initial
            // state — read the initial pin from the picker's own inline script.
            var pin0 = null;
            clone.querySelectorAll('script').forEach(function(s) {
                var m = /_aovPin_\w+_current = '([A-Za-z_]+)'/.exec(s.textContent || '');
                if (m) pin0 = m[1];
            });
            if (pin0) {
                clone.querySelectorAll('select[id^="aov-remap-"][id$="-' + id + '"]').forEach(function(sel) {
                    var ch = sel.id.slice('aov-remap-'.length, sel.id.length - id.length - 1);
                    var radio = clone.querySelector('input[name="aov-pin-' + id + '"][value="' + ch + '"]');
                    // Fixed channels keep their authored disabled select (their radio
                    // is disabled too and _aovPin never touches radios); x/y/off radios
                    // are disabled without disabling their selects.
                    var fixedCh = radio && radio.disabled && ch !== 'x' && ch !== 'y' && ch !== 'off';
                    if (ch === pin0 || fixedCh) sel.setAttribute('disabled', 'disabled');
                    else sel.removeAttribute('disabled');
                });
                clone.querySelectorAll('input[name="aov-pin-' + id + '"]').forEach(function(r) {
                    if (r.value === pin0) r.setAttribute('checked', 'checked');
                    else r.removeAttribute('checked');
                });
            }

            // <head> pieces, scraped from the live document: the same Vega CDN
            // scripts, runtime, and caption CSS the live page runs.
            var headParts = [];
            document.querySelectorAll('script[src]').forEach(function(s) {
                var src = s.getAttribute('src') || '';
                if (/\/vega(-lite|-embed)?@/.test(src)) headParts.push(s.outerHTML);
            });
            document.querySelectorAll('script:not([src])').forEach(function(s) {
                var t = s.textContent || '';
                if (t.indexOf('window.AoV = window.AoV ||') !== -1 ||
                    t.indexOf('window.AoV = Object.assign(window.AoV') !== -1 ||
                    t.indexOf('function sortTable(') !== -1) {
                    headParts.push(s.outerHTML);
                }
            });
            document.querySelectorAll('style').forEach(function(s) {
                var t = s.textContent || '';
                if (t.indexOf('aov-data-preview') !== -1 || t.indexOf('caption-actions') !== -1) {
                    headParts.push(s.outerHTML);
                }
            });

            var title = 'AoV plot';
            var capTitle = clone.querySelector('figcaption .caption-header strong');
            if (capTitle && capTitle.textContent) title = capTitle.textContent;
            else if (document.title) title = document.title;
            title = title.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

            var page = '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n' +
                '<title>' + title + '</title>\n' +
                '<style>body{font-family:system-ui,sans-serif;margin:1rem}</style>\n' +
                headParts.join('\n') + '\n</head>\n<body>\n' +
                clone.outerHTML + '\n</body>\n</html>\n';
            this._triggerDownload(page, filenameBase + '.html', 'text/html');
        },

        // Public: render the plot's data as sortable HTML table(s) into `container`.
        // Builds lazily — call from the <details> "toggle" event.
        showPlotData: function(id, container, labels) {
            labels = labels || {};
            if (container.dataset.aovRendered === '1') return;
            var rows = this._plotData(id);
            if (!rows) { container.textContent = '(no data available)'; container.dataset.aovRendered = '1'; return; }
            var groups = this._splitBySource(rows);
            container.innerHTML = '';
            var self = this;
            groups.forEach(function(g) {
                if (g.label !== null) {
                    var h = document.createElement('h6');
                    h.textContent = labels[g.label] || g.label;
                    h.style.margin = '0.5rem 0 0.25rem';
                    container.appendChild(h);
                }
                container.appendChild(self._buildSortableTable(g.rows));
            });
            container.dataset.aovRendered = '1';
        },

        _buildSortableTable: function(rows, cols) {
            var table = document.createElement('table');
            table.className = 'striped';
            table.setAttribute('role', 'grid');
            if (!rows || !rows.length) {
                table.innerHTML = '<tbody><tr><td>(empty)</td></tr></tbody>';
                return table;
            }
            if (!cols) {
                var rawCols = Object.keys(rows[0]);
                var stringCols = [], numericCols = [];
                rawCols.forEach(function(c) {
                    var isNumeric = false;
                    for (var i = 0; i < rows.length; i++) {
                        var v = rows[i][c];
                        if (v === null || v === undefined || v === '') continue;
                        isNumeric = (typeof v === 'number');
                        break;
                    }
                    (isNumeric ? numericCols : stringCols).push(c);
                });
                stringCols.sort();
                numericCols.sort();
                cols = stringCols.concat(numericCols);
            }
            var thead = document.createElement('thead');
            var trh = document.createElement('tr');
            cols.forEach(function(c, i) {
                var th = document.createElement('th');
                th.textContent = c;
                th.style.cursor = 'pointer';
                th.onclick = function() {
                    if (typeof window.sortTable === 'function') window.sortTable(i, th);
                };
                trh.appendChild(th);
            });
            thead.appendChild(trh);
            table.appendChild(thead);
            var tbody = document.createElement('tbody');
            rows.forEach(function(r) {
                var tr = document.createElement('tr');
                cols.forEach(function(c) {
                    var td = document.createElement('td');
                    var v = r[c];
                    td.textContent = (v === null || v === undefined) ? '' : String(v);
                    tr.appendChild(td);
                });
                tbody.appendChild(tr);
            });
            table.appendChild(tbody);
            return table;
        },

        // Public: toggle between Pretty and Raw views inside a captioned plot's
        // <details>. Sets details[data-mode] (CSS keys off it to show/hide
        // [data-view] wrappers) and aria-pressed on the toggle buttons.
        // Lazily renders the chosen view on first switch.
        toggleDataView: function(btn, view) {
            var details = btn.closest('details');
            if (!details) return;
            details.dataset.mode = view;
            var group = details.querySelector('[role="group"]');
            if (group) {
                group.querySelectorAll('button[data-view]').forEach(function(b) {
                    if (b.dataset.view === view) b.setAttribute('aria-pressed', 'true');
                    else b.removeAttribute('aria-pressed');
                });
            }
            this._lazyRenderDataView(details, view);
        },

        _lazyRenderDataView: function(details, view) {
            if (view === 'raw') {
                var body = details.querySelector('.aov-data-raw-body');
                if (body && body.dataset.aovRendered !== '1') {
                    var pid = body.dataset.aovPlotId;
                    var labels = body.dataset.aovLabels ? JSON.parse(body.dataset.aovLabels) : {};
                    if (pid) this.showPlotData(pid, body, labels);
                }
            } else if (view === 'pretty') {
                var body = details.querySelector('.aov-data-pretty-body');
                if (body && body.dataset.aovRendered !== '1') {
                    var pid = body.dataset.aovPlotId;
                    var opts = body.dataset.aovSummaryOpts ? JSON.parse(body.dataset.aovSummaryOpts) : {};
                    if (pid) this.renderPrettySummary(pid, body, opts);
                }
            }
        },

        // Public: render a "point [lo, hi]" pretty summary table from the live
        // Vega view's source_0, which already holds the aggregated columns
        // produced by Julia. Two modes:
        //   1. Auto-detect: looks for __point__ or __median__ as the central col,
        //      and lo_<prob>_ / hi_<prob>_ pairs for the intervals (used by
        //      pointinterval/gradient/dot/lineribbon).
        //   2. Explicit (opts.bands): caller passes [[loCol, hiCol, label], ...]
        //      and opts.point_col (used by lineribbon(bands=...) precomputed).
        //
        //   opts.ci: 'outer' (default, widest band) | 'inner' | Number (closest prob)
        //   opts.sigfigs: significant figures for numeric formatting (default 2)
        //   opts.value_label: header for the formatted value column (default 'value')
        //   opts.point_label: 'Median' (default) | 'Mean' | custom — used in caption
        renderPrettySummary: function(id, container, opts) {
            opts = opts || {};
            if (container.dataset.aovRendered === '1') return;
            var rows = this._plotData(id);
            if (!rows || !rows.length) {
                container.textContent = '(no summary data available)';
                container.dataset.aovRendered = '1';
                return;
            }
            var groups = this._splitBySource(rows);
            container.innerHTML = '';
            var labels = opts.labels || {};
            var self = this;
            groups.forEach(function(g) {
                if (g.label !== null) {
                    var heading = document.createElement('h6');
                    heading.textContent = labels[g.label] || g.label;
                    heading.style.margin = '0.5rem 0 0.25rem';
                    container.appendChild(heading);
                }
                var built = self._buildPrettyRows(g.rows, opts);
                if (!built) {
                    container.appendChild(self._buildSortableTable(g.rows));
                    return;
                }
                if (built.caption) {
                    var cap = document.createElement('figcaption');
                    cap.textContent = built.caption;
                    cap.style.cssText = 'font-size:0.85em;opacity:0.75;margin:0 0 0.25rem';
                    container.appendChild(cap);
                }
                container.appendChild(self._buildSortableTable(built.rows, built.cols));
            });
            container.dataset.aovRendered = '1';
        },

        _buildPrettyRows: function(rows, opts) {
            if (!rows || !rows.length) return null;
            var first = rows[0];
            var pointCol = opts.point_col ||
                ('__point__' in first ? '__point__' :
                 ('__median__' in first ? '__median__' : null));
            if (!pointCol || !(pointCol in first)) return null;

            var bands; // [{lo, hi, label}, ...] sorted inner→outer
            if (opts.bands && opts.bands.length) {
                // AoV passes explicit bands outermost-first (lineribbon convention);
                // internal representation is inner→outer to match the auto-detect path.
                bands = opts.bands.slice().reverse().map(function(b) {
                    return {lo: b[0], hi: b[1], label: b[2] || (b[0] + ' / ' + b[1])};
                });
            } else {
                var probMap = {};
                Object.keys(first).forEach(function(c) {
                    var m = /^lo_(\d+(?:_\d+)?)_$/.exec(c);
                    if (m && ('hi_' + m[1] + '_') in first) {
                        probMap[m[1]] = parseFloat(m[1].replace('_', '.'));
                    }
                });
                var probKeys = Object.keys(probMap);
                if (!probKeys.length) return null;
                probKeys.sort(function(a, b) { return probMap[a] - probMap[b]; });
                bands = probKeys.map(function(k) {
                    return {
                        lo: 'lo_' + k + '_',
                        hi: 'hi_' + k + '_',
                        label: Math.round(probMap[k] * 100) + '%',
                        prob: probMap[k]
                    };
                });
            }

            var pick;
            var ci = opts.ci;
            if (typeof ci === 'number' && bands[0].prob !== undefined) {
                pick = bands[0]; var bestDiff = Math.abs(pick.prob - ci);
                bands.forEach(function(b) {
                    var d = Math.abs(b.prob - ci);
                    if (d < bestDiff) { pick = b; bestDiff = d; }
                });
            } else if (ci === 'inner') {
                pick = bands[0];
            } else {
                pick = bands[bands.length - 1];
            }

            var sigfigs = (opts.sigfigs === undefined) ? 2 : opts.sigfigs;
            var fmt = function(x) {
                if (x === null || x === undefined || (typeof x === 'number' && isNaN(x))) return '';
                if (typeof x !== 'number') return String(x);
                return parseFloat(x.toPrecision(sigfigs)).toString();
            };
            var label = opts.value_label || 'value';
            var pointLabel = opts.point_label || 'Median';

            var hidden = {};
            hidden[pointCol] = 1;
            bands.forEach(function(b) { hidden[b.lo] = 1; hidden[b.hi] = 1; });

            var visibleSourceCols = Object.keys(first).filter(function(c) {
                if (hidden[c]) return false;
                if (c.indexOf('__') === 0) return false;
                return true;
            });
            // Categorical first (alpha), then numeric (alpha), then the value col.
            var stringCols = [], numericCols = [];
            visibleSourceCols.forEach(function(c) {
                var isNumeric = false;
                for (var i = 0; i < rows.length; i++) {
                    var v = rows[i][c];
                    if (v === null || v === undefined || v === '') continue;
                    isNumeric = (typeof v === 'number');
                    break;
                }
                (isNumeric ? numericCols : stringCols).push(c);
            });
            stringCols.sort(); numericCols.sort();
            var orderedCols = stringCols.concat(numericCols).concat([label]);

            var roundNum = function(v) {
                if (typeof v !== 'number' || isNaN(v)) return v;
                return parseFloat(v.toPrecision(sigfigs));
            };
            var built = rows.map(function(r) {
                var out = {};
                visibleSourceCols.forEach(function(c) { out[c] = roundNum(r[c]); });
                out[label] = fmt(r[pointCol]) + ' [' + fmt(r[pick.lo]) + ', ' + fmt(r[pick.hi]) + ']';
                return out;
            });

            var caption = pointLabel + ' [' + pick.label + (pick.prob !== undefined ? ' credible interval' : '') + ']';
            return {rows: built, cols: orderedCols, caption: caption};
        },

        // Wire a signal to an HTMX GET request.
        // Standalone (no-server) pages load no HTMX: degrade silently instead
        // of throwing a ReferenceError from the debounced callback.
        signalToHtmx: function(id, signal, url, target, swap, debounceMs) {
            debounceMs = debounceMs || 300;
            var timer = null;
            this.onSignal(id, signal, function(name, value) {
                clearTimeout(timer);
                timer = setTimeout(function() {
                    if (typeof htmx === 'undefined' || !htmx.ajax) return;
                    var params = typeof value === 'object' ? value : {};
                    var qs = Object.keys(params).map(function(k) {
                        return encodeURIComponent(k) + '=' + encodeURIComponent(JSON.stringify(params[k]));
                    }).join('&');
                    var fullUrl = qs ? url + '?' + qs : url;
                    htmx.ajax('GET', fullUrl, {target: target, swap: swap || 'innerHTML'});
                }, debounceMs);
            });
        },

        // Client-side encoding remapping: swap color/row/column fields without server round-trip
        remapEncoding: function(id, mapping) {
            var orig = this._origSpecs[id];
            if (!orig) { console.warn('AoV.remapEncoding: no stored spec for', id); return; }
            var spec = JSON.parse(JSON.stringify(orig));

            // If combo data was pre-built by the caller (multi-select picker),
            // inject it into the cloned spec so combos are available to all channels
            if (mapping._comboData && mapping._comboData.values) {
                if (spec.data && spec.data.values) spec.data = mapping._comboData;
                else if (spec.spec && spec.spec.data) spec.spec.data = mapping._comboData;
            }

            // Per-column-Y concat (`hconcat` of per-column facet views —
            // `scales(Y=(; scale=Dict(...)))`): remap color/row/detail/axes in
            // EVERY child, preserving each child's Y scale type and column
            // filter. Column remapping is not supported — the per-column scale
            // keys bind to the authored column field — so it logs and no-ops
            // (the picker should pin the column channel on these figures).
            if (spec.hconcat && Array.isArray(spec.hconcat)) {
                // Local title lookup — the shared `_titles`/`_fieldTitle` pair is
                // declared further down, so at this point the hoisted `var` is
                // still undefined (proven live: `_titles[f]` TypeError).
                var _titlesC = mapping._comboTitles || {};
                function _fieldTitleC(f) { return _titlesC[f] || f; }
                if ('column' in mapping) {
                    console.info('AoV.remapEncoding: column remap is not supported on per-column-scale (hconcat) figures; keeping the authored column field.');
                }
                if ('color' in mapping) {
                    var cfC = mapping.color;
                    spec.hconcat.forEach(function(child) {
                        if (!child || !child.spec || !Array.isArray(child.spec.layer)) return;
                        child.spec.layer.forEach(function(l) {
                            if (!l || !l.encoding || l._keep_color) return;
                            if (cfC) {
                                l.encoding.color = {field: cfC, type: 'nominal', title: _fieldTitleC(cfC)};
                            } else {
                                delete l.encoding.color;
                            }
                        });
                    });
                }
                if ('row' in mapping) {
                    var rfC = mapping.row;
                    spec.hconcat.forEach(function(child) {
                        if (!child || !child.facet) return;
                        if (rfC) {
                            child.facet.row = {field: rfC, type: 'nominal', title: _fieldTitleC(rfC)};
                        } else {
                            delete child.facet.row;
                        }
                    });
                }
                if (mapping._dimensions) {
                    var detailFieldsC = mapping._dimensions;
                    spec.hconcat.forEach(function(child) {
                        if (!child || !child.spec || !Array.isArray(child.spec.layer)) return;
                        child.spec.layer.forEach(function(l) {
                            if (!l || !l.encoding) return;
                            if (detailFieldsC.length > 0) {
                                l.encoding.detail = detailFieldsC.length === 1 ?
                                    {field: detailFieldsC[0], type: 'nominal'} :
                                    detailFieldsC.map(function(f) { return {field: f, type: 'nominal'}; });
                            } else {
                                delete l.encoding.detail;
                            }
                        });
                    });
                }
                function _remapConcatAxis(axis) {
                    if (!(axis in mapping)) return;
                    var newField = mapping[axis];
                    if (!newField) return;
                    var valsC = spec.data && Array.isArray(spec.data.values) ? spec.data.values : null;
                    var sampleC = null;
                    if (valsC) {
                        for (var i = 0; i < valsC.length; i++) {
                            if (valsC[i] && valsC[i][newField] !== undefined && valsC[i][newField] !== null) { sampleC = valsC[i][newField]; break; }
                        }
                    }
                    var newTypeC = sampleC !== null ? _inferType(sampleC) : null;
                    spec.hconcat.forEach(function(child) {
                        if (!child || !child.spec || !Array.isArray(child.spec.layer)) return;
                        child.spec.layer.forEach(function(l) {
                            if (!l || l._no_axis_remap || !l.encoding) return;
                            var encC = l.encoding[axis];
                            if (!encC || typeof encC !== 'object' || encC.field === undefined) return;
                            var oldField = encC.field;
                            encC.field = newField;
                            if (newTypeC) {
                                encC.type = newTypeC;
                                if (newTypeC !== 'quantitative' && encC.scale && encC.scale.type) {
                                    var stC = encC.scale.type;
                                    if (stC === 'log' || stC === 'sqrt' || stC === 'pow') delete encC.scale.type;
                                }
                            }
                            encC.title = _fieldTitleC(newField);
                            if (Array.isArray(encC.tooltip)) {
                                encC.tooltip.forEach(function(t) {
                                    if (t && t.field === oldField) {
                                        t.field = newField;
                                        t.title = _fieldTitleC(newField);
                                        if (newTypeC) t.type = newTypeC;
                                    }
                                });
                            }
                        });
                    });
                }
                _remapConcatAxis('x');
                _remapConcatAxis('y');

                // Re-broadcast cross-source layers after row mutations
                this._broadcastCrossSource(spec);

                // Re-embed, but preserve the TRUE original spec
                var savedOrigC = this._origSpecs[id];
                this._embed(id, spec, this._embedOpts[id], true);
                this._origSpecs[id] = savedOrigC;
                return;
            }

            // Find layers in either simple or faceted structure
            var isFaceted = !!(spec.facet || (spec.spec && spec.spec.layer));
            var layers = isFaceted ? (spec.spec && spec.spec.layer || []) : (spec.layer || [spec]);

            // Migrate encoding-based row/column to facet key structure
            // (encoding.row/column is VL inline faceting that conflicts with facet key)
            function _migrateEncodingFacets() {
                var enc = spec.encoding || (spec.spec && spec.spec.encoding);
                if (!enc) {
                    // Check sublayer encodings
                    layers.forEach(function(l) {
                        if (!l.encoding) return;
                        ['row', 'column'].forEach(function(ch) {
                            if (l.encoding[ch]) {
                                if (!isFaceted) { wrapFaceted(); }
                                spec.facet = spec.facet || {};
                                spec.facet[ch] = spec.facet[ch] || l.encoding[ch];
                                delete l.encoding[ch];
                            }
                        });
                    });
                    return;
                }
                ['row', 'column'].forEach(function(ch) {
                    if (enc[ch]) {
                        if (!isFaceted) { wrapFaceted(); }
                        spec.facet = spec.facet || {};
                        spec.facet[ch] = spec.facet[ch] || enc[ch];
                        delete enc[ch];
                    }
                });
            }
            _migrateEncodingFacets();

            // Resolve combo titles for human-readable legend/facet headers
            var _titles = mapping._comboTitles || {};
            function _fieldTitle(f) { return _titles[f] || f; }

            // Color remapping
            if ('color' in mapping) {
                var cf = mapping.color;
                var lrMeta = orig._aov && orig._aov.lineribbon;
                if (lrMeta && lrMeta.templateLayers) {
                    // Lineribbon per-group layering: rebuild layers from template
                    var tmpl = lrMeta.templateLayers;
                    var newLayers = [];
                    // When the spec uses merged data (with __src filters added by
                    // layers_to_vl), the rebuilt LR layers must inherit the same
                    // __src filter so they don't render rows from other sources.
                    var srcFilter = null;
                    for (var li = 0; li < layers.length; li++) {
                        var lll = layers[li];
                        if (lll && lll._lr_layer && Array.isArray(lll.transform)) {
                            for (var ti = 0; ti < lll.transform.length; ti++) {
                                var tf = lll.transform[ti];
                                if (tf && typeof tf.filter === 'string' && tf.filter.indexOf('__src') !== -1) {
                                    srcFilter = tf;
                                    break;
                                }
                            }
                            if (srcFilter) break;
                        }
                    }
                    if (cf) {
                        // Get unique values of the new color field from data
                        var vals = spec.data && spec.data.values || [];
                        var seen = {}; var groups = [];
                        vals.forEach(function(r) {
                            var v = r[cf];
                            if (v !== undefined && !seen[v]) { seen[v] = true; groups.push(v); }
                        });
                        groups.sort();
                        groups.forEach(function(gval) {
                            var filterExpr = 'datum[' + JSON.stringify(cf) + '] === ' + JSON.stringify(gval);
                            tmpl.forEach(function(tl) {
                                var gl = JSON.parse(JSON.stringify(tl));
                                gl.transform = srcFilter ? [srcFilter, {filter: filterExpr}] : [{filter: filterExpr}];
                                gl.encoding.color = {field: cf, type: 'nominal', title: _fieldTitle(cf)};
                                gl._lr_layer = true;
                                newLayers.push(gl);
                            });
                        });
                    } else {
                        // No color: use template layers as-is (with __src filter if any)
                        tmpl.forEach(function(tl) {
                            var gl = JSON.parse(JSON.stringify(tl));
                            if (srcFilter) gl.transform = [srcFilter];
                            gl._lr_layer = true;
                            newLayers.push(gl);
                        });
                    }
                    // Preserve non-lineribbon layers (e.g. cross-source dose VLines)
                    // and replace only the tagged lineribbon layers.
                    var preserved = layers.filter(function(l) { return !(l && l._lr_layer); });
                    var allLayers = preserved.concat(newLayers);
                    if (isFaceted) {
                        spec.spec.layer = allLayers;
                    } else {
                        spec.layer = allLayers;
                    }
                    layers = allLayers;
                } else {
                    // Non-lineribbon: standard color remapping. Skip layers
                    // whose mark statically sets `color` — those layers were
                    // intentionally given a fixed color (e.g. black observation
                    // scatters) and should not be data-driven by the picker.
                    layers.forEach(function(l) {
                        if (!l.encoding) return;
                        if (l._keep_color) return;  // layer-fixed color (field outside remappable dims)
                        var staticColor = l.mark && typeof l.mark === 'object' && l.mark.color;
                        if (staticColor) return;
                        if (cf) {
                            l.encoding.color = {field: cf, type: 'nominal', title: _fieldTitle(cf)};
                        } else {
                            delete l.encoding.color;
                        }
                        // Sync tooltips: remove old color entries, add new
                        if (Array.isArray(l.encoding.tooltip)) {
                            l.encoding.tooltip = l.encoding.tooltip.filter(function(t) {
                                return t.type !== 'nominal' || t.field === (spec.facet && spec.facet.row && spec.facet.row.field) ||
                                       t.field === (spec.facet && spec.facet.column && spec.facet.column.field);
                            });
                            if (cf) l.encoding.tooltip.push({field: cf, type: 'nominal'});
                        }
                    });
                }
            }

            // Count unique values for a field in the data (for nFacetCols hint)
            function countUnique(field) {
                var vals = spec.data && spec.data.values;
                if (!vals) return 1;
                var seen = {};
                vals.forEach(function(r) { if (r[field] !== undefined) seen[r[field]] = true; });
                return Math.max(Object.keys(seen).length, 1);
            }

            // Helper: wrap a non-faceted spec into faceted structure
            function wrapFaceted() {
                if (isFaceted) return;
                if (spec.layer) {
                    spec.spec = {layer: spec.layer};
                    delete spec.layer;
                } else {
                    // Single-view spec: move mark+encoding into spec.spec
                    var inner = {};
                    ['mark', 'encoding', 'transform', 'selection', 'params', '_aovLegend'].forEach(function(k) {
                        if (spec[k] !== undefined) { inner[k] = spec[k]; delete spec[k]; }
                    });
                    spec.spec = inner;
                }
                // Width/height describe the child view in a facet operator.
                // Leaving height on the outer object loses the authored size;
                // a categorical axis then falls back to step sizing (and VL's
                // nearest-point overlay can compile an unbound datum expression).
                ['width', 'height'].forEach(function(k) {
                    if (spec[k] !== undefined) { spec.spec[k] = spec[k]; delete spec[k]; }
                });
                spec.facet = {};
                // Remove single-view-only properties from outer spec
                delete spec.autosize;
                // Add _aov hint for responsive faceted sizing
                spec._aov = spec._aov || {};
                isFaceted = true;
                layers = spec.spec.layer || [spec.spec];
            }

            // Helper: unwrap faceted spec back to flat
            function unwrapFaceted() {
                if (!spec.facet) return;
                if (spec.facet.column || spec.facet.row) return;
                var inner = spec.spec || {};
                if (inner.layer) {
                    spec.layer = inner.layer;
                    ['width', 'height'].forEach(function(k) {
                        if (inner[k] !== undefined) spec[k] = inner[k];
                    });
                } else {
                    // Restore single-view keys
                    Object.keys(inner).forEach(function(k) { spec[k] = inner[k]; });
                }
                delete spec.spec;
                delete spec.facet;
                if (!spec.layer) {
                    // Single-view: use VL native responsive width
                    spec.width = 'container';
                    spec.autosize = {type: 'fit', contains: 'padding'};
                    delete spec._aov;
                } else {
                    // Layered: use _aov marker for JS responsive sizing
                    // (preserve keys such as maxWidth).
                    spec._aov = spec._aov || {};
                }
                isFaceted = false;
                layers = spec.layer || [spec];
            }

            // Row facet remapping
            if ('row' in mapping) {
                var rf = mapping.row;
                if (rf) {
                    wrapFaceted();
                    spec.facet.row = {field: rf, type: 'nominal', title: _fieldTitle(rf)};
                } else if (spec.facet) {
                    delete spec.facet.row;
                    unwrapFaceted();
                }
            }

            // Column facet remapping
            if ('column' in mapping) {
                var clf = mapping.column;
                if (clf) {
                    wrapFaceted();
                    spec.facet.column = {field: clf, type: 'nominal', title: _fieldTitle(clf)};
                } else if (spec.facet) {
                    delete spec.facet.column;
                    unwrapFaceted();
                }
            }

            // Update _aov.nFacetCols for responsive sizing
            if (isFaceted && spec._aov && spec.facet) {
                if (spec.facet.column) {
                    spec._aov.nFacetCols = countUnique(spec.facet.column.field);
                } else {
                    delete spec._aov.nFacetCols;
                }
            }

            // Detail encoding: put explicitly-specified dimension fields into detail
            // so VL groups by them without assigning visual properties.
            // With the multi-select picker, _dimensions is the resolved detail
            // channel contents (no set subtraction needed).
            if (mapping._dimensions) {
                var detailFields = mapping._dimensions;
                layers.forEach(function(l) {
                    if (!l.encoding) return;
                    if (detailFields.length > 0) {
                        l.encoding.detail = detailFields.length === 1 ?
                            {field: detailFields[0], type: 'nominal'} :
                            detailFields.map(function(f) { return {field: f, type: 'nominal'}; });
                    } else {
                        delete l.encoding.detail;
                    }
                });
            }

            // x/y axis remapping. Each swap: rewrite encoding.<axis>.field, re-infer
            // the type from a sample value in the data, refresh axis title and any
            // tooltip entry referencing the old field. Layers tagged `_no_axis_remap`
            // (planned: analysis layers with value axes bound to computed columns)
            // are skipped.
            function _inferType(v) {
                if (typeof v === 'number') return 'quantitative';
                if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return 'temporal';
                return 'nominal';
            }
            function _sampleVals() {
                if (spec.data && Array.isArray(spec.data.values)) return spec.data.values;
                if (spec.spec && spec.spec.data && Array.isArray(spec.spec.data.values)) return spec.spec.data.values;
                return null;
            }
            function _remapAxis(axis) {
                if (!(axis in mapping)) return;
                var newField = mapping[axis];
                if (!newField) return;  // empty = don't change (defensive: avoids breaking mandatory axes)
                var vals = _sampleVals();
                var sample = null;
                if (vals) {
                    for (var i = 0; i < vals.length; i++) {
                        if (vals[i] && vals[i][newField] !== undefined && vals[i][newField] !== null) {
                            sample = vals[i][newField]; break;
                        }
                    }
                }
                var newType = sample !== null ? _inferType(sample) : null;
                layers.forEach(function(l) {
                    if (!l || l._no_axis_remap) return;
                    var enc = l.encoding;
                    if (!enc || !enc[axis] || typeof enc[axis] !== 'object') return;
                    var oldField = enc[axis].field;
                    if (oldField === undefined) return;
                    enc[axis].field = newField;
                    if (newType) {
                        enc[axis].type = newType;
                        // When the axis type flips from quantitative to nominal, a log/sqrt
                        // scale no longer makes sense — drop it rather than leave VL with
                        // an invalid scale it will ignore with warnings.
                        if (newType !== 'quantitative' && enc[axis].scale && enc[axis].scale.type) {
                            var st = enc[axis].scale.type;
                            if (st === 'log' || st === 'sqrt' || st === 'pow') {
                                delete enc[axis].scale.type;
                            }
                        }
                    }
                    enc[axis].title = _fieldTitle(newField);
                    var tt = enc.tooltip;
                    if (Array.isArray(tt)) {
                        tt.forEach(function(t) {
                            if (t && t.field === oldField) {
                                t.field = newField;
                                t.title = _fieldTitle(newField);
                                if (newType) t.type = newType;
                            }
                        });
                    }
                });
            }
            _remapAxis('x');
            _remapAxis('y');

            // Re-broadcast cross-source layers after row/column mutations
            // (color mutations need no broadcast — see _broadcastCrossSource).
            this._broadcastCrossSource(spec);

            // Re-embed, but preserve the TRUE original spec
            var savedOrig = this._origSpecs[id];
            this._embed(id, spec, this._embedOpts[id], true);
            this._origSpecs[id] = savedOrig;
        }
    };
    """))
end
