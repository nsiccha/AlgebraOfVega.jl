# title: Histogram row-faceted — linkxaxes=:none ignored (bug)
# description: Histogram with row=:param and config(facet=(; linkxaxes=:none)) should give each facet its own x-range; observed: all rows share the union x-range. Pre-dates overlays.

# Two params with wildly different value ranges:
df = (;
    param = vcat(fill(\"a\", 200), fill(\"b\", 200)),
    value = vcat(randn(200), randn(200) .- 8))
data(df) * mapping(:value; row=:param) * histogram() *
    config(facet=(; linkxaxes=:none),
           title=\"Expect independent x per facet; get shared\")
