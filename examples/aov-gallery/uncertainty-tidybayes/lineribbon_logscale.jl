# title: Ribbon + Scatter (log scale)
# description: faceted lineribbon+scatter with AoG-style scales(Y=(; scale=log10))

using Tables
exp_table(t) = (x=Tables.getcolumn(t,:x), y=exp.(Tables.getcolumn(t,:y)),
    (k => Tables.getcolumn(t,k) for k in Tables.columnnames(t) if k ∉ (:x,:y))...)
pred = data(exp_table(faceted_regression_predictions())) *
    mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
obs = data(exp_table(faceted_observations())) *
    mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
(pred + obs) * config(width=180, height=120, scales=scales(Y=(; scale=log10)))
