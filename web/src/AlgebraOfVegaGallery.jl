module AlgebraOfVegaGallery

using HTMXObjects
using AlgebraOfVega
using JSON

# --- Sample datasets ---

cars() = (;
    horsepower = [130,165,150,150,140,198,220,215,225,190,170,160,150,225,95,95,97,85,88,46,87,90,95,113,90,215,200,210,193,88,90,95,100,105,100,88,100,165,175,153,150,180,170,175,110,72,100,88,86,90,70,76,65,69,60,70,95,80,54,90,86,110],
    mpg = [18,15,18,16,17,15,14,14,14,15,15,14,15,14,24,22,18,21,27,26,25,24,25,26,21,10,10,11,9,27,28,25,25,19,16,17,19,18,14,14,15,15,14,15,24,20,25,21,27,26,26,28,25,26,30,22,17,23,36,25,22,18],
    origin = ["USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","Europe","Europe","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","USA","USA","USA","Japan","Europe","Europe","Europe"],
    cylinders = [8,8,8,8,8,8,8,8,8,8,8,8,8,8,4,4,4,4,4,4,4,4,4,4,4,8,8,8,8,4,4,4,4,4,4,4,4,6,6,6,6,8,8,8,4,4,4,4,4,4,4,4,4,4,4,6,6,6,4,4,4,4],
    weight = [3504,3693,3436,3433,3449,4341,4354,4312,4425,3850,3563,3609,3761,3086,2372,2833,2774,2587,2130,1835,2672,2430,2375,2234,2648,4615,4376,4382,4732,2130,2264,2228,2046,2634,2702,2875,2901,3353,3169,2906,3380,3740,4080,3645,2585,2310,2472,2265,2110,2800,2110,2085,2245,1965,1755,2815,3210,3380,1760,2130,2205,2245],
    acceleration = [12.0,11.5,11.0,12.0,10.5,10.0,9.0,8.5,10.0,8.5,10.0,8.0,9.5,10.0,15.0,15.5,15.5,16.0,14.5,20.5,17.5,15.0,17.5,15.5,18.5,14.0,13.0,13.5,18.0,14.5,13.5,15.5,19.0,13.0,15.5,16.5,17.0,11.0,11.5,12.5,13.5,12.0,11.0,11.5,14.0,19.0,15.0,16.0,19.5,14.5,19.5,17.0,17.0,15.0,17.0,14.0,12.5,13.5,15.5,14.0,15.5,13.5],
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

monthly_sales() = (;
    month = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"],
    online = [120,135,140,160,180,200,220,210,190,175,160,250],
    store = [200,180,190,170,160,150,140,145,155,170,180,300],
)

function melt_sales(s)
    n = length(s.month)
    (;
        month = [s.month; s.month],
        sales = [s.online; s.store],
        channel = [fill("Online", n); fill("Store", n)],
    )
end

# --- Simulated posterior data (tidybayes-style) ---

# Simple Box-Muller normal RNG (no dependencies)
function randn_bm(n; rng=nothing)
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

function grouped_regression_predictions(; n_x=30, n_draws=100)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    rows_group = String[]
    for (gname, α0, β0) in [("Treatment A", 2.0, 0.8), ("Treatment B", 1.0, 1.5)]
        for d in 1:n_draws
            α = α0 + 0.5 * randn_bm(1)[1]
            β = β0 + 0.3 * randn_bm(1)[1]
            σ = 0.8 + 0.2 * abs(randn_bm(1)[1])
            for x in xs
                push!(rows_x, x)
                push!(rows_y, α + β * x + σ * randn_bm(1)[1])
                push!(rows_draw, d)
                push!(rows_group, gname)
            end
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw, group=rows_group)
end

# --- Plot specifications ---

# Each entry: (id, title, description, code_string, spec_fn)
PLOTS = [
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
     """let species = rand(["Adelie","Chinstrap","Gentoo"], 200)
    sex = rand(["male","female"], 200)
    depth = [s == "Adelie" ? 18.0 : s == "Chinstrap" ? 18.5 : 15.0 for s in species] .+ randn_bm(200)
    df = (; species, bill_depth=depth, sex)
    data(df) * visual(BoxPlot) * mapping(:species, :bill_depth, color=:sex, dodge_x=:sex) *
        config(title="Box Plot by Species & Sex")
end""",
     () -> let
        species = [["Adelie","Chinstrap","Gentoo"][mod1(k,3)] for k in 1:200]
        sex = [isodd(k) ? "male" : "female" for k in 1:200]
        depth = [s == "Adelie" ? 18.0 : s == "Chinstrap" ? 18.5 : 15.0 for s in species] .+ randn_bm(200)
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
     """let df = (x=rand(["a","b","c"], 100), y=rand(100))
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
     """let df1 = (; x=rand(["one","two"], 100), y=randn_bm(100))
    df2 = (; x=rand(["three","four"], 50), y=randn_bm(50))
    (data(df1) + data(df2)) * mapping(:x, :y) * visual(BoxPlot) *
        config(title="Combined Categories")
end""",
     () -> let
        df1 = (; x=[isodd(k) ? "one" : "two" for k in 1:100], y=randn_bm(100))
        df2 = (; x=[isodd(k) ? "three" : "four" for k in 1:50], y=randn_bm(50))
        (data(df1) + data(df2)) * mapping(:x, :y) * visual(BoxPlot) *
            config(title="Combined Categories")
     end,
     "https://aog.makie.org/stable/examples/scales/discrete-scales"),

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
    y = cumsum(randn_bm(2N))
    grp = [fill("a", N); fill("b", N)]
    df = (; x, y, grp)
    (visual(Lines) + visual(Scatter)) *
        data(df) * mapping(:x, :y, color=:grp) *
        config(title="Legend Merge: Lines + Scatter")
end""",
     () -> let
        N = 40
        x = [collect(1:N); collect(1:N)]
        y = cumsum(randn_bm(2N))
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
    x = [randn_bm(n); 1.5 .+ randn_bm(n)]
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
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/density-plots"),

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
    x = [randn_bm(n); 1.0 .+ randn_bm(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c, stack=:c) * histogram() *
        config(title="Stacked Histogram")
end""",
     () -> let
        n = 500
        x = [randn_bm(n); 1.0 .+ randn_bm(n)]
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
    y = [xi + 0.3 * randn_bm(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (linear() + visual(Scatter)) *
        config(title="Scatter + Linear Regression")
end""",
     () -> let
        x = [0.01i for i in 1:100]
        y = [xi + 0.3*randn_bm(1)[1] for xi in x]
        df = (; x, y)
        data(df) * mapping(:x, :y) * (linear() + visual(Scatter)) *
            config(title="Scatter + Linear Regression")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/regression-plots"),

    ("aog_smooth", "Smooth Regression",
     "smooth() + Scatter (loess)",
     """let x = [0.01i for i in 1:100]
    y = [5*xi^2 + 0.3*randn_bm(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (smooth() + visual(Scatter)) *
        config(title="Scatter + Smooth (Loess)")
end""",
     () -> let
        x = [0.01i for i in 1:100]
        y = [5*xi^2 + 0.3*randn_bm(1)[1] for xi in x]
        df = (; x, y)
        data(df) * mapping(:x, :y) * (smooth() + visual(Scatter)) *
            config(title="Scatter + Smooth (Loess)")
     end,
     "https://aog.makie.org/stable/examples/statistical-analyses/regression-plots"),

    ("aog_linear_band", "Linear + Confidence Band",
     "Linear regression with confidence ribbon (AoG linear(interval=:confidence))",
     """let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [1.2*xi*parse(Int,ai) + parse(Int,ai) + 5*randn_bm(1)[1] for (xi,ai) in zip(x,a)]
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
     end,
     "https://aog.makie.org/stable/reference/analyses#Linear"),

    ("aog_smooth_band", "Smooth + Confidence Band",
     "Smooth regression with confidence ribbon (AoG smooth())",
     """let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [sin(xi)*parse(Int,ai) + parse(Int,ai) + 0.5*randn_bm(1)[1] for (xi,ai) in zip(x,a)]
    df = (; x, y, a)
    data(df) * mapping(:x, :y, color=:a) * (smooth(interval=:confidence) + visual(Scatter)) *
        config(title="Smooth + Confidence Band")
end""",
     () -> let
        x = [0.05i for i in 1:200]
        a = [isodd(i) ? "1" : "2" for i in 1:200]
        y = [sin(xi)*parse(Int,ai) + parse(Int,ai) + 0.5*randn_bm(1)[1] for (xi,ai) in zip(x,a)]
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
    df = (; x=rand(N), y=rand(N), i, j)
    data(df) * mapping(:x, :y, row=:i, col=:j) * visual(Scatter) *
        config(title="Facet Grid")
end""",
     () -> let
        N = 200
        i = [isodd(k) ? "α" : "β" for k in 1:N]
        j = [["a","b","c"][mod1(k,3)] for k in 1:N]
        x = [0.01k + 0.3*randn_bm(1)[1] for k in 1:N]
        y = [0.01k + 0.3*randn_bm(1)[1] for k in 1:N]
        df = (; x, y, i, j)
        data(df) * mapping(:x, :y, row=:i, col=:j) * visual(Scatter) *
            config(title="Facet Grid")
     end,
     "https://aog.makie.org/stable/examples/layout/faceting"),

    ("aog_facet_wrap", "Facet Wrap",
     "Layout wrapping with 5 groups",
     """let df = (x=rand(100), y=rand(100), l=rand(["a","b","c","d","e"], 100))
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
     """let df1 = (x=rand(100), y=rand(100), i=rand(["a","b","c"], 100), j=rand(["d","e","f"], 100))
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
    y1 = cumsum(randn_bm(31))
    y2 = cumsum(randn_bm(31))
    n = length(dates)
    df = (; date=[dates;dates], value=[y1;y2], series=[fill("y",n);fill("z",n)])
    data(df) * mapping(:date, :value, color=:series) * visual(Lines) *
        config(title="Time Series")
end""",
     () -> let
        dates = ["2025-01-$(lpad(d,2,'0'))" for d in 1:31]
        y1 = cumsum(randn_bm(31))
        y2 = cumsum(randn_bm(31))
        n = length(dates)
        df = (; date=[dates;dates], value=[y1;y2], series=[fill("y",n);fill("z",n)])
        data(df) * mapping(:date, :value, color=:series) * visual(Lines) *
            config(title="Time Series")
     end,
     "https://aog.makie.org/stable/examples/applications/time-series"),

    ("aog_timeseries_box", "Time Series Box Plot",
     "Box plot of observations per date",
     """let dates = ["2025-01-\$(lpad(d,2,'0'))" for d in 1:15]
    trend = cumsum(randn_bm(15))
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
        trend = cumsum(randn_bm(15))
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
]

# --- Utilities ---

function wants_plain(req)
    accept = HTTP.header(req, "Accept", "")
    contains(accept, "text/plain") || haskey(HTTP.queryparams(req), "plain")
end

function raw_response(text)
    HTTP.Response(200, ["Content-Type" => "text/plain; charset=utf-8"], body=text)
end

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
    req = nothing
    plain = wants_plain(req)

    flag_button(id) = begin
        flagged = id in load_flags()
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
        spec = isnothing(entry) ? nothing : entry[5]()
        code_str = isnothing(entry) ? "" : entry[4]
        json_str = isnothing(spec) ? "" : JSON.json(to_vegalite(spec), 2)
        h.article(; style="margin:0; padding:0.5rem;")(
            h.header(; style="padding:0 0 0.25rem; margin:0; display:flex; align-items:center; flex-wrap:wrap;")(
                h.a(title;
                    href="/standalone/$id", target="_blank",
                    style="font-size:0.9em; font-weight:bold; text-decoration:none;",
                ),
                flag_button(id),
                isnothing(ref_url) ? h.span() :
                    h.a(" [ref]";
                        href=ref_url, target="_blank",
                        style="font-size:0.8em; margin-left:0.3em;",
                    ),
            ),
            isnothing(spec) ? h.p("Unknown plot") : draw(spec),
            h.details(; style="margin-top:0.25rem")(
                h.summary("Code"; style="font-size:0.8em;"),
                h.pre(h.code(code_str); style="background:var(--pico-code-background-color); padding:0.5rem; border-radius:0.25rem; overflow-x:auto; font-size:0.75em;"),
            ),
        )
    end

    # Group plots by category for the index
    PLOT_SECTIONS = [
        ("Basic" => ["scatter", "bar", "line", "lines_only", "area", "histogram", "heatmap", "boxplot"]),
        ("Composition" => ["layered", "multi_layer", "stacked_bar", "grouped_bar", "bubble", "scatter_jitter", "custom_config"]),
        ("Interactive" => ["interactive_brush", "interactive_highlight", "interactive_zoom", "interactive_slider", "interactive_dropdown"]),
        ("AoG: Basic Visualizations" => ["aog_scatter_basic", "aog_sine_lines", "aog_lines_scatter", "aog_two_sources", "aog_boxplot"]),
        ("AoG: Additional Marks" => ["aog_step", "aog_rules", "aog_errorbars"]),
        ("AoG: Data Manipulations" => ["aog_wide_lines", "aog_wide_scatter", "aog_presorted_bar"]),
        ("AoG: Scales" => ["aog_log_transform", "aog_discrete_boxplot", "aog_combined_boxplot", "aog_barplot_names", "aog_dodge", "aog_legend_merge", "aog_multi_color"]),
        ("AoG: Statistical Analyses" => ["aog_density", "aog_histogram_basic", "aog_histogram", "aog_frequency", "aog_expectation", "aog_frequency_color", "aog_linear", "aog_smooth", "aog_linear_band", "aog_smooth_band"]),
        ("AoG: Composition Patterns" => ["aog_scatter_regression", "aog_scatter_smooth", "aog_bar_line_combo", "aog_stacked_area", "aog_color_regression"]),
        ("AoG: Layout" => ["aog_facet", "aog_facet_wrap", "aog_facet_multi_layer", "aog_facet_regression"]),
        ("AoG: Applications" => ["aog_timeseries", "aog_timeseries_box", "aog_2d_histogram"]),
        ("Uncertainty (tidybayes)" => ["pointinterval", "halfeye", "gradient_interval", "lineribbon", "lineribbon_grouped", "ribbon_only", "dotinterval", "raincloud"]),
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
            h.a("View flagged plots →"; href="/flagged", style="font-size:0.9em;"),
        ),
        [gallery_section(title, ids) for (title, ids) in PLOT_SECTIONS]...,
        h.div(; style="margin-bottom:2rem")(
            h.h3("HTMX + Vega Demos"; style="margin-bottom:0.5rem"),
            h.div(; style="display:grid; grid-template-columns:repeat(4, 1fr); gap:0.5rem;")(
                demo_card("/demo_brush", "Brush → Server Stats", "Brush a scatter plot, server computes stats on selection"),
                demo_card("/demo_update", "Server-Side Data Update", "Buttons fetch filtered data from server, plot animates update"),
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

    plot_detail[id] = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, description, code_str, spec_fn = entry[2], entry[3], entry[4], entry[5]
            spec = spec_fn()
            json_str = JSON.json(to_vegalite(spec), 2)
            h.div(
                plot_nav(id),
                h.h2(title),
                h.p(description),
                draw(spec),
                h.h4("Julia Code"; style="margin-top:1.5rem"),
                h.pre(h.code(code_str); style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
                h.details(; style="margin-top:1rem")(
                    h.summary("Vega-Lite JSON Spec"),
                    h.pre(h.code(escape_html(json_str)); style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto; max-height:400px;"),
                ),
            )
        end
    end

    page[content] = htmx(
        h.main(class="container-fluid", style="padding:1rem 2rem;")(
            h.div(content; id="main-content"),
        );
        pico_version="2",
        extra_head=vega_head(),
    )

    @get index = if plain
        raw_response(join(["$(p[1]): $(p[2]) — $(p[3])" for p in PLOTS], "\n"))
    else
        page[gallery_index]
    end

    @get plot[id] = begin
        entry = find_plot(id)
        if !isnothing(entry) && plain
            spec = entry[5]()
            json_response(JSON.json(to_vegalite(spec), 2))
        else
            fragment = plot_detail[id]
            if is_htmx(req)
                fragment
            else
                page[fragment]
            end
        end
    end

    @get card_plot[id] = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, code_str, spec_fn = entry[2], entry[4], entry[5]
            spec = spec_fn()
            json_str = JSON.json(to_vegalite(spec), 2)
            h.div(
                draw(spec),
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

    @post flag[id] = begin
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
        page[content]
    end

    @get spec[id] = begin
        entry = find_plot(id)
        if isnothing(entry)
            raw_response("Unknown plot: $id")
        else
            spec = entry[5]()
            json_response(JSON.json(to_vegalite(spec), 2))
        end
    end

    @get inspect_layer[expr] = begin
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
            raw_response("Unknown: $expr")
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
            raw_response(join(lines, "\n"))
        end
    end

    # --- Standalone HTML page for any plot ---
    @get standalone[id] = begin
        entry = find_plot(id)
        if isnothing(entry)
            HTTP.Response(404, ["Content-Type" => "text/plain"], body="Unknown plot: $id")
        else
            spec = entry[5]()
            HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body=to_html(spec))
        end
    end

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

    @get brush_stats = begin
        params = HTTP.queryparams(req)
        horsepower = get(params, "horsepower", "")
        mpg = get(params, "mpg", "")
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

    @get demo_brush = begin
        fragment = h.div(
            plot_nav("demo_brush"),
            h.h2("Brush → Server Stats"),
            h.p("Drag a selection on the scatter plot. The brush bounds are sent to the server via HTMX, ",
                "which computes summary statistics in Julia and returns them as HTML."),
            draw(brush_plot_spec;
                id="brush-demo",
                signals=[(signal="brush", url="/brush_stats", target="#brush-stats", debounce=200)],
            ),
            h.div(; id="brush-stats", style="margin-top:1rem")(
                h.p("Drag a rectangle on the plot to select points."; style="color:var(--pico-muted-color)"),
            ),
            h.h4("How it works"; style="margin-top:1.5rem"),
            h.pre(h.code("""# In the @htmx struct:
draw(spec;
    id="brush-demo",
    signals=[(signal="brush", url="/brush_stats", target="#brush-stats")],
)

# The signal listener sends brush bounds as query params:
#   GET /brush_stats?horsepower=[50,200]&mpg=[15,30]
# Server computes stats and returns HTML fragment.""");
                style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
        )
        if is_htmx(req)
            fragment
        else
            page[fragment]
        end
    end

    # --- Interactive demo: Server-side data update ---

    @get demo_update = begin
        origins = ["All", "USA", "Europe", "Japan"]
        fragment = h.div(
            plot_nav("demo_update"),
            h.h2("Server-Side Data Filtering"),
            h.p("Click a button to fetch filtered data from the server. ",
                "The Vega view's dataset is swapped without re-creating the plot — axes animate smoothly."),
            draw(
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
@get update_data[origin] = begin
    filtered = origin == "All" ? cars() : filter_by_origin(cars(), origin)
    update_data("update-demo", filtered)
end""");
                style="background:var(--pico-code-background-color); padding:1rem; border-radius:0.5rem; overflow-x:auto;"),
        )
        if is_htmx(req)
            fragment
        else
            page[fragment]
        end
    end

    @get filter_data[origin] = begin
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
end

function __init__()
    route!(AppContext())
end

end # module AlgebraOfVegaGallery
