# title: Facet Wrap
# description: Layout wrapping with 5 groups

let df = (x=rand(100), y=rand(100), l=[["a","b","c","d","e"][mod1(k,5)] for k in 1:100])
    data(df) * mapping(:x, :y, col=:l) * visual(Scatter) *
        config(title="Facet Wrap", columns=3)
end
