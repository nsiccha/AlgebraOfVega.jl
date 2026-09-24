# title: Slider Filter
# description: Use the slider to filter cars by minimum MPG

data(cars()) *
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
)
