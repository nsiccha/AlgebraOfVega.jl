# title: Ribbon (no line)
# description: tidybayes-style: uncertainty ribbons without median line

data(regression_predictions()) *
mapping(:x, :y, group=:draw) *
ribbon() *
config(width=500, height=350, title="Ribbon Only (tidybayes-style)")
