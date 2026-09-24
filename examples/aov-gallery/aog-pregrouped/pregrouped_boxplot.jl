# title: Pregrouped Box Plot
# description: Box plot from pregrouped data with renamer labels

pregrouped(
    fill.(1:3, 10) => renamer(["A", "B", "C"]),
    [randn(10) for _ in 1:3]
) * visual(BoxPlot) *
    config(title="Pregrouped Box Plot")
