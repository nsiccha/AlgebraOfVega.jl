# title: Filter by Origin
# description: Dropdown filters scatter plot by car origin

data(cars()) *
mapping(:horsepower, :mpg, color=:origin) *
visual(Scatter) *
config(width=500, height=350, title="Cars: Filter by Origin",
       select=:origin)
