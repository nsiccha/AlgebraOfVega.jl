# title: Filter Tips
# description: Explore tips data by day and meal time

data(tips()) *
mapping(:total_bill, :tip, color=:sex) *
visual(Scatter) *
config(width=500, height=350, title="Tips Explorer",
       select=[:day, :sex])
