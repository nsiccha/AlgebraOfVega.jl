# Generate gallery-examples.md with inline Vega-Lite specs for VitePress docs
using AlgebraOfVega
using JSON

# --- Sample datasets (subset from web gallery) ---

cars() = (;
    horsepower = [130,165,150,150,140,198,220,215,225,190,170,160,150,225,95,95,97,85,88,46,87,90,95,113,90,215,200,210,193,88,90,95,100,105,100,88,100,165,175,153,150,180,170,175,110,72,100,88,86,90,70,76,65,69,60,70,95,80,54,90,86,110],
    mpg = [18,15,18,16,17,15,14,14,14,15,15,14,15,14,24,22,18,21,27,26,25,24,25,26,21,10,10,11,9,27,28,25,25,19,16,17,19,18,14,14,15,15,14,15,24,20,25,21,27,26,26,28,25,26,30,22,17,23,36,25,22,18],
    origin = ["USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","Europe","Europe","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","USA","USA","USA","Japan","Europe","Europe","Europe"],
    cylinders = [8,8,8,8,8,8,8,8,8,8,8,8,8,8,4,4,4,4,4,4,4,4,4,4,4,8,8,8,8,4,4,4,4,4,4,4,4,6,6,6,6,8,8,8,4,4,4,4,4,4,4,4,4,4,4,6,6,6,4,4,4,4],
    weight = [3504,3693,3436,3433,3449,4341,4354,4312,4425,3850,3563,3609,3761,3086,2372,2833,2774,2587,2130,1835,2672,2430,2375,2234,2648,4615,4376,4382,4732,2130,2264,2228,2046,2634,2702,2875,2901,3353,3169,2906,3380,3740,4080,3645,2585,2310,2472,2265,2110,2800,2110,2085,2245,1965,1755,2815,3210,3380,1760,2130,2205,2245],
)

tips() = (;
    total_bill = [16.99,10.34,21.01,23.68,24.59,25.29,8.77,26.88,15.04,14.78,10.27,35.26,15.42,18.43,14.83,21.58,10.33,16.29,16.97,20.65],
    tip = [1.01,1.66,3.50,3.31,3.61,4.71,2.0,3.12,1.96,3.23,1.71,5.0,1.57,3.0,1.44,3.5,1.7,3.31,3.5,3.35],
    sex = ["Female","Male","Male","Male","Female","Male","Male","Male","Male","Female","Male","Female","Male","Male","Female","Male","Male","Male","Male","Male"],
    day = ["Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun"],
    size = [2,3,3,2,4,4,2,4,2,2,2,4,2,2,2,2,3,3,3,3],
)

stocks() = let
    dates = ["2000-01-01","2000-02-01","2000-03-01","2000-04-01","2000-05-01","2000-06-01"]
    n = length(dates)
    (;
        date = repeat(dates, 3),
        price = [Float64[100,110,105,115,120,118]; Float64[80,85,90,88,92,95]; Float64[50,55,60,58,65,70]],
        symbol = [fill("AAPL", n); fill("GOOG", n); fill("MSFT", n)],
    )
end

temperatures() = (;
    month = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3),
    city = [fill("New York", 12); fill("London", 12); fill("Tokyo", 12)],
    temp = [
        0,1,5,12,18,24,27,26,22,15,8,3,
        5,5,7,10,13,16,19,18,15,11,8,5,
        5,6,9,15,19,23,27,28,24,18,12,7,
    ],
)

population() = (;
    category = ["0-14","15-24","25-54","55-64","65+"],
    male = [25,18,40,12,10],
    female = [24,17,38,13,14],
)

function melt_population(pop)
    n = length(pop.category)
    (;
        category = [pop.category; pop.category],
        count = [pop.male; pop.female],
        sex = [fill("Male", n); fill("Female", n)],
    )
end

function randn_bm(n)
    out = Float64[]
    while length(out) < n
        u1, u2 = rand(), rand()
        u1 == 0.0 && continue
        z0 = sqrt(-2 * log(u1)) * cos(2π * u2)
        z1 = sqrt(-2 * log(u1)) * sin(2π * u2)
        push!(out, z0, z1)
    end
    out[1:n]
end

function posterior_draws(; n=500)
    (;
        parameter = [fill("α", n); fill("β", n); fill("σ", n)],
        value = [2.0 .+ 0.5 .* randn_bm(n); 0.8 .+ 0.3 .* randn_bm(n); 1.2 .+ 0.2 .* abs.(randn_bm(n))],
        chain = [repeat(1:4, n÷4); repeat(1:4, n÷4); repeat(1:4, n÷4)],
    )
end

function regression_predictions(; n_x=50, n_draws=200)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    for d in 1:n_draws
        α = 2.0 + 0.5 * randn_bm(1)[1]
        β = 0.8 + 0.3 * randn_bm(1)[1]
        σ = 1.2 + 0.2 * abs(randn_bm(1)[1])
        for x in xs
            push!(rows_x, x)
            push!(rows_y, α + β * x + σ * randn_bm(1)[1])
            push!(rows_draw, d)
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw)
end

# --- Define curated examples ---
# Each: (id, title, description, code_string, spec_thunk)

EXAMPLES = [
    # Interactive Filtering
    ("filter_origin", "Filter by Origin", "Dropdown filters scatter plot by car origin — fully client-side",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(width=500, height=350, title="Cars: Filter by Origin",
           select=:origin)""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(width=500, height=350, title="Cars: Filter by Origin",
               select=:origin)),

    ("filter_multi", "Multi-Filter", "Two dropdowns: origin + cylinders",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(width=500, height=350, title="Cars: Multi-Filter",
           select=[:origin, :cylinders])""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(width=500, height=350, title="Cars: Multi-Filter",
               select=[:origin, :cylinders])),

    ("filter_regression", "Filtered Regression", "Scatter + linear fit updates with dropdown",
     """data(cars()) *
    mapping(:horsepower, :mpg) *
    (visual(Scatter, opacity=0.5) + linear()) *
    config(width=500, height=350, title="Regression by Origin",
           select=:origin)""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg) *
        (visual(Scatter, opacity=0.5) + linear()) *
        config(width=500, height=350, title="Regression by Origin",
               select=:origin)),

    # Basic
    ("scatter", "Scatter Plot", "Horsepower vs MPG colored by origin",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(width=500, height=350, title="Cars: Horsepower vs MPG")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(width=500, height=350, title="Cars: Horsepower vs MPG")),

    ("bar", "Bar Chart", "Average tip by gender",
     """data(tips()) *
    mapping(:sex, :tip) *
    visual(BarPlot) *
    config(width=400, height=300, title="Average Tip by Gender",
           encoding=Dict("y" => Dict("aggregate" => "mean")))""",
     () -> data(tips()) *
        mapping(:sex, :tip) *
        visual(BarPlot) *
        config(width=400, height=300, title="Average Tip by Gender",
               encoding=Dict("y" => Dict("aggregate" => "mean")))),

    ("line", "Line Chart", "Stock prices over time with points",
     """data(stocks()) *
    mapping(:date, :price, color=:symbol) *
    visual(ScatterLines) *
    config(width=500, height=350, title="Stock Prices Over Time")""",
     () -> data(stocks()) *
        mapping(:date, :price, color=:symbol) *
        visual(ScatterLines) *
        config(width=500, height=350, title="Stock Prices Over Time")),

    ("histogram", "Histogram", "Distribution of MPG values",
     """data(cars()) *
    mapping(:mpg) *
    histogram() *
    config(height=300, title="MPG Distribution")""",
     () -> data(cars()) *
        mapping(:mpg) *
        histogram() *
        config(height=300, title="MPG Distribution")),

    ("heatmap", "Heatmap", "Monthly temperatures across cities",
     """data(temperatures()) *
    mapping(:month, :city, color=:temp) *
    visual(Heatmap) *
    config(width=500, height=200, title="Monthly Temperatures by City")""",
     () -> data(temperatures()) *
        mapping(:month, :city, color=:temp) *
        visual(Heatmap) *
        config(width=500, height=200, title="Monthly Temperatures by City")),

    ("boxplot", "Box Plot", "MPG distribution by number of cylinders",
     """data(cars()) *
    mapping(:cylinders, :mpg) *
    visual(BoxPlot) *
    config(width=400, height=350, title="MPG by Cylinders")""",
     () -> data(cars()) *
        mapping(:cylinders, :mpg) *
        visual(BoxPlot) *
        config(width=400, height=350, title="MPG by Cylinders")),

    # Composition
    ("stacked_bar", "Stacked Bar", "Population by age group and sex",
     """data(melt_population(population())) *
    mapping(:category, :count, color=:sex) *
    visual(BarPlot) *
    config(width=400, height=300, title="Population by Age Group")""",
     () -> data(melt_population(population())) *
        mapping(:category, :count, color=:sex) *
        visual(BarPlot) *
        config(width=400, height=300, title="Population by Age Group")),

    ("layered", "Layered Plot", "Scatter + trend line using + operator",
     """data(tips()) * (
    mapping(:total_bill, :tip) * visual(Scatter, opacity=0.6) +
    mapping(:total_bill, :tip) * visual(Lines, color=:firebrick)
) * config(width=500, height=350, title="Tips: Scatter + Trend")""",
     () -> data(tips()) * (
        mapping(:total_bill, :tip) * visual(Scatter, opacity=0.6) +
        mapping(:total_bill, :tip) * visual(Lines, color=:firebrick)
    ) * config(width=500, height=350, title="Tips: Scatter + Trend")),

    # Interactive
    ("interactive_brush", "Brush Selection", "Drag to select points — unselected points fade out",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(
        width=500, height=350,
        title="Drag to Select",
        params=[Dict("name" => "brush", "select" => "interval")],
        encoding=Dict(
            "opacity" => Dict(
                "condition" => Dict("param" => "brush", "value" => 1),
                "value" => 0.1,
            ),
        ),
    )""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=500, height=350,
            title="Drag to Select",
            params=[Dict("name" => "brush", "select" => "interval")],
            encoding=Dict(
                "opacity" => Dict(
                    "condition" => Dict("param" => "brush", "value" => 1),
                    "value" => 0.1,
                ),
            ),
        )),

    ("interactive_slider", "Slider Filter", "Use the slider to filter cars by minimum MPG",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(
        width=500, height=350,
        title="Filter by Minimum MPG",
        params=[Dict(
            "name" => "min_mpg",
            "value" => 10,
            "bind" => Dict("input" => "range", "min" => 5, "max" => 40, "step" => 1),
        )],
        transform=[Dict("filter" => "datum.mpg >= min_mpg")],
    )""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=500, height=350,
            title="Filter by Minimum MPG",
            params=[Dict(
                "name" => "min_mpg",
                "value" => 10,
                "bind" => Dict("input" => "range", "min" => 5, "max" => 40, "step" => 1),
            )],
            transform=[Dict("filter" => "datum.mpg >= min_mpg")],
        )),

    # Statistical
    ("density", "Density Plot", "Density with color grouping",
     """let n = 500
    x = [randn(n); 1.5 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c) * density() *
        config(title="Density Plot")
end""",
     () -> let
        n = 500
        x = [randn_bm(n); 1.5 .+ randn_bm(n)]
        c = [fill("a", n); fill("b", n)]
        df = (; x, c)
        data(df) * mapping(:x, color=:c) * density() *
            config(title="Density Plot")
     end),

    ("linear_band", "Linear + Confidence Band", "Linear regression with confidence ribbon",
     """let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [1.2*xi*parse(Int,ai) + parse(Int,ai) + 5*randn(1)[1] for (xi,ai) in zip(x,a)]
    df = (; x, y, a)
    data(df) * mapping(:x, :y, color=:a) * (linear(interval=:confidence) + visual(Scatter)) *
        config(title="Linear + Confidence Band")
end""",
     () -> let
        x = [0.05i for i in 1:200]
        a = [isodd(i) ? "1" : "2" for i in 1:200]
        y = [1.2*xi*parse(Int,ai) + parse(Int,ai) + 5*randn_bm(1)[1] for (xi,ai) in zip(x,a)]
        df = (; x, y, a)
        data(df) * mapping(:x, :y, color=:a) * (linear(interval=:confidence) + visual(Scatter)) *
            config(height=300, title="Linear + Confidence Band")
     end),

    # Uncertainty (tidybayes)
    ("pointinterval", "Point + Interval", "tidybayes-style: median with 50%/80%/95% credible intervals",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    pointinterval() *
    config(width=500, height=200, title="Point + Interval (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        pointinterval() *
        config(width=500, height=200, title="Point + Interval (tidybayes-style)")),

    ("halfeye", "Half-Eye Plot", "tidybayes-style: density + point + interval for each parameter",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    (density() + pointinterval()) *
    config(width=500, height=80, title="Half-Eye Plot (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        (density() + pointinterval()) *
        config(width=500, height=80, title="Half-Eye Plot (tidybayes-style)")),

    ("lineribbon", "Line + Ribbon", "tidybayes-style: regression line with uncertainty ribbons",
     """data(regression_predictions()) *
    mapping(:x, :y, group=:draw) *
    lineribbon() *
    config(width=500, height=350, title="Line + Ribbon (tidybayes-style)")""",
     () -> data(regression_predictions()) *
        mapping(:x, :y, group=:draw) *
        lineribbon() *
        config(width=500, height=350, title="Line + Ribbon (tidybayes-style)")),
]

# --- Sections for organizing the gallery page ---

SECTIONS = [
    "Interactive Filtering" => ["filter_origin", "filter_multi", "filter_regression"],
    "Basic" => ["scatter", "bar", "line", "histogram", "heatmap", "boxplot"],
    "Composition" => ["stacked_bar", "layered"],
    "Interactive" => ["interactive_brush", "interactive_slider"],
    "Statistical Analyses" => ["density", "linear_band"],
    "Uncertainty (tidybayes)" => ["pointinterval", "halfeye", "lineribbon"],
]

# --- Generate the markdown and JSON spec files ---

function generate_gallery(srcdir)
    specsdir = joinpath(srcdir, "public", "specs")
    mkpath(specsdir)

    examples_by_id = Dict(e[1] => e for e in EXAMPLES)
    sections_md = String[]

    for (section_title, ids) in SECTIONS
        section_parts = String[]
        push!(section_parts, "## $section_title\n")

        for id in ids
            e = examples_by_id[id]
            title, description, code_str, spec_fn = e[2], e[3], e[4], e[5]

            # Generate and write JSON spec
            spec = spec_fn()
            vl = to_vegalite(spec)
            json_path = joinpath(specsdir, "$id.json")
            write(json_path, JSON.json(vl))
            println("  wrote $json_path")

            push!(section_parts, """
### $title

$description

```julia
$code_str
```

```@raw html
<VegaPlot src="/specs/$id.json" />
```
""")
        end

        push!(sections_md, join(section_parts, "\n"))
    end

    # --- Generate the Data Explorer widget ---
    explorer_datasets = Dict("cars" => cars(), "tips" => tips(), "stocks" => stocks(), "temperatures" => temperatures())
    ds_names = sort(collect(keys(explorer_datasets)))

    function table_to_rows(tbl)
        cols = keys(tbl)
        n = length(tbl[first(cols)])
        [Dict(string(c) => tbl[c][i] for c in cols) for i in 1:n]
    end

    function classify_columns(tbl)
        cols = string.(keys(tbl))
        numeric = [c for c in cols if eltype(tbl[Symbol(c)]) <: Number]
        categorical = [c for c in cols if !(eltype(tbl[Symbol(c)]) <: Number)]
        (all=cols, numeric=numeric, categorical=categorical)
    end

    ds_json = JSON.json(Dict(name => table_to_rows(explorer_datasets[name]) for name in ds_names))
    col_json = JSON.json(Dict(name => Dict(
        "all" => collect(classify_columns(explorer_datasets[name]).all),
        "numeric" => classify_columns(explorer_datasets[name]).numeric,
        "categorical" => classify_columns(explorer_datasets[name]).categorical,
    ) for name in ds_names))

    # Build dropdown options for default dataset
    default_ds = "cars"
    default_cols = classify_columns(explorer_datasets[default_ds])
    ds_options = join(["<option value=\"$n\">$n</option>" for n in ds_names], "\n")
    all_options = join(["<option value=\"$c\">$c</option>" for c in default_cols.all], "\n")
    all_options_y = join(["<option value=\"$c\"$(c == default_cols.all[min(2,end)] ? " selected" : "")>$c</option>" for c in default_cols.all], "\n")
    cat_options = join(["<option value=\"$c\">$c</option>" for c in default_cols.categorical], "\n")

    explorer_html = """
<div>
<p>Build faceted plots interactively — all client-side, no server round-trips.</p>

<div id="explorer-controls" style="display:flex; flex-wrap:wrap; gap:1rem; margin-bottom:1rem; align-items:end;">
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Dataset:
    <select id="ex-dataset" onchange="_explorerUpdateDropdowns(); explorerUpdate()">$ds_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">X:
    <select id="ex-x" onchange="explorerUpdate()">$all_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Y:
    <select id="ex-y" onchange="explorerUpdate()">$all_options_y</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Color:
    <select id="ex-color" onchange="explorerUpdate()"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Column:
    <select id="ex-col" onchange="explorerUpdate()"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Facet Row:
    <select id="ex-row" onchange="explorerUpdate()"><option value="">(none)</option>$cat_options</select>
  </label>
  <label style="display:flex; flex-direction:column; gap:0.25rem;">Mark:
    <select id="ex-mark" onchange="explorerUpdate()">
      <option value="point">point</option>
      <option value="bar">bar</option>
      <option value="line">line</option>
      <option value="area">area</option>
      <option value="boxplot">boxplot</option>
      <option value="rect">rect (heatmap)</option>
    </select>
  </label>
</div>

<div id="explorer-plot" style="width:100%; min-width:0;"></div>
</div>
<ExplorerLoader />
"""

    # Write datasets JSON and explorer JS to public/
    write(joinpath(specsdir, "..", "explorer-data.json"), ds_json)
    write(joinpath(specsdir, "..", "explorer-columns.json"), col_json)
    println("  wrote explorer data files")

    explorer_js = """
(function() {
  if (typeof document === 'undefined') return;
  var _explorerDatasets, _explorerColumns;

  function init() {
    // Derive base path from this script's own URL
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
    ['ex-color', 'ex-col', 'ex-row'].forEach(function(id) {
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
"""
    write(joinpath(specsdir, "..", "explorer.js"), explorer_js)
    println("  wrote explorer.js")

    md = """# Gallery Examples

A curated selection of interactive examples from the [full gallery](gallery.md) of 70+ plots.
All plots are rendered client-side using [Vega-Lite](https://vega.github.io/vega-lite/) — try interacting with them!

## Data Explorer

```@raw html
$explorer_html
```

$(join(sections_md, "\n"))

---

For the complete set of 70+ examples, including HTMX demos and the interactive data explorer, see the [Gallery](gallery.md) page for instructions on running the full web gallery locally.
"""

    outpath = joinpath(srcdir, "gallery-examples.md")
    write(outpath, md)
    println("Generated gallery: $outpath")
end

# Run
generate_gallery(joinpath(@__DIR__, "src"))
