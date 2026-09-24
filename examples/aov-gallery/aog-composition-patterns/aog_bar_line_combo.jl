# title: Bar + Line
# description: Sales bars with trend line overlay

let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    sales = [120, 135, 148, 142, 165, 178, 195, 188, 172, 158, 145, 162]
    trend = [125, 130, 138, 145, 152, 160, 168, 175, 170, 163, 155, 158]
    (data((; month=months, sales)) * mapping(:month, :sales) * visual(BarPlot, opacity=0.6) +
     data((; month=months, trend)) * mapping(:month, :trend) * visual(Lines, color=:red)) *
        config(title="Monthly Sales with Trend")
end
