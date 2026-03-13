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

"""
    explorer_js(; namespace="", plot_selector="#explorer-plot", spec_selector=nothing)

Return a String of JS code that implements the explorer widget logic.

Generates two JS functions: `_explorerUpdateDropdowns` (repopulates dropdown options
when the dataset changes) and `explorerUpdate` (builds and renders the Vega-Lite spec).

Dropdowns: dataset, x, y, color, group (detail encoding), facet column, facet row, mark type.
The group dropdown maps to Vega-Lite's `detail` encoding channel, which groups data
(e.g. draws separate lines per group) without assigning a visual property like color.

- `namespace`: JS namespace prefix for functions (e.g. "AoV." for web app, "" for standalone)
- `plot_selector`: CSS selector for the plot container
- `spec_selector`: CSS selector for spec JSON display (nothing to skip)
"""
function explorer_js(; namespace="", plot_selector="#explorer-plot", spec_selector=nothing)
    spec_line = isnothing(spec_selector) ? "" : """
                document.querySelector('$spec_selector').textContent = JSON.stringify(spec, null, 2);"""
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

                var encoding = {
                    x: {field: x, type: fieldType(x)},
                    y: {field: y, type: fieldType(y)},
                    tooltip: [{field: x, type: fieldType(x)}, {field: y, type: fieldType(y)}],
                };

                if (color) {
                    encoding.color = {field: color, type: 'nominal'};
                    encoding.tooltip.push({field: color, type: 'nominal'});
                }

                if (group) {
                    encoding.detail = {field: group, type: 'nominal'};
                }

                var spec;
                if (facetCol || facetRow) {
                    var facet = {};
                    if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
                    if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
                    spec = {
                        data: {values: data},
                        facet: facet,
                        spec: {mark: mark, encoding: encoding, width: 250, height: 200},
                    };
                } else {
                    spec = {
                        data: {values: data},
                        mark: mark,
                        encoding: encoding,
                        width: $(plot_selector == "#explorer-plot" ? "600" : "'container'"),
                        height: 350,
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
    explorer_controls_html(datasets; default_ds="cars", onchange_fn="explorerUpdate()")

Return an HTML string for the explorer dropdown controls.

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type.
Datasets can be any Tables.jl-compatible type (NamedTuples, DataFrames, etc.).
"""
function explorer_controls_html(datasets; default_ds="cars", onchange_fn="explorerUpdate()")
    ds_names = sort(collect(keys(datasets)))
    cols = classify_columns(datasets[default_ds])

    ds_options = join(["<option value=\"$n\">$n</option>" for n in ds_names], "\n")
    all_options = join(["<option value=\"$c\">$c</option>" for c in cols.all], "\n")
    all_options_y = join(["<option value=\"$c\"$(c == cols.all[min(2,end)] ? " selected" : "")>$c</option>" for c in cols.all], "\n")
    cat_options = join(["<option value=\"$c\">$c</option>" for c in cols.categorical], "\n")

    """
<div id="explorer-controls" style="display:flex; flex-wrap:wrap; gap:1rem; margin-bottom:1rem; align-items:end;">
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Dataset:
    <select id="ex-dataset" onchange="_explorerUpdateDropdowns(); $onchange_fn">$ds_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">X:
    <select id="ex-x" onchange="$onchange_fn">$all_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Y:
    <select id="ex-y" onchange="$onchange_fn">$all_options_y</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Color:
    <select id="ex-color" onchange="$onchange_fn"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Group:
    <select id="ex-group" onchange="$onchange_fn"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Column:
    <select id="ex-col" onchange="$onchange_fn"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Row:
    <select id="ex-row" onchange="$onchange_fn"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Mark:
    <select id="ex-mark" onchange="$onchange_fn">
      <option value="point">point</option>
      <option value="bar">bar</option>
      <option value="line">line</option>
      <option value="area">area</option>
      <option value="boxplot">boxplot</option>
      <option value="rect">rect (heatmap)</option>
    </select>
  </label>
</div>
<div id="explorer-plot" style="width:100%; min-width:0;"></div>"""
end

"""
    explorer_widget(datasets; default_ds="cars")

Return an HTMX Node for the explorer widget (for web apps using HTMXObjects).

Includes dropdowns for: dataset, x, y, color, group (detail encoding),
facet column, facet row, and mark type.
Datasets can be any Tables.jl-compatible type (NamedTuples, DataFrames, etc.).
"""
function explorer_widget(datasets; default_ds="cars")
    ds_names = sort(collect(keys(datasets)))
    cols = classify_columns(datasets[default_ds])

    h.div(
        h.h1("Data Explorer"),
        h.p("Build faceted plots interactively — all client-side, no server round-trips."),

        # Controls
        h.div(; id="explorer-controls", style="display:flex; flex-wrap:wrap; gap:1rem; margin-bottom:1rem; align-items:end;")(
            h.label("Dataset: ",
                h.select(; id="ex-dataset", onchange="AoV.explorerUpdate()")(
                    [h.option(n; value=n, selected=(n == default_ds) ? "selected" : nothing) for n in ds_names]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("X: ",
                h.select(; id="ex-x", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c) for c in cols.all]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Y: ",
                h.select(; id="ex-y", onchange="AoV.explorerUpdate()")(
                    [h.option(c; value=c, selected=(c == cols.all[min(2,end)]) ? "selected" : nothing) for c in cols.all]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Color: ",
                h.select(; id="ex-color", onchange="AoV.explorerUpdate()")(
                    h.option("(none)"; value=""),
                    [h.option(c; value=c) for c in cols.categorical]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Group: ",
                h.select(; id="ex-group", onchange="AoV.explorerUpdate()")(
                    h.option("(none)"; value=""),
                    [h.option(c; value=c) for c in cols.categorical]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Facet Column: ",
                h.select(; id="ex-col", onchange="AoV.explorerUpdate()")(
                    h.option("(none)"; value=""),
                    [h.option(c; value=c) for c in cols.categorical]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Facet Row: ",
                h.select(; id="ex-row", onchange="AoV.explorerUpdate()")(
                    h.option("(none)"; value=""),
                    [h.option(c; value=c) for c in cols.categorical]...
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
            h.label("Mark: ",
                h.select(; id="ex-mark", onchange="AoV.explorerUpdate()")(
                    h.option("point"; value="point"),
                    h.option("bar"; value="bar"),
                    h.option("line"; value="line"),
                    h.option("area"; value="area"),
                    h.option("boxplot"; value="boxplot"),
                    h.option("rect (heatmap)"; value="rect"),
                ); style="display:flex; flex-direction:column; gap:0.25rem;",
            ),
        ),

        # Plot container
        h.div(; id="explorer-plot", style="width:100%; min-width:0;"),

        # Generated spec viewer
        h.details(; style="margin-top:1rem")(
            h.summary("Vega-Lite JSON Spec"),
            h.pre(; id="explorer-spec-json", style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto; max-height:400px;"),
        ),

        # Inline script with data + logic
        h.script(
            explorer_data_init_js(datasets; namespace="AoV.") *
            explorer_js(; namespace="AoV.", plot_selector="#explorer-plot", spec_selector="#explorer-spec-json") * """

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
    write_explorer_assets(dir, datasets)

Write explorer JSON data and JS files to `dir` for static sites (VitePress docs).
Creates `explorer-data.json`, `explorer-columns.json`, and `explorer.js`.
"""
function write_explorer_assets(dir, datasets)
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

    # Write explorer.js (self-contained IIFE that fetches data)
    js_logic = explorer_js(; namespace="", plot_selector="#explorer-plot")
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
    var encoding = {
      x: {field: x, type: fieldType(x)},
      y: {field: y, type: fieldType(y)},
      tooltip: [{field: x, type: fieldType(x)}, {field: y, type: fieldType(y)}],
    };
    if (color) {
      encoding.color = {field: color, type: 'nominal'};
      encoding.tooltip.push({field: color, type: 'nominal'});
    }
    if (group) {
      encoding.detail = {field: group, type: 'nominal'};
    }
    var spec;
    if (facetCol || facetRow) {
      var facet = {};
      if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
      if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
      spec = {data: {values: data}, facet: facet, spec: {mark: mark, encoding: encoding, width: 250, height: 200}};
    } else {
      spec = {data: {values: data}, mark: mark, encoding: encoding, width: 600, height: 350};
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
