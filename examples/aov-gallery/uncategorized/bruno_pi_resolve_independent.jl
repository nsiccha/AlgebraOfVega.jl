# title: Bruno QT — PI picker + raw resolve indep (regression)
# description: Mirrors web-pkpd/qt.jl _render_posterior: horizontal pointinterval through with_plot_caption(auto_remap=...), row=:basename, raw config(resolve=Dict("scale"=>Dict("x"=>"independent","y"=>"independent"))). When the picker collapses :basename to a single value, the spec ends up non-faceted; the user's facet-intended resolve was previously inherited at top level and made VL emit per-layer x-axes (stacked at the chart top). Now scrubbed by _scrub_independent_resolve_if_unfaceted!.

# 1 basename, 4 names — matches screenshot ("1 parameter family, 4 total")
using Random
rng = MersenneTwister(7)
names = String[]; basenames = String[]; values = Float64[]
centers = [-0.1, -0.15, 0.45, -1.3]; widths = [0.3, 0.3, 0.3, 0.9]
for (k, nm) in enumerate(("pop_loc_loc_beta_pop.1","pop_loc_loc_beta_pop.2","pop_loc_loc_beta_pop.3","pop_loc_loc_beta_pop.4"))
    for _ in 1:200
        push!(names, nm); push!(basenames, "pop_loc_loc_beta_pop")
        push!(values, centers[k] + widths[k]*randn(rng))
    end
end
gdf = (; name=names, basename=basenames, value=values)
spec = data(gdf) * mapping(:value => "Value"; y=:name => "Parameter", row=:basename) *
       pointinterval() *
       config(width=400, height=120,
              resolve=Dict("scale" => Dict("x" => "independent", "y" => "independent")))
with_plot_caption(spec, "Baseline — population — 4 params";
    plot_id="bruno-pi-repro",
    auto_remap=(; dims=["basename" => "Parameter family"], pinned=:row))
