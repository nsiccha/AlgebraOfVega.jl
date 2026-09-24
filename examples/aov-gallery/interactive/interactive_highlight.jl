# title: Click to Highlight
# description: Click a point to highlight its origin group

data(cars()) *
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
)
