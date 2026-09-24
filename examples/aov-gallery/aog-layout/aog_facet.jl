# title: Facet Grid
# description: Row/col faceting with scatter

let N = 200
    i = [isodd(k) ? "α" : "β" for k in 1:N]
    j = [["a","b","c"][mod1(k,3)] for k in 1:N]
    x = [0.01k + 0.3*randn(1)[1] for k in 1:N]
    y = [0.01k + 0.3*randn(1)[1] for k in 1:N]
    df = (; x, y, i, j)
    data(df) * mapping(:x, :y, row=:i, col=:j) * visual(Scatter) *
        config(title="Facet Grid")
end
