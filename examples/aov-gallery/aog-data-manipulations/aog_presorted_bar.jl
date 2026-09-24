# title: Presorted Bar
# description: Bar chart preserving custom data order

let countries = ["Algeria","Bolivia","China","Denmark","Ecuador","France"]
    vals = [2.72, 0.84, 1.41, 2.72, 0.84, 1.41]
    group = ["2","3","1","1","3","2"]
    df = (; countries, value=vals, group)
    data(df) * mapping(:countries, :value, color=:group) * visual(BarPlot) *
        config(title="Presorted Bar Chart")
end
