# title: Line + Ribbon, Facet-Wrapped
# description: tidybayes-style small multiples: layout= wraps into a columns=N grid

data(faceted_regression_predictions()) *
mapping(:x, :y, group=:draw, color=:site, layout=:panel) *
lineribbon() *
config(width=180, height=120, columns=2, title="Line + Ribbon, Facet-Wrapped")
