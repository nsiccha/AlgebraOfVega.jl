# title: Multi-Filter
# description: Two dropdowns: origin + cylinders

data(cars()) *
mapping(:horsepower, :mpg, color=:origin) *
visual(Scatter) *
config(width=500, height=350, title="Cars: Multi-Filter",
       select=[:origin, :cylinders])
