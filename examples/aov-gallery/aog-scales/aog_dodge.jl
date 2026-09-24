# title: Dodged Bar Plot
# description: Bar plot with dodge by group

let df = (; x=["One","One","Two","Two"], y=1:4, group=["A","B","A","B"])
    data(df) * mapping(:x, :y, dodge_x=:group, color=:group) * visual(BarPlot) *
        config(title="Dodged Bar Plot")
end
