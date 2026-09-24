# title: Histogram
# description: Distribution of MPG values

data(cars()) *
mapping(:mpg) *
histogram() *
config(height=300, title="MPG Distribution")
