# title: Faceted Line + Ribbon
# description: tidybayes-style: line ribbons faceted by col+row

data(faceted_regression_predictions()) *
mapping(:x, :y, group=:draw, col=:panel, row=:site) *
lineribbon() *
config(width=180, height=120, title="Faceted Line + Ribbon")
