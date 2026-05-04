# title: Bubble Chart
# description: Scatter plot with size encoding for weight

data(cars()) *
mapping(:horsepower, :mpg, color=:origin, markersize=:weight) *
visual(Scatter) *
config(width=500, height=400, title="Cars: HP vs MPG (bubble = weight)")
