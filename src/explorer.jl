# Reusable data explorer widget and utilities

"""
    default_explorer_datasets()

Return a Dict of default datasets for the explorer widget.
"""
default_explorer_datasets() = Dict(
    "cars" => sample_cars(),
    "tips" => sample_tips(),
    "stocks" => sample_stocks(),
    "temperatures" => sample_temperatures(),
)

_default_marks() = [
    "point" => "point",
    "bar" => "bar",
    "line" => "line",
    "area" => "area",
    "boxplot" => "boxplot",
    "rect" => "rect (heatmap)",
]

"""
    explorer_js(; namespace="", plot_selector="#explorer-plot", spec_selector=nothing, width="container", height=350)

Return a String of JS code that implements the explorer widget logic.

Generates two JS functions: `_explorerUpdateDropdowns` (repopulates dropdown options
when the dataset changes) and `explorerUpdate` (builds and renders the Vega-Lite spec).

Dropdowns: dataset, x, y, color, group (detail encoding), facet column, facet row, mark type.
Checkboxes: independent X/Y axis (adds VL `resolve` for faceted specs).
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
    js_width = width isa Integer ? string(width) : "'$width'"
    """
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
                var data = $(namespace)_explorerDatasets[ds];

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

                var spec;
                if (facetCol || facetRow) {
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
    explorer_controls_html(datasets; default_ds="cars", onchange_fn="explorerUpdate()", kwargs...)

Return an HTML string for the explorer dropdown controls.

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type, plus checkboxes for independent X/Y axes.
Datasets can be any Tables.jl-compatible type (NamedTuples, DataFrames, etc.).

# Keyword arguments
- `default_ds`: which dataset to pre-select
- `onchange_fn`: JS function to call on dropdown change
- `default_x`, `default_y`: pre-select x/y columns (default: first and second column)
- `default_color`, `default_group`, `default_col`, `default_row`: pre-select categorical dropdowns (default: nothing = "(none)")
- `default_mark`: pre-select mark type (default: "point")
- `marks`: list of `value => label` pairs for the mark dropdown (default: `_default_marks()`)
"""
function explorer_controls_html(datasets; default_ds="cars", onchange_fn="explorerUpdate()",
        default_x=nothing, default_y=nothing, default_color=nothing, default_group=nothing,
        default_col=nothing, default_row=nothing, default_mark="point",
        default_indep_x=false, default_indep_y=false,
        marks=_default_marks())
    ds_names = sort(collect(keys(datasets)))
    cols = classify_columns(datasets[default_ds])

    dx = something(default_x, first(cols.all))
    dy = something(default_y, cols.all[min(2, end)])

    ds_options = join(["<option value=\"$n\">$n</option>" for n in ds_names], "\n")
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

    """
<div id="explorer-controls" style="display:flex; flex-wrap:wrap; gap:1rem; margin-bottom:1rem; align-items:end;">
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Dataset:
    <select id="ex-dataset" onchange="_explorerUpdateDropdowns(); $onchange_fn">$ds_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">X:
    <select id="ex-x" onchange="$onchange_fn">$all_options_x</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Y:
    <select id="ex-y" onchange="$onchange_fn">$all_options_y</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Color:
    <select id="ex-color" onchange="$onchange_fn">$(cat_options_html(default_color))</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Group:
    <select id="ex-group" onchange="$onchange_fn">$(cat_options_html(default_group))</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Column:
    <select id="ex-col" onchange="$onchange_fn">$(cat_options_html(default_col))</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Row:
    <select id="ex-row" onchange="$onchange_fn">$(cat_options_html(default_row))</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Mark:
    <select id="ex-mark" onchange="$onchange_fn">
      $mark_options
    </select>
  </label>
  <label style="display:flex; align-items:center; gap:0.25rem;">
    <input type="checkbox" id="ex-indep-x" onchange="$onchange_fn"$(default_indep_x ? " checked" : "")> Independent X
  </label>
  <label style="display:flex; align-items:center; gap:0.25rem;">
    <input type="checkbox" id="ex-indep-y" onchange="$onchange_fn"$(default_indep_y ? " checked" : "")> Independent Y
  </label>
</div>
<div id="explorer-plot" style="width:100%; min-width:0;"></div>"""
end

"""
    explorer_widget(datasets; kwargs...)

Return an HTMX Node for the explorer widget (for web apps using HTMXObjects).

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type, plus checkboxes for independent X/Y axes.
Datasets can be any Tables.jl-compatible type (NamedTuples, DataFrames, etc.).

# Keyword arguments
- `default_ds`: which dataset to pre-select (default: "cars")
- `title`: heading text, or `nothing` to hide (default: `nothing`)
- `subtitle`: description text, or `nothing` to hide (default: `nothing`)
- `default_x`, `default_y`: pre-select x/y columns (default: nothing = first/second column)
- `default_color`, `default_group`, `default_col`, `default_row`: pre-select categorical dropdowns (default: nothing = "(none)")
- `default_mark`: pre-select mark type (default: "point")
- `width`: plot width for non-faceted specs — integer or "container" (default: "container")
- `height`: plot height for non-faceted specs (default: 350)
- `marks`: list of `value => label` pairs for the mark dropdown (default: `_default_marks()`)
- `show_spec`: whether to show the Vega-Lite JSON spec details section (default: false)

Faceted specs use responsive cell widths derived from the container's `clientWidth`
rather than a fixed size. See [`explorer_js`](@ref) for details.
"""
function explorer_widget(datasets; default_ds="cars",
        title=nothing,
        subtitle=nothing,
        default_x=nothing, default_y=nothing, default_color=nothing, default_group=nothing,
        default_col=nothing, default_row=nothing, default_mark="point",
        default_indep_x=false, default_indep_y=false,
        width="container", height=350,
        marks=_default_marks(), show_spec=false)
    ds_names = sort(collect(keys(datasets)))
    cols = classify_columns(datasets[default_ds])

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
        h.div(; id="explorer-controls", style="display:flex; flex-wrap:wrap; gap:1rem; margin-bottom:1rem; align-items:end;")(
            h.label("Dataset: ",
                h.select(; id="ex-dataset", onchange="AoV.explorerUpdate()")(
                    [h.option(n; value=n, selected=(n == default_ds) ? "selected" : nothing) for n in ds_names]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("X: ",
                h.select(; id="ex-x", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c, selected=(c == dx) ? "selected" : nothing) for c in cols.all]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Y: ",
                h.select(; id="ex-y", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c, selected=(c == dy) ? "selected" : nothing) for c in cols.all]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Color: ", cat_select("ex-color", default_color);
                style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Group: ", cat_select("ex-group", default_group);
                style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Facet Column: ", cat_select("ex-col", default_col);
                style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Facet Row: ", cat_select("ex-row", default_row);
                style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Mark: ",
                h.select(; id="ex-mark", onchange="AoV.explorerUpdate()")(
                    [h.option(last(m); value=first(m), selected=(first(m) == default_mark) ? "selected" : nothing) for m in marks]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-indep-x", onchange="AoV.explorerUpdate()",
                    checked=default_indep_x ? "checked" : nothing),
                " Independent X";
                style="display:flex; align-items:center; gap:0.25rem;",
            ),
            h.label(
                h.input(; type="checkbox", id="ex-indep-y", onchange="AoV.explorerUpdate()",
                    checked=default_indep_y ? "checked" : nothing),
                " Independent Y";
                style="display:flex; align-items:center; gap:0.25rem;",
            ),
        ),

        # Plot container
        h.div(; id="explorer-plot", style="width:100%; min-width:0;"),

        # Generated spec viewer (conditional)
        show_spec ? h.details(; style="margin-top:1rem")(
            h.summary("Vega-Lite JSON Spec"),
            h.pre(; id="explorer-spec-json", style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto; max-height:400px;"),
        ) : "",

        # Inline script with data + logic
        h.script(
            explorer_data_init_js(datasets; namespace="AoV.") *
            explorer_js(; namespace="AoV.", plot_selector="#explorer-plot", spec_selector=spec_selector, width=width, height=height) * """

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
    write_explorer_assets(dir, datasets; width="container", height=350)

Write explorer JSON data and JS files to `dir` for static sites (VitePress docs).
Creates `explorer-data.json`, `explorer-columns.json`, and `explorer.js`.

- `width`: plot width for non-faceted specs (integer or "container")
- `height`: plot height for non-faceted specs

Faceted specs use responsive cell widths derived from the container's `clientWidth`
rather than a fixed size. See [`explorer_js`](@ref) for details.
"""
function write_explorer_assets(dir, datasets; width="container", height=350)
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

    js_width = width isa Integer ? string(width) : "'$width'"

    # Write explorer.js (self-contained IIFE that fetches data)
    write(joinpath(dir, "explorer.js"), """
(function() {
  if (typeof document === 'undefined') return;
  var _explorerDatasets, _explorerColumns;

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
    var color = document.getElementById('ex-color').value;
    var group = document.getElementById('ex-group').value;
    var facetCol = document.getElementById('ex-col').value;
    var facetRow = document.getElementById('ex-row').value;
    var mark = document.getElementById('ex-mark').value;
    var data = _explorerDatasets[ds];
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
    var spec;
    if (facetCol || facetRow) {
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
