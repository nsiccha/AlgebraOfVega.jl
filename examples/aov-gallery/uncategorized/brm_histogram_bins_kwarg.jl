# title: Histogram with bins=30 kwarg (regression)
# description: histogram(; bins=30) kwarg should reach VL's bin config as maxbins=30. Row-faceted + color-stacked to exercise the in-spec transform path.

df = (;
    param = vcat(fill("a", 500), fill("b", 500)),
    value = vcat(randn(500), randn(500) .- 8))
data(df) * mapping(:value; row=:param) * histogram(; bins=30) *
    config(facet=(; linkxaxes=:none),
           title="histogram(; bins=30), row-faceted")
