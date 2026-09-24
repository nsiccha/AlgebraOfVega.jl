# title: Combined Categories
# description: Two datasets with unified categories

let df1 = (; x=[isodd(k) ? "one" : "two" for k in 1:100], y=randn(100))
    df2 = (; x=[isodd(k) ? "three" : "four" for k in 1:50], y=randn(50))
    (data(df1) + data(df2)) * mapping(:x, :y) * visual(BoxPlot) *
        config(title="Combined Categories")
end
