# title: Grouped Line + Ribbon
# description: tidybayes-style: multiple groups with separate ribbon bands

data(grouped_regression_predictions()) *
mapping(:x, :y, group=:draw, color=:group) *
lineribbon() *
config(width=500, height=350, title="Grouped Line + Ribbon")
