# title: Sine Wave (Lines)
# description: Lines visual with sin(x)

let x = range(-π, π, length=100)
    df = (; x=collect(x), y=sin.(x))
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="Sine Wave")
end
