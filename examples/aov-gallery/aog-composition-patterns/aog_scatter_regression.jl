# title: Scatter + Regression
# description: Points with linear fit and confidence band

data(cars()) *
mapping(:horsepower, :mpg) *
(visual(Scatter, opacity=0.5) + linear(interval=:confidence)) *
config(title="MPG vs Horsepower with Regression")
