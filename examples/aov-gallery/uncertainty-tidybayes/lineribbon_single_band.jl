# title: Single-band Line + Ribbon
# description: lineribbon with ONE precomputed band (regression test for n_bands==1)

summary = _preaggregate(regression_predictions(), :x)
data(summary) * mapping(:x, :median => "Response") *
    lineribbon(bands=[:q025 => :q975]) *
    config(width=500, height=350, title="Single-band Line + Ribbon")
