# title: Mean (Expectation)
# description: Average value per category

data(cars()) * mapping(:origin, :mpg) * expectation() *
config(title="Mean MPG by Origin")
