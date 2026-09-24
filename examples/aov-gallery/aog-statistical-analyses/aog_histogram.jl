# title: Stacked Histogram
# description: Histogram with color stacking

let n = 500
    x = [randn(n); 1.0 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c, stack=:c) * histogram() *
        config(title="Stacked Histogram")
end
