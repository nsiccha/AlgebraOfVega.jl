# title: Smooth Regression
# description: smooth() + Scatter (loess)

let x = [0.01i for i in 1:100]
    y = [5*xi^2 + 0.3*randn(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (smooth() + visual(Scatter)) *
        config(title="Scatter + Smooth (Loess)")
end
