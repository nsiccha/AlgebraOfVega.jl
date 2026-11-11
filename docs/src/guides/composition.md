# Composition

Build a figure by combining a table, mappings, and marks; add independently defined layers to compare different kinds of data on shared axes.

## Terms

```@example composition
using AlgebraOfVega
using Main.DocsPlots # hide
measurements = (time=[0, 1, 2], temperature=[18, 21, 25])
base = data(measurements) * mapping(:time => "Time (min)", :temperature => "Temperature (°C)")
points = base * visual(Scatter; color="#2a78d6")
lines = base * visual(Lines; color="#eb6834")
plot = (lines + points) * config(height=220)
vdraw(plot);
DocsPlots.figure(plot, "composition"; caption="The two marks use the same measurements: points identify observations and segments connect them in time.") # hide
```

`data`, `mapping`, and `visual` are AlgebraOfGraphics functions re-exported by AlgebraOfVega. Multiplication combines their roles. Addition creates layers. `config` attaches browser-specific settings to the resulting object. Keep it last so the scope of the settings is apparent.

A named tuple of equal-length columns is enough; `data` accepts Tables.jl sources. A mapping names a column and optionally a label. Labels express units without changing the values. Use a named mapping such as `color=:instrument` to identify groups; a fixed `visual(...; color="…")` sets the mark appearance without introducing groups.

## Layers

The generated specification preserves both marks.

```@example composition
spec = to_vegalite(plot; interactive=false)
[layer["mark"]["type"] for layer in spec["layer"]]
```

Each layer can instead have its own table. A threshold rule needs only the coordinate that positions the rule. The [measurements example](../examples/measurements.md) overlays such a rule with observed trajectories.

## Coordinates

Most marks map their first two positional arguments to x and y. The exceptions below matter when replacing one visual with another.

| Mark | Positional coordinates |
| --- | --- |
| `HLines` | y |
| `VLines` | x |
| `HSpan` | y, y2 |
| `VSpan` | x, x2 |
| `Band`, `Rangebars`, `Errorbars` | x, y, y2 |
| Horizontal `BarPlot` | y, x |

For categorical groups encoded numerically, use `nonnumeric` in the mapping. For facets use `row`, `col`, or `layout`. A facet splits a figure into panels; adding layers overlays marks within the same figure. These are different comparisons, even when both use the same grouping column.

Follow [Repeated measurements](../examples/measurements.md) for a complete layered figure with checks of its data and generated specification.
