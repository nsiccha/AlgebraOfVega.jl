# title: Pre-aggregated Grouped Ribbon
# description: pre-aggregated lineribbon with color grouping

summary = _preaggregate(grouped_regression_predictions(), :x, :group)
data(summary) * mapping(:x, :median, color=:group) *
    lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=350, title="Pre-aggregated Grouped Ribbon")
