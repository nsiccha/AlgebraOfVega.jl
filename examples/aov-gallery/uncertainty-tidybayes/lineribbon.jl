# title: Line + Ribbon
# description: tidybayes-style: regression line with uncertainty ribbons

data(regression_predictions()) *
mapping(:x, :y, group=:draw) *
lineribbon() *
config(width=500, height=350, title="Line + Ribbon (tidybayes-style)")
