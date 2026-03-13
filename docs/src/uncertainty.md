# Uncertainty Visualization

AlgebraOfVega includes tidybayes-style uncertainty visualizations inspired by R's [ggdist](https://mjskay.github.io/ggdist/) package. These are expressed through the standard AoG algebra using custom analysis types.

## Point + Interval

Nested credible intervals with a point estimate:

```julia
data(draws) * mapping(:value, y=:parameter) * pointinterval()
```

Options: `probs=[0.95, 0.8, 0.5]` (interval widths), `point=:median` or `:mean`.

## Gradient Interval

Same intervals but with uniform width and varying opacity:

```julia
data(draws) * mapping(:value, y=:parameter) * gradient_interval()
```

## Half-Eye

Density + point interval — pure composition of existing primitives:

```julia
data(draws) * mapping(:value, y=:parameter) * (density() + pointinterval())
```

## Line + Ribbon

For draw-level predictions (many y values per x):

```julia
data(preds) * mapping(:x, :y, group=:draw) * lineribbon()
```

With grouping:

```julia
data(preds) * mapping(:x, :y, group=:draw, color=:treatment) * lineribbon()
```

Ribbon only (no median line):

```julia
data(preds) * mapping(:x, :y, group=:draw) * ribbon()
```

## Dot + Interval

Quantile dotplot with interval overlay:

```julia
data(draws) * mapping(:value, y=:parameter) * dotinterval()
```

## Raincloud

Pure composition of density, scatter, and boxplot:

```julia
data(draws) * mapping(:value, y=:parameter) *
    (density() + visual(Scatter, opacity=0.3) + visual(BoxPlot))
```

## How it works

The analysis types (`PointIntervalAnalysis`, `GradientIntervalAnalysis`, etc.) compute summary statistics in Julia:

- **Point/Gradient/Dot intervals**: `compute_interval_summary()` calculates quantiles and point estimates, embeds as inline VL data, generates rule layers (varying stroke width or opacity) + point layer.
- **Line/Ribbon**: `compute_ribbon_summary()` groups by x, computes quantiles of y across draws, generates area layers (y/y2) + median line.
- **Density**: Uses Vega-Lite's native `{"density": field}` transform.

All compose naturally with `*` and `+`, so `density() + pointinterval()` creates a multi-layer spec combining VL's density transform with Julia-computed interval data.
