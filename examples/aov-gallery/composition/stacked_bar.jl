# title: Stacked Bar
# description: Population by age group and sex

data(melt_population(population())) *
mapping(:category, :count, color=:sex) *
visual(BarPlot) *
config(width=400, height=300, title="Population by Age Group")
