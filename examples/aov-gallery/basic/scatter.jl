# title: Scatter Plot
# description: Horsepower vs MPG colored by origin

data(cars()) *
mapping(:horsepower, :mpg, color=:origin) *
visual(Scatter) *
config(width=500, height=350, title="Cars: Horsepower vs MPG")
