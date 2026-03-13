# Translation Guide

AlgebraOfVega translates AoG `Layer` / `Layers` objects to Vega-Lite JSON by reading the raw struct fields (`.data`, `.positional`, `.named`, `.transformation`).

## Translation pipeline

```
AoG Layer → check transformation chain for known analyses:
  → TidybayesAnalysis  → analysis_to_vl()     (multi-layer VL spec)
  → DensityAnalysis     → density_to_vl()      (VL density transform)
  → FrequencyAnalysis   → frequency_to_vl()    (VL aggregate count)
  → ExpectationAnalysis → expectation_to_vl()  (VL aggregate mean)
  → LinearAnalysis      → linear_to_vl()       (VL regression transform)
  → SmoothAnalysis      → smooth_to_vl()       (VL loess transform)
  → HistogramAnalysis   → histogram_to_vl()    (VL bin + bar)
  → (standard path):
      extract_data()    → Vega inline "values"
      extract_visual()  → Vega mark type + properties
      positional args   → x/y encoding channels
      named args        → color/size/shape/etc channels
      infer_types!()    → quantitative/nominal/ordinal
      auto-tooltip      → from all mapped fields
  → config properties merged on top (encoding deep-merged per channel)
```

## Named argument mapping

| AoG kwarg | Vega-Lite channel |
|---|---|
| `color` | color |
| `marker` | shape |
| `markersize` | size |
| `dodge_x` | xOffset |
| `dodge_y` | yOffset |
| `col` | column (facet) |
| `row` | row (facet) |
| `group` | detail |

## Positional channel mapping

Most mark types map the first two positional arguments to `x` and `y`. Exceptions:

| Mark type | Positional channels |
|---|---|
| `HLines` | `[y]` (first positional → y only) |
| `VLines` | `[x]` (first positional → x only) |
| `Rangebars` / `Errorbars` | `[x, y, y2]` |
| All others | `[x, y]` |

## Config deep-merge

`config(encoding=...)` is deep-merged per channel. This means you can add properties to auto-generated encodings without losing the `field` and `type`:

```julia
# Adds aggregate to the auto-generated y encoding
config(encoding=Dict("y" => Dict("aggregate" => "mean")))

# Adds log scale to x
config(encoding=Dict("x" => Dict("scale" => Dict("type" => "log"))))
```

## Confidence bands

Vega-Lite's native `errorband` requires multiple observations per x value, which typical scatter data doesn't have. When `interval=:confidence` is set on `linear()` or `smooth()`, the CI is computed in Julia:

- **`linear`**: Analytic regression CI using standard error of the mean response
- **`smooth`**: Moving-window weighted mean ± SE with tricube weights

The CI data is embedded as a separate area+y2 layer with its own inline data.

## Faceted specs

For faceted specs (using `col=` or `row=` in mapping), config `width`/`height` are routed to the inner `spec` dict (per-cell size), not the top level (total size).
