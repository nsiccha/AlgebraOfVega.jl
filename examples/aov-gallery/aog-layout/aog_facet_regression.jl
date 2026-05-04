# title: Faceted Regression
# description: Scatter + linear fit per facet panel

data(cars()) *
mapping(:horsepower, :mpg, col=:origin) *
(visual(Scatter, opacity=0.5) + linear()) *
config(title="MPG vs HP by Origin")
