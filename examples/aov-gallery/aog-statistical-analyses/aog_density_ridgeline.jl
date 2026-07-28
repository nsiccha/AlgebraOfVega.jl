# title: Density Ridgeline
# description: `y=` stacks one KDE per level, each with its own extent

# `y=` claims the facet operator (wrap form, one column). The KDE is computed in
# Julia per level: with the Vega-Lite transform this single-sublayer spec was
# hoisted above the facet split, which both pooled the levels into one curve and
# left the facet nothing to partition on — it rendered as a single panel.
let n = 400
    parameter = repeat(["alpha", "beta", "sigma"], inner=n)
    value = vcat(1.0 .+ 0.6 .* randn(n), -2.0 .+ 1.4 .* randn(n), 0.4 .+ 0.08 .* randn(n))
    df = (; parameter, value)
    data(df) * mapping(:value; y=:parameter) * density() *
        config(title="Density Ridgeline")
end
