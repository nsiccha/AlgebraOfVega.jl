# title: Time Series Box Plot
# description: Box plot of observations per date

let dates = ["2025-01-\$(lpad(d,2,'0'))" for d in 1:15]
    trend = cumsum(randn(15))
    rows_date = String[]
    rows_obs = Float64[]
    for _ in 1:500
        idx = rand(1:15)
        push!(rows_date, dates[idx])
        push!(rows_obs, trend[idx] + 2*rand())
    end
    df = (; date=rows_date, observation=rows_obs)
    data(df) * mapping(:date, :observation) * visual(BoxPlot) *
        config(title="Time Series Box Plot")
end
