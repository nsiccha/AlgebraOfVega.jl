# Scales

Set category order, colors, and axis transforms while retaining the original values and units in the table.

## Categories

```@example scales
using AlgebraOfVega
using Main.DocsPlots # hide
values = (time=repeat([1, 2, 3], 2), concentration=[1, 10, 100, 2, 20, 200],
          group=repeat(["A", "B"], inner=3))
plot = data(values) *
    mapping(:time => "Time (h)", :concentration => "Concentration (mg/L)"; color=:group => "Group") *
    visual(ScatterLines) * config(height=240,
        scales=scales(Color=(categories=["A", "B"], palette=["#2a78d6", "#eb6834"]),
                      Y=(scale=log10,)))
vdraw(plot);
DocsPlots.figure(plot, "scales"; caption="Equal vertical steps indicate equal concentration ratios on the logarithmic axis. Labels and tooltips retain concentration in mg/L.") # hide
```

`categories` pins the meaning of each palette entry. Use the same category list when comparing several figures. For a continuous color mapping, choose `colormap` and, when required, `colorrange` instead of a categorical palette.

`scales` is the AlgebraOfGraphics scale API. Pass it through `config(scales=...)`, or as the second positional argument to `vdraw` or `to_vegalite`. It is not a term multiplied into the expression.

## Numeric axes

The generated y scale is logarithmic; the original concentrations remain unchanged.

```@example scales
__docs_output__ = begin # hide
spec = to_vegalite(plot; interactive=false)
(scale_type=spec["encoding"]["y"]["scale"]["type"],
 source_concentration_mg_per_L=values.concentration)
end # hide
show(stdout, MIME"text/plain"(), __docs_output__) # hide
println() # hide
```

Use a log axis for strictly positive quantities spanning multiplicative ranges. Transforming the values beforehand would change the numbers shown in tooltips. When genuine zeros must remain visible across a wide range, `symlog` provides a linear region around zero and logarithmic behavior farther away. Choose the scale based on the quantity being compared; do not use a log axis to conceal invalid nonpositive data.

Facet panels that show different quantities can take different y scale types in one figure. Key the scale by the facet value: on a figure faceted by `row=`, `scales(Y=(scale=Dict("Cmax (ng/mL)" => log10),))` draws the Cmax row on a log axis and the other rows on the shared linear one, on one x axis. With a `col=` facet the same `Dict` keys the columns, and with a wrapped `layout=` facet the panels: each keeps its own x and y axes, and the panels still wrap to the plot's width.

Axis options also include `zero`, `nice`, `domain`, and `clamp`. AoV's quantitative axes do not force zero into the domain, as AlgebraOfGraphics does not for points and lines. A bar's value axis is the exception: bars, `frequency()`, `expectation()` and `histogram()` start at zero, as AlgebraOfGraphics draws them, unless the bars have a base of their own (`fillto`) or stand on a log axis. `zero=false` on that axis starts the bars at the axis edge instead, which makes their lengths unreadable.

Every one of these Y options can also be given per panel, keyed the same way. `scales(Y=(scale=Dict(p => log10 for p in panels), domain=Dict("Ctrough (ng/mL)" => (0.3, 3e5)), clamp=Dict("Ctrough (ng/mL)" => true)))` puts every panel on a log axis and cuts the Ctrough panel's at 0.3, drawing its lower values on the axis edge, while the other panels fit their own ranges. The values themselves are unchanged, so tooltips, the readout and the CSV download still show them. An option given as a plain value applies to every panel, beside the per-panel ones.

## Appearance

The browser runtime follows the page's foreground color for axes and text. An authored categorical palette keeps its colors when the theme changes. Use `color=:ink` for reference rules that should follow the foreground, instead of a fixed black mark that could disappear on a dark page.

A palette entry can be `:ink` too: `palette=[:ink, "#e03131"]` draws the first category in the foreground color, its legend entry included, while the other entries keep their colors. Use it for a reference series that belongs in the color legend.

The [measurement comparison](../examples/measurements.md) uses a fixed category order and a theme-aware reference rule in one figure.
