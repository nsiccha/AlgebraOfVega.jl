# title: Error Bars
# description: Point estimates with error bars

let categories = ["A", "B", "C", "D", "E"]
    means = [4.2, 3.8, 5.1, 4.6, 3.5]
    lo = means .- [0.5, 0.3, 0.7, 0.4, 0.6]
    hi = means .+ [0.5, 0.3, 0.7, 0.4, 0.6]
    df = (; category=categories, mean=means, lo, hi)
    (data(df) * mapping(:category, :mean) * visual(Scatter) +
     data(df) * mapping(:category, :lo, :hi) * visual(Rangebars)) *
        config(title="Estimates with Error Bars")
end
