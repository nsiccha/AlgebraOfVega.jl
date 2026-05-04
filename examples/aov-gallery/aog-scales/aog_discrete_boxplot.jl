# title: Discrete Box Plot
# description: Box plot with categorical x axis

let df = (x=[["a","b","c"][mod1(k,3)] for k in 1:100], y=rand(100))
    data(df) * mapping(:x, :y) * visual(BoxPlot) *
        config(title="Box Plot with Categories")
end
