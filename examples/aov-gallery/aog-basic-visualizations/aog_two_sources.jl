# title: Two Data Sources
# description: Lines from one source + Scatter from another

let df1 = (; x=collect(range(-3.14, 3.14, length=100)), y=sin.(range(-3.14, 3.14, length=100)))
    df2 = (x=rand(10) .* 6 .- 3, y=rand(10) .* 2 .- 1)
    (data(df1) * visual(Lines) + data(df2) * visual(Scatter)) *
        mapping(:x, :y) * config(title="Two Data Sources")
end
