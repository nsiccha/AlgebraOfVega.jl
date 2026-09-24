# title: Area Chart
# description: Stock prices as area chart

data(stocks()) *
mapping(:date, :price, color=:symbol) *
visual(Band, opacity=0.6) *
config(width=500, height=350, title="Stock Prices (Area)")
