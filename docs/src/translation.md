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
      auto-tooltip      → from all mapped fields, in channel order (x, y, …, color, …)
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

The NamedTuple spelling is equivalent and lowers to the same Dict: `config(encoding=(; x=(; scale=(; type="log"))))`. Raw `config(config=...)` (a Dict or NamedTuple) is deep-merged the same way into AoV's default Vega-Lite `config`.

Successive `config(encoding=...)` terms merge the same way, channel by channel; on the same key the later term wins.

### Per-layer overrides

An encoding override multiplied onto one summand of a `+` sum applies to that summand's layers only, just as `a * visual(...) + b` styles only `a`. Multiply it onto the whole sum to reach every layer:

```julia
# The observed marks get their own tooltip; the posterior keeps its automatic one.
posterior + observed * config(encoding=Dict(:tooltip => [Dict("field" => "label")]))

# Every layer gets the tooltip.
(posterior + observed) * config(encoding=Dict(:tooltip => [Dict("field" => "label")]))
```

`row`/`column`/`facet` overrides always configure the one facet every layer shares, and every other `config` property (`width`, `title`, `scales`, `params`, …) describes the whole figure whichever summand carries it. Scales, axes and legends are still shared between layers: Vega-Lite merges a per-layer scale override into the shared scale.

## Confidence bands

Vega-Lite's native `errorband` requires multiple observations per x value, which typical scatter data doesn't have. When `interval=:confidence` is set on `linear()` or `smooth()`, the CI is computed in Julia:

- **`linear`**: Analytic regression CI using standard error of the mean response
- **`smooth`**: Moving-window weighted mean ± SE with tricube weights

The CI data is embedded as a separate area+y2 layer with its own inline data.

## Faceted specs

For faceted specs (using `col=` or `row=` in mapping), config `width`/`height` are routed to the inner `spec` dict (per-cell size), not the top level (total size).

### Median marker categories in interval plots

`mapping(...; marker=:sex => "Sex")` also applies to `pointinterval()`,
`pointinterval(bands=...)`, `gradient_interval()`, and the median in
`dotinterval()`. The marker column participates in draw summarization, so
categories are never pooled merely because their other mapping keys match.
Intervals keep their colour mapping and the median retains its white fill and
dark outline. Both orientations and facets preserve the mapping.

Use `config(scales=scales(Marker=(categories=["Female", "Male"],
palette=["circle", "square"])))` to keep marker categories and shapes stable
across figures. As with `Color`, this override only touches field-bearing shape
encodings; it does not add shape encodings to interval rules.
