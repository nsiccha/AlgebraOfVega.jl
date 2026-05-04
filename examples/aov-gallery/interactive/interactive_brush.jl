# title: Brush Selection
# description: Drag to select points — unselected points fade out

data(cars()) *
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
)
