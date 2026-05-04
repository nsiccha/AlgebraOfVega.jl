# title: Legend Merge
# description: Lines + Scatter sharing color legend

let N = 40
    x = [1:N; 1:N]
    y = cumsum(randn(2N))
    grp = [fill("a", N); fill("b", N)]
    df = (; x, y, grp)
    (visual(Lines) + visual(Scatter)) *
        data(df) * mapping(:x, :y, color=:grp) *
        config(title="Legend Merge: Lines + Scatter")
end
