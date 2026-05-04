# title: PPC Overlay
# description: ppc_overlay recipe: observations + predictions + truth with independent scales

ppc_overlay(
    faceted_observations(), faceted_regression_predictions();
    x=:x, y=:y, col=:panel, row=:site, group=:draw,
) * config(width=180, height=120, facet=(; linkxaxes=:none, linkyaxes=:none)) |> vdraw
