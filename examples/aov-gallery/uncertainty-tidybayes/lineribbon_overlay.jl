# title: Ribbon + Scatter Overlay
# description: faceted lineribbon (col+row) with observed data points overlaid

pred = data(faceted_regression_predictions()) *
    mapping(:x, :y, group=:draw, col=:panel, row=:site) * lineribbon()
obs = data(faceted_observations()) *
    mapping(:x, :y, col=:panel, row=:site) * visual(Scatter; color=:black, size=30)
(pred + obs) * config(width=180, height=120, title="Ribbon + Observations")
