# title: Gradient Interval
# description: tidybayes-style: nested intervals with opacity gradient

data(posterior_draws()) *
mapping(:value, y=:parameter) *
gradient_interval() *
config(width=500, height=200, title="Gradient Interval (tidybayes-style)")
