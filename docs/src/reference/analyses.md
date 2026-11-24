# Analyses

## AlgebraOfGraphics transforms

| Names | Task |
| --- | --- |
| `density`, `histogram` | Summarize a distribution. |
| `frequency`, `expectation` | Count rows or summarize conditional values. |
| `linear`, `smooth` | Fit a trend. |

AlgebraOfVega provides these analyses itself, with AlgebraOfGraphics' names and options; with AlgebraOfGraphics and Makie loaded, `sdraw` hands them to AlgebraOfGraphics. The [interval example](../examples/intervals.md) uses empirical quantiles and checks their interpretation against the source values.

```@docs
density
histogram
frequency
expectation
linear
smooth
```

## Intervals

```@docs
pointinterval
gradient_interval
dotinterval
lineribbon
ribbon
ribbon_view
intervals_switch
```

## Geography and comparisons

```@docs
geoshape
geobox
ecdf_grid
ppc_overlay
```
