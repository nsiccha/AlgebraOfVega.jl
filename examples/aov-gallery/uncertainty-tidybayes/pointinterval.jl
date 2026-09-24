# title: Point + Interval
# description: tidybayes-style: median with 50%/80%/95% credible intervals

data(posterior_draws()) *
mapping(:value, y=:parameter) *
pointinterval() *
config(width=500, height=200, title="Point + Interval (tidybayes-style)")
