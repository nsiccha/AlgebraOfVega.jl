# title: Pregrouped (no renamer)
# description: Box plot from pregrouped data without renamer

pregrouped(
    fill.(1:4, 20),
    [randn(20) .+ i for i in 1:4]
) * visual(BoxPlot) *
    config(title="Pregrouped (no renamer)")
