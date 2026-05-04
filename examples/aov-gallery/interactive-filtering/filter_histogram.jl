# title: Filtered Histogram
# description: Histogram updates with dropdown selection

data(cars()) *
mapping(:mpg) *
histogram() *
config(width=500, height=300, title="MPG Distribution by Origin",
       select=:origin)
