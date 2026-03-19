module Gallery

using HTMXObjects
using AlgebraOfVega

# --- Sample datasets ---

cars() = (;
    horsepower = [130,165,150,150,140,198,220,215,225,190,170,160,150,225,95,95,97,85,88,46,87,90,95,113,90,215,200,210,193,88,90,95,100,105,100,88,100,165,175,153,150,180,170,175,110,72,100,88,86,90,70,76,65,69,60,70,95,80,54,90,86,110,none(Float64)...],
    mpg = [18,15,18,16,17,15,14,14,14,15,15,14,15,14,24,22,18,21,27,26,25,24,25,26,21,10,10,11,9,27,28,25,25,19,16,17,19,18,14,14,15,15,14,15,24,20,25,21,27,26,26,28,25,26,30,22,17,23,36,25,22,18,Float64[]...],
    origin = ["USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","Europe","Europe","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","USA","USA","USA","Japan","Europe","Europe","Europe",String[]...],
)
none(T) = T[]

tips() = (;
    total_bill = [16.99,10.34,21.01,23.68,24.59,25.29,8.77,26.88,15.04,14.78,10.27,35.26,15.42,18.43,14.83,21.58,10.33,16.29,16.97,20.65],
    tip = [1.01,1.66,3.50,3.31,3.61,4.71,2.0,3.12,1.96,3.23,1.71,5.0,1.57,3.0,1.44,3.5,1.7,3.31,3.5,3.35],
    sex = ["Female","Male","Male","Male","Female","Male","Male","Male","Male","Female","Male","Female","Male","Male","Female","Male","Male","Male","Male","Male"],
    day = ["Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun"],
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

# --- Plot specifications ---

scatter_plot() = data(cars()) *
    mapping(:horsepower, :mpg, color=:origin) *
    visual(:point) *
    config(width=500, height=350, title="Cars: Horsepower vs MPG")

bar_plot() = data(tips()) *
    mapping(x=:sex, y=:tip) *
    visual(:bar) *
    config(width=400, height=300, title="Average Tip by Gender")

line_plot() = data(stocks()) *
    mapping(x=:date, y=:price, color=:symbol) *
    visual(:line, point=true) *
    config(width=500, height=350, title="Stock Prices Over Time")

layered_plot() = data(tips()) * (
    mapping(:total_bill, :tip) * visual(:point, opacity=0.6) +
    mapping(:total_bill, :tip) * visual(:line, color="firebrick")
) * config(width=500, height=350, title="Tips: Scatter + Trend")

histogram_plot() = data(cars()) *
    mapping(x=:mpg) *
    visual(:bar) *
    config(
        width=500, height=300, title="MPG Distribution",
        encoding=Dict("x" => Dict("bin" => true), "y" => Dict("aggregate" => "count")),
    )

# --- Available plots ---

const PLOTS = [
    ("scatter", "Scatter Plot", scatter_plot),
    ("bar", "Bar Chart", bar_plot),
    ("line", "Line Chart", line_plot),
    ("layered", "Layered Plot", layered_plot),
    ("histogram", "Histogram", histogram_plot),
]

# --- HTMXObjects App ---

@htmx struct AppContext
    req = nothing

    nav_item(id, label, active) = h.a(
        href="/plot/$id",
        hx_get="/plot/$id",
        hx_target="#plot-area",
        hx_swap="innerHTML",
        hx_push_url="true",
        class=active ? "contrast" : "secondary",
        role="button",
        style="margin: 0.25rem;",
    )(label)

    nav_bar(active="scatter") = h.nav(style="display:flex; flex-wrap:wrap; gap:0.25rem; margin-bottom:1rem;")(
        [nav_item(id, label, id == active) for (id, label, _) in PLOTS]...
    )

    plot_fragment(id) = begin
        idx = findfirst(p -> p[1] == id, PLOTS)
        if isnothing(idx)
            h.p("Unknown plot: $id")
        else
            spec = PLOTS[idx][3]()
            h.div(
                nav_bar(id),
                vdraw(spec),
            )
        end
    end

    @get index = htmx(
        h.main(class="container", style="max-width:800px; margin:auto; padding:2rem;")(
            h.h1("AlgebraOfVega Gallery"),
            h.p("Interactive Vega-Lite plots served via HTMXObjects.jl"),
            h.div(id="plot-area")(
                plot_fragment("scatter"),
            ),
        );
        pico_version="2",
        extra_head=vega_head(),
    )

    @get plot[id] = begin
        fragment = plot_fragment(id)
        if is_htmx(req)
            fragment
        else
            htmx(
                h.main(class="container", style="max-width:800px; margin:auto; padding:2rem;")(
                    h.h1("AlgebraOfVega Gallery"),
                    h.p("Interactive Vega-Lite plots served via HTMXObjects.jl"),
                    h.div(id="plot-area")(fragment),
                );
                pico_version="2",
                extra_head=vega_head(),
            )
        end
    end
end

function __init__()
    route!(AppContext())
end

end # module Gallery
