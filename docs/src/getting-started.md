# Getting Started

## Basic plots

AlgebraOfVega re-exports AlgebraOfGraphics, so you use the same `data`, `mapping`, and `visual` functions:

```julia
using AlgebraOfVega

# Scatter plot
spec = data(df) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter)
draw(spec)
```

## Config

Use `config()` to set Vega-Lite properties like width, height, title, and custom encodings:

```julia
spec = data(df) * mapping(:x, :y) * visual(Lines) *
    config(width=600, height=400, title="Time Series")
```

Config's `encoding` is **deep-merged** with auto-generated encodings, so you can add properties like aggregation without losing the generated field/type:

```julia
# Add mean aggregation to y
config(encoding=Dict("y" => Dict("aggregate" => "mean")))
```

## Composition

Use `+` to layer and `*` to combine:

```julia
# Scatter + regression line
spec = data(df) * mapping(:x, :y) * (visual(Scatter) + linear())

# Multiple layers with shared data
spec = data(df) * mapping(:x, :y, color=:group) *
    (visual(Scatter, opacity=0.5) + smooth())
```

## Statistical analyses

AoG analyses are translated to native Vega-Lite transforms:

```julia
density()      # kernel density → area mark
histogram()    # binning → bar mark
linear()       # OLS regression → line mark
smooth()       # LOESS smoothing → line mark
frequency()    # count aggregation → bar mark
expectation()  # mean aggregation → bar mark
```

Add confidence intervals:

```julia
linear(interval=:confidence)  # regression line + CI band
smooth(interval=:confidence)  # LOESS line + CI band
```

## Faceting

Use AoG's `col` and `row` mappings for faceted layouts:

```julia
# Column facets
spec = data(df) * mapping(:x, :y, col=:species) * visual(Scatter)

# Row + column grid
spec = data(df) * mapping(:x, :y, row=:sex, col=:species) * visual(Scatter)
```

## Output formats

```julia
draw(spec)         # HTMX Node (for web apps using HTMXObjects)
to_html(spec)      # standalone HTML string with embedded scripts
to_vegalite(spec)  # Vega-Lite JSON as Dict
to_json(spec)      # Vega-Lite JSON string
```

## Mark types

| AoG visual | Vega-Lite mark |
|---|---|
| `Scatter` | point |
| `Lines` | line |
| `ScatterLines` | line (point: true) |
| `BarPlot` | bar |
| `Heatmap` | rect |
| `BoxPlot` | boxplot |
| `Band` | area |
| `HLines` / `VLines` | rule |
| `Stairs` | line (step-after) |
| `Errorbars` / `Rangebars` | errorbar |
