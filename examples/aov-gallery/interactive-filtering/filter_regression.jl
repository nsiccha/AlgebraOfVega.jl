# title: Filtered Regression
# description: Scatter + linear fit updates with dropdown

data(cars()) *
mapping(:horsepower, :mpg) *
(visual(Scatter, opacity=0.5) + linear()) *
config(width=500, height=350, title="Regression by Origin",
       select=:origin)
