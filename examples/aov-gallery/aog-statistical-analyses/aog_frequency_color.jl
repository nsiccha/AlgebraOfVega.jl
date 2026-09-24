# title: Frequency by Group
# description: Stacked frequency counts with color

data(tips()) * mapping(:day, color=:sex) * frequency() *
config(title="Tips per Day by Gender")
