# title: Scatter + Smooth
# description: Points with loess curve and confidence band

data(cars()) *
mapping(:horsepower, :mpg) *
(visual(Scatter, opacity=0.5) + smooth(interval=:confidence)) *
config(title="MPG vs Horsepower with Smooth")
