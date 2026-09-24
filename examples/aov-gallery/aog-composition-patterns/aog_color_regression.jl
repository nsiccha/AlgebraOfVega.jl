# title: Grouped Regression
# description: Per-group linear fit with color

data(cars()) *
mapping(:horsepower, :mpg, color=:origin) *
(visual(Scatter, opacity=0.5) + linear()) *
config(title="MPG vs HP by Origin (colored)")
