# title: Lines + Scatter
# description: Scatter + Lines composition

let x = range(-π, π, length=100)
    df = (; x=collect(x), y=sin.(x))
    data(df) * mapping(:x, :y) * (visual(Scatter) + visual(Lines)) *
        config(title="Lines + Scatter")
end
