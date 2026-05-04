# title: Faceted Multi-Layer
# description: Scatter + Lines across facets from different data

let df1 = (x=rand(100), y=rand(100),
               i=[["a","b","c"][mod1(k,3)] for k in 1:100],
               j=[["d","e","f"][mod1(k,3)] for k in 1:100])
    df2 = (x=[0.0,1.0], y=[0.5,0.5], i=["a","a"], j=["e","e"])
    layers = data(df1) * visual(Scatter) + data(df2) * visual(Lines)
    layers * mapping(:x, :y, col=:i, row=:j) *
        config(title="Faceted Multi-Layer")
end
