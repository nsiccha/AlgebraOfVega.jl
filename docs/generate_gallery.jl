# Generate gallery-examples.md with inline Vega-Lite specs for VitePress docs
using AlgebraOfVega
using JSON

# Local aliases for shared datasets (keep plot code concise)
cars() = sample_cars()
tips() = sample_tips()
stocks() = sample_stocks()
temperatures() = sample_temperatures()
population() = sample_population()
posterior_draws(; kw...) = sample_posterior_draws(; kw...)
regression_predictions(; kw...) = sample_regression_predictions(; kw...)

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
        x = [randn(n); 1.5 .+ randn(n)]
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
        y = [1.2*xi*parse(Int,ai) + parse(Int,ai) + 5*randn(1)[1] for (xi,ai) in zip(x,a)]
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
    explorer_datasets = default_explorer_datasets()
    explorer_html = """
<div>
<p>Build faceted plots interactively — all client-side, no server round-trips.</p>
$(explorer_controls_html(explorer_datasets))
</div>
<ExplorerLoader />
"""

    # Write explorer assets (data JSON + JS) to public/
    write_explorer_assets(joinpath(srcdir, "public"), explorer_datasets)

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
