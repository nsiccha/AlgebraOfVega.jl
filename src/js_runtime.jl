# --- Output ---

"""
    to_json(spec; kwargs...) -> String

Convert a spec to a Vega-Lite JSON string. Passes `kwargs` to `JSON.json`.
"""
to_json(x; kwargs...) = JSON.json(to_vegalite(x); kwargs...)

VEGA_VERSION = "5"
VEGALITE_VERSION = "5"
VEGA_EMBED_VERSION = "6"

"""
    vega_head(; vega_version, vegalite_version, vega_embed_version, zoom)

Return a vector of `h.script`/`h.style` nodes to include in `htmx(; extra_head=vega_head())`.

`zoom` uniformly scales all plots (chart area, fonts, axes, legend). Responsive plots
are sized to `containerWidth / zoom` so they don't overflow their container.
"""
function vega_head(;
    vega_version=VEGA_VERSION,
    vegalite_version=VEGALITE_VERSION,
    vega_embed_version=VEGA_EMBED_VERSION,
    zoom=nothing,
    max_width=nothing,
    actions=nothing,
)
    nodes = [
        h.script(src="https://cdn.jsdelivr.net/npm/vega@$vega_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-lite@$vegalite_version"),
        h.script(src="https://cdn.jsdelivr.net/npm/vega-embed@$vega_embed_version"),
        # Fix vega-embed actions SVG sizing when CSS frameworks (Pico) override defaults
        h.style(Raw("""
            details[title] > summary > svg { width: 14px !important; height: 14px !important; }
            .chart-wrapper { height: auto !important; }

            /* AoV-specific role classes. Generic concepts (gallery
               grid, sortable table, status badges, …) live upstream in
               HTMXObjects; this block only carries roles peculiar to
               the AoV gallery shell. */
            .aov-plot-area { width: 100%; min-width: 0; }
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

"""Count the number of facet columns in a VL spec by inspecting the data."""
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
    return n > 0 ? n : 1
end

_push_row_value!(args...) = nothing
function _push_row_value!(vals, row::Dict, col_field)
    haskey(row, col_field) && push!(vals, row[col_field])
end

"""
    vega_runtime()

Return a `h.script` node with the AlgebraOfVega JS runtime.
Manages Vega views by ID and provides helpers for HTMX integration.

Client-side API:
- `AoV.views[id]` — access Vega views by element ID
- `AoV.embed(id, spec, opts)` — embed and register a view
- `AoV.updateData(id, data)` — swap a view's data without re-creating it
- `AoV.onSignal(id, signal, callback)` — listen to a Vega signal
- Signal→HTMX wiring is set up automatically by `to_node(; signals=...)`
"""
function vega_runtime()
    h.script(Raw(raw"""
    window.AoV = window.AoV || {
        views: {},
        _pending: {},
        _origSpecs: {},

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

            // Faceted specs: set per-cell width from container / nCols
            if (spec._aov && spec._aov.nFacetCols && spec.spec) {
                var nCols = spec._aov.nFacetCols;
                var cellWidth = Math.floor((containerWidth - padding) / nCols) - padding;
                if (cellWidth > 50) {
                    spec.spec = Object.assign({}, spec.spec, {width: cellWidth});
                }
                return spec;
            }

            // Faceted (row-only, no columns) or layered specs: set width responsively
            if (spec._aov && !spec._aov.nFacetCols) {
                var w = containerWidth - padding;
                if (spec.spec) {
                    // Row-only faceted: set width on inner spec
                    spec.spec = Object.assign({}, spec.spec, {width: w});
                } else {
                    spec = Object.assign({}, spec, {width: w});
                }
                return spec;
            }

            return spec;
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

            // Collect partition fields from facet config AND color encodings
            var fields = [];
            var pushField = function(f) {
                if (f && f.field && fields.indexOf(f.field) === -1) fields.push(f.field);
            };
            if (spec.facet) { pushField(spec.facet.row); pushField(spec.facet.column); }
            // Also broadcast for color fields (cross-source layers need them too)
            var layers = inner && inner.layer ? inner.layer : (spec.layer || null);
            if (layers) {
                layers.forEach(function(l) {
                    if (l && l.encoding && l.encoding.color) pushField(l.encoding.color);
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
            opts = opts || {};
            if (window.AoV && window.AoV.defaultActions !== undefined) {
                opts = Object.assign({}, opts, {actions: window.AoV.defaultActions});
            }
            var self = this;
            // Store original spec for re-embed on resize and remapEncoding
            var origSpec = JSON.parse(JSON.stringify(spec));
            self._broadcastCrossSource(origSpec);
            self._origSpecs[id] = origSpec;
            var sized = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));

            var doEmbed = function() {
                var s = self._applyResponsiveWidth(id, JSON.parse(JSON.stringify(origSpec)));
                // Tag VL warnings/errors with the plot ID for easier debugging
                var _warn = console.warn, _error = console.error;
                console.warn = function() { var a = Array.from(arguments); a[0] = '[' + id + '] ' + a[0]; _warn.apply(console, a); };
                console.error = function() { var a = Array.from(arguments); a[0] = '[' + id + '] ' + a[0]; _error.apply(console, a); };
                return vegaEmbed('#' + id, s, opts).then(function(result) {
                    console.warn = _warn; console.error = _error;
                    self.views[id] = result.view;
                    if (self._pending[id]) {
                        self._pending[id].forEach(function(p) {
                            self.onSignal(id, p.signal, p.callback);
                        });
                        delete self._pending[id];
                    }
                    return result;
                }).catch(function(err) { console.warn = _warn; console.error = _error; _error.call(console, '[' + id + ']', err); });
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

        updateData: function(id, data, name) {
            var view = this.views[id];
            if (!view) { console.warn('AoV: no view for', id); return; }
            name = name || 'source_0';
            var changeset = vega.changeset().remove(function() { return true; }).insert(data);
            view.change(name, changeset).run();
        },

        onSignal: function(id, signal, callback) {
            var view = this.views[id];
            if (!view) {
                // View not ready yet — queue it
                this._pending[id] = this._pending[id] || [];
                this._pending[id].push({signal: signal, callback: callback});
                return;
            }
            view.addSignalListener(signal, function(name, value) {
                callback(name, value, view);
            });
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

        // Wire a signal to an HTMX GET request
        signalToHtmx: function(id, signal, url, target, swap, debounceMs) {
            debounceMs = debounceMs || 300;
            var timer = null;
            this.onSignal(id, signal, function(name, value) {
                clearTimeout(timer);
                timer = setTimeout(function() {
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
                    ['mark', 'encoding', 'transform', 'selection', 'params'].forEach(function(k) {
                        if (spec[k] !== undefined) { inner[k] = spec[k]; delete spec[k]; }
                    });
                    spec.spec = inner;
                }
                spec.facet = {};
                // Remove single-view-only properties from outer spec
                delete spec.width;
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
                    spec._aov = {};
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

            // Re-broadcast cross-source layers after row/column/color mutations
            this._broadcastCrossSource(spec);

            // Re-embed, but preserve the TRUE original spec
            var savedOrig = this._origSpecs[id];
            this.embed(id, spec);
            this._origSpecs[id] = savedOrig;
        }
    };
    """))
end
