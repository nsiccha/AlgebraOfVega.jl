# AlgebraOfVega.jl

AlgebraOfVega translates [AlgebraOfGraphics.jl](https://aog.makie.org/stable/) specs into [Vega-Lite](https://vega.github.io/vega-lite/) JSON for interactive client-side rendering. Write standard AoG (`data * mapping * visual`) and get plots that run in the browser with tooltips, legend filtering, zoom/pan, and HTMX-driven server-side updates — without a Makie backend.

## Why?

- **Interactive by default** — tooltips, legend click filtering, and zoom/pan without configuration
- **Composable algebra** — the same `*` (intersection), `+` (union), and `dims(...)` from AoG
- **Client-side rendering** — Vega-Lite in the browser, no Makie required
- **HTMX integration** — wire Vega signals to server-side Julia handlers for dynamic dashboards
- **Tidybayes-style uncertainty** — `lineribbon`, `pointinterval`, `dotinterval`, `gradient_interval`, `ribbon` for posterior visualisation
- **Static export** — also produces standalone HTML, raw Vega-Lite JSON, or SVG via `sdraw`

## Quick example

```julia
using AlgebraOfVega

spec = data(df) * mapping(:x, :y, color=:group) * visual(Scatter) *
       config(width=500, title="My Plot")

draw(spec)        # HTMX Node — embed in HTMXObjects/Oxygen apps
to_html(spec)     # standalone HTML string
to_vegalite(spec) # raw Vega-Lite JSON Dict
```

## Where to next

| Page | What it covers |
|------|----------------|
| [Getting Started](getting-started.md) | Quick example end-to-end, the algebra (`*`, `+`, `dims`), faceting, mark types |
| [Translation Guide](translation.md)   | How AoG specs are lowered to Vega-Lite — mappings, layers, scales, the deep-merge contract |
| [Interactivity](interactivity.md)     | Tooltips, legend filtering, dropdown selection, signal binding, HTMX wiring with `update_data` |
| [Uncertainty Visualisation](uncertainty.md) | Tidybayes-style `lineribbon`, `pointinterval`, `gradient_interval`, `dotinterval`, `ribbon` |
| [Gallery](gallery.md) and [Gallery Examples](gallery-examples.md) | ~50 worked examples, from scatter to ridgeline plots |
| [FAQ / Gotchas](faq.md)               | Aliases (`vdraw`, `vdata`), common deep-merge surprises, faceting + select, legend binding caveats |
| [API Reference](api.md)               | Full export list, organised by use case |

## Installation

AlgebraOfVega is not yet registered. Install from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/nsiccha/AlgebraOfVega.jl")
```
