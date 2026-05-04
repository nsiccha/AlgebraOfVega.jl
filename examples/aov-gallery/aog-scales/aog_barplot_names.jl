# title: Named Bar Plot
# description: Bar chart with string category names

let df = (; name=["Anna Coolidge","Berta Bauer","Charlie Archer"], age=[34,79,58])
    data(df) * mapping(:name, :age) * visual(BarPlot) *
        config(title="Named Bar Plot")
end
