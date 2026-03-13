# AlgebraOfVega.jl

AlgebraOfVega translates [AlgebraOfGraphics.jl](https://aog.makie.org/stable/) specs into [Vega-Lite](https://vega.github.io/vega-lite/) JSON for interactive client-side rendering.

Write standard AoG code — `data * mapping * visual` — and get interactive Vega-Lite plots that run in the browser with tooltips, legend filtering, and more.

## Why?

- **Interactive by default** — tooltips, legend click filtering, and zoom/pan without any configuration
- **Composable algebra** — the same `*` and `+` operators from AlgebraOfGraphics
- **Client-side rendering** — plots render in the browser via Vega-Lite, no Makie backend needed
- **HTMX integration** — wire Vega signals to server-side Julia handlers for dynamic dashboards

## Quick example

```julia
using AlgebraOfVega

spec = data(df) * mapping(:x, :y, color=:group) * visual(Scatter) *
    config(width=500, title="My Plot")

draw(spec)        # HTMX Node for web apps
to_html(spec)     # standalone HTML string
to_vegalite(spec) # Vega-Lite JSON Dict
```

## Installation

AlgebraOfVega is not yet registered. Install from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/nsiccha/AlgebraOfVega.jl")
```
