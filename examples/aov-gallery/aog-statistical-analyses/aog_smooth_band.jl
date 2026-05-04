# title: Smooth + Confidence Band
# description: Smooth regression with confidence ribbon (AoG smooth())

let x = [0.05i for i in 1:200]
    a = [isodd(i) ? "1" : "2" for i in 1:200]
    y = [sin(xi)*parse(Int,ai) + parse(Int,ai) + 0.5*randn(1)[1] for (xi,ai) in zip(x,a)]
    df = (; x, y, a)
    data(df) * mapping(:x, :y, color=:a) * (smooth(interval=:confidence) + visual(Scatter)) *
        config(title="Smooth + Confidence Band")
end
