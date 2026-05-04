# title: ECDF with nominal color (works)
# description: ECDFPlot base layer with color=:Int => nonnumeric renders a discrete categorical legend. Regression entry for the base-layer color path.

long = (;
    param = repeat([\"a\",\"b\"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
data(long) *
    mapping(:value; row=:param, color=:index => nonnumeric) *
    visual(ECDFPlot) *
    config(facet=(; linkxaxes=:none),
           title=\"ECDF faceted + nominal color (works)\")
