# title: ECDF Plot
# description: Empirical cumulative distribution function

let n = 200
    x = randn(n)
    df = (; x)
    data(df) * mapping(:x) * visual(ECDFPlot) *
        config(title="ECDF Plot")
end
