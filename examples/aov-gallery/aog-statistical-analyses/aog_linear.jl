# title: Linear Regression
# description: linear() + Scatter

let x = [0.01i for i in 1:100]
    y = [xi + 0.3 * randn(1)[1] for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * (linear() + visual(Scatter)) *
        config(title="Scatter + Linear Regression")
end
