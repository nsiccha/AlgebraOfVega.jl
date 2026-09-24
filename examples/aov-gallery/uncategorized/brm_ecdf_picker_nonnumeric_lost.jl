# title: ECDF + VLines via picker — nonnumeric lost (bug)
# description: Same spec as brm_ecdf_vlines_overlay_dual_legend (which now renders a single color legend), but routed through with_plot_caption(spec; auto_remap=…). BRM reports the picker path reverts to dual legends — _auto_remap_parts must be dropping the nonnumeric Pair modifier when re-composing layers.

long = (;
    param = repeat(["a","b"], inner=300),
    index = repeat(repeat(1:3, inner=100), 2),
    value = vcat(randn(300), randn(300) .- 5))
truth = (;
    param = ["a","a","a","b","b","b"],
    index = [1, 2, 3, 1, 2, 3],
    truth = [0.1, -0.2, 0.3, -5.1, -4.9, -5.2])
base = data(long) *
       mapping(:value; row=:param, color=:index => nonnumeric) *
       visual(ECDFPlot)
overlay = data(truth) *
          mapping(:truth; row=:param, color=:index => nonnumeric) *
          visual(VLines)
spec = (base + overlay) *
       config(facet=(; linkxaxes=:none),
              title="ECDF + VLines via auto_remap (picker)")
auto_remap_node("brm-ecdf-picker", spec;
    dims=["param" => "Parameter", "index" => "Index"])
