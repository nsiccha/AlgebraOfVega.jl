# Analyses

## AlgebraOfGraphics transforms

| Names | Task |
| --- | --- |
| `density`, `histogram` | Summarize a distribution. |
| `frequency`, `expectation` | Count rows or summarize conditional values. |
| `linear`, `smooth` | Fit a trend. |

These functions are re-exported from AlgebraOfGraphics. The [interval example](../examples/intervals.md) uses empirical quantiles and checks their interpretation against the source values.

## Intervals

```@docs
pointinterval
gradient_interval
dotinterval
lineribbon
ribbon
ribbon_view
```

## Geography and comparisons

```@docs
geoshape
geobox
ecdf_grid
ppc_overlay
```
