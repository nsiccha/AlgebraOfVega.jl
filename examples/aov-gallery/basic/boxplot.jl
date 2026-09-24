# title: Box Plot
# description: MPG distribution by number of cylinders

data(cars()) *
mapping(:cylinders, :mpg) *
visual(BoxPlot) *
config(width=400, height=350, title="MPG by Cylinders")
