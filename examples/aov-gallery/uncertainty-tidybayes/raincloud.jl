# title: Raincloud Plot
# description: tidybayes-style: density + jittered points + boxplot

data(posterior_draws()) *
mapping(:value, y=:parameter) *
(density() + visual(Scatter, opacity=0.3) + visual(BoxPlot)) *
config(width=500, height=300, title="Raincloud Plot (tidybayes-style)")
