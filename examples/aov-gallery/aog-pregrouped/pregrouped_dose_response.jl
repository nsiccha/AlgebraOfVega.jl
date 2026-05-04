# title: Dose Response (pregrouped)
# description: Simulated dose-response box plots like a pharmacometrics QT study

let doses = ["Placebo", "Low", "Medium", "High"]
    n = 30
    effects = [randn(n) .* 2, randn(n) .* 2 .+ 1,
               randn(n) .* 2 .+ 3, randn(n) .* 2 .+ 5]
    pregrouped(
        fill.(1:4, n) => renamer(doses),
        effects
    ) * visual(BoxPlot) *
        config(title="Dose Response")
end
