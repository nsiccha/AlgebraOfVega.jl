# title: Bar Chart
# description: Average tip by gender

data(tips()) *
mapping(:sex, :tip) *
visual(BarPlot) *
config(width=400, height=300, title="Average Tip by Gender",
       encoding=Dict("y" => Dict("aggregate" => "mean")))
