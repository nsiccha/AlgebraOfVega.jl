# title: Faceted Density
# description: One KDE per panel, each sampled over its OWN [min, max]

# The three parameters live on wildly different scales. A Vega-Lite `density`
# transform computes a single extent for the whole dataset, so every panel would
# sample the pooled [0.2, 145] grid and the two tight parameters would collapse
# into slivers. AoV computes the curves in Julia instead, per facet level, so
# each panel spans its own data.
let n = 400
    parameter = repeat(["mu", "sigma", "tau"], inner=n)
    value = vcat(100 .+ 15 .* randn(n), 0.5 .+ 0.1 .* randn(n), 3 .+ 0.4 .* randn(n))
    df = (; parameter, value)
    data(df) * mapping(:value; col=:parameter) * density() *
        config(width=180, height=180, title="Faceted Density",
               facet=(; linkxaxes=:none))
end
