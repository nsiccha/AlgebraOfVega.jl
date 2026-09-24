# title: Quantile Dotplot
# description: tidybayes-style: quantile dots with interval overlay

data(posterior_draws()) *
mapping(:value, y=:parameter) *
dotinterval() *
config(width=500, height=200, title="Quantile Dotplot + Interval (tidybayes-style)")
