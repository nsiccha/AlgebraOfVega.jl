# title: Basic Histogram
# description: Simple histogram with 20 bins

let df = (x=rand(0:99, 1000),)
    data(df) * mapping(:x) * histogram() *
        config(title="Basic Histogram")
end
