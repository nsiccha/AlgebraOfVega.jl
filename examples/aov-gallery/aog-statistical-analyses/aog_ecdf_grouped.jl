# title: Grouped ECDF
# description: ECDF with color grouping

let n = 200
    x = [randn(n); 1.5 .+ randn(n)]
    c = [fill("a", n); fill("b", n)]
    df = (; x, c)
    data(df) * mapping(:x, color=:c) * visual(ECDFPlot) *
        config(title="Grouped ECDF")
end
