# title: Pan & Zoom
# description: Scroll to zoom, drag to pan the scatter plot

data(cars()) *
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
)
