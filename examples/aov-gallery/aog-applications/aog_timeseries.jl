# title: Time Series
# description: Multi-series line plot over dates

let dates = ["2025-01-\$(lpad(d,2,'0'))" for d in 1:31]
    y1 = cumsum(randn(31))
    y2 = cumsum(randn(31))
    n = length(dates)
    df = (; date=[dates;dates], value=[y1;y2], series=[fill("y",n);fill("z",n)])
    data(df) * mapping(:date, :value, color=:series) * visual(Lines) *
        config(title="Time Series")
end
