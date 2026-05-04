# title: 2D Histogram
# description: Binned heatmap showing point density

data(cars()) *
mapping(:horsepower, :mpg) *
visual(Heatmap) *
config(title="HP vs MPG Density",
       encoding=Dict(
           "x" => Dict("bin" => Dict("maxbins" => 15)),
           "y" => Dict("bin" => Dict("maxbins" => 15)),
           "color" => Dict("aggregate" => "count", "type" => "quantitative")))
