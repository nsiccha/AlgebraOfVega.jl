# Construction

## Algebra and mappings

These names are re-exported from AlgebraOfGraphics and retain its meaning.

| Names | Task |
| --- | --- |
| `data`, `vdata` | Attach a Tables.jl source; `vdata` avoids a local name collision. |
| `mapping`, `visual`, `dims` | Map columns, set mark attributes, or map array dimensions. |
| `renamer`, `sorter`, `nonnumeric`, `verbatim`, `presorted`, `direct` | Label, order, or classify mapping values. |
| `scale`, `scales`, `pregrouped`, `wrapped` | Identify scales, configure them, supply grouped data, or wrap facets. |

The [composition guide](../guides/composition.md) demonstrates the algebra. The [scale guide](../guides/scales.md) shows the supported scale-configuration path.

## Marks

| Names | Graphic |
| --- | --- |
| `Scatter`, `Lines`, `ScatterLines`, `Stairs` | Points and ordered trajectories. |
| `BarPlot`, `Heatmap` | Bars and rectangular cells. |
| `BoxPlot`, `Violin`, `RainClouds`, `Hist`, `ECDFPlot` | Distribution displays. |
| `Band`, `Errorbars`, `Rangebars`, `CrossBar` | Bounds and intervals supplied as coordinates. |
| `HLines`, `VLines`, `HSpan`, `VSpan` | Reference rules and shaded ranges. |
| `Contour` | Contours. |

These are re-exported Makie plot types used as arguments to `visual`; browser rendering does not require a Makie backend. See [coordinates](../guides/composition.md#Coordinates) for positional-mapping exceptions.

## Configuration

```@docs
config
vlspec
vdata
symlog
locale_config
```
