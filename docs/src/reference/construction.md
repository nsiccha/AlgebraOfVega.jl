# Construction

## Algebra and mappings

AlgebraOfVega provides these names itself, with AlgebraOfGraphics' spelling and meaning, so the browser path loads neither AlgebraOfGraphics nor Makie.

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

These are AlgebraOfVega's plot-type names (`AlgebraOfVega.PlotTypes`), spelled like Makie's plot types and used as arguments to `visual`; browser rendering loads no Makie. With Makie loaded, `visual` also accepts Makie's own plot types, such as `Makie.Text`. See [coordinates](../guides/composition.md#Coordinates) for positional-mapping exceptions.

## Stacked panels

```@docs
vconcat
```

## Configuration

```@docs
config
vlspec
vdata
symlog
locale_config
```
