# title: Pre-aggregated Line + Ribbon
# description: lineribbon from pre-computed quantile columns (no draws)

summary = _preaggregate(regression_predictions(), :x)
data(summary) * mapping(:x, :median => "Response") *
    lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=350, title="Pre-aggregated Line + Ribbon")
