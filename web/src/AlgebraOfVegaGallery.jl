module AlgebraOfVegaGallery

using HTMXObjects
using AlgebraOfVega
import CairoMakie
using JSON
using TestModules, Random, Tables, Statistics

include("test/runtests.jl")

# --- Sample datasets (from AlgebraOfVega.datasets) ---
# Local aliases to keep existing plot code unchanged
cars() = sample_cars()
tips() = sample_tips()
stocks() = sample_stocks()
temperatures() = sample_temperatures()
population() = sample_population()
monthly_sales() = sample_monthly_sales()
posterior_draws(; kw...) = sample_posterior_draws(; kw...)
regression_predictions(; kw...) = sample_regression_predictions(; kw...)
grouped_regression_predictions(; kw...) = sample_grouped_regression_predictions(; kw...)
faceted_regression_predictions(; kw...) = sample_faceted_regression_predictions(; kw...)
faceted_observations(; kw...) = sample_faceted_observations(; kw...)

function _preaggregate(raw, group_keys::Symbol...)
    ct = Tables.columntable(raw)
    ys = ct.y
    key_cols = [ct[k] for k in group_keys]
    nk = length(group_keys)
    groups = Dict{Any,Vector{Int}}()
    for i in eachindex(ys)
        key = nk == 1 ? key_cols[1][i] : Tuple(kc[i] for kc in key_cols)
        push!(get!(Vector{Int}, groups, key), i)
    end
    out_keys = [Any[] for _ in 1:nk]
    out_q025 = Float64[]; out_q10 = Float64[]; out_q25 = Float64[]; out_med = Float64[]
    out_q75 = Float64[]; out_q90 = Float64[]; out_q975 = Float64[]
    for key in sort(collect(keys(groups)))
        idxs = groups[key]
        v = sort(ys[idxs])
        if nk == 1
            push!(out_keys[1], key)
        else
            for (j, k) in enumerate(key)
                push!(out_keys[j], k)
            end
        end
        push!(out_q025, quantile(v, 0.025))
        push!(out_q10, quantile(v, 0.10))
        push!(out_q25, quantile(v, 0.25))
        push!(out_med, quantile(v, 0.5))
        push!(out_q75, quantile(v, 0.75))
        push!(out_q90, quantile(v, 0.90))
        push!(out_q975, quantile(v, 0.975))
    end
    (; (k => out_keys[i] for (i, k) in enumerate(group_keys))...,
       q025=out_q025, q10=out_q10, q25=out_q25, median=out_med, q75=out_q75, q90=out_q90, q975=out_q975)
end

# --- Plot specifications ---

# Each entry: (id, title, description, code_string, spec_fn)
PLOTS = [
    # --- Interactive Filtering (client-side, no server) ---

    ("filter_origin", "Filter by Origin", "Dropdown filters scatter plot by car origin",
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

    ("filter_tips", "Filter Tips", "Explore tips data by day and meal time",
     """data(tips()) *
    mapping(:total_bill, :tip, color=:sex) *
    visual(Scatter) *
    config(width=500, height=350, title="Tips Explorer",
           select=[:day, :sex])""",
     () -> data(tips()) *
        mapping(:total_bill, :tip, color=:sex) *
        visual(Scatter) *
        config(width=500, height=350, title="Tips Explorer",
               select=[:day, :sex])),

    ("filter_histogram", "Filtered Histogram", "Histogram updates with dropdown selection",
     """data(cars()) *
    mapping(:mpg) *
    histogram() *
    config(width=500, height=300, title="MPG Distribution by Origin",
           select=:origin)""",
     () -> data(cars()) *
        mapping(:mpg) *
        histogram() *
        config(width=500, height=300, title="MPG Distribution by Origin",
               select=:origin)),

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

    ("filter_bar", "Filtered Bar Chart", "Mean tip by gender filtered by day",
     """data(tips()) *
    mapping(:sex, :tip) *
    visual(BarPlot) *
    config(width=400, height=300, title="Average Tip by Gender",
           encoding=Dict("y" => Dict("aggregate" => "mean")),
           select=:day)""",
     () -> data(tips()) *
        mapping(:sex, :tip) *
        visual(BarPlot) *
        config(width=400, height=300, title="Average Tip by Gender",
               encoding=Dict("y" => Dict("aggregate" => "mean")),
               select=:day)),

    # --- Basic ---

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

    ("layered", "Layered Plot", "Scatter + trend line using + operator",
     """data(tips()) * (
    mapping(:total_bill, :tip) * visual(Scatter, opacity=0.6) +
    mapping(:total_bill, :tip) * visual(Lines, color=:firebrick)
) * config(width=500, height=350, title="Tips: Scatter + Trend")""",
     () -> data(tips()) * (
        mapping(:total_bill, :tip) * visual(Scatter, opacity=0.6) +
        mapping(:total_bill, :tip) * visual(Lines, color=:firebrick)
    ) * config(width=500, height=350, title="Tips: Scatter + Trend")),

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

    ("scatter_jitter", "Jittered Scatter", "Individual data points by origin with jitter",
     """data(cars()) *
    mapping(:origin, :mpg) *
    visual(Scatter) *
    config(width=400, height=350, title="MPG by Origin (Jittered)",
           transform=[Dict("calculate" => "(random() - 0.5) * 0.8", "as" => "jitter")],
           encoding=Dict("xOffset" => Dict("field" => "jitter", "type" => "quantitative",
                                            "scale" => Dict("domain" => [-0.5, 0.5]))))""",
     () -> data(cars()) *
        mapping(:origin, :mpg) *
        visual(Scatter) *
        config(width=400, height=350, title="MPG by Origin (Jittered)",
               transform=[Dict("calculate" => "(random() - 0.5) * 0.8", "as" => "jitter")],
               encoding=Dict("xOffset" => Dict("field" => "jitter", "type" => "quantitative",
                                                "scale" => Dict("domain" => [-0.5, 0.5]))))),

    ("stacked_bar", "Stacked Bar", "Population by age group and sex",
     """data(melt_population(population())) *
    mapping(:category, :count, color=:sex) *
    visual(BarPlot) *
    config(width=400, height=300, title="Population by Age Group")""",
     () -> data(melt_population(population())) *
        mapping(:category, :count, color=:sex) *
        visual(BarPlot) *
        config(width=400, height=300, title="Population by Age Group")),

    ("grouped_bar", "Grouped Bar", "Sales by channel with grouped bars",
     """data(melt_sales(monthly_sales())) *
    mapping(:month, :sales, color=:channel, dodge_x=:channel) *
    visual(BarPlot) *
    config(width=600, height=300, title="Monthly Sales by Channel")""",
     () -> data(melt_sales(monthly_sales())) *
        mapping(:month, :sales, color=:channel, dodge_x=:channel) *
        visual(BarPlot) *
        config(width=600, height=300, title="Monthly Sales by Channel")),

    ("area", "Area Chart", "Stock prices as area chart",
     """data(stocks()) *
    mapping(:date, :price, color=:symbol) *
    visual(Band, opacity=0.6) *
    config(width=500, height=350, title="Stock Prices (Area)")""",
     () -> data(stocks()) *
        mapping(:date, :price, color=:symbol) *
        visual(Band, opacity=0.6) *
        config(width=500, height=350, title="Stock Prices (Area)")),

    ("bubble", "Bubble Chart", "Scatter plot with size encoding for weight",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin, markersize=:weight) *
    visual(Scatter) *
    config(width=500, height=400, title="Cars: HP vs MPG (bubble = weight)")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin, markersize=:weight) *
        visual(Scatter) *
        config(width=500, height=400, title="Cars: HP vs MPG (bubble = weight)")),

    ("multi_layer", "Multi-Layer", "Scatter with dashed trend line overlay",
     """data(cars()) * (
    mapping(:horsepower, :mpg) * visual(Scatter, opacity=0.5) +
    mapping(:horsepower, :mpg) * visual(Lines, color=:red, strokeDash=[4,4])
) * config(width=500, height=350, title="HP vs MPG with Trend")""",
     () -> data(cars()) * (
        mapping(:horsepower, :mpg) * visual(Scatter, opacity=0.5) +
        mapping(:horsepower, :mpg) * visual(Lines, color=:red, strokeDash=[4,4])
    ) * config(width=500, height=350, title="HP vs MPG with Trend")),

    ("custom_config", "Custom Styling", "Customized background, fonts, and grid",
     """data(tips()) *
    mapping(:total_bill, :tip, color=:sex) *
    visual(Scatter, size=80) *
    config(
        width=500, height=350,
        title="Tips (Custom Style)",
        config=Dict(
            "background" => "#f8f8f8",
            "title" => Dict("fontSize" => 20, "anchor" => "start"),
            "axis" => Dict("grid" => true, "gridColor" => "#ddd"),
        ),
    )""",
     () -> data(tips()) *
        mapping(:total_bill, :tip, color=:sex) *
        visual(Scatter, size=80) *
        config(
            width=500, height=350,
            title="Tips (Custom Style)",
            config=Dict(
                "background" => "#f8f8f8",
                "title" => Dict("fontSize" => 20, "anchor" => "start"),
                "axis" => Dict("grid" => true, "gridColor" => "#ddd"),
            ),
        )),

    ("lines_only", "Lines Chart", "Stock prices as simple lines",
     """data(stocks()) *
    mapping(:date, :price, color=:symbol) *
    visual(Lines) *
    config(width=500, height=350, title="Stock Prices (Lines)")""",
     () -> data(stocks()) *
        mapping(:date, :price, color=:symbol) *
        visual(Lines) *
        config(width=500, height=350, title="Stock Prices (Lines)")),

    # --- Interactive examples (Vega-Lite params via config) ---

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

    ("interactive_highlight", "Click to Highlight", "Click a point to highlight its origin group",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(
        width=500, height=350,
        title="Click to Highlight Origin",
        params=[Dict(
            "name" => "picked",
            "select" => Dict("type" => "point", "fields" => ["origin"]),
        )],
        encoding=Dict(
            "size" => Dict(
                "condition" => Dict("param" => "picked", "value" => 200),
                "value" => 50,
            ),
            "opacity" => Dict(
                "condition" => Dict("param" => "picked", "value" => 1),
                "value" => 0.2,
            ),
        ),
    )""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=500, height=350,
            title="Click to Highlight Origin",
            params=[Dict(
                "name" => "picked",
                "select" => Dict("type" => "point", "fields" => ["origin"]),
            )],
            encoding=Dict(
                "size" => Dict(
                    "condition" => Dict("param" => "picked", "value" => 200),
                    "value" => 50,
                ),
                "opacity" => Dict(
                    "condition" => Dict("param" => "picked", "value" => 1),
                    "value" => 0.2,
                ),
            ),
        )),

    ("interactive_zoom", "Pan & Zoom", "Scroll to zoom, drag to pan the scatter plot",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(
        width=500, height=350,
        title="Scroll to Zoom, Drag to Pan",
        params=[Dict(
            "name" => "grid",
            "select" => Dict("type" => "interval"),
            "bind" => "scales",
        )],
    )""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=500, height=350,
            title="Scroll to Zoom, Drag to Pan",
            params=[Dict(
                "name" => "grid",
                "select" => Dict("type" => "interval"),
                "bind" => "scales",
            )],
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

    ("interactive_dropdown", "Dropdown Filter", "Select an origin to filter the scatter plot",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(Scatter) *
    config(
        width=500, height=350,
        title="Filter by Origin",
        params=[Dict(
            "name" => "origin_select",
            "value" => "All",
            "bind" => Dict(
                "input" => "select",
                "options" => ["All", "USA", "Europe", "Japan"],
            ),
        )],
        transform=[Dict(
            "filter" => "origin_select == 'All' || datum.origin == origin_select",
        )],
    )""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=500, height=350,
            title="Filter by Origin",
            params=[Dict(
                "name" => "origin_select",
                "value" => "All",
                "bind" => Dict(
                    "input" => "select",
                    "options" => ["All", "USA", "Europe", "Japan"],
                ),
            )],
            transform=[Dict(
                "filter" => "origin_select == 'All' || datum.origin == origin_select",
            )],
        )),

    ("remap_encoding", "Remap Encoding", "Client-side color/row switching via mapping_controls — no server round-trip",
     """id = "remap-demo"
spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
       config(title="Remap Encoding Demo")
auto_remap_node(id, spec; dims=[:origin => "Origin", :cylinders => "Cylinders"])""",
     () -> begin
        id = "remap-demo"
        spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
               config(title="Remap Encoding Demo")
        auto_remap_node(id, spec; dims=[:origin => "Origin", :cylinders => "Cylinders"])
     end),

    ("remap_lineribbon", "Remap Line + Ribbon", "Client-side color/row/col switching on a lineribbon plot",
     """id = "remap-lr"
preds = faceted_regression_predictions()
spec = data(preds) * mapping(:x, :y, group=:draw, color=:panel, row=:site) *
       lineribbon() * config(title="Remap Line + Ribbon")
auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])""",
     () -> begin
        id = "remap-lr"
        preds = faceted_regression_predictions()
        spec = data(preds) * mapping(:x, :y, group=:draw, color=:panel, row=:site) *
               lineribbon() * config(title="Remap Line + Ribbon")
        auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])
     end),

    ("remap_axes", "Remap X/Y Axes (axes=true)",
     "Client-side x/y axis swap via `axes=true`. Positional fields are auto-added to the picker's dim set, so they appear as X/Y defaults AND become selectable on color/row/column. Off by default because X/Y are single-select and usually positional fields aren't meant to be re-routed.",
     """id = "remap-axes"
spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
       config(title="Remap X/Y Axes", width=500, height=350)
auto_remap_node(id, spec;
    dims=["origin" => "Origin", "cylinders" => "Cylinders"],
    axes=true)""",
     () -> begin
        id = "remap-axes"
        spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
               config(title="Remap X/Y Axes", width=500, height=350)
        auto_remap_node(id, spec;
            dims=["origin" => "Origin", "cylinders" => "Cylinders"],
            axes=true)
     end),

    ("remap_detail", "Remap with Detail", "Lineribbon with extra grouping dimensions via detail= for client-side remapping",
     """# Simulate PK-style data: 2 assays × 2 groups × 2 sites × 50 draws
id = "remap-detail"
using Random
rng = Random.MersenneTwister(42)
rows = NamedTuple[]
for assay in ["CSF", "PBMC"], grp in ["Healthy", "PD"], site in ["US", "EU"]
    offset = (assay == "CSF" ? 0.0 : -2.0) + (grp == "PD" ? 1.5 : 0.0) + (site == "EU" ? 0.5 : 0.0)
    for d in 1:50, x in range(0, 5, length=20)
        push!(rows, (x=x, y=offset + 0.8x + 0.5randn(rng), draw=d, assay=assay, health=grp, site=site))
    end
end
df = (; (k => getindex.(rows, k) for k in keys(rows[1]))...)
spec = data(df) * mapping(:x, :y, group=:draw, color=:health, col=:assay) *
       lineribbon(; detail=[:site]) * config(title="Remap with Detail")
auto_remap_node(id, spec; dims=[:health => "Health", :site => "Site"],
    fixed=Dict(:column => "assay"))""",
     () -> begin
        id = "remap-detail"
        rng = Random.MersenneTwister(42)
        rows = NamedTuple[]
        for assay in ["CSF", "PBMC"], grp in ["Healthy", "PD"], site in ["US", "EU"]
            offset = (assay == "CSF" ? 0.0 : -2.0) + (grp == "PD" ? 1.5 : 0.0) + (site == "EU" ? 0.5 : 0.0)
            for d in 1:50, x in range(0, 5, length=20)
                push!(rows, (x=x, y=offset + 0.8x + 0.5randn(rng), draw=d, assay=assay, health=grp, site=site))
            end
        end
        df = (; (k => getindex.(rows, k) for k in keys(rows[1]))...)
        spec = data(df) * mapping(:x, :y, group=:draw, color=:health, col=:assay) *
               lineribbon(; detail=[:site]) * config(title="Remap with Detail")
        auto_remap_node(id, spec; dims=[:health => "Health", :site => "Site"],
            fixed=Dict(:column => "assay"))
     end),

    # === AoG gallery replications (https://aog.makie.org/stable/) ===

    # --- Basic Visualizations: Lines and Markers ---

    ("aog_scatter_basic", "Basic Scatter",
     "Random x/y scatter",
     """data((x=rand(100), y=rand(100))) * mapping(:x, :y) * visual(Scatter) *
    config(title="Basic Scatter")""",
     () -> let
        df = (x=rand(100), y=rand(100))
        data(df) * mapping(:x, :y) * visual(Scatter) *
            config(title="Basic Scatter")
     end,
     "https://aog.makie.org/stable/examples/basic-visualizations/lines-and-markers"),

    ("aog_sine_lines", "Sine Wave (Lines)",
     "Lines visual with sin(x)",
     """let x = range(-π, π, length=100)
    df = (; x=collect(x), y=sin.(x))
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="Sine Wave")
end""",
     () -> let x = range(-Float64(π), Float64(π), length=100)
        df = (; x=collect(x), y=sin.(x))
        data(df) * mapping(:x, :y) * visual(Lines) *
            config(title="Sine Wave")
     end,
     "https://aog.makie.org/stable/examples/basic-visualizations/lines-and-markers"),

    ("aog_lines_scatter", "Lines + Scatter",
     "Scatter + Lines composition",
     """let x = range(-π, π, length=100)
    df = (; x=collect(x), y=sin.(x))
    data(df) * mapping(:x, :y) * (visual(Scatter) + visual(Lines)) *
        config(title="Lines + Scatter")
end""",
     () -> let x = range(-Float64(π), Float64(π), length=100)
        df = (; x=collect(x), y=sin.(x))
        data(df) * mapping(:x, :y) * (visual(Scatter) + visual(Lines)) *
            config(title="Lines + Scatter")
     end,
     "https://aog.makie.org/stable/examples/basic-visualizations/lines-and-markers"),

    ("aog_two_sources", "Two Data Sources",
     "Lines from one source + Scatter from another",
     """let df1 = (; x=collect(range(-3.14, 3.14, length=100)), y=sin.(range(-3.14, 3.14, length=100)))
    df2 = (x=rand(10) .* 6 .- 3, y=rand(10) .* 2 .- 1)
    (data(df1) * visual(Lines) + data(df2) * visual(Scatter)) *
        mapping(:x, :y) * config(title="Two Data Sources")
end""",
     () -> let
        df1 = (; x=collect(range(-3.14, 3.14, length=100)), y=sin.(range(-3.14, 3.14, length=100)))
        df2 = (x=rand(10) .* 6 .- 3, y=rand(10) .* 2 .- 1)
        (data(df1) * visual(Lines) + data(df2) * visual(Scatter)) *
            mapping(:x, :y) * config(title="Two Data Sources")
     end,
     "https://aog.makie.org/stable/examples/basic-visualizations/lines-and-markers"),

    # --- Basic Visualizations: Statistical ---

    ("aog_boxplot", "Box Plot",
     "Box plot by category with color dodge",
     """let species = [["Adelie","Chinstrap","Gentoo"][mod1(k,3)] for k in 1:200]
    sex = [isodd(k) ? "male" : "female" for k in 1:200]
    depth = [s == "Adelie" ? 18.0 : s == "Chinstrap" ? 18.5 : 15.0 for s in species] .+ randn(200)
    df = (; species, bill_depth=depth, sex)
    data(df) * visual(BoxPlot) * mapping(:species, :bill_depth, color=:sex, dodge_x=:sex) *
        config(title="Box Plot by Species & Sex")
end""",
     () -> let
        species = [["Adelie","Chinstrap","Gentoo"][mod1(k,3)] for k in 1:200]
        sex = [isodd(k) ? "male" : "female" for k in 1:200]
        depth = [s == "Adelie" ? 18.0 : s == "Chinstrap" ? 18.5 : 15.0 for s in species] .+ randn(200)
        df = (; species, bill_depth=depth, sex)
        data(df) * visual(BoxPlot) * mapping(:species, :bill_depth, color=:sex, dodge_x=:sex) *
            config(title="Box Plot by Species & Sex")
     end,
     "https://aog.makie.org/stable/examples/basic-visualizations/statistical-visualizations"),

    # --- Data Manipulations ---

    ("aog_wide_lines", "Wide Data (Lines)",
     "Multiple y-columns mapped with color",
     """let df = (; x=collect(0.0:0.5:10), y1=(0.0:0.5:10).^0.5, y2=(0.0:0.5:10).^0.6, y3=(0.0:0.5:10).^0.7)
    n = length(df.x)
    long = (; x=[df.x;df.x;df.x], y=[df.y1;df.y2;df.y3], group=[fill("y1",n);fill("y2",n);fill("y3",n)])
    data(long) * mapping(:x, :y, color=:group) * visual(Lines) *
        config(title="Wide Data as Lines")
end""",
     () -> let
        x = collect(0.0:0.5:10)
        n = length(x)
        long = (; x=[x;x;x], y=[x.^0.5; x.^0.6; x.^0.7], group=[fill("y1",n);fill("y2",n);fill("y3",n)])
        data(long) * mapping(:x, :y, color=:group) * visual(Lines) *
            config(title="Wide Data as Lines")
     end,
     "https://aog.makie.org/stable/examples/data-manipulations/wide-data"),

    ("aog_wide_scatter", "Wide Data (Scatter)",
     "Multiple y-columns as scatter with color",
     """let df = (; x=collect(0.0:0.5:10), y1=(0.0:0.5:10).^0.5, y2=(0.0:0.5:10).^0.6, y3=(0.0:0.5:10).^0.7)
    n = length(df.x)
    long = (; x=[df.x;df.x;df.x], y=[df.y1;df.y2;df.y3], group=[fill("y1",n);fill("y2",n);fill("y3",n)])
    data(long) * mapping(:x, :y, color=:group) * visual(Scatter) *
        config(title="Wide Data as Scatter")
end""",
     () -> let
        x = collect(0.0:0.5:10)
        n = length(x)
        long = (; x=[x;x;x], y=[x.^0.5; x.^0.6; x.^0.7], group=[fill("y1",n);fill("y2",n);fill("y3",n)])
        data(long) * mapping(:x, :y, color=:group) * visual(Scatter) *
            config(title="Wide Data as Scatter")
     end,
     "https://aog.makie.org/stable/examples/data-manipulations/wide-data"),

    ("aog_presorted_bar", "Presorted Bar",
     "Bar chart preserving custom data order",
     """let countries = ["Algeria","Bolivia","China","Denmark","Ecuador","France"]
    vals = [2.72, 0.84, 1.41, 2.72, 0.84, 1.41]
    group = ["2","3","1","1","3","2"]
    df = (; countries, value=vals, group)
    data(df) * mapping(:countries, :value, color=:group) * visual(BarPlot) *
        config(title="Presorted Bar Chart")
end""",
     () -> let
        df = (; countries=["Algeria","Bolivia","China","Denmark","Ecuador","France"],
               value=[2.72, 0.84, 1.41, 2.72, 0.84, 1.41],
               group=["2","3","1","1","3","2"])
        data(df) * mapping(:countries, :value, color=:group) * visual(BarPlot) *
            config(title="Presorted Bar Chart")
     end,
     "https://aog.makie.org/stable/examples/data-manipulations/presorted-data"),

    # --- Scales: Continuous ---

    ("aog_log_transform", "Log Transform",
     "Apply log transform to y in mapping",
     """let x = collect(1:100)
    y = [sqrt(xi) + 20xi + 100 for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="y = √x + 20x + 100 (log scale)",
               encoding=Dict("y" => Dict("scale" => Dict("type" => "log"))))
end""",
     () -> let
        x = collect(1:100)
        y = [sqrt(xi) + 20xi + 100 for xi in x]
        df = (; x, y)
        data(df) * mapping(:x, :y) * visual(Lines) *
            config(height=300, title="y = √x + 20x + 100 (log scale)",
                   encoding=Dict("y" => Dict("scale" => Dict("type" => "log"))))
     end,
     "https://aog.makie.org/stable/examples/scales/continuous-scales"),

    # --- Scales: Discrete ---

    ("aog_discrete_boxplot", "Discrete Box Plot",
     "Box plot with categorical x axis",
     """let df = (x=[["a","b","c"][mod1(k,3)] for k in 1:100], y=rand(100))
    data(df) * mapping(:x, :y) * visual(BoxPlot) *
        config(title="Box Plot with Categories")
end""",
     () -> let
        df = (x=[["a","b","c"][mod1(k,3)] for k in 1:100], y=rand(100))
        data(df) * mapping(:x, :y) * visual(BoxPlot) *
            config(title="Box Plot with Categories")
     end,
     "https://aog.makie.org/stable/examples/scales/discrete-scales"),

    ("aog_combined_boxplot", "Combined Categories",
     "Two datasets with unified categories",
     """let df1 = (; x=[isodd(k) ? "one" : "two" for k in 1:100], y=randn(100))
    df2 = (; x=[isodd(k) ? "three" : "four" for k in 1:50], y=randn(50))
    (data(df1) + data(df2)) * mapping(:x, :y) * visual(BoxPlot) *
        config(title="Combined Categories")
end""",
     () -> let
        df1 = (; x=[isodd(k) ? "one" : "two" for k in 1:100], y=randn(100))
        df2 = (; x=[isodd(k) ? "three" : "four" for k in 1:50], y=randn(50))
        (data(df1) + data(df2)) * mapping(:x, :y) * visual(BoxPlot) *
            config(title="Combined Categories")
     end,
     "https://aog.makie.org/stable/examples/scales/discrete-scales"),

    # --- Pregrouped ---

    ("pregrouped_boxplot", "Pregrouped Box Plot",
     "Box plot from pregrouped data with renamer labels",
     """pregrouped(
    fill.(1:3, 10) => renamer(["A", "B", "C"]),
    [randn(10) for _ in 1:3]
) * visual(BoxPlot) *
    config(title="Pregrouped Box Plot")""",
     () -> pregrouped(
        fill.(1:3, 10) => renamer(["A", "B", "C"]),
        [randn(10) for _ in 1:3]
    ) * visual(BoxPlot) *
        config(title="Pregrouped Box Plot")),

    ("pregrouped_boxplot_plain", "Pregrouped (no renamer)",
     "Box plot from pregrouped data without renamer",
     """pregrouped(
    fill.(1:4, 20),
    [randn(20) .+ i for i in 1:4]
) * visual(BoxPlot) *
    config(title="Pregrouped (no renamer)")""",
     () -> pregrouped(
        fill.(1:4, 20),
        [randn(20) .+ i for i in 1:4]
    ) * visual(BoxPlot) *
        config(title="Pregrouped (no renamer)")),

    ("pregrouped_dose_response", "Dose Response (pregrouped)",
     "Simulated dose-response box plots like a pharmacometrics QT study",
     """let doses = ["Placebo", "Low", "Medium", "High"]
    n = 30
    effects = [randn(n) .* 2, randn(n) .* 2 .+ 1,
               randn(n) .* 2 .+ 3, randn(n) .* 2 .+ 5]
    pregrouped(
        fill.(1:4, n) => renamer(doses),
        effects
    ) * visual(BoxPlot) *
        config(title="Dose Response")
end""",
     () -> let
        doses = ["Placebo", "Low", "Medium", "High"]
        n = 30
        effects = [randn(n) .* 2, randn(n) .* 2 .+ 1,
                   randn(n) .* 2 .+ 3, randn(n) .* 2 .+ 5]
        pregrouped(
            fill.(1:4, n) => renamer(doses),
            effects
        ) * visual(BoxPlot) *
            config(title="Dose Response")
     end),

    ("aog_barplot_names", "Named Bar Plot",
     "Bar chart with string category names",
     """let df = (; name=["Anna Coolidge","Berta Bauer","Charlie Archer"], age=[34,79,58])
    data(df) * mapping(:name, :age) * visual(BarPlot) *
        config(title="Named Bar Plot")
end""",
     () -> let
        df = (; name=["Anna Coolidge","Berta Bauer","Charlie Archer"], age=[34,79,58])
        data(df) * mapping(:name, :age) * visual(BarPlot) *
            config(title="Named Bar Plot")
     end,
     "https://aog.makie.org/stable/examples/scales/discrete-scales"),

    # --- Scales: Dodging ---

    ("aog_dodge", "Dodged Bar Plot",
     "Bar plot with dodge by group",
     """let df = (; x=["One","One","Two","Two"], y=1:4, group=["A","B","A","B"])
    data(df) * mapping(:x, :y, dodge_x=:group, color=:group) * visual(BarPlot) *
        config(title="Dodged Bar Plot")
end""",
     () -> let
        df = (; x=["One","One","Two","Two"], y=[1,2,3,4], group=["A","B","A","B"])
        data(df) * mapping(:x, :y, dodge_x=:group, color=:group) * visual(BarPlot) *
            config(title="Dodged Bar Plot")
     end,
     "https://aog.makie.org/stable/examples/scales/dodging"),

    # --- Scales: Legend Merging ---

    ("aog_legend_merge", "Legend Merge",
     "Lines + Scatter sharing color legend",
     """let N = 40
    x = [1:N; 1:N]
    y = cumsum(randn(2N))
    grp = [fill("a", N); fill("b", N)]
    df = (; x, y, grp)
    (visual(Lines) + visual(Scatter)) *
        data(df) * mapping(:x, :y, color=:grp) *
        config(title="Legend Merge: Lines + Scatter")
end""",
     () -> let
        N = 40
        x = [collect(1:N); collect(1:N)]
        y = cumsum(randn(2N))
        grp = [fill("a", N); fill("b", N)]
        df = (; x, y, grp)
        (visual(Lines) + visual(Scatter)) *
            data(df) * mapping(:x, :y, color=:grp) *
            config(title="Legend Merge: Lines + Scatter")
     end,
     "https://aog.makie.org/stable/examples/scales/legend-merging"),

    # --- Scales: Multiple Color Scales ---

    ("aog_multi_color", "Multi Color Scales",
     "Continuous + discrete color on same plot",
     """let x = collect(range(-3.14, 3.14, length=100))
    y = sin.(x)
    z = cos.(x)
    c = [isodd(i) ? "a" : "b" for i in 1:100]
    df = (; x, y, z, c)
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="Lines with continuous z coloring",
               encoding=Dict("color" => Dict("field" => "z", "type" => "quantitative")))
end""",
     () -> let
        x = collect(range(-3.14, 3.14, length=100))
        y = sin.(x)
        z = cos.(x)
        df = (; x, y, z)
        data(df) * mapping(:x, :y, color=:z) * visual(Lines) *
            config(title="Lines with continuous z coloring")
     end,
     "https://aog.makie.org/stable/examples/scales/multiple-color-scales"),

    # --- Statistical Analyses: Density ---

    ("aog_density", "Density Plot",
     "Density with color grouping",
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
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/density-plots"),

    # --- Statistical Analyses: ECDF ---

    ("aog_ecdf", "ECDF Plot",
     "Empirical cumulative distribution function",
     """let n = 200
    x = randn(n)
    df = (; x)
    data(df) * mapping(:x) * visual(ECDFPlot) *
        config(title="ECDF Plot")
end""",
     () -> let
        n = 200
        x = randn(n)
        df = (; x)
        data(df) * mapping(:x) * visual(ECDFPlot) *
            config(title="ECDF Plot")
     end),

    ("aog_ecdf_grouped", "Grouped ECDF",
     "ECDF with color grouping",
     """let n = 200
    x = [randn(n); 1.5 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c) * visual(ECDFPlot) *
        config(title="Grouped ECDF")
end""",
     () -> let
        n = 200
        x = [randn(n); 1.5 .+ randn(n)]
        c = [fill("a", n); fill("b", n)]
        df = (; x, c)
        data(df) * mapping(:x, color=:c) * visual(ECDFPlot) *
            config(title="Grouped ECDF")
     end),

    # --- Statistical Analyses: Histograms ---

    ("aog_histogram_basic", "Basic Histogram",
     "Simple histogram with 20 bins",
     """let df = (x=rand(0:99, 1000),)
    data(df) * mapping(:x) * histogram() *
        config(title="Basic Histogram")
end""",
     () -> let
        df = (x=rand(0:99, 1000),)
        data(df) * mapping(:x) * histogram() *
            config(title="Basic Histogram")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/histograms"),

    ("aog_histogram", "Stacked Histogram",
     "Histogram with color stacking",
     """let n = 500
    x = [randn(n); 1.0 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c, stack=:c) * histogram() *
        config(title="Stacked Histogram")
end""",
     () -> let
        n = 500
        x = [randn(n); 1.0 .+ randn(n)]
        c = [fill("a", n); fill("b", n)]
        df = (; x, c)
        data(df) * mapping(:x, color=:c, stack=:c) * histogram() *
            config(title="Stacked Histogram")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/histograms"),

    # --- Statistical Analyses: Regression ---

    ("aog_linear", "Linear Regression",
     "linear() + Scatter",
     """let x = [0.01i for i in 1:100]
    y = [xi + 0.3 * randn(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (linear() + visual(Scatter)) *
        config(title="Scatter + Linear Regression")
end""",
     () -> let
        x = [0.01i for i in 1:100]
        y = [xi + 0.3*randn(1)[1] for xi in x]
        df = (; x, y)
        data(df) * mapping(:x, :y) * (linear() + visual(Scatter)) *
            config(title="Scatter + Linear Regression")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/regression-plots"),

    ("aog_smooth", "Smooth Regression",
     "smooth() + Scatter (loess)",
     """let x = [0.01i for i in 1:100]
    y = [5*xi^2 + 0.3*randn(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (smooth() + visual(Scatter)) *
        config(title="Scatter + Smooth (Loess)")
end""",
     () -> let
        x = [0.01i for i in 1:100]
        y = [5*xi^2 + 0.3*randn(1)[1] for xi in x]
        df = (; x, y)
        data(df) * mapping(:x, :y) * (smooth() + visual(Scatter)) *
            config(title="Scatter + Smooth (Loess)")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/regression-plots"),

    ("aog_linear_band", "Linear + Confidence Band",
     "Linear regression with confidence ribbon (AoG linear(interval=:confidence))",
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
     end,
     "https://aog.makie.org/stable/reference/analyses#Linear"),

    ("aog_smooth_band", "Smooth + Confidence Band",
     "Smooth regression with confidence ribbon (AoG smooth())",
     """let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [sin(xi)*parse(Int,ai) + parse(Int,ai) + 0.5*randn(1)[1] for (xi,ai) in zip(x,a)]
    df = (; x, y, a)
    data(df) * mapping(:x, :y, color=:a) * (smooth(interval=:confidence) + visual(Scatter)) *
        config(title="Smooth + Confidence Band")
end""",
     () -> let
        x = [0.05i for i in 1:200]
        a = [isodd(i) ? "1" : "2" for i in 1:200]
        y = [sin(xi)*parse(Int,ai) + parse(Int,ai) + 0.5*randn(1)[1] for (xi,ai) in zip(x,a)]
        df = (; x, y, a)
        data(df) * mapping(:x, :y, color=:a) * (smooth(interval=:confidence) + visual(Scatter)) *
            config(height=300, title="Smooth + Confidence Band")
     end,
     "https://aog.makie.org/stable/reference/analyses#Smooth"),

    # --- Layout: Faceting ---

    ("aog_facet", "Facet Grid",
     "Row/col faceting with scatter",
     """let N = 200
    i = [isodd(k) ? "α" : "β" for k in 1:N]
    j = [["a","b","c"][mod1(k,3)] for k in 1:N]
    x = [0.01k + 0.3*randn(1)[1] for k in 1:N]
    y = [0.01k + 0.3*randn(1)[1] for k in 1:N]
    df = (; x, y, i, j)
    data(df) * mapping(:x, :y, row=:i, col=:j) * visual(Scatter) *
        config(title="Facet Grid")
end""",
     () -> let
        N = 200
        i = [isodd(k) ? "α" : "β" for k in 1:N]
        j = [["a","b","c"][mod1(k,3)] for k in 1:N]
        x = [0.01k + 0.3*randn(1)[1] for k in 1:N]
        y = [0.01k + 0.3*randn(1)[1] for k in 1:N]
        df = (; x, y, i, j)
        data(df) * mapping(:x, :y, row=:i, col=:j) * visual(Scatter) *
            config(title="Facet Grid")
     end,
     "https://aog.makie.org/stable/examples/layout/faceting"),

    ("aog_facet_wrap", "Facet Wrap",
     "Layout wrapping with 5 groups",
     """let df = (x=rand(100), y=rand(100), l=[["a","b","c","d","e"][mod1(k,5)] for k in 1:100])
    data(df) * mapping(:x, :y, col=:l) * visual(Scatter) *
        config(title="Facet Wrap", columns=3)
end""",
     () -> let
        df = (x=rand(100), y=rand(100), l=[["a","b","c","d","e"][mod1(k,5)] for k in 1:100])
        data(df) * mapping(:x, :y, col=:l) * visual(Scatter) *
            config(title="Facet Wrap", columns=3)
     end,
     "https://aog.makie.org/stable/examples/layout/faceting"),

    ("aog_facet_multi_layer", "Faceted Multi-Layer",
     "Scatter + Lines across facets from different data",
     """let df1 = (x=rand(100), y=rand(100),
               i=[["a","b","c"][mod1(k,3)] for k in 1:100],
               j=[["d","e","f"][mod1(k,3)] for k in 1:100])
    df2 = (x=[0.0,1.0], y=[0.5,0.5], i=["a","a"], j=["e","e"])
    layers = data(df1) * visual(Scatter) + data(df2) * visual(Lines)
    layers * mapping(:x, :y, col=:i, row=:j) *
        config(title="Faceted Multi-Layer")
end""",
     () -> let
        df1 = (x=rand(100), y=rand(100),
               i=[["a","b","c"][mod1(k,3)] for k in 1:100],
               j=[["d","e","f"][mod1(k,3)] for k in 1:100])
        df2 = (x=[0.0,1.0], y=[0.5,0.5], i=["a","a"], j=["e","e"])
        layers = data(df1) * visual(Scatter) + data(df2) * visual(Lines)
        layers * mapping(:x, :y, col=:i, row=:j) *
            config(title="Faceted Multi-Layer")
     end,
     "https://aog.makie.org/stable/examples/layout/faceting"),

    # --- Applications: Time Series ---

    ("aog_timeseries", "Time Series",
     "Multi-series line plot over dates",
     """let dates = ["2025-01-\$(lpad(d,2,'0'))" for d in 1:31]
    y1 = cumsum(randn(31))
    y2 = cumsum(randn(31))
    n = length(dates)
    df = (; date=[dates;dates], value=[y1;y2], series=[fill("y",n);fill("z",n)])
    data(df) * mapping(:date, :value, color=:series) * visual(Lines) *
        config(title="Time Series")
end""",
     () -> let
        dates = ["2025-01-$(lpad(d,2,'0'))" for d in 1:31]
        y1 = cumsum(randn(31))
        y2 = cumsum(randn(31))
        n = length(dates)
        df = (; date=[dates;dates], value=[y1;y2], series=[fill("y",n);fill("z",n)])
        data(df) * mapping(:date, :value, color=:series) * visual(Lines) *
            config(title="Time Series")
     end,
     "https://aog.makie.org/stable/examples/applications/time-series"),

    ("aog_timeseries_box", "Time Series Box Plot",
     "Box plot of observations per date",
     """let dates = ["2025-01-\$(lpad(d,2,'0'))" for d in 1:15]
    trend = cumsum(randn(15))
    rows_date = String[]
    rows_obs = Float64[]
    for _ in 1:500
        idx = rand(1:15)
        push!(rows_date, dates[idx])
        push!(rows_obs, trend[idx] + 2*rand())
    end
    df = (; date=rows_date, observation=rows_obs)
    data(df) * mapping(:date, :observation) * visual(BoxPlot) *
        config(title="Time Series Box Plot")
end""",
     () -> let
        dates = ["2025-01-$(lpad(d,2,'0'))" for d in 1:15]
        trend = cumsum(randn(15))
        rows_date = String[]
        rows_obs = Float64[]
        for _ in 1:500
            idx = rand(1:15)
            push!(rows_date, dates[idx])
            push!(rows_obs, trend[idx] + 2*rand())
        end
        df = (; date=rows_date, observation=rows_obs)
        data(df) * mapping(:date, :observation) * visual(BoxPlot) *
            config(title="Time Series Box Plot")
     end,
     "https://aog.makie.org/stable/examples/applications/time-series"),

    # --- tidybayes-style uncertainty visualizations ---

    ("pointinterval", "Point + Interval", "tidybayes-style: median with 50%/80%/95% credible intervals",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    pointinterval() *
    config(width=500, height=200, title="Point + Interval (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        pointinterval() *
        config(width=500, height=200, title="Point + Interval (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_pointinterval.html"),

    ("pointinterval_vertical", "Point + Interval (vertical)", "pointinterval with orientation=:vertical — category on x, value on y",
     """data(posterior_draws()) *
    mapping(:parameter, :value) *
    pointinterval(orientation=:vertical) *
    config(width=400, height=300, title="Point + Interval (vertical)")""",
     () -> data(posterior_draws()) *
        mapping(:parameter, :value) *
        pointinterval(orientation=:vertical) *
        config(width=400, height=300, title="Point + Interval (vertical)"),
     "https://mjskay.github.io/ggdist/reference/stat_pointinterval.html"),

    ("halfeye", "Half-Eye Plot", "tidybayes-style: density + point + interval for each parameter",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    (density() + pointinterval()) *
    config(width=500, height=80, title="Half-Eye Plot (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        (density() + pointinterval()) *
        config(width=500, height=80, title="Half-Eye Plot (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_halfeye.html"),

    ("gradient_interval", "Gradient Interval", "tidybayes-style: nested intervals with opacity gradient",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    gradient_interval() *
    config(width=500, height=200, title="Gradient Interval (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        gradient_interval() *
        config(width=500, height=200, title="Gradient Interval (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_gradientinterval.html"),

    ("lineribbon", "Line + Ribbon", "tidybayes-style: regression line with uncertainty ribbons",
     """data(regression_predictions()) *
    mapping(:x, :y, group=:draw) *
    lineribbon() *
    config(width=500, height=350, title="Line + Ribbon (tidybayes-style)")""",
     () -> data(regression_predictions()) *
        mapping(:x, :y, group=:draw) *
        lineribbon() *
        config(width=500, height=350, title="Line + Ribbon (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_lineribbon.html"),

    ("lineribbon_grouped", "Grouped Line + Ribbon", "tidybayes-style: multiple groups with separate ribbon bands",
     """data(grouped_regression_predictions()) *
    mapping(:x, :y, group=:draw, color=:group) *
    lineribbon() *
    config(width=500, height=350, title="Grouped Line + Ribbon")""",
     () -> data(grouped_regression_predictions()) *
        mapping(:x, :y, group=:draw, color=:group) *
        lineribbon() *
        config(width=500, height=350, title="Grouped Line + Ribbon"),
     "https://mjskay.github.io/ggdist/reference/stat_lineribbon.html"),

    ("lineribbon_faceted", "Faceted Line + Ribbon", "tidybayes-style: line ribbons faceted by col+row",
     """data(faceted_regression_predictions()) *
    mapping(:x, :y, group=:draw, col=:panel, row=:site) *
    lineribbon() *
    config(width=180, height=120, title="Faceted Line + Ribbon")""",
     () -> data(faceted_regression_predictions()) *
        mapping(:x, :y, group=:draw, col=:panel, row=:site) *
        lineribbon() *
        config(width=180, height=120, title="Faceted Line + Ribbon"),
     "https://mjskay.github.io/ggdist/reference/stat_lineribbon.html"),

    ("lineribbon_overlay", "Ribbon + Scatter Overlay", "faceted lineribbon (col+row) with observed data points overlaid",
     """pred = data(faceted_regression_predictions()) *
    mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
obs = data(faceted_observations()) *
    mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
(pred + obs) * config(width=180, height=120, title="Ribbon + Observations")""",
     () -> begin
        pred = data(faceted_regression_predictions()) *
            mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
        obs = data(faceted_observations()) *
            mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
        (pred + obs) * config(width=180, height=120, title="Ribbon + Observations")
     end,
     "https://mjskay.github.io/ggdist/reference/stat_lineribbon.html"),

    ("lineribbon_logscale", "Ribbon + Scatter (log scale)", "faceted lineribbon+scatter with AoG-style scales(Y=(; scale=log10))",
     """using Tables
exp_table(t) = (x=Tables.getcolumn(t,:x), y=exp.(Tables.getcolumn(t,:y)),
    (k => Tables.getcolumn(t,k) for k in Tables.columnnames(t) if k ∉ (:x,:y))...)
pred = data(exp_table(faceted_regression_predictions())) *
    mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
obs = data(exp_table(faceted_observations())) *
    mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
(pred + obs) * config(width=180, height=120, scales=scales(Y=(; scale=log10)))""",
     () -> begin
        exp_table(t) = (x=Tables.getcolumn(t,:x), y=exp.(Tables.getcolumn(t,:y)),
            (k => Tables.getcolumn(t,k) for k in Tables.columnnames(t) if k ∉ (:x,:y))...)
        pred = data(exp_table(faceted_regression_predictions())) *
            mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
        obs = data(exp_table(faceted_observations())) *
            mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
        (pred + obs) * config(width=180, height=120, scales=scales(Y=(; scale=log10)))
     end),

    ("ppc_overlay", "PPC Overlay", "ppc_overlay recipe: observations + predictions + truth with independent scales",
     """ppc_overlay(
    faceted_observations(), faceted_regression_predictions();
    x=:x, y=:y, col=:panel, row=:site, group=:draw,
) * config(width=180, height=120, facet=(; linkxaxes=:none, linkyaxes=:none)) |> vdraw""",
     () -> ppc_overlay(
        faceted_observations(), faceted_regression_predictions();
        x=:x, y=:y, col=:panel, row=:site, group=:draw,
    ) * config(width=180, height=120, facet=(; linkxaxes=:none, linkyaxes=:none))),

    ("ribbon_only", "Ribbon (no line)", "tidybayes-style: uncertainty ribbons without median line",
     """data(regression_predictions()) *
    mapping(:x, :y, group=:draw) *
    ribbon() *
    config(width=500, height=350, title="Ribbon Only (tidybayes-style)")""",
     () -> data(regression_predictions()) *
        mapping(:x, :y, group=:draw) *
        ribbon() *
        config(width=500, height=350, title="Ribbon Only (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_ribbon.html"),

    ("precomputed_lineribbon", "Pre-aggregated Line + Ribbon", "lineribbon from pre-computed quantile columns (no draws)",
     """summary = _preaggregate(regression_predictions(), :x)
data(summary) * mapping(:x, :median => "Response") *
    lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=350, title="Pre-aggregated Line + Ribbon")""",
     () -> begin
        summary = _preaggregate(regression_predictions(), :x)
        data(summary) * mapping(:x, :median => "Response") *
            lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
            config(width=500, height=350, title="Pre-aggregated Line + Ribbon")
     end),

    ("precomputed_lineribbon_grouped", "Pre-aggregated Grouped Ribbon", "pre-aggregated lineribbon with color grouping",
     """summary = _preaggregate(grouped_regression_predictions(), :x, :group)
data(summary) * mapping(:x, :median, color=:group) *
    lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=350, title="Pre-aggregated Grouped Ribbon")""",
     () -> begin
        summary = _preaggregate(grouped_regression_predictions(), :x, :group)
        data(summary) * mapping(:x, :median, color=:group) *
            lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
            config(width=500, height=350, title="Pre-aggregated Grouped Ribbon")
     end),

    ("precomputed_pointinterval", "Pre-aggregated Point + Interval", "pointinterval from pre-computed quantile columns (no draws)",
     """raw = posterior_draws()
summary = _preaggregate((; y=raw.value, parameter=raw.parameter), :parameter)
data(summary) * mapping(:median, y=:parameter) *
    pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=200, title="Pre-aggregated Point + Interval")""",
     () -> begin
        raw = posterior_draws()
        summary = _preaggregate((; y=raw.value, parameter=raw.parameter), :parameter)
        data(summary) * mapping(:median, y=:parameter) *
            pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
            config(width=500, height=200, title="Pre-aggregated Point + Interval")
     end),

    ("pointinterval_vertical_overlay", "Vertical PI + Scatter overlay (BRM bug repro)",
     "Vertical pointinterval(bands=...) + visual(Scatter), row-faceted, integer :index, scalar params (one row per facet) — matches BRM's stan_generate truth overlay shape.",
     """# Match BRM: integer :index, some scalar params (index=0), bands=3
params = ["α","β","σ","β","σ","σ"]  # scalars α once; β has index 0+1; σ has 0+1+2
indices = [0, 0, 0, 1, 1, 2]
medians = [2.0, 0.8, 1.2, 0.85, 1.25, 1.3]
q025s   = [1.5, 0.5, 1.0, 0.55, 1.05, 1.1]
q975s   = [2.5, 1.1, 1.4, 1.15, 1.45, 1.5]
q10s    = [1.7, 0.6, 1.1, 0.65, 1.15, 1.2]
q90s    = [2.3, 1.0, 1.3, 1.05, 1.35, 1.4]
q25s    = [1.8, 0.7, 1.15, 0.75, 1.2, 1.25]
q75s    = [2.2, 0.9, 1.25, 0.95, 1.3, 1.35]
summary = (; param=params, index=indices, median=medians,
             q025=q025s, q10=q10s, q25=q25s, q75=q75s, q90=q90s, q975=q975s)
truth = (; param=params, index=indices, truth=[2.05, 0.82, 1.22, 0.87, 1.27, 1.32])
pi = data(summary) * mapping(:index, :median, row=:param) *
     pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75],
                   orientation=:vertical)
overlay = data(truth) * mapping(:index, :truth, row=:param) *
          visual(Scatter; color=:black, strokewidth=0)
(pi + overlay) * config(width=400, height=80, facet=(; linkyaxes=:none),
                         title="Vertical PI + Scatter overlay (BRM pattern)")""",
     () -> begin
        params = ["α","β","σ","β","σ","σ"]
        indices = [0, 0, 0, 1, 1, 2]
        medians = [2.0, 0.8, 1.2, 0.85, 1.25, 1.3]
        q025s   = [1.5, 0.5, 1.0, 0.55, 1.05, 1.1]
        q975s   = [2.5, 1.1, 1.4, 1.15, 1.45, 1.5]
        q10s    = [1.7, 0.6, 1.1, 0.65, 1.15, 1.2]
        q90s    = [2.3, 1.0, 1.3, 1.05, 1.35, 1.4]
        q25s    = [1.8, 0.7, 1.15, 0.75, 1.2, 1.25]
        q75s    = [2.2, 0.9, 1.25, 0.95, 1.3, 1.35]
        summary = (; param=params, index=indices, median=medians,
                     q025=q025s, q10=q10s, q25=q25s, q75=q75s, q90=q90s, q975=q975s)
        truth = (; param=params, index=indices, truth=[2.05, 0.82, 1.22, 0.87, 1.27, 1.32])
        pi = data(summary) * mapping(:index, :median, row=:param) *
             pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75],
                           orientation=:vertical)
        overlay = data(truth) * mapping(:index, :truth, row=:param) *
                  visual(Scatter; color=:black, strokewidth=0)
        (pi + overlay) * config(width=400, height=80, facet=(; linkyaxes=:none),
                                 title="Vertical PI + Scatter overlay (BRM pattern)")
     end),

    ("remap_precomputed_pointinterval_positional", "Remap Pre-agg. PI — positional dim",
     "BRM-style repro: horizontal PI with :index on x (positional), :param on row (named). " *
     "Verifies the pinned catch-all leaves positionally-assigned fields alone rather than combining them " *
     "(was producing a `param/index` combo and „/ undefined“ titles).",
     """raw = posterior_draws()
# Build a fake long-form summary: 3 params × 2 index positions, pre-aggregated.
params = repeat(["α", "β", "σ"]; inner=2)
indices = repeat(string.(1:2); outer=3)
medians = [2.0, 2.1, 0.8, 0.85, 1.2, 1.25]
q025s   = [1.5, 1.6, 0.5, 0.55, 1.0, 1.05]
q975s   = [2.5, 2.6, 1.1, 1.15, 1.4, 1.45]
summary = (; param=params, index=indices, median=medians, q025=q025s, q975=q975s)
spec = data(summary) *
       mapping(:index, :median, row=:param) *   # :index on x (positional); :param on row
       pointinterval(bands=[:q025 => :q975], orientation=:vertical) *
       config(width=400, height=150, title="BRM-style: positional :index + row=:param")
auto_remap_node("remap-pi-positional", spec;
    dims=["param" => "Parameter", "index" => "Index"],
    pinned=:row)""",
     () -> begin
        params = repeat(["α", "β", "σ"]; inner=2)
        indices = repeat(string.(1:2); outer=3)
        medians = [2.0, 2.1, 0.8, 0.85, 1.2, 1.25]
        q025s   = [1.5, 1.6, 0.5, 0.55, 1.0, 1.05]
        q975s   = [2.5, 2.6, 1.1, 1.15, 1.4, 1.45]
        summary = (; param=params, index=indices, median=medians, q025=q025s, q975=q975s)
        spec = data(summary) *
               mapping(:index, :median, row=:param) *
               pointinterval(bands=[:q025 => :q975], orientation=:vertical) *
               config(width=400, height=150, title="BRM-style: positional :index + row=:param")
        auto_remap_node("remap-pi-positional", spec;
            dims=["param" => "Parameter", "index" => "Index"],
            pinned=:row)
     end),

    ("remap_precomputed_lineribbon", "Remap Pre-aggregated Ribbon", "auto_remap_node on pre-aggregated lineribbon with color/row switching",
     """id = "remap-precomp-lr"
summary = _preaggregate(faceted_regression_predictions(), :x, :panel, :site)
spec = data(summary) * mapping(:x, :median, color=:panel, row=:site) *
       lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
       config(title="Remap Pre-aggregated Ribbon")
auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])""",
     () -> begin
        id = "remap-precomp-lr"
        summary = _preaggregate(faceted_regression_predictions(), :x, :panel, :site)
        spec = data(summary) * mapping(:x, :median, color=:panel, row=:site) *
               lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
               config(title="Remap Pre-aggregated Ribbon")
        auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])
     end),

    ("dotinterval", "Quantile Dotplot", "tidybayes-style: quantile dots with interval overlay",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    dotinterval() *
    config(width=500, height=200, title="Quantile Dotplot + Interval (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        dotinterval() *
        config(width=500, height=200, title="Quantile Dotplot + Interval (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/reference/stat_dotsinterval.html"),

    ("raincloud", "Raincloud Plot", "tidybayes-style: density + jittered points + boxplot",
     """data(posterior_draws()) *
    mapping(:value, y=:parameter) *
    (density() + visual(Scatter, opacity=0.3) + visual(BoxPlot)) *
    config(width=500, height=300, title="Raincloud Plot (tidybayes-style)")""",
     () -> data(posterior_draws()) *
        mapping(:value, y=:parameter) *
        (density() + visual(Scatter, opacity=0.3) + visual(BoxPlot)) *
        config(width=500, height=300, title="Raincloud Plot (tidybayes-style)"),
     "https://mjskay.github.io/ggdist/articles/raincloud.html"),

    # --- Additional Marks ---

    ("aog_step", "Step Chart", "Staircase interpolation for cumulative/discrete data",
     """let x = collect(1:20)
    y = cumsum(rand(20) .- 0.3)
    data((; x, y)) * mapping(:x, :y) * visual(Stairs) *
        config(title="Step Chart (Stairs)")
end""",
     () -> let
        x = collect(1:20)
        y = cumsum(rand(20) .- 0.3)
        data((; x, y)) * mapping(:x, :y) * visual(Stairs) *
            config(title="Step Chart (Stairs)")
     end),

    ("aog_rules", "Reference Lines", "Scatter with mean reference line overlay",
     """let df = cars()
    mean_mpg = sum(df.mpg) / length(df.mpg)
    (data(df) * mapping(:horsepower, :mpg) * visual(Scatter) +
     data((; y=[mean_mpg])) * mapping(:y) * visual(HLines)) *
        config(title="MPG with Mean Reference Line")
end""",
     () -> let
        df = cars()
        mean_mpg = sum(df.mpg) / length(df.mpg)
        (data(df) * mapping(:horsepower, :mpg) * visual(Scatter) +
         data((; y=[mean_mpg])) * mapping(:y) * visual(HLines)) *
            config(title="MPG with Mean Reference Line")
     end),

    ("aog_vlines_faceted_color", "VLines color mapping (bug)",
     "Two scatter layers (obs + pred) faceted by assay (col) × subject (row), plus a VLines dosing layer with its own color=:vessel mapping. The VLines should render one color per vessel, but the per-layer color mapping is currently ignored.",
     """let
    subjects = [\"S1\", \"S2\"]
    assays   = [\"A\", \"B\"]
    obs = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_obs   = randn(40))
    pred = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_pred  = randn(40) .+ 0.2)
    dose = (;
        subject = [\"S1\",\"S1\",\"S1\",\"S2\",\"S2\",\"S2\",\"S1\",\"S1\",\"S2\",\"S2\"],
        diet    = [\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\"],
        amount_mug = [10.0, 20.0, 10.0, 10.0, 20.0, 10.0, 5.0, 5.0, 5.0, 5.0],
        time_h  = [0.0, 8.0, 16.0, 0.0, 8.0, 16.0, 0.0, 12.0, 0.0, 12.0],
        vessel  = [\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"Oral\",\"IV\"])
    (data(obs) *
        mapping(:time_h => \"Time (h)\", :y_obs => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"black\") +
     data(pred) *
        mapping(:time_h => \"Time (h)\", :y_pred => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"steelblue\", opacity=0.6) +
     data(dose) *
        mapping(:time_h => \"Time (h)\"; row=:subject,
                color=:vessel => \"Vessel\",
                linestyle=:diet => \"Diet\",
                linewidth=:amount_mug => \"Dose (μg)\") *
        visual(VLines; opacity=0.5)) *
        config(title=\"VLines color=:vessel should render per-vessel colors\")
end""",
     () -> let
        subjects = ["S1", "S2"]
        assays   = ["A", "B"]
        obs = (;
            subject = repeat(subjects, inner=20),
            assay   = repeat(assays, 20),
            time_h  = repeat(collect(range(0, 24, length=20)), 2),
            y_obs   = randn(40))
        pred = (;
            subject = repeat(subjects, inner=20),
            assay   = repeat(assays, 20),
            time_h  = repeat(collect(range(0, 24, length=20)), 2),
            y_pred  = randn(40) .+ 0.2)
        dose = (;
            subject = ["S1","S1","S1","S2","S2","S2","S1","S1","S2","S2"],
            diet    = ["Fed","Fasted","Fed","Fed","Fasted","Fed","Fed","Fed","Fasted","Fed"],
            amount_mug = [10.0, 20.0, 10.0, 10.0, 20.0, 10.0, 5.0, 5.0, 5.0, 5.0],
            time_h  = [0.0, 8.0, 16.0, 0.0, 8.0, 16.0, 0.0, 12.0, 0.0, 12.0],
            vessel  = ["IV","Oral","IV","Oral","IV","Oral","IV","Oral","Oral","IV"])
        (data(obs) *
            mapping(:time_h => "Time (h)", :y_obs => "Response"; row=:subject, col=:assay) *
            visual(Scatter; color="black") +
         data(pred) *
            mapping(:time_h => "Time (h)", :y_pred => "Response"; row=:subject, col=:assay) *
            visual(Scatter; color="steelblue", opacity=0.6) +
         data(dose) *
            mapping(:time_h => "Time (h)"; row=:subject,
                    color=:vessel => "Vessel",
                    linestyle=:diet => "Diet",
                    linewidth=:amount_mug => "Dose (μg)") *
            visual(VLines; opacity=0.5)) *
            config(title="VLines color=:vessel should render per-vessel colors")
     end),

    ("aog_vlines_faceted_color_remap", "VLines color mapping under auto_remap (bug)",
     "Same 2 scatter + VLines setup as aog_vlines_faceted_color, but wrapped in auto_remap_node. VLines' per-layer color=:vessel should survive the Julia-side _rebuild_layer pass AND the JS remapEncoding color override, but is currently clobbered.",
     """let
    subjects = [\"S1\", \"S2\"]
    assays   = [\"A\", \"B\"]
    obs = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_obs   = randn(40))
    pred = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_pred  = randn(40) .+ 0.2)
    dose = (;
        subject = [\"S1\",\"S1\",\"S1\",\"S2\",\"S2\",\"S2\",\"S1\",\"S1\",\"S2\",\"S2\"],
        diet    = [\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\"],
        amount_mug = [10.0, 20.0, 10.0, 10.0, 20.0, 10.0, 5.0, 5.0, 5.0, 5.0],
        time_h  = [0.0, 8.0, 16.0, 0.0, 8.0, 16.0, 0.0, 12.0, 0.0, 12.0],
        vessel  = [\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"Oral\",\"IV\"])
    spec = (data(obs) *
        mapping(:time_h => \"Time (h)\", :y_obs => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"black\") +
     data(pred) *
        mapping(:time_h => \"Time (h)\", :y_pred => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"steelblue\", opacity=0.6) +
     data(dose) *
        mapping(:time_h => \"Time (h)\"; row=:subject,
                color=:vessel => \"Vessel\",
                linestyle=:diet => \"Diet\",
                linewidth=:amount_mug => \"Dose (μg)\") *
        visual(VLines; opacity=0.5)) *
        config(title=\"VLines color=:vessel under auto_remap\")
    auto_remap_node(\"vlines-remap-bug\", spec;
        dims=[:subject => \"Subject\", :assay => \"Assay\"])
end""",
     () -> let
        subjects = ["S1", "S2"]
        assays   = ["A", "B"]
        obs = (;
            subject = repeat(subjects, inner=20),
            assay   = repeat(assays, 20),
            time_h  = repeat(collect(range(0, 24, length=20)), 2),
            y_obs   = randn(40))
        pred = (;
            subject = repeat(subjects, inner=20),
            assay   = repeat(assays, 20),
            time_h  = repeat(collect(range(0, 24, length=20)), 2),
            y_pred  = randn(40) .+ 0.2)
        dose = (;
            subject = ["S1","S1","S1","S2","S2","S2","S1","S1","S2","S2"],
            diet    = ["Fed","Fasted","Fed","Fed","Fasted","Fed","Fed","Fed","Fasted","Fed"],
            amount_mug = [10.0, 20.0, 10.0, 10.0, 20.0, 10.0, 5.0, 5.0, 5.0, 5.0],
            time_h  = [0.0, 8.0, 16.0, 0.0, 8.0, 16.0, 0.0, 12.0, 0.0, 12.0],
            vessel  = ["IV","Oral","IV","Oral","IV","Oral","IV","Oral","Oral","IV"])
        spec = (data(obs) *
            mapping(:time_h => "Time (h)", :y_obs => "Response"; row=:subject, col=:assay) *
            visual(Scatter; color="black") +
         data(pred) *
            mapping(:time_h => "Time (h)", :y_pred => "Response"; row=:subject, col=:assay) *
            visual(Scatter; color="steelblue", opacity=0.6) +
         data(dose) *
            mapping(:time_h => "Time (h)"; row=:subject,
                    color=:vessel => "Vessel",
                    linestyle=:diet => "Diet",
                    linewidth=:amount_mug => "Dose (μg)") *
            visual(VLines; opacity=0.5)) *
            config(title="VLines color=:vessel under auto_remap")
        auto_remap_node("vlines-remap-bug", spec;
            dims=[:subject => "Subject", :assay => "Assay"])
     end),

    ("aog_errorbars", "Error Bars", "Point estimates with error bars",
     """let categories = ["A", "B", "C", "D", "E"]
    means = [4.2, 3.8, 5.1, 4.6, 3.5]
    lo = means .- [0.5, 0.3, 0.7, 0.4, 0.6]
    hi = means .+ [0.5, 0.3, 0.7, 0.4, 0.6]
    df = (; category=categories, mean=means, lo, hi)
    (data(df) * mapping(:category, :mean) * visual(Scatter) +
     data(df) * mapping(:category, :lo, :hi) * visual(Rangebars)) *
        config(title="Estimates with Error Bars")
end""",
     () -> let
        categories = ["A", "B", "C", "D", "E"]
        means = [4.2, 3.8, 5.1, 4.6, 3.5]
        lo = means .- [0.5, 0.3, 0.7, 0.4, 0.6]
        hi = means .+ [0.5, 0.3, 0.7, 0.4, 0.6]
        df = (; category=categories, mean=means, lo=lo, hi=hi)
        (data(df) * mapping(:category, :mean) * visual(Scatter) +
         data(df) * mapping(:category, :lo, :hi) * visual(Rangebars)) *
            config(title="Estimates with Error Bars")
     end),

    # --- Composition Patterns ---

    ("aog_scatter_regression", "Scatter + Regression", "Points with linear fit and confidence band",
     """data(cars()) *
    mapping(:horsepower, :mpg) *
    (visual(Scatter, opacity=0.5) + linear(interval=:confidence)) *
    config(title="MPG vs Horsepower with Regression")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg) *
        (visual(Scatter, opacity=0.5) + linear(interval=:confidence)) *
        config(title="MPG vs Horsepower with Regression")),

    ("aog_scatter_smooth", "Scatter + Smooth", "Points with loess curve and confidence band",
     """data(cars()) *
    mapping(:horsepower, :mpg) *
    (visual(Scatter, opacity=0.5) + smooth(interval=:confidence)) *
    config(title="MPG vs Horsepower with Smooth")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg) *
        (visual(Scatter, opacity=0.5) + smooth(interval=:confidence)) *
        config(title="MPG vs Horsepower with Smooth")),

    ("aog_bar_line_combo", "Bar + Line", "Sales bars with trend line overlay",
     """let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    sales = [120, 135, 148, 142, 165, 178, 195, 188, 172, 158, 145, 162]
    trend = [125, 130, 138, 145, 152, 160, 168, 175, 170, 163, 155, 158]
    (data((; month=months, sales)) * mapping(:month, :sales) * visual(BarPlot, opacity=0.6) +
     data((; month=months, trend)) * mapping(:month, :trend) * visual(Lines, color=:red)) *
        config(title="Monthly Sales with Trend")
end""",
     () -> let
        months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        sales = [120, 135, 148, 142, 165, 178, 195, 188, 172, 158, 145, 162]
        trend = [125, 130, 138, 145, 152, 160, 168, 175, 170, 163, 155, 158]
        (data((; month=months, sales=sales)) * mapping(:month, :sales) * visual(BarPlot, opacity=0.6) +
         data((; month=months, trend=trend)) * mapping(:month, :trend) * visual(Lines, color=:red)) *
            config(title="Monthly Sales with Trend")
     end),

    ("aog_stacked_area", "Stacked Area", "Stacked area chart with color groups",
     """let n = 12
    months = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3)
    category = repeat(["Web", "Mobile", "Desktop"], inner=12)
    values = [45,52,58,55,62,68,72,70,65,58,50,48,
              30,35,42,48,55,60,65,62,55,45,38,35,
              25,22,20,18,15,12,10,12,15,18,22,24]
    data((; month=months, value=values, category)) *
        mapping(:month, :value, color=:category) *
        visual(Band) *
        config(title="Traffic by Channel",
               encoding=Dict("y" => Dict("stack" => "zero")))
end""",
     () -> let
        months = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3)
        category = repeat(["Web", "Mobile", "Desktop"], inner=12)
        values = [45,52,58,55,62,68,72,70,65,58,50,48,
                  30,35,42,48,55,60,65,62,55,45,38,35,
                  25,22,20,18,15,12,10,12,15,18,22,24]
        data((; month=months, value=values, category=category)) *
            mapping(:month, :value, color=:category) *
            visual(Band) *
            config(title="Traffic by Channel",
                   encoding=Dict("y" => Dict("stack" => "zero")))
     end),

    # --- Frequency & Expectation ---

    ("aog_frequency", "Frequency Count", "Count occurrences per category",
     """data(cars()) * mapping(:origin) * frequency() *
    config(title="Car Count by Origin")""",
     () -> data(cars()) * mapping(:origin) * frequency() *
        config(title="Car Count by Origin")),

    ("aog_expectation", "Mean (Expectation)", "Average value per category",
     """data(cars()) * mapping(:origin, :mpg) * expectation() *
    config(title="Mean MPG by Origin")""",
     () -> data(cars()) * mapping(:origin, :mpg) * expectation() *
        config(title="Mean MPG by Origin")),

    ("aog_frequency_color", "Frequency by Group", "Stacked frequency counts with color",
     """data(tips()) * mapping(:day, color=:sex) * frequency() *
    config(title="Tips per Day by Gender")""",
     () -> data(tips()) * mapping(:day, color=:sex) * frequency() *
        config(title="Tips per Day by Gender")),

    # --- Advanced Patterns ---

    ("aog_facet_regression", "Faceted Regression", "Scatter + linear fit per facet panel",
     """data(cars()) *
    mapping(:horsepower, :mpg, col=:origin) *
    (visual(Scatter, opacity=0.5) + linear()) *
    config(title="MPG vs HP by Origin")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, col=:origin) *
        (visual(Scatter, opacity=0.5) + linear()) *
        config(title="MPG vs HP by Origin")),

    ("aog_color_regression", "Grouped Regression", "Per-group linear fit with color",
     """data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    (visual(Scatter, opacity=0.5) + linear()) *
    config(title="MPG vs HP by Origin (colored)")""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        (visual(Scatter, opacity=0.5) + linear()) *
        config(title="MPG vs HP by Origin (colored)")),

    ("aog_2d_histogram", "2D Histogram", "Binned heatmap showing point density",
     """data(cars()) *
    mapping(:horsepower, :mpg) *
    visual(Heatmap) *
    config(title="HP vs MPG Density",
           encoding=Dict(
               "x" => Dict("bin" => Dict("maxbins" => 15)),
               "y" => Dict("bin" => Dict("maxbins" => 15)),
               "color" => Dict("aggregate" => "count", "type" => "quantitative")))""",
     () -> data(cars()) *
        mapping(:horsepower, :mpg) *
        visual(Heatmap) *
        config(title="HP vs MPG Density",
               encoding=Dict(
                   "x" => Dict("bin" => Dict("maxbins" => 15)),
                   "y" => Dict("bin" => Dict("maxbins" => 15)),
                   "color" => Dict("aggregate" => "count", "type" => "quantitative")))),

    # --- BRM-encountered repros (bugs + regressions for things that work) ---

    ("brm_histogram_faceted_shared_x", "Histogram row-faceted — linkxaxes=:none ignored (bug)",
     "Histogram with row=:param and config(facet=(; linkxaxes=:none)) should give each facet its own x-range; observed: all rows share the union x-range. Pre-dates overlays.",
     """# Two params with wildly different value ranges:
df = (;
    param = vcat(fill(\"a\", 200), fill(\"b\", 200)),
    value = vcat(randn(200), randn(200) .- 8))
data(df) * mapping(:value; row=:param) * histogram() *
    config(facet=(; linkxaxes=:none),
           title=\"Expect independent x per facet; get shared\")""",
     () -> let
        df = (;
            param = vcat(fill("a", 200), fill("b", 200)),
            value = vcat(randn(200), randn(200) .- 8))
        data(df) * mapping(:value; row=:param) * histogram() *
            config(facet=(; linkxaxes=:none),
                   title="Expect independent x per facet; get shared")
     end),

    ("brm_histogram_bins_kwarg", "Histogram with bins=30 kwarg (regression)",
     "histogram(; bins=30) kwarg should reach VL's bin config as maxbins=30. Row-faceted + color-stacked to exercise the in-spec transform path.",
     """df = (;
    param = vcat(fill(\"a\", 500), fill(\"b\", 500)),
    value = vcat(randn(500), randn(500) .- 8))
data(df) * mapping(:value; row=:param) * histogram(; bins=30) *
    config(facet=(; linkxaxes=:none),
           title=\"histogram(; bins=30), row-faceted\")""",
     () -> let
        df = (;
            param = vcat(fill("a", 500), fill("b", 500)),
            value = vcat(randn(500), randn(500) .- 8))
        data(df) * mapping(:value; row=:param) * histogram(; bins=30) *
            config(facet=(; linkxaxes=:none),
                   title="histogram(; bins=30), row-faceted")
     end),

    ("brm_histogram_datalimits_extrema", "Histogram with datalimits=extrema (works)",
     "Per-facet local bin extents via AoG.histogram(; bins=30, datalimits=extrema). Regression entry confirming the workaround for the shared-x issue above.",
     """df = (;
    param = vcat(fill(\"a\", 200), fill(\"b\", 200)),
    value = vcat(randn(200), randn(200) .- 8))
data(df) * mapping(:value; row=:param) *
    histogram(; bins=30, datalimits=extrema) *
    config(facet=(; linkxaxes=:none),
           title=\"Per-facet bins via datalimits=extrema\")""",
     () -> let
        df = (;
            param = vcat(fill("a", 200), fill("b", 200)),
            value = vcat(randn(200), randn(200) .- 8))
        data(df) * mapping(:value; row=:param) *
            histogram(; bins=30, datalimits=extrema) *
            config(facet=(; linkxaxes=:none),
                   title="Per-facet bins via datalimits=extrema")
     end),

    ("brm_scatter_filled_default", "Scatter filled by default",
     "visual(Scatter) fills by default (matches Makie). Override with filled=false for hollow markers.",
     """df = (; x=1:10, y=randn(10))
filled = data(df) * mapping(:x, :y) * visual(Scatter; color=:black) *
         config(title=\"visual(Scatter) -- filled (default)\")
hollow = data(df) * mapping(:x, :y) * visual(Scatter; color=:black, filled=false) *
         config(title=\"visual(Scatter; filled=false) -- hollow\")
(filled + hollow)""",
     () -> let
        df = (; x=1:10, y=randn(10))
        filled = data(df) * mapping(:x, :y) * visual(Scatter; color=:black) *
                 config(title="visual(Scatter) -- filled (default)")
        hollow = data(df) * mapping(:x, :y) * visual(Scatter; color=:black, filled=false) *
                 config(title="visual(Scatter; filled=false) -- hollow")
        (filled + hollow)
     end),

    ("brm_lineribbon_bands_scatter_overlay", "LineRibbon + Scatter overlay (works)",
     "Parallel of the PI-overlay bug but on lineribbon(bands=...): works. Regression entry so the counterpart PI-overlay fix doesn't break this path.",
     """params = [\"a\", \"a\", \"a\", \"b\", \"b\", \"b\"]
indices = [1, 2, 3, 1, 2, 3]
medians = [2.0, 2.1, 2.2, 0.8, 0.9, 1.0]
q025s   = [1.5, 1.6, 1.7, 0.5, 0.6, 0.7]
q975s   = [2.5, 2.6, 2.7, 1.1, 1.2, 1.3]
q25s    = [1.8, 1.9, 2.0, 0.7, 0.8, 0.9]
q75s    = [2.2, 2.3, 2.4, 0.9, 1.0, 1.1]
summary = (; param=params, index=indices, median=medians,
             q025=q025s, q25=q25s, q75=q75s, q975=q975s)
truth = (; param=params, index=indices, truth=[2.05, 2.15, 2.25, 0.85, 0.95, 1.05])
lr = data(summary) * mapping(:index, :median, row=:param) *
     lineribbon(bands=[:q025 => :q975, :q25 => :q75])
overlay = data(truth) * mapping(:index, :truth, row=:param) *
          visual(Scatter; color=:black, filled=true)
(lr + overlay) * config(facet=(; linkyaxes=:none),
                         title=\"LineRibbon + Scatter overlay (works)\")""",
     () -> let
        params = ["a", "a", "a", "b", "b", "b"]
        indices = [1, 2, 3, 1, 2, 3]
        medians = [2.0, 2.1, 2.2, 0.8, 0.9, 1.0]
        q025s   = [1.5, 1.6, 1.7, 0.5, 0.6, 0.7]
        q975s   = [2.5, 2.6, 2.7, 1.1, 1.2, 1.3]
        q25s    = [1.8, 1.9, 2.0, 0.7, 0.8, 0.9]
        q75s    = [2.2, 2.3, 2.4, 0.9, 1.0, 1.1]
        summary = (; param=params, index=indices, median=medians,
                     q025=q025s, q25=q25s, q75=q75s, q975=q975s)
        truth = (; param=params, index=indices,
                   truth=[2.05, 2.15, 2.25, 0.85, 0.95, 1.05])
        lr = data(summary) * mapping(:index, :median, row=:param) *
             lineribbon(bands=[:q025 => :q975, :q25 => :q75])
        overlay = data(truth) * mapping(:index, :truth, row=:param) *
                  visual(Scatter; color=:black, filled=true)
        (lr + overlay) * config(facet=(; linkyaxes=:none),
                                 title="LineRibbon + Scatter overlay (works)")
     end),

    ("brm_ecdf_vlines_overlay_dual_legend", "ECDF + VLines overlay — dual color legends (bug)",
     "Base ECDFPlot and overlay VLines both use color=:index => nonnumeric, but render with two separate color scales/legends. VLines layer's nonnumeric modifier appears not to propagate into its scale emission.",
     """# long: per-draw values, color=:index
long = (;
    param = repeat([\"a\",\"b\"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
truth = (;
    param = [\"a\",\"a\",\"a\",\"b\",\"b\",\"b\"],
    index = [1, 2, 3, 1, 2, 3],
    truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
base = data(long) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       visual(ECDFPlot)
overlay = data(truth) *
          mapping(:truth; row=:param, color=:index => nonnumeric) *
          visual(VLines)
(base + overlay) *
    config(facet=(; linkxaxes=:none),
           title=\"ECDF + VLines overlay -- expect one merged color legend\")""",
     () -> let
        long = (;
            param = repeat(["a","b"], inner=300),
            index = repeat(repeat(1:3, inner=100), 2),
            value = vcat(randn(300), randn(300) .- 5))
        truth = (;
            param = ["a","a","a","b","b","b"],
            index = [1, 2, 3, 1, 2, 3],
            truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
        base = data(long) *
               mapping(:value; row=:param, color=:index => nonnumeric) *
               visual(ECDFPlot)
        overlay = data(truth) *
                  mapping(:truth; row=:param, color=:index => nonnumeric) *
                  visual(VLines)
        (base + overlay) *
            config(facet=(; linkxaxes=:none),
                   title="ECDF + VLines overlay -- expect one merged color legend")
     end),

    ("brm_ecdf_faceted_nominal_color", "ECDF with nominal color (works)",
     "ECDFPlot base layer with color=:Int => nonnumeric renders a discrete categorical legend. Regression entry for the base-layer color path.",
     """long = (;
    param = repeat([\"a\",\"b\"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
data(long) *
    mapping(:value; row=:param, color=:index => nonnumeric) *
    visual(ECDFPlot) *
    config(facet=(; linkxaxes=:none),
           title=\"ECDF faceted + nominal color (works)\")""",
     () -> let
        long = (;
            param = repeat(["a","b"], inner=300),
            index = repeat(repeat(1:3, inner=100), 2),
            value = vcat(randn(300), randn(300) .- 5))
        data(long) *
            mapping(:value; row=:param, color=:index => nonnumeric) *
            visual(ECDFPlot) *
            config(facet=(; linkxaxes=:none),
                   title="ECDF faceted + nominal color (works)")
     end),

    ("brm_ecdf_picker_nonnumeric_lost", "ECDF + VLines via picker — nonnumeric lost (bug)",
     "Same spec as brm_ecdf_vlines_overlay_dual_legend (which now renders a single color legend), but routed through with_plot_caption(spec; auto_remap=…). BRM reports the picker path reverts to dual legends — _auto_remap_parts must be dropping the nonnumeric Pair modifier when re-composing layers.",
     """long = (;
    param = repeat([\"a\",\"b\"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
truth = (;
    param = [\"a\",\"a\",\"a\",\"b\",\"b\",\"b\"],
    index = [1, 2, 3, 1, 2, 3],
    truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
base = data(long) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       visual(ECDFPlot)
overlay = data(truth) *
          mapping(:truth; row=:param, color=:index => nonnumeric) *
          visual(VLines)
spec = (base + overlay) *
       config(facet=(; linkxaxes=:none),
              title=\"ECDF + VLines via auto_remap (picker)\")
auto_remap_node(\"brm-ecdf-picker\", spec;
    dims=[\"param\" => \"Parameter\", \"index\" => \"Index\"])""",
     () -> let
        long = (;
            param = repeat(["a","b"], inner=300),
            index = repeat(repeat(1:3, inner=100), 2),
            value = vcat(randn(300), randn(300) .- 5))
        truth = (;
            param = ["a","a","a","b","b","b"],
            index = [1, 2, 3, 1, 2, 3],
            truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
        base = data(long) *
               mapping(:value; row=:param, color=:index => nonnumeric) *
               visual(ECDFPlot)
        overlay = data(truth) *
                  mapping(:truth; row=:param, color=:index => nonnumeric) *
                  visual(VLines)
        spec = (base + overlay) *
               config(facet=(; linkxaxes=:none),
                      title="ECDF + VLines via auto_remap (picker)")
        auto_remap_node("brm-ecdf-picker", spec;
            dims=["param" => "Parameter", "index" => "Index"])
     end),

    ("brm_histogram_picker_diverges", "Histogram picker vs no-picker — diverges (bug)",
     "Same histogram spec rendered via to_node(spec) and with_plot_caption(spec; auto_remap=…) produces different specs. BRM pattern: row=:param (facet) + color=:index (per-index colors within a facet). Picker path re-composes layers and may drop nonnumeric / facet wrapping that histogram_to_vl sets up.",
     """df = (;
    param = repeat([\"a\",\"b\"], inner=600),
    index = repeat(repeat(1:3, inner=200), 2),
    value = vcat(randn(600), randn(600) .- 8))
spec = data(df) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       histogram() *
       config(facet=(; linkxaxes=:none),
              title=\"Histogram via auto_remap (picker)\")
auto_remap_node(\"brm-hist-picker\", spec;
    dims=[\"param\" => \"Parameter\", \"index\" => \"Index\"])""",
     () -> let
        df = (;
            param = repeat(["a","b"], inner=600),
            index = repeat(repeat(1:3, inner=200), 2),
            value = vcat(randn(600), randn(600) .- 8))
        spec = data(df) *
               mapping(:value; row=:param, color=:index => nonnumeric) *
               histogram() *
               config(facet=(; linkxaxes=:none),
                      title="Histogram via auto_remap (picker)")
        auto_remap_node("brm-hist-picker", spec;
            dims=["param" => "Parameter", "index" => "Index"])
     end),
]

# --- Utilities ---


function json_response(text)
    HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8"], body=text)
end

function find_plot(id)
    idx = findfirst(p -> p[1] == id, PLOTS)
    isnothing(idx) ? nothing : PLOTS[idx]
end

function escape_html(s::AbstractString)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s
end

# --- Flagged plots persistence ---
flags_file() = joinpath(@__DIR__, "..", "flagged.txt")

function load_flags()
    s = Set{String}()
    f = flags_file()
    isfile(f) || return s
    for line in readlines(f)
        l = strip(line)
        !isempty(l) && push!(s, l)
    end
    s
end

function save_flags(flagged)
    open(flags_file(), "w") do io
        for id in sort(collect(flagged))
            println(io, id)
        end
    end
end

function toggle_flag!(id)
    flagged = load_flags()
    if id in flagged
        delete!(flagged, id)
    else
        push!(flagged, id)
    end
    save_flags(flagged)
    id in flagged
end

# --- HTMXObjects App ---

@htmx struct AppContext
    flag_button(id) = let flagged = id in load_flags()
        label = flagged ? "flagged" : "flag"
        color = flagged ? "color:var(--pico-del-color);" : "color:var(--pico-muted-color);"
        h.button(label;
            hx_post="/flag/$id",
            hx_target="#flag-$id",
            hx_swap="outerHTML",
            id="flag-$id",
            style="$(color) font-size:0.7em; padding:0.1rem 0.3rem; margin-left:0.3em; border:1px solid; background:none; cursor:pointer; border-radius:0.2rem;",
        )
    end

    plot_card(id, title, description, ref_url=nothing) = begin
        entry = find_plot(id)
        let spec = isnothing(entry) ? nothing : entry[5]()
            code_str = isnothing(entry) ? "" : entry[4]
            is_node = spec isa HTMX.Node
            json_str = isnothing(spec) || is_node ? "" : JSON.json(to_vegalite(spec), 2)
            h.article(; style="margin:0; padding:0.5rem; min-width:0; overflow:hidden;")(
                h.header(; style="padding:0 0 0.25rem; margin:0; display:flex; align-items:center; flex-wrap:wrap;")(
                    h.a(title;
                        href="/standalone/$id", target="_blank",
                        style="font-size:0.9em; font-weight:bold; text-decoration:none;",
                    ),
                    is_node ? h.span() : h.a("static";
                        href="/static_plot/$id", target="_blank",
                        style="font-size:0.7em; margin-left:0.3em; padding:0.1rem 0.3rem; border:1px solid; border-radius:0.2rem; text-decoration:none; color:var(--pico-muted-color);",
                    ),
                    flag_button(id),
                    isnothing(ref_url) ? h.span() :
                        h.a(" [ref]";
                            href=ref_url, target="_blank",
                            style="font-size:0.8em; margin-left:0.3em;",
                        ),
                ),
                isnothing(spec) ? h.p("Unknown plot") : is_node ? spec : vdraw(spec; id=id),
                h.details(; style="margin-top:0.25rem")(
                    h.summary("Code"; style="font-size:0.8em;"),
                    h.pre(h.code(code_str); style="background:var(--pico-code-background-color); padding:0.5rem; border-radius:0.25rem; overflow-x:auto; font-size:0.75em;"),
                ),
            )
        end
    end

    # Group plots by category for the index
    PLOT_SECTIONS = [
        ("Interactive Filtering" => ["filter_origin", "filter_multi", "filter_tips", "filter_histogram", "filter_regression", "filter_bar"]),
        ("Basic" => ["scatter", "bar", "line", "lines_only", "area", "histogram", "heatmap", "boxplot"]),
        ("Composition" => ["layered", "multi_layer", "stacked_bar", "grouped_bar", "bubble", "scatter_jitter", "custom_config"]),
        ("Interactive" => ["interactive_brush", "interactive_highlight", "interactive_zoom", "interactive_slider", "interactive_dropdown", "remap_encoding", "remap_axes", "remap_lineribbon", "remap_detail", "remap_precomputed_lineribbon"]),
        ("AoG: Basic Visualizations" => ["aog_scatter_basic", "aog_sine_lines", "aog_lines_scatter", "aog_two_sources", "aog_boxplot"]),
        ("AoG: Additional Marks" => ["aog_step", "aog_rules", "aog_vlines_faceted_color", "aog_vlines_faceted_color_remap", "aog_errorbars"]),
        ("AoG: Data Manipulations" => ["aog_wide_lines", "aog_wide_scatter", "aog_presorted_bar"]),
        ("AoG: Pregrouped" => ["pregrouped_boxplot", "pregrouped_boxplot_plain", "pregrouped_dose_response"]),
        ("AoG: Scales" => ["aog_log_transform", "aog_discrete_boxplot", "aog_combined_boxplot", "aog_barplot_names", "aog_dodge", "aog_legend_merge", "aog_multi_color"]),
        ("AoG: Statistical Analyses" => ["aog_density", "aog_ecdf", "aog_ecdf_grouped", "aog_histogram_basic", "aog_histogram", "aog_frequency", "aog_expectation", "aog_frequency_color", "aog_linear", "aog_smooth", "aog_linear_band", "aog_smooth_band"]),
        ("AoG: Composition Patterns" => ["aog_scatter_regression", "aog_scatter_smooth", "aog_bar_line_combo", "aog_stacked_area", "aog_color_regression"]),
        ("AoG: Layout" => ["aog_facet", "aog_facet_wrap", "aog_facet_multi_layer", "aog_facet_regression"]),
        ("AoG: Applications" => ["aog_timeseries", "aog_timeseries_box", "aog_2d_histogram"]),
        ("Uncertainty (tidybayes)" => ["pointinterval", "pointinterval_vertical", "halfeye", "gradient_interval", "lineribbon", "lineribbon_grouped", "lineribbon_faceted", "lineribbon_overlay", "lineribbon_logscale", "ppc_overlay", "ribbon_only", "precomputed_lineribbon", "precomputed_lineribbon_grouped", "precomputed_pointinterval", "remap_precomputed_pointinterval_positional", "dotinterval", "raincloud"]),
    ]

    gallery_section(section_title, ids) = begin
        entries = filter(!isnothing, [find_plot(id) for id in ids])
        h.div(; style="margin-bottom:2rem")(
            h.h3(section_title; style="margin-bottom:0.5rem"),
            h.div(; style="display:grid; grid-template-columns:repeat(4, 1fr); gap:0.5rem;")(
                [plot_card(e[1], e[2], e[3], length(e) >= 6 ? e[6] : nothing) for e in entries]...,
            ),
        )
    end

    demo_card(href, title, description) = h.article(; style="margin:0; padding:0.5rem;")(
        h.a(;
            href=href,
            hx_get=href,
            hx_target="#main-content",
            hx_swap="innerHTML",
            hx_push_url="true",
            style="text-decoration:none; color:inherit;",
        )(
            h.strong(title; style="font-size:0.9em;"),
            h.span(" — $description"; style="color:var(--pico-muted-color); font-size:0.8em;"),
        ),
    )

    gallery_index = h.div(
        h.h1("AlgebraOfVega Gallery"),
        h.p(
            "$(length(PLOTS)) examples of AlgebraOfGraphics.jl specs translated to Vega-Lite. ",
            h.a("Data Explorer →"; href="/explorer", style="font-size:0.9em; margin-right:1em;"),
            h.a("View flagged plots →"; href="/flagged", style="font-size:0.9em;"),
        ),
        [gallery_section(title, ids) for (title, ids) in PLOT_SECTIONS]...,
        h.div(; style="margin-bottom:2rem")(
            h.h3("HTMX + Vega Demos"; style="margin-bottom:0.5rem"),
            h.div(; style="display:grid; grid-template-columns:repeat(4, 1fr); gap:0.5rem;")(
                demo_card("/demo_brush", "Brush → Server Stats", "Brush a scatter plot, server computes stats on selection"),
                demo_card("/demo_update", "Server-Side Data Update", "Buttons fetch filtered data from server, plot animates update"),
                demo_card("/demo_responsive", "Responsive Width", "Plots adapt to container width — 50%, side-by-side, faceted"),
            ),
        ),
    )

    plot_nav(active_id) = h.nav(; style="display:flex; flex-wrap:wrap; gap:0.25rem; margin-bottom:1rem; align-items:center;")(
        h.a("← Gallery"; href="/", hx_get="/", hx_target="#main-content", hx_swap="innerHTML", hx_push_url="true", role="button", class="outline secondary", style="margin-right:auto;"),
        [h.a(title;
            href="/plot/$id",
            hx_get="/plot/$id",
            hx_target="#main-content",
            hx_swap="innerHTML",
            hx_push_url="true",
            role="button",
            class=id == active_id ? "contrast" : "secondary outline",
            style="margin:0.1rem; font-size:0.85em; padding:0.3rem 0.6rem;",
        ) for p in PLOTS for (id, title) in ((p[1], p[2]),)]...
    )

    plot_detail(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, description, code_str, spec_fn = entry[2], entry[3], entry[4], entry[5]
            let spec = spec_fn()
                is_node = spec isa HTMX.Node
                plot_body = is_node ? spec : vdraw(spec)
                json_details = is_node ? h.span() : h.details(; style="margin-top:1rem")(
                    h.summary("Vega-Lite JSON Spec"),
                    h.pre(h.code(escape_html(JSON.json(to_vegalite(spec), 2))); style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto; max-height:400px;"),
                )
                h.div(
                    plot_nav(id),
                    h.h2(title),
                    h.p(description),
                    plot_body,
                    h.h4("Julia Code"; style="margin-top:1.5rem"),
                    h.pre(h.code(code_str); style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
                    json_details,
                )
            end
        end
    end

    __page__(content) = htmx(
        h.main(class="container-fluid", style="padding:1rem 2rem;")(
            h.div(content; id="main-content"),
        );
        pico_version="2",
        extra_head=(vega_head()..., h.style(":root { font-size: 14px; }")),
    )

    @get index = gallery_index

    compact_card(id) = begin
        entry = find_plot(id)
        isnothing(entry) && return h.span()
        let spec = entry[5]()
            isnothing(spec) && return h.span()
            is_node = spec isa HTMX.Node
            h.div(; style="border:1px solid var(--pico-muted-border-color); border-radius:0.2rem; padding:0.2rem; overflow:hidden; min-width:0;")(
                h.div(entry[2]; style="font-weight:bold; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-bottom:0.1rem;"),
                is_node ? spec : vdraw(spec; width="container"),
            )
        end
    end

    @get compact = begin
        all_cards = [compact_card(e[1]) for section in PLOT_SECTIONS for e in filter(!isnothing, [find_plot(id) for id in section[2]])]
        h.div(; style="width:100vw; padding:0.5rem; font-size:0.5em;")(
            h.h2("AlgebraOfVega Gallery"; style="margin-bottom:0.5rem;"),
            h.div(; style="display:grid; grid-template-columns:repeat(16, 1fr); gap:0.25rem;")(
                all_cards...,
            ),
        )
    end

    static_compact_card(id) = begin
        entry = find_plot(id)
        isnothing(entry) && return h.span()
        let spec = entry[5]()
            isnothing(spec) && return h.span()
            path = joinpath(plots_dir, "$id.png")
            try
                sdraw_file(spec, path; px_per_unit=2)
                h.div(; style="border:1px solid var(--pico-muted-border-color); border-radius:0.2rem; padding:0.2rem; overflow:hidden; min-width:0;")(
                    h.div(entry[2]; style="font-weight:bold; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-bottom:0.1rem;"),
                    h.img(; src="/plot_img/$id.png", style="width:100%;"),
                )
            catch
                h.div(; style="border:1px solid var(--pico-muted-border-color); border-radius:0.2rem; padding:0.2rem; overflow:hidden; min-width:0; opacity:0.4;")(
                    h.div(entry[2]; style="font-weight:bold; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; margin-bottom:0.1rem;"),
                    h.div("✗"; style="text-align:center; color:red;"),
                )
            end
        end
    end

    @get static_compact = begin
        all_cards = [static_compact_card(e[1]) for section in PLOT_SECTIONS for e in filter(!isnothing, [find_plot(id) for id in section[2]])]
        h.div(; style="width:100vw; padding:0.5rem; font-size:0.5em;")(
            h.h2("AlgebraOfVega Static Gallery"; style="margin-bottom:0.5rem;"),
            h.div(; style="display:grid; grid-template-columns:repeat(16, 1fr); gap:0.25rem;")(
                all_cards...,
            ),
        )
    end

    @get plot(id) = plot_detail[id]

    @get captioned_demo = let
        id = "captioned-demo"
        summary = _preaggregate(faceted_regression_predictions(), :x, :panel, :site)
        the_spec = data(summary) * mapping(:x, :median, color=:panel, row=:site) *
                   lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
                   config(title="Captioned Pre-aggregated Lineribbon")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned pre-aggregated lineribbon",
            short = "Posterior medians + 50/80/95% CrIs across 2 conditions × 2 sites. " *
                    "Use the picker to remap color/row; the data button always reflects " *
                    "the underlying summary table.",
            long = "The plot is built via the spec-dispatch `with_plot_caption` with " *
                   "`auto_remap=(; dims=...)`, over a pre-aggregated summary (median, " *
                   "q025, q10, q25, q75, q90, q975 columns). Controls appear above the " *
                   "`<figure>` (controls → caption → plot). The CSV button reads from " *
                   "the live Vega view via `view.data('source_0')`, so after a remap it " *
                   "still returns the original input rows. The lazy 'Show data' details " *
                   "below the plot renders the same table client-side, sortable.",
        )
        h.main(class="container")(
            h.h1("Captioned plot demo"),
            h.p("Verifies the HTMXObjects caption integration on the most common " *
                "bruno path: pre-aggregated lineribbon + auto_remap_node via spec dispatch."),
            with_plot_caption(the_spec, caption;
                plot_id=id,
                filename_base="lineribbon_summary",
                auto_remap=(; dims=[:panel => "Condition", :site => "Site"]),
            ),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get captioned_spec_demo = let
        id = "captioned-spec-demo"
        draws = sample_posterior_draws()
        the_spec = data(draws) * mapping(:value, y=:parameter, color=:chain) * pointinterval() *
                   config(title="Captioned pointinterval (spec dispatch)")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned pointinterval via spec dispatch",
            short = "Exercises `with_plot_caption(spec::VegaSpec, caption; auto_remap, summary_table=:auto)` — " *
                    "controls hoist above the figure, auto-summary table below the plot.",
            long = "The `::VegaSpec` dispatch builds the plot internally, detects the " *
                   "PointIntervalAnalysis transformation, and auto-generates a `draws_summary_table` " *
                   "with one column per parameter (grouped by :chain via the color mapping).",
        )
        h.main(class="container")(
            h.h1("Captioned spec-dispatch demo"),
            h.p("Verifies auto-summary + auto_remap placement (controls above, caption+plot+summary below)."),
            with_plot_caption(the_spec, caption;
                plot_id=id,
                filename_base="pointinterval",
                auto_remap=(; dims=[:chain => "Chain"]),
            ),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get captioned_lineribbon_demo = let
        id = "captioned-lineribbon-demo"
        the_spec = data(grouped_regression_predictions()) *
                   mapping(:x, :y, group=:draw, color=:group) *
                   lineribbon() *
                   config(width=500, height=350, title="Captioned raw-draws lineribbon")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned lineribbon (raw draws, auto-summary)",
            short = "Verifies the lineribbon path of `_auto_summary_args`: long-format draws " *
                    "table → per-x median [lo, hi] grouped by color, inside the Pretty/Raw toggle.",
            long = "Uses `lineribbon()` over raw draws (one row per (x, draw, group)). The " *
                   "summary table groups by [x, color, ...] and reports the value field's " *
                   "median + 95% CI per group.",
        )
        h.main(class="container")(
            h.h1("Captioned lineribbon (raw draws) demo"),
            h.p("Verifies auto-summary on raw-draws lineribbon (LineRibbonAnalysis)."),
            with_plot_caption(the_spec, caption; plot_id=id, filename_base="lineribbon"),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get card_plot(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, code_str, spec_fn = entry[2], entry[4], entry[5]
            let spec = spec_fn()
                json_str = JSON.json(to_vegalite(spec), 2)
                h.div(
                    vdraw(spec),
                    h.details(; style="margin-top:0.5rem")(
                        h.summary("Julia Code"),
                        h.pre(h.code(code_str); style="background:var(--pico-code-background-color); padding:0.75rem; border-radius:0.5rem; overflow-x:auto; font-size:0.85em;"),
                    ),
                    h.details(; style="margin-top:0.25rem")(
                        h.summary("Vega-Lite JSON"),
                        h.pre(h.code(escape_html(json_str)); style="background:var(--pico-code-background-color); padding:0.75rem; border-radius:0.5rem; overflow-x:auto; max-height:300px; font-size:0.85em;"),
                    ),
                )
            end
        end
    end

    @post flag(id) = begin
        toggle_flag!(id)
        flag_button(id)
    end

    @get flagged = begin
        flags = load_flags()
        content = if isempty(flags)
            h.div(
                h.h1("Flagged Plots"),
                h.p("No flagged plots."),
                h.a("← Back to gallery"; href="/", style="font-size:0.9em;"),
            )
        else
            flagged_ids = sort(collect(flags))
            flagged_entries = filter(!isnothing, [find_plot(id) for id in flagged_ids])
            h.div(
                h.h1("Flagged Plots ($(length(flagged_entries)))"),
                h.a("← Back to gallery"; href="/", style="font-size:0.9em; margin-bottom:1rem; display:inline-block;"),
                h.div(; style="display:grid; grid-template-columns:repeat(4, 1fr); gap:0.5rem;")(
                    [plot_card(e[1], e[2], e[3], length(e) >= 6 ? e[6] : nothing) for e in flagged_entries]...,
                ),
            )
        end
        content
    end

    @get spec(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            "Unknown plot: $id"
        else
            spec = entry[5]()
            json_response(JSON.json(to_vegalite(spec), 2))
        end
    end

    @get inspect_layer(expr) = begin
        layer = try
            if expr == "linear"
                linear()
            elseif expr == "smooth"
                smooth()
            elseif expr == "density"
                density()
            elseif expr == "histogram"
                histogram()
            elseif expr == "frequency"
                frequency()
            elseif expr == "expectation"
                expectation()
            else
                nothing
            end
        catch e
            nothing
        end
        if isnothing(layer)
            "Unknown: $expr"
        else
            lines = String[]
            push!(lines, "typeof: $(typeof(layer))")
            push!(lines, "fields: $(fieldnames(typeof(layer)))")
            t = layer.transformation
            push!(lines, "transformation: $t")
            push!(lines, "transformation type: $(typeof(t))")
            if t isa ComposedFunction
                push!(lines, "  outer: $(t.outer) ($(typeof(t.outer)))")
                push!(lines, "  inner: $(t.inner) ($(typeof(t.inner)))")
            end
            if hasproperty(layer, :positional)
                push!(lines, "positional: $(layer.positional)")
            end
            if hasproperty(layer, :named)
                push!(lines, "named: $(layer.named)")
            end
            join(lines, "\n")
        end
    end

    # --- Pregrouped debug page ---
    @get debug_pregrouped = begin
        # Test case 1: basic with renamer
        spec1 = pregrouped(
            fill.(1:3, 100) => renamer(["A", "B", "C"]),
            [randn(100) for _ in 1:3]
        ) * visual(BoxPlot) * config(title="1. Basic with renamer")

        # Test case 2: without renamer
        spec2 = pregrouped(
            fill.(1:2, 50),
            [randn(50) for _ in 1:2]
        ) * visual(BoxPlot) * config(title="2. Without renamer")

        # Test case 3: Bruno QT pattern (axes/eachcol)
        cdslope = randn(5000)
        cdslope_mat = reshape(cdslope, 1000, 5)
        spec3 = pregrouped(
            fill.(axes(cdslope_mat, 2), size(cdslope_mat, 1)) => renamer(string.([0, 10, 20, 40, 80])),
            collect(eachcol(cdslope_mat))
        ) * visual(BoxPlot) * config(title="3. Bruno QT pattern (axes/eachcol)")

        specs = [spec1, spec2, spec3]
        h.div(
            vega_head(),
            h.h2("Pregrouped Debug"),
            [h.div(; style="margin-bottom:2rem")(
                vdraw(s),
                h.details(
                    h.summary("Spec JSON"),
                    h.pre(h.code(JSON.json(to_vegalite(s), 2)); style="font-size:0.8em; max-height:400px; overflow:auto;"),
                ),
            ) for s in specs]...,
        )
    end

    # --- Standalone HTML page for any plot ---
    @get standalone(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            HTTP.Response(404, ["Content-Type" => "text/plain"], body="Unknown plot: $id")
        else
            let spec = entry[5]()
                if spec isa HTMX.Node
                    h.html(h.head(vega_head()...), h.body(spec))
                else
                    HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body=to_html(spec))
                end
            end
        end
    end

    # --- Data Explorer (fully client-side) ---

    EXPLORER_DATASETS = default_explorer_datasets()

    @get explorer = h.div(
        explorer_widget(EXPLORER_DATASETS),
        h.a("← Back to gallery"; href="/", style="display:inline-block; margin-top:1rem;"),
    )

    # --- Interactive demo: Brush → Server Stats ---

    brush_plot_spec = data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=550, height=350,
            title="Brush to Compute Server-Side Stats",
            params=[Dict("name" => "brush", "select" => "interval")],
            encoding=Dict(
                "opacity" => Dict(
                    "condition" => Dict("param" => "brush", "value" => 1),
                    "value" => 0.15,
                ),
            ),
        )

    @get brush_stats(; horsepower="", mpg="") = begin
        c = cars()
        hp_range = try JSON.parse(horsepower) catch; nothing end
        mpg_range = try JSON.parse(mpg) catch; nothing end

        if isnothing(hp_range) || isnothing(mpg_range)
            h.div(; id="brush-stats")(
                h.p("Drag a rectangle on the plot to select points."; style="color:var(--pico-muted-color)"),
            )
        else
            hp_min, hp_max = extrema(hp_range)
            mpg_min, mpg_max = extrema(mpg_range)
            mask = [
                hp_min <= hp <= hp_max && mpg_min <= m <= mpg_max
                for (hp, m) in zip(c.horsepower, c.mpg)
            ]
            n = sum(mask)
            if n == 0
                h.div(; id="brush-stats")(h.p("No points in selection."))
            else
                sel_hp = c.horsepower[mask]
                sel_mpg = c.mpg[mask]
                sel_origins = c.origin[mask]
                origin_counts = Dict{String,Int}()
                for o in sel_origins
                    origin_counts[o] = get(origin_counts, o, 0) + 1
                end
                h.div(; id="brush-stats")(
                    h.h4("Selection: $n points"),
                    h.table(; role="grid")(
                        h.thead(h.tr(h.th("Stat"), h.th("Horsepower"), h.th("MPG"))),
                        h.tbody(
                            h.tr(h.td("Min"), h.td(string(minimum(sel_hp))), h.td(string(minimum(sel_mpg)))),
                            h.tr(h.td("Max"), h.td(string(maximum(sel_hp))), h.td(string(maximum(sel_mpg)))),
                            h.tr(h.td("Mean"), h.td(string(round(sum(sel_hp)/n, digits=1))), h.td(string(round(sum(sel_mpg)/n, digits=1)))),
                        ),
                    ),
                    h.p("Origins: ", join(["$o ($c)" for (o, c) in sort(collect(origin_counts))], ", ")),
                )
            end
        end
    end

    @get demo_brush = h.div(
            plot_nav("demo_brush"),
            h.h2("Brush → Server Stats"),
            h.p("Drag a selection on the scatter plot. The brush bounds are sent to the server via HTMX, ",
                "which computes summary statistics in Julia and returns them as HTML."),
            vdraw(brush_plot_spec;
                id="brush-demo",
                signals=[(signal="brush", url="/brush_stats", target="#brush-stats", debounce=200)],
            ),
            h.div(; id="brush-stats", style="margin-top:1rem")(
                h.p("Drag a rectangle on the plot to select points."; style="color:var(--pico-muted-color)"),
            ),
            h.h4("How it works"; style="margin-top:1.5rem"),
            h.pre(h.code("""# In the @htmx struct:
vdraw(spec;
    id="brush-demo",
    signals=[(signal="brush", url="/brush_stats", target="#brush-stats")],
)

# The signal listener sends brush bounds as query params:
#   GET /brush_stats?horsepower=[50,200]&mpg=[15,30]
# Server computes stats and returns HTML fragment.""");
                style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
    )

    # --- Interactive demo: Server-side data update ---

    @get demo_update = begin
        origins = ["All", "USA", "Europe", "Japan"]
        h.div(
            plot_nav("demo_update"),
            h.h2("Server-Side Data Filtering"),
            h.p("Click a button to fetch filtered data from the server. ",
                "The Vega view's dataset is swapped without re-creating the plot — axes animate smoothly."),
            vdraw(
                data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
                config(width=550, height=350, title="Click a button to filter");
                id="update-demo",
            ),
            h.div(; style="display:flex; gap:0.5rem; margin-top:1rem")(
                [h.button(o;
                    hx_get="/filter_data/$o",
                    hx_target="#update-script",
                    hx_swap="innerHTML",
                    class="outline",
                ) for o in origins]...
            ),
            h.div(; id="update-script"),
            h.h4("How it works"; style="margin-top:1.5rem"),
            h.pre(h.code("""# Button triggers HTMX GET:
#   <button hx-get="/update_data/USA" hx-target="#update-script">

# Server filters data and returns a script that updates the view:
@get update_data(origin) = begin
    filtered = origin == "All" ? cars() : filter_by_origin(cars(), origin)
    update_data("update-demo", filtered)
end""");
                style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
        )
    end

    @get demo_responsive = begin
        let spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter)
            faceted_spec = data(cars()) * mapping(:horsepower, :mpg, col=:origin) * visual(Scatter)
            h.div(
                h.h2("Responsive Width Demo"),
                h.p("Plots adapt to their container width. Resize the browser to see them reflow."),

                h.h4("Full width (layered)"),
                vdraw(spec + (data(cars()) * mapping(:horsepower, :mpg) * linear())),

                h.h4("50% width"; style="margin-top:1.5rem;"),
                h.div(; style="width:50%;")(vdraw(spec)),

                h.h4("Side by side (50% each)"; style="margin-top:1.5rem;"),
                h.div(; style="display:flex; gap:1rem;")(
                    h.div(; style="flex:1;")(vdraw(spec)),
                    h.div(; style="flex:1;")(vdraw(spec + (data(cars()) * mapping(:horsepower, :mpg) * linear()))),
                ),

                h.h4("Faceted — full width"; style="margin-top:1.5rem;"),
                vdraw(faceted_spec),

                h.h4("Faceted — 60% width"; style="margin-top:1.5rem;"),
                h.div(; style="width:60%;")(vdraw(faceted_spec)),

                h.h4("Saveable (actions=true)"; style="margin-top:1.5rem;"),
                h.p("Click the ⋯ menu to Save as PNG/SVG."),
                vdraw(spec; actions=true),
            )
        end
    end

    @get filter_data(origin) = begin
        c = cars()
        if origin == "All"
            update_data("update-demo", c)
        else
            mask = [o == origin for o in c.origin]
            filtered = (;
                horsepower = c.horsepower[mask],
                mpg = c.mpg[mask],
                origin = c.origin[mask],
                cylinders = c.cylinders[mask],
                weight = c.weight[mask],
                acceleration = c.acceleration[mask],
            )
            update_data("update-demo", filtered)
        end
    end

    plots_dir = let d = joinpath(@__DIR__, "..", "plots"); mkpath(d); d end

    @get static_plot(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, spec_fn = entry[2], entry[5]
            let spec = spec_fn()
                path = joinpath(plots_dir, "$id.png")
                sdraw_file(spec, path; px_per_unit=2)
                h.div(
                    h.h3(title),
                    h.img(; src="/plot_img/$id.png", style="max-width:100%;"),
                )
            end
        end
    end

    @get plot_img(filename) = begin
        path = joinpath(plots_dir, filename)
        if isfile(path)
            HTTP.Response(200, ["Content-Type" => "image/png"], read(path))
        else
            HTTP.Response(404, "Not found")
        end
    end

    static_plot_card(id) = begin
        let entry = find_plot(id)
            isnothing(entry) && return h.article(h.p("Unknown: $id"))
            title = entry[2]
            let spec = entry[5]()
                path = joinpath(plots_dir, "$id.png")
                try
                    sdraw_file(spec, path; px_per_unit=2)
                    h.article(; style="margin:0; padding:0.5rem; min-width:0; overflow:hidden;")(
                        h.header(; style="padding:0 0 0.25rem; margin:0; display:flex; align-items:center; flex-wrap:wrap;")(
                            h.a(title;
                                href="/static_plot/$id", target="_blank",
                                style="font-size:0.9em; font-weight:bold; text-decoration:none;",
                            ),
                            flag_button(id),
                        ),
                        h.img(; src="/plot_img/$id.png", style="width:100%;"),
                    )
                catch e
                    h.article(; style="margin:0; padding:0.5rem; min-width:0; overflow:hidden;")(
                        h.header(; style="padding:0 0 0.25rem; margin:0; display:flex; align-items:center; flex-wrap:wrap;")(
                            h.span(title; style="font-size:0.9em; font-weight:bold;"),
                            flag_button(id),
                        ),
                        h.p("Error: $(sprint(showerror, e))"; style="color:red; font-size:0.8em;"),
                    )
                end
            end
        end
    end

    static_gallery_section(section_title, ids) = begin
        entries = filter(!isnothing, [find_plot(id) for id in ids])
        h.div(; style="margin-bottom:2rem")(
            h.h3(section_title; style="margin-bottom:0.5rem"),
            h.div(; style="display:grid; grid-template-columns:repeat(4, 1fr); gap:0.5rem;")(
                [static_plot_card(e[1]) for e in entries]...,
            ),
        )
    end

    @get static_gallery = h.div(
        h.h2("Static Gallery (Makie/CairoMakie)"),
        [static_gallery_section(title, ids) for (title, ids) in PLOT_SECTIONS]...,
    )

    @include tests = TestRoutes(; __req__, test_module=@__MODULE__)
end

function __init__()
    route!(AppContext())
end

end # module AlgebraOfVegaGallery
