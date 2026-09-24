# title: Multi-Layer
# description: Scatter with dashed trend line overlay

data(cars()) * (
    mapping(:horsepower, :mpg) * visual(Scatter, opacity=0.5) +
    mapping(:horsepower, :mpg) * visual(Lines, color=:red, strokeDash=[4,4])
) * config(width=500, height=350, title="HP vs MPG with Trend")
