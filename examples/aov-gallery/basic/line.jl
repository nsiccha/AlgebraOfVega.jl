# title: Line Chart
# description: Stock prices over time with points

data(stocks()) *
mapping(:date, :price, color=:symbol) *
visual(ScatterLines) *
config(width=500, height=350, title="Stock Prices Over Time")
