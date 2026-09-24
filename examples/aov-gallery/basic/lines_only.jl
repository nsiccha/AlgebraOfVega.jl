# title: Lines Chart
# description: Stock prices as simple lines

data(stocks()) *
mapping(:date, :price, color=:symbol) *
visual(Lines) *
config(width=500, height=350, title="Stock Prices (Lines)")
