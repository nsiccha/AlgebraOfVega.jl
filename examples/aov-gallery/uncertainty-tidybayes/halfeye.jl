# title: Half-Eye Plot
# description: tidybayes-style: density + point + interval for each parameter

data(posterior_draws()) *
mapping(:value, y=:parameter) *
(density() + pointinterval()) *
config(width=500, height=80, title="Half-Eye Plot (tidybayes-style)")
