# title: Basic Scatter
# description: Random x/y scatter

data((x=rand(100), y=rand(100))) * mapping(:x, :y) * visual(Scatter) *
config(title="Basic Scatter")
