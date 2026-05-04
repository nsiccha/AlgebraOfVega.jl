# title: ECDF + VLines overlay — dual color legends (bug)
# description: Base ECDFPlot and overlay VLines both use color=:index => nonnumeric, but render with two separate color scales/legends. VLines layer's nonnumeric modifier appears not to propagate into its scale emission.

# long: per-draw values, color=:index
long = (;
    param = repeat([\"a\",\"b\"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
truth = (;
    param = [\"a\",\"a\",\"a\",\"b\",\"b\",\"b\"],
    index = [1, 2, 3, 1, 2, 3],
    truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
base = data(long) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       visual(ECDFPlot)
overlay = data(truth) *
          mapping(:truth; row=:param, color=:index => nonnumeric) *
          visual(VLines)
(base + overlay) *
    config(facet=(; linkxaxes=:none),
           title=\"ECDF + VLines overlay -- expect one merged color legend\")
