# title: Point intervals after a facet collapses
# description: Synthetic values exercise a single-family picker with independent facet scales. Collapsing the family must leave one horizontal axis.

values = [center + offset for center in (0.0, 1.0, 2.0) for offset in range(-0.5, 0.5; length=21)]
rows = (; value=values, parameter=repeat(["A", "B", "C"], inner=21), family=fill("Example", length(values)))
spec = data(rows) * mapping(:value => "Value"; y=:parameter => "Parameter", row=:family) *
    pointinterval() * config(width=400, height=120,
        resolve=Dict("scale" => Dict("x" => "independent", "y" => "independent")))
with_plot_caption(spec, "Synthetic intervals with one family";
    plot_id="single-family-intervals",
    auto_remap=(; dims=["family" => "Family"], pinned=:row))
