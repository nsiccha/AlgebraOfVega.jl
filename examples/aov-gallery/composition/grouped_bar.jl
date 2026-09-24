# title: Grouped Bar
# description: Sales by channel with grouped bars

data(melt_sales(monthly_sales())) *
mapping(:month, :sales, color=:channel, dodge_x=:channel) *
visual(BarPlot) *
config(width=600, height=300, title="Monthly Sales by Channel")
