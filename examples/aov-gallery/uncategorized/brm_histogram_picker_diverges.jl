# title: Histogram picker vs no-picker — diverges (bug)
# description: Same histogram spec rendered via to_node(spec) and with_plot_caption(spec; auto_remap=…) produces different specs. BRM pattern: row=:param (facet) + color=:index (per-index colors within a facet). Picker path re-composes layers and may drop nonnumeric / facet wrapping that histogram_to_vl sets up.

df = (;
    param = repeat([\"a\",\"b\"], inner=600),
    index = repeat(repeat(1:3, inner=200), 2),
    value = vcat(randn(600), randn(600) .- 8))
spec = data(df) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       histogram() *
       config(facet=(; linkxaxes=:none),
              title=\"Histogram via auto_remap (picker)\")
auto_remap_node(\"brm-hist-picker\", spec;
    dims=[\"param\" => \"Parameter\", \"index\" => \"Index\"])
