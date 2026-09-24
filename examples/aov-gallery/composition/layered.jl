# title: Layered Plot
# description: Scatter + trend line using + operator

data(tips()) * (
    mapping(:total_bill, :tip) * visual(Scatter, opacity=0.6) +
    mapping(:total_bill, :tip) * visual(Lines, color=:firebrick)
) * config(width=500, height=350, title="Tips: Scatter + Trend")
