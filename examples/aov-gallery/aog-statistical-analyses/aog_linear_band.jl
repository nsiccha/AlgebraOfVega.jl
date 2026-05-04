# title: Linear + Confidence Band
# description: Linear regression with confidence ribbon (AoG linear(interval=:confidence))

let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [1.2*xi*parse(Int,ai) + parse(Int,ai) + 5*randn(1)[1] for (xi,ai) in zip(x,a)]
    df = (; x, y, a)
    data(df) * mapping(:x, :y, color=:a) * (linear(interval=:confidence) + visual(Scatter)) *
        config(title="Linear + Confidence Band")
end
