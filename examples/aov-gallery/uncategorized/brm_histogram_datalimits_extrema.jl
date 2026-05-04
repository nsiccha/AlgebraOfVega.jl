# title: Histogram with datalimits=extrema (works)
# description: Per-facet local bin extents via AoG.histogram(; bins=30, datalimits=extrema). Regression entry confirming the workaround for the shared-x issue above.

df = (;
    param = vcat(fill(\"a\", 200), fill(\"b\", 200)),
    value = vcat(randn(200), randn(200) .- 8))
data(df) * mapping(:value; row=:param) *
    histogram(; bins=30, datalimits=extrema) *
    config(facet=(; linkxaxes=:none),
           title=\"Per-facet bins via datalimits=extrema\")
