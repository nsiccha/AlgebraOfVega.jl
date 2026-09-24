# title: Filtered Bar Chart
# description: Mean tip by gender filtered by day

data(tips()) *
mapping(:sex, :tip) *
visual(BarPlot) *
config(width=400, height=300, title="Average Tip by Gender",
       encoding=Dict("y" => Dict("aggregate" => "mean")),
       select=:day)
