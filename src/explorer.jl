# Reusable data explorer widget and utilities

"""
    default_explorer_datasets()

Return a Dict of default datasets for the explorer widget.
"""
default_explorer_datasets() = Dict(
    "penguins" => sample_penguins(),
    "cars" => sample_cars(),
    "tips" => sample_tips(),
    "stocks" => sample_stocks(),
    "temperatures" => sample_temperatures(),
)

"""
    _resolve_filter_include(filter_include, tbl) -> Dict{String, Vector{String}}

Resolve a `default_filter_include` value into a Dict mapping column names to included values.
Accepts `nothing` (no pre-filtering), a `Dict`, or a `Function(col, val) -> Bool`.
"""
function _resolve_filter_include(::Nothing, tbl)
    nothing
end

_js_width(w::Integer) = string(w)
_js_width(w) = "'$w'"

_filter_include_for(_, c, v) = (string(c) => [string(x) for x in v])
function _filter_include_for(tbl, c, v::Function)
    vals = unique(string.(Tables.getcolumn(tbl, Symbol(c))))
    included = filter(v, vals)
    length(included) < length(vals) ? (string(c) => included) : nothing
end

function _resolve_filter_include(d::AbstractDict, tbl)
    result = Dict{String, Vector{String}}()
    for (k, v) in d
        entry = _filter_include_for(tbl, k, v)
        isnothing(entry) || (result[first(entry)] = last(entry))
    end
    isempty(result) ? nothing : result
end
function _resolve_filter_include(f::Function, tbl)
    cols = classify_columns(tbl)
    result = Dict{String, Vector{String}}()
    for c in cols.categorical
        vals = unique(string.(Tables.getcolumn(tbl, Symbol(c))))
        included = filter(v -> f(c, v), vals)
        if length(included) < length(vals)
            result[c] = included
        end
    end
    isempty(result) ? nothing : result
end

"""
    _filter_init_js(resolved, namespace) -> String

Return a JS snippet that pre-seeds `_explorerFilterSelected` from a resolved filter dict.
Returns `""` for `nothing` (no pre-filtering).
"""
function _filter_init_js(::Nothing, namespace)
    ""
end
function _filter_init_js(d::AbstractDict, namespace)
    parts = join(["'$(k)': new Set($(JSON.json(v)))" for (k, v) in d], ", ")
    "\n            $(namespace)_explorerFilterSelected = {$parts};"
end

_default_marks() = [
    "point" => "point",
    "bar" => "bar",
    "line" => "line",
    "area" => "area",
    "line+ribbon" => "line + ribbon",
    "boxplot" => "boxplot",
    "rect" => "rect (heatmap)",
]

"""
    explorer_js(; namespace="", plot_selector="#explorer-plot", spec_selector=nothing, width="container", height=350)

Return a String of JS code that implements the explorer widget logic.

Generates two JS functions: `_explorerUpdateDropdowns` (repopulates dropdown options
when the dataset changes) and `explorerUpdate` (builds and renders the Vega-Lite spec).

Dropdowns: dataset, x, y, color, group (detail encoding), facet column, facet row, mark type.
Checkboxes: independent X/Y axis (adds VL `resolve` for faceted specs), log X/Y scale.
The group dropdown maps to Vega-Lite's `detail` encoding channel, which groups data
(e.g. draws separate lines per group) without assigning a visual property like color.

- `namespace`: JS namespace prefix for functions (e.g. "AoV." for web app, "" for standalone)
- `plot_selector`: CSS selector for the plot container
- `spec_selector`: CSS selector for spec JSON display (nothing to skip)
- `width`: plot width for non-faceted specs (integer or "container")
- `height`: plot height for non-faceted specs

Faceted specs use responsive cell widths: container `clientWidth` divided by the number
of unique facet column values (min 100px). Row-only facets use full container width minus
padding (min 250px). Falls back to 800px if the container element isn't found.
"""
function explorer_js(; namespace="", plot_selector="#explorer-plot", spec_selector=nothing, width="container", height=350)
    spec_line = isnothing(spec_selector) ? "" : """
                document.querySelector('$spec_selector').textContent = JSON.stringify(spec, null, 2);"""
    js_width = _js_width(width)
    """
            $(namespace)_explorerFilterSelected = {};

            $(namespace)_explorerUpdateFilterPills = function(activeCols, data) {
                var container = document.getElementById('ex-filter-pills');
                if (!container) return;
                container.innerHTML = '';
                if (!activeCols || activeCols.length === 0 || !data) return;
                var stored = $(namespace)_explorerFilterSelected;
                activeCols.forEach(function(col) {
                    var unique = {};
                    for (var i = 0; i < data.length; i++) {
                        var v = data[i][col];
                        if (v !== null && v !== undefined) unique[String(v)] = true;
                    }
                    var values = Object.keys(unique).sort();
                    if (!stored[col]) {
                        stored[col] = new Set(values);
                    }
                    var row = document.createElement('div');
                    row.style.cssText = 'display:flex; flex-wrap:wrap; align-items:center; gap:0.3rem; margin-bottom:0.25rem;';
                    var label = document.createElement('strong');
                    label.textContent = col + ': ';
                    label.style.cssText = 'font-size:0.85rem; min-width:5rem;';
                    row.appendChild(label);
                    values.forEach(function(v) {
                        var pill = document.createElement('button');
                        pill.type = 'button';
                        pill.textContent = v;
                        var sel = stored[col].has(v);
                        pill.style.cssText = 'border:1px solid var(--pico-primary);border-radius:1rem;padding:0.15rem 0.6rem;cursor:pointer;font-size:0.85rem;' +
                            (sel ? 'background:var(--pico-primary);color:var(--pico-primary-inverse);' : 'background:transparent;color:var(--pico-primary);');
                        pill.onclick = function(e) {
                            if (e.ctrlKey || e.metaKey) {
                                stored[col] = new Set([v]);
                            } else {
                                if (stored[col].has(v)) stored[col].delete(v);
                                else stored[col].add(v);
                            }
                            $(namespace)explorerUpdate();
                        };
                        row.appendChild(pill);
                    });
                    container.appendChild(row);
                });
            };

            $(namespace)_explorerUpdateDropdowns = function() {
                var ds = document.getElementById('ex-dataset').value;
                var cols = $(namespace)_explorerColumns[ds];
                var allCols = cols.all;
                var catCols = cols.categorical;

                ['ex-x', 'ex-y'].forEach(function(id) {
                    var sel = document.getElementById(id);
                    var prev = sel.value;
                    sel.innerHTML = '';
                    allCols.forEach(function(c) {
                        var opt = document.createElement('option');
                        opt.value = c; opt.textContent = c;
                        sel.appendChild(opt);
                    });
                    if (allCols.indexOf(prev) >= 0) sel.value = prev;
                    else if (id === 'ex-y' && allCols.length > 1) sel.value = allCols[1];
                });

                ['ex-color', 'ex-group', 'ex-col', 'ex-row'].forEach(function(id) {
                    var sel = document.getElementById(id);
                    if (!sel) return;
                    var prev = sel.value;
                    sel.innerHTML = '<option value="">(none)</option>';
                    catCols.forEach(function(c) {
                        var opt = document.createElement('option');
                        opt.value = c; opt.textContent = c;
                        sel.appendChild(opt);
                    });
                    if (catCols.indexOf(prev) >= 0) sel.value = prev;
                    else sel.value = '';
                });
            };

            $(namespace)explorerUpdate = function() {
                if (!$(namespace)_explorerDatasets) return;
                var ds = document.getElementById('ex-dataset').value;
                var x = document.getElementById('ex-x').value;
                var y = document.getElementById('ex-y').value;
                var color = document.getElementById('ex-color').value;
                var group = document.getElementById('ex-group').value;
                var facetCol = document.getElementById('ex-col').value;
                var facetRow = document.getElementById('ex-row').value;
                var mark = document.getElementById('ex-mark').value;
                var rawData = $(namespace)_explorerDatasets[ds];

                var activeCatCols = [];
                [color, group, facetCol, facetRow].forEach(function(c) {
                    if (c && activeCatCols.indexOf(c) < 0) activeCatCols.push(c);
                });

                $(namespace)_explorerUpdateFilterPills(activeCatCols, rawData);

                var data = rawData;
                var stored = $(namespace)_explorerFilterSelected;
                activeCatCols.forEach(function(col) {
                    if (stored[col] && stored[col].size > 0) {
                        data = data.filter(function(row) { return stored[col].has(String(row[col])); });
                    }
                });

                function fieldType(field) {
                    for (var i = 0; i < data.length; i++) {
                        var v = data[i][field];
                        if (v !== null && v !== undefined) {
                            return typeof v === 'number' ? 'quantitative' : 'nominal';
                        }
                    }
                    return 'nominal';
                }

                var xType = fieldType(x), yType = fieldType(y);
                var zeroX = xType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
                var zeroY = yType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
                var encoding = {
                    x: {field: x, type: xType, scale: zeroX},
                    y: {field: y, type: yType, scale: zeroY},
                    tooltip: [{field: x, type: xType}, {field: y, type: yType}],
                };

                if (color) {
                    encoding.color = {field: color, type: 'nominal'};
                    encoding.tooltip.push({field: color, type: 'nominal'});
                }

                if (group) {
                    encoding.detail = {field: group, type: 'nominal'};
                }

                var indepX = document.getElementById('ex-indep-x') && document.getElementById('ex-indep-x').checked;
                var indepY = document.getElementById('ex-indep-y') && document.getElementById('ex-indep-y').checked;
                var logX = document.getElementById('ex-log-x') && document.getElementById('ex-log-x').checked;
                var logY = document.getElementById('ex-log-y') && document.getElementById('ex-log-y').checked;

                if (logX && xType === 'quantitative') { encoding.x.scale = Object.assign({}, encoding.x.scale, {type: 'log'}); }
                if (logY && yType === 'quantitative') { encoding.y.scale = Object.assign({}, encoding.y.scale, {type: 'log'}); }

                var ribbonEl = document.getElementById('ex-ribbon-levels-label');
                if (ribbonEl) ribbonEl.style.display = (mark === 'line+ribbon') ? '' : 'none';

                var spec;
                if (mark === 'line+ribbon') {
                    var levelsStr = document.getElementById('ex-ribbon-levels') ? document.getElementById('ex-ribbon-levels').value : '0.5, 0.9';
                    var levels = levelsStr.split(',').map(function(s) { return parseFloat(s.trim()); }).filter(function(v) { return v > 0 && v < 1; }).sort();
                    var groups = {};
                    for (var i = 0; i < data.length; i++) {
                        var row = data[i];
                        var key = color ? row[x] + '|||' + row[color] : String(row[x]);
                        if (!groups[key]) groups[key] = {xv: row[x], cv: color ? row[color] : null, ys: []};
                        var yVal = parseFloat(row[y]);
                        if (!isNaN(yVal)) groups[key].ys.push(yVal);
                    }
                    function _quantile(sorted, p) {
                        if (sorted.length === 0) return null;
                        var idx = p * (sorted.length - 1);
                        var lo = Math.floor(idx), hi = Math.ceil(idx);
                        if (lo === hi) return sorted[lo];
                        return sorted[lo] + (idx - lo) * (sorted[hi] - sorted[lo]);
                    }
                    var summaryData = [];
                    Object.keys(groups).forEach(function(key) {
                        var g = groups[key];
                        g.ys.sort(function(a, b) { return a - b; });
                        var sr = {_x: g.xv, _median: _quantile(g.ys, 0.5)};
                        if (g.cv !== null) sr._color = g.cv;
                        levels.forEach(function(p) {
                            var lo = (1 - p) / 2, hi = 1 - lo;
                            sr['_lo_' + p] = _quantile(g.ys, lo);
                            sr['_hi_' + p] = _quantile(g.ys, hi);
                        });
                        summaryData.push(sr);
                    });
                    var layers = [];
                    var opStep = levels.length > 1 ? 0.4 / (levels.length - 1) : 0;
                    for (var li = levels.length - 1; li >= 0; li--) {
                        var p = levels[li];
                        var bandEnc = {
                            x: {field: '_x', type: xType, scale: encoding.x.scale},
                            y: {field: '_lo_' + p, type: 'quantitative', scale: encoding.y.scale, title: y},
                            y2: {field: '_hi_' + p},
                        };
                        if (color) bandEnc.color = {field: '_color', type: 'nominal', title: color};
                        layers.push({mark: {type: 'area', opacity: 0.15 + opStep * li}, encoding: bandEnc});
                    }
                    var lineEnc = {
                        x: {field: '_x', type: xType, scale: encoding.x.scale, title: x},
                        y: {field: '_median', type: 'quantitative', scale: encoding.y.scale, title: y},
                        tooltip: [{field: '_x', type: xType, title: x}, {field: '_median', type: 'quantitative', title: 'median'}],
                    };
                    if (color) {
                        lineEnc.color = {field: '_color', type: 'nominal', title: color};
                        lineEnc.tooltip.push({field: '_color', type: 'nominal', title: color});
                    }
                    layers.push({mark: 'line', encoding: lineEnc});

                    if (facetCol || facetRow) {
                        var facet = {};
                        if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
                        if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
                        var plotEl = document.querySelector('$plot_selector');
                        var availWidth = plotEl ? plotEl.clientWidth : 800;
                        var cellWidth = 250;
                        if (facetCol) {
                            var uniqueCols = {};
                            for (var i = 0; i < summaryData.length; i++) { uniqueCols[summaryData[i][facetCol]] = true; }
                            var nCols = Object.keys(uniqueCols).length;
                            if (nCols > 0) cellWidth = Math.max(100, Math.floor((availWidth - 60) / nCols));
                        } else {
                            cellWidth = Math.max(250, availWidth - 60);
                        }
                        spec = {data: {values: summaryData}, facet: facet, spec: {layer: layers, width: cellWidth, height: 200}};
                        if (indepX || indepY) {
                            var resolve = {scale: {}, axis: {}};
                            if (indepX) { resolve.scale.x = 'independent'; resolve.axis.x = 'independent'; }
                            if (indepY) { resolve.scale.y = 'independent'; resolve.axis.y = 'independent'; }
                            spec.resolve = resolve;
                        }
                    } else {
                        spec = {data: {values: summaryData}, layer: layers, width: $js_width, height: $height};
                    }
                } else if (facetCol || facetRow) {
                    var facet = {};
                    if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
                    if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
                    var plotEl = document.querySelector('$plot_selector');
                    var availWidth = plotEl ? plotEl.clientWidth : 800;
                    var cellWidth = 250;
                    if (facetCol) {
                        var uniqueCols = {};
                        for (var i = 0; i < data.length; i++) { uniqueCols[data[i][facetCol]] = true; }
                        var nCols = Object.keys(uniqueCols).length;
                        if (nCols > 0) cellWidth = Math.max(100, Math.floor((availWidth - 60) / nCols));
                    } else {
                        cellWidth = Math.max(250, availWidth - 60);
                    }
                    spec = {
                        data: {values: data},
                        facet: facet,
                        spec: {mark: mark, encoding: encoding, width: cellWidth, height: 200},
                    };
                    if (indepX || indepY) {
                        var resolve = {scale: {}, axis: {}};
                        if (indepX) { resolve.scale.x = 'independent'; resolve.axis.x = 'independent'; }
                        if (indepY) { resolve.scale.y = 'independent'; resolve.axis.y = 'independent'; }
                        spec.resolve = resolve;
                    }
                } else {
                    spec = {
                        data: {values: data},
                        mark: mark,
                        encoding: encoding,
                        width: $js_width,
                        height: $height,
                    };
                }
$spec_line

                function doEmbed() {
                    vegaEmbed('$plot_selector', spec, {actions: false}).catch(console.error);
                }
                if (typeof vegaEmbed !== 'undefined') { doEmbed(); }
                else {
                    var check = setInterval(function() {
                        if (typeof vegaEmbed !== 'undefined') { clearInterval(check); doEmbed(); }
                    }, 100);
                }
            };
"""
end

"""
    explorer_data_init_js(datasets; namespace="")

Return JS code that initializes the datasets and columns variables.
"""
function explorer_data_init_js(datasets; namespace="")
    ds_names = sort(collect(keys(datasets)))
    ds_dict = Dict(name => table_to_rows(datasets[name]) for name in ds_names)
    col_dict = Dict(name => Dict(
        "all" => collect(classify_columns(datasets[name]).all),
        "numeric" => classify_columns(datasets[name]).numeric,
        "categorical" => classify_columns(datasets[name]).categorical,
    ) for name in ds_names)
    """
            $(namespace)_explorerDatasets = $(JSON.json(ds_dict));
            $(namespace)_explorerColumns = $(JSON.json(col_dict));"""
end

"""
    explorer_controls_html(datasets_or_table; default_ds="penguins", onchange_fn="explorerUpdate()", kwargs...)

Return an HTML string for the explorer dropdown controls.

Accepts either a `Dict{String => table}` of named datasets or a bare table (auto-wrapped as
`Dict("data" => table)` with the dataset dropdown hidden).

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type, plus checkboxes for independent X/Y axes and log X/Y scale.
When mark is "line+ribbon", a "Ribbon levels" text input appears for tuning quantile bands.

# Keyword arguments
- `default_ds`: which dataset to pre-select (auto-falls back to first available key)
- `onchange_fn`: JS function to call on dropdown change
- `default_x`, `default_y`: pre-select x/y columns (default: first and second column)
- `default_color`, `default_group`, `default_col`, `default_row`: pre-select categorical dropdowns (default: nothing = "(none)")
- `default_mark`: pre-select mark type (default: "point")
- `default_indep_x`, `default_indep_y`: pre-check independent axis checkboxes (default: false)
- `default_log_x`, `default_log_y`: pre-check log scale checkboxes (default: false)
- `default_filter_include`: initial filter pill selection for categorical columns. Accepts three
  forms: a `Dict` of lists (`Dict("col" => ["val1", "val2"])`) to select specific values, a `Dict`
  of functions (`Dict("col" => v -> v != "x")`) to select values matching a predicate, or a global
  callback `(col, val) -> Bool` applied to every categorical column. Default: `nothing` (all values
  selected).
- `marks`: list of `value => label` pairs for the mark dropdown (default: `_default_marks()`)
"""
function explorer_controls_html(datasets_or_table; default_ds="penguins", onchange_fn="explorerUpdate()",
        default_x="bill_length", default_y="bill_depth", default_color=:species, default_group=nothing,
        default_col=nothing, default_row=nothing, default_mark="point",
        default_filter_include=nothing,
        default_indep_x=false, default_indep_y=false,
        default_log_x=false, default_log_y=false,
        marks=_default_marks())
    datasets = _wrap_datasets(datasets_or_table)
    ds_names = sort(collect(keys(datasets)))
    default_ds = default_ds in ds_names ? default_ds : first(ds_names)
    cols = classify_columns(datasets[default_ds])

    dx = something(default_x, first(cols.all))
    dy = something(default_y, cols.all[min(2, end)])

    ds_options = join(["<option value=\"$n\"$(n == default_ds ? " selected" : "")>$n</option>" for n in ds_names], "\n")
    all_options_x = join(["<option value=\"$c\"$(c == dx ? " selected" : "")>$c</option>" for c in cols.all], "\n")
    all_options_y = join(["<option value=\"$c\"$(c == dy ? " selected" : "")>$c</option>" for c in cols.all], "\n")

    function cat_options_html(default_val)
        opts = "<option value=\"\">(none)</option>"
        for c in cols.categorical
            sel = (!isnothing(default_val) && c == string(default_val)) ? " selected" : ""
            opts *= "<option value=\"$c\"$sel>$c</option>"
        end
        opts
    end

    mark_options = join(["<option value=\"$(first(m))\"$(first(m) == default_mark ? " selected" : "")>$(last(m))</option>" for m in marks], "\n")

    hide_ds = length(ds_names) == 1
    ds_label_class = hide_ds ? "u-hidden" : "u-stack-tight"
    ribbon_class = default_mark == "line+ribbon" ? "u-stack-tight" : "u-hidden"

    """
<div id="explorer-controls" class="u-flex-wide u-flex-wrap u-mb-2">
  <label class="$ds_label_class">Dataset:
    <select id="ex-dataset" onchange="_explorerUpdateDropdowns(); $onchange_fn">$ds_options</select>
  </label>
  <label class="u-stack-tight">X:
    <select id="ex-x" onchange="$onchange_fn">$all_options_x</select>
  </label>
  <label class="u-stack-tight">Y:
    <select id="ex-y" onchange="$onchange_fn">$all_options_y</select>
  </label>
  <label class="u-stack-tight">Color:
    <select id="ex-color" onchange="$onchange_fn">$(cat_options_html(default_color))</select>
  </label>
  <label class="u-stack-tight">Group:
    <select id="ex-group" onchange="$onchange_fn">$(cat_options_html(default_group))</select>
  </label>
  <label class="u-stack-tight">Facet Column:
    <select id="ex-col" onchange="$onchange_fn">$(cat_options_html(default_col))</select>
  </label>
  <label class="u-stack-tight">Facet Row:
    <select id="ex-row" onchange="$onchange_fn">$(cat_options_html(default_row))</select>
  </label>
  <label class="u-stack-tight">Mark:
    <select id="ex-mark" onchange="$onchange_fn">
      $mark_options
    </select>
  </label>
  <label class="u-flex-tight">
    <input type="checkbox" id="ex-indep-x" onchange="$onchange_fn"$(default_indep_x ? " checked" : "")> Independent X
  </label>
  <label class="u-flex-tight">
    <input type="checkbox" id="ex-indep-y" onchange="$onchange_fn"$(default_indep_y ? " checked" : "")> Independent Y
  </label>
  <label class="u-flex-tight">
    <input type="checkbox" id="ex-log-x" onchange="$onchange_fn"$(default_log_x ? " checked" : "")> Log X
  </label>
  <label class="u-flex-tight">
    <input type="checkbox" id="ex-log-y" onchange="$onchange_fn"$(default_log_y ? " checked" : "")> Log Y
  </label>
  <label id="ex-ribbon-levels-label" class="$ribbon_class">Ribbon levels:
    <input type="text" id="ex-ribbon-levels" value="0.5, 0.9" onchange="$onchange_fn" class="aov-w-8">
  </label>
</div>
<div id="ex-filter-pills" class="u-flex u-flex-wrap u-mb-2"></div>
<div id="explorer-plot" class="aov-plot-area"></div>"""
end

"""
    explorer_widget(datasets_or_table; kwargs...)

Return an HTMX Node for the explorer widget (for web apps using HTMXObjects).

Accepts either a `Dict{String => table}` of named datasets or a bare table (auto-wrapped as
`Dict("data" => table)` with the dataset dropdown hidden).

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type, plus checkboxes for independent X/Y axes and log X/Y scale.
When mark is "line+ribbon", a "Ribbon levels" text input appears for tuning quantile bands.

# Keyword arguments
- `default_ds`: which dataset to pre-select (auto-falls back to first available key)
- `title`: heading text, or `nothing` to hide (default: `nothing`)
- `subtitle`: description text, or `nothing` to hide (default: `nothing`)
- `default_x`, `default_y`: pre-select x/y columns (default: nothing = first/second column)
- `default_color`, `default_group`, `default_col`, `default_row`: pre-select categorical dropdowns (default: nothing = "(none)")
- `default_mark`: pre-select mark type (default: "point")
- `default_indep_x`, `default_indep_y`: pre-check independent axis checkboxes (default: false)
- `default_log_x`, `default_log_y`: pre-check log scale checkboxes (default: false)
- `width`: plot width for non-faceted specs — integer or "container" (default: "container")
- `height`: plot height for non-faceted specs (default: 350)
- `default_filter_include`: initial filter pill selection for categorical columns. Accepts three
  forms: a `Dict` of lists (`Dict("col" => ["val1", "val2"])`) to select specific values, a `Dict`
  of functions (`Dict("col" => v -> v != "x")`) to select values matching a predicate, or a global
  callback `(col, val) -> Bool` applied to every categorical column. Default: `nothing` (all values
  selected).
- `marks`: list of `value => label` pairs for the mark dropdown (default: `_default_marks()`)
- `show_spec`: whether to show the Vega-Lite JSON spec details section (default: false)

Faceted specs use responsive cell widths derived from the container's `clientWidth`
rather than a fixed size. See [`explorer_js`](@ref) for details.
"""
function explorer_widget(datasets_or_table; default_ds="penguins",
        title=nothing,
        subtitle=nothing,
        default_x="bill_length", default_y="bill_depth", default_color=:species, default_group=nothing,
        default_col=nothing, default_row=nothing, default_mark="point",
        default_filter_include=nothing,
        default_indep_x=false, default_indep_y=false,
        default_log_x=false, default_log_y=false,
        width="container", height=350,
        marks=_default_marks(), show_spec=false)
    datasets = _wrap_datasets(datasets_or_table)
    ds_names = sort(collect(keys(datasets)))
    default_ds = default_ds in ds_names ? default_ds : first(ds_names)
    cols = classify_columns(datasets[default_ds])
    hide_ds = length(ds_names) == 1

    dx = something(default_x, first(cols.all))
    dy = something(default_y, cols.all[min(2, end)])

    function cat_select(id, default_val)
        h.select(; id=id, onchange="AoV.explorerUpdate()")(
            h.option("(none)"; value=""),
            [h.option(c; value=c, selected=(!isnothing(default_val) && c == string(default_val)) ? "selected" : nothing) for c in cols.categorical]...
        )
    end

    spec_selector = show_spec ? "#explorer-spec-json" : nothing

    h.div(
        # Title / subtitle
        isnothing(title) ? "" : h.h1(title),
        isnothing(subtitle) ? "" : h.p(subtitle),

        # Controls
        h.div(; id="explorer-controls", class="u-flex-wide u-flex-wrap u-mb-2")(
            h.label("Dataset: ",
                h.select(; id="ex-dataset", onchange="AoV.explorerUpdate()")(
                    [h.option(n; value=n, selected=(n == default_ds) ? "selected" : nothing) for n in ds_names]...
                ); class=hide_ds ? "u-hidden" : "u-stack-tight",
            ),
            h.label("X: ",
                h.select(; id="ex-x", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c, selected=(c == dx) ? "selected" : nothing) for c in cols.all]...
                ); class="u-stack-tight",
            ),
            h.label("Y: ",
                h.select(; id="ex-y", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c, selected=(c == dy) ? "selected" : nothing) for c in cols.all]...
                ); class="u-stack-tight",
            ),
            h.label("Color: ", cat_select("ex-color", default_color); class="u-stack-tight"),
            h.label("Group: ", cat_select("ex-group", default_group); class="u-stack-tight"),
            h.label("Facet Column: ", cat_select("ex-col", default_col); class="u-stack-tight"),
            h.label("Facet Row: ", cat_select("ex-row", default_row); class="u-stack-tight"),
            h.label("Mark: ",
                h.select(; id="ex-mark", onchange="AoV.explorerUpdate()")(
                    [h.option(last(m); value=first(m), selected=(first(m) == default_mark) ? "selected" : nothing) for m in marks]...
                ); class="u-stack-tight",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-indep-x", onchange="AoV.explorerUpdate()",
                    checked=default_indep_x ? "checked" : nothing),
                " Independent X";
                class="u-flex-tight",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-indep-y", onchange="AoV.explorerUpdate()",
                    checked=default_indep_y ? "checked" : nothing),
                " Independent Y";
                class="u-flex-tight",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-log-x", onchange="AoV.explorerUpdate()",
                    checked=default_log_x ? "checked" : nothing),
                " Log X";
                class="u-flex-tight",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-log-y", onchange="AoV.explorerUpdate()",
                    checked=default_log_y ? "checked" : nothing),
                " Log Y";
                class="u-flex-tight",
            ),
            h.label("Ribbon levels: ",
                h.input(; type="text", id="ex-ribbon-levels", value="0.5, 0.9",
                    onchange="AoV.explorerUpdate()", class="aov-w-8");
                id="ex-ribbon-levels-label",
                class=default_mark == "line+ribbon" ? "u-stack-tight" : "u-hidden",
            ),
        ),

        # Filter pills
        h.div(; id="ex-filter-pills", class="u-flex u-flex-wrap u-mb-2"),

        # Plot container
        h.div(; id="explorer-plot", class="aov-plot-area"),

        # Generated spec viewer (conditional)
        show_spec ? h.details(; class="u-mt-4")(
            h.summary("Vega-Lite JSON Spec"),
            h.pre(; id="explorer-spec-json", class="u-code-block u-scroll-y-lg"),
        ) : "",

        # Inline script with data + logic
        h.script(
            explorer_data_init_js(datasets; namespace="AoV.") *
            explorer_js(; namespace="AoV.", plot_selector="#explorer-plot", spec_selector=spec_selector, width=width, height=height) *
            _filter_init_js(_resolve_filter_include(default_filter_include, datasets[default_ds]), "AoV.") * """

            document.getElementById('ex-dataset').addEventListener('change', function() {
                AoV._explorerUpdateDropdowns();
                AoV.explorerUpdate();
            });

            AoV.explorerUpdate();
            """
        ),
    )
end

"""
    write_explorer_assets(dir, datasets_or_table; width="container", height=350)

Write explorer JSON data and JS files to `dir` for static sites (VitePress docs).
Creates `explorer-data.json`, `explorer-columns.json`, and `explorer.js`.

Accepts either a `Dict{String => table}` of named datasets or a bare table.

- `width`: plot width for non-faceted specs (integer or "container")
- `height`: plot height for non-faceted specs

Faceted specs use responsive cell widths derived from the container's `clientWidth`
rather than a fixed size. See [`explorer_js`](@ref) for details.
"""
function write_explorer_assets(dir, datasets_or_table; width="container", height=350)
    datasets = _wrap_datasets(datasets_or_table)
    mkpath(dir)
    ds_names = sort(collect(keys(datasets)))

    # Write data JSON
    ds_dict = Dict(name => table_to_rows(datasets[name]) for name in ds_names)
    write(joinpath(dir, "explorer-data.json"), JSON.json(ds_dict))

    # Write columns JSON
    col_dict = Dict(name => Dict(
        "all" => collect(classify_columns(datasets[name]).all),
        "numeric" => classify_columns(datasets[name]).numeric,
        "categorical" => classify_columns(datasets[name]).categorical,
    ) for name in ds_names)
    write(joinpath(dir, "explorer-columns.json"), JSON.json(col_dict))

    js_width = _js_width(width)

    # Write explorer.js (self-contained IIFE that fetches data)
    write(joinpath(dir, "explorer.js"), """
(function() {
  if (typeof document === 'undefined') return;
  var _explorerDatasets, _explorerColumns;
  var _explorerFilterSelected = {};

  function init() {
    var scripts = document.querySelectorAll('script[src*="explorer.js"]');
    var base = '';
    if (scripts.length > 0) {
      var src = scripts[scripts.length - 1].src;
      base = src.substring(0, src.lastIndexOf('/'));
    }
    Promise.all([
      fetch(base + '/explorer-data.json'),
      fetch(base + '/explorer-columns.json'),
    ]).then(function(responses) {
      return Promise.all(responses.map(function(r) { return r.json(); }));
    }).then(function(data) {
      _explorerDatasets = data[0];
      _explorerColumns = data[1];
      explorerUpdate();
    });
  }

  window._explorerUpdateFilterPills = function(activeCols, data) {
    var container = document.getElementById('ex-filter-pills');
    if (!container) return;
    container.innerHTML = '';
    if (!activeCols || activeCols.length === 0 || !data) return;
    var stored = _explorerFilterSelected;
    activeCols.forEach(function(col) {
      var unique = {};
      for (var i = 0; i < data.length; i++) {
        var v = data[i][col];
        if (v !== null && v !== undefined) unique[String(v)] = true;
      }
      var values = Object.keys(unique).sort();
      if (!stored[col]) {
        stored[col] = new Set(values);
      }
      var row = document.createElement('div');
      row.style.cssText = 'display:flex; flex-wrap:wrap; align-items:center; gap:0.3rem; margin-bottom:0.25rem;';
      var label = document.createElement('strong');
      label.textContent = col + ': ';
      label.style.cssText = 'font-size:0.85rem; min-width:5rem;';
      row.appendChild(label);
      values.forEach(function(v) {
        var pill = document.createElement('button');
        pill.type = 'button';
        pill.textContent = v;
        var sel = stored[col].has(v);
        pill.style.cssText = 'border:1px solid var(--pico-primary);border-radius:1rem;padding:0.15rem 0.6rem;cursor:pointer;font-size:0.85rem;' +
          (sel ? 'background:var(--pico-primary);color:var(--pico-primary-inverse);' : 'background:transparent;color:var(--pico-primary);');
        pill.onclick = function(e) {
          if (e.ctrlKey || e.metaKey) {
            stored[col] = new Set([v]);
          } else {
            if (stored[col].has(v)) stored[col].delete(v);
            else stored[col].add(v);
          }
          explorerUpdate();
        };
        row.appendChild(pill);
      });
      container.appendChild(row);
    });
  };

  window._explorerUpdateDropdowns = function() {
    var ds = document.getElementById('ex-dataset').value;
    var cols = _explorerColumns[ds];
    var allCols = cols.all;
    var catCols = cols.categorical;
    ['ex-x', 'ex-y'].forEach(function(id) {
      var sel = document.getElementById(id);
      var prev = sel.value;
      sel.innerHTML = '';
      allCols.forEach(function(c) {
        var opt = document.createElement('option');
        opt.value = c; opt.textContent = c;
        sel.appendChild(opt);
      });
      if (allCols.indexOf(prev) >= 0) sel.value = prev;
      else if (id === 'ex-y' && allCols.length > 1) sel.value = allCols[1];
    });
    ['ex-color', 'ex-group', 'ex-col', 'ex-row'].forEach(function(id) {
      var sel = document.getElementById(id);
      if (!sel) return;
      var prev = sel.value;
      sel.innerHTML = '<option value="">(none)</option>';
      catCols.forEach(function(c) {
        var opt = document.createElement('option');
        opt.value = c; opt.textContent = c;
        sel.appendChild(opt);
      });
      if (catCols.indexOf(prev) >= 0) sel.value = prev;
      else sel.value = '';
    });
  };

  window.explorerUpdate = function() {
    if (!_explorerDatasets) return;
    var ds = document.getElementById('ex-dataset').value;
    var x = document.getElementById('ex-x').value;
    var y = document.getElementById('ex-y').value;
    var color = (document.getElementById('ex-color') || {}).value || '';
    var group = (document.getElementById('ex-group') || {}).value || '';
    var facetCol = (document.getElementById('ex-col') || {}).value || '';
    var facetRow = (document.getElementById('ex-row') || {}).value || '';
    var mark = (document.getElementById('ex-mark') || {}).value || 'point';
    var rawData = _explorerDatasets[ds];
    var activeCatCols = [];
    [color, group, facetCol, facetRow].forEach(function(c) {
      if (c && activeCatCols.indexOf(c) < 0) activeCatCols.push(c);
    });
    _explorerUpdateFilterPills(activeCatCols, rawData);
    var data = rawData;
    var stored = _explorerFilterSelected;
    activeCatCols.forEach(function(col) {
      if (stored[col] && stored[col].size > 0) {
        data = data.filter(function(row) { return stored[col].has(String(row[col])); });
      }
    });
    function fieldType(field) {
      for (var i = 0; i < data.length; i++) {
        var v = data[i][field];
        if (v !== null && v !== undefined) return typeof v === 'number' ? 'quantitative' : 'nominal';
      }
      return 'nominal';
    }
    var xType = fieldType(x), yType = fieldType(y);
    var zeroX = xType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
    var zeroY = yType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
    var encoding = {
      x: {field: x, type: xType, scale: zeroX},
      y: {field: y, type: yType, scale: zeroY},
      tooltip: [{field: x, type: xType}, {field: y, type: yType}],
    };
    if (color) {
      encoding.color = {field: color, type: 'nominal'};
      encoding.tooltip.push({field: color, type: 'nominal'});
    }
    if (group) {
      encoding.detail = {field: group, type: 'nominal'};
    }
    var indepX = document.getElementById('ex-indep-x') && document.getElementById('ex-indep-x').checked;
    var indepY = document.getElementById('ex-indep-y') && document.getElementById('ex-indep-y').checked;
    var logX = document.getElementById('ex-log-x') && document.getElementById('ex-log-x').checked;
    var logY = document.getElementById('ex-log-y') && document.getElementById('ex-log-y').checked;
    if (logX && xType === 'quantitative') { encoding.x.scale = Object.assign({}, encoding.x.scale, {type: 'log'}); }
    if (logY && yType === 'quantitative') { encoding.y.scale = Object.assign({}, encoding.y.scale, {type: 'log'}); }
    var ribbonEl = document.getElementById('ex-ribbon-levels-label');
    if (ribbonEl) ribbonEl.style.display = (mark === 'line+ribbon') ? '' : 'none';
    var spec;
    if (mark === 'line+ribbon') {
      var levelsStr = document.getElementById('ex-ribbon-levels') ? document.getElementById('ex-ribbon-levels').value : '0.5, 0.9';
      var levels = levelsStr.split(',').map(function(s) { return parseFloat(s.trim()); }).filter(function(v) { return v > 0 && v < 1; }).sort();
      var groups = {};
      for (var i = 0; i < data.length; i++) {
        var row = data[i];
        var key = color ? row[x] + '|||' + row[color] : String(row[x]);
        if (!groups[key]) groups[key] = {xv: row[x], cv: color ? row[color] : null, ys: []};
        var yVal = parseFloat(row[y]);
        if (!isNaN(yVal)) groups[key].ys.push(yVal);
      }
      function _quantile(sorted, p) {
        if (sorted.length === 0) return null;
        var idx = p * (sorted.length - 1);
        var lo = Math.floor(idx), hi = Math.ceil(idx);
        if (lo === hi) return sorted[lo];
        return sorted[lo] + (idx - lo) * (sorted[hi] - sorted[lo]);
      }
      var summaryData = [];
      Object.keys(groups).forEach(function(key) {
        var g = groups[key];
        g.ys.sort(function(a, b) { return a - b; });
        var sr = {_x: g.xv, _median: _quantile(g.ys, 0.5)};
        if (g.cv !== null) sr._color = g.cv;
        levels.forEach(function(p) {
          var lo = (1 - p) / 2, hi = 1 - lo;
          sr['_lo_' + p] = _quantile(g.ys, lo);
          sr['_hi_' + p] = _quantile(g.ys, hi);
        });
        summaryData.push(sr);
      });
      var layers = [];
      var opStep = levels.length > 1 ? 0.4 / (levels.length - 1) : 0;
      for (var li = levels.length - 1; li >= 0; li--) {
        var p = levels[li];
        var bandEnc = {
          x: {field: '_x', type: xType, scale: encoding.x.scale},
          y: {field: '_lo_' + p, type: 'quantitative', scale: encoding.y.scale, title: y},
          y2: {field: '_hi_' + p},
        };
        if (color) bandEnc.color = {field: '_color', type: 'nominal', title: color};
        layers.push({mark: {type: 'area', opacity: 0.15 + opStep * li}, encoding: bandEnc});
      }
      var lineEnc = {
        x: {field: '_x', type: xType, scale: encoding.x.scale, title: x},
        y: {field: '_median', type: 'quantitative', scale: encoding.y.scale, title: y},
        tooltip: [{field: '_x', type: xType, title: x}, {field: '_median', type: 'quantitative', title: 'median'}],
      };
      if (color) {
        lineEnc.color = {field: '_color', type: 'nominal', title: color};
        lineEnc.tooltip.push({field: '_color', type: 'nominal', title: color});
      }
      layers.push({mark: 'line', encoding: lineEnc});
      if (facetCol || facetRow) {
        var facet = {};
        if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
        if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
        var plotEl = document.querySelector('#explorer-plot');
        var availWidth = plotEl ? plotEl.clientWidth : 800;
        var cellWidth = 250;
        if (facetCol) {
          var uniqueCols = {};
          for (var i = 0; i < summaryData.length; i++) { uniqueCols[summaryData[i][facetCol]] = true; }
          var nCols = Object.keys(uniqueCols).length;
          if (nCols > 0) cellWidth = Math.max(100, Math.floor((availWidth - 60) / nCols));
        } else {
          cellWidth = Math.max(250, availWidth - 60);
        }
        spec = {data: {values: summaryData}, facet: facet, spec: {layer: layers, width: cellWidth, height: 200}};
        if (indepX || indepY) {
          var resolve = {scale: {}, axis: {}};
          if (indepX) { resolve.scale.x = 'independent'; resolve.axis.x = 'independent'; }
          if (indepY) { resolve.scale.y = 'independent'; resolve.axis.y = 'independent'; }
          spec.resolve = resolve;
        }
      } else {
        spec = {data: {values: summaryData}, layer: layers, width: $js_width, height: $height};
      }
    } else if (facetCol || facetRow) {
      var facet = {};
      if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
      if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
      var plotEl = document.querySelector('#explorer-plot');
      var availWidth = plotEl ? plotEl.clientWidth : 800;
      var cellWidth = 250;
      if (facetCol) {
        var uniqueCols = {};
        for (var i = 0; i < data.length; i++) { uniqueCols[data[i][facetCol]] = true; }
        var nCols = Object.keys(uniqueCols).length;
        if (nCols > 0) cellWidth = Math.max(100, Math.floor((availWidth - 60) / nCols));
      } else {
        cellWidth = Math.max(250, availWidth - 60);
      }
      spec = {data: {values: data}, facet: facet, spec: {mark: mark, encoding: encoding, width: cellWidth, height: 200}};
      if (indepX || indepY) {
        var resolve = {scale: {}, axis: {}};
        if (indepX) { resolve.scale.x = 'independent'; resolve.axis.x = 'independent'; }
        if (indepY) { resolve.scale.y = 'independent'; resolve.axis.y = 'independent'; }
        spec.resolve = resolve;
      }
    } else {
      spec = {data: {values: data}, mark: mark, encoding: encoding, width: $js_width, height: $height};
    }
    function doEmbed() {
      vegaEmbed('#explorer-plot', spec, {actions: false}).catch(console.error);
    }
    if (typeof vegaEmbed !== 'undefined') { doEmbed(); }
    else {
      var check = setInterval(function() {
        if (typeof vegaEmbed !== 'undefined') { clearInterval(check); doEmbed(); }
      }, 100);
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
""")
    println("  wrote explorer assets to $dir")
end

# Bare table convenience methods — auto-wrap as Dict("data" => table)

"""
    _wrap_datasets(datasets) -> Dict

If `datasets` is already a Dict, return as-is. Otherwise, wrap a bare table as `Dict("data" => table)`.
"""
_wrap_datasets(datasets::AbstractDict) = datasets
function _wrap_datasets(table)
    Tables.istable(table) || throw(ArgumentError("expected a Dict of datasets or a Tables.jl-compatible table, got $(typeof(table))"))
    Dict("data" => table)
end
