# title: Density Plot
# description: Density with color grouping

let n = 500
    x = [randn(n); 1.5 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c) * density() *
        config(title="Density Plot")
end
