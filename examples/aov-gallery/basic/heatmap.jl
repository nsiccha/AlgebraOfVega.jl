# title: Heatmap
# description: Monthly temperatures across cities

data(temperatures()) *
mapping(:month, :city, color=:temp) *
visual(Heatmap) *
config(width=500, height=200, title="Monthly Temperatures by City")
