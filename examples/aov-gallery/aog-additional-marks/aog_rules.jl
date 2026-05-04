# title: Reference Lines
# description: Scatter with mean reference line overlay

let df = cars()
    mean_mpg = sum(df.mpg) / length(df.mpg)
    (data(df) * mapping(:horsepower, :mpg) * visual(Scatter) +
     data((; y=[mean_mpg])) * mapping(:y) * visual(HLines)) *
        config(title="MPG with Mean Reference Line")
end
