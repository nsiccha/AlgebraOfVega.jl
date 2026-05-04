# title: Remap X/Y Axes (axes=true)
# description: Client-side x/y axis swap via `axes=true`. Positional fields are auto-added to the picker's dim set, so they appear as X/Y defaults AND become selectable on color/row/column. Off by default because X/Y are single-select and usually positional fields aren't meant to be re-routed.

id = "remap-axes"
spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
       config(title="Remap X/Y Axes", width=500, height=350)
auto_remap_node(id, spec;
    dims=["origin" => "Origin", "cylinders" => "Cylinders"],
    axes=true)
