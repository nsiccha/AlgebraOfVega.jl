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

to_node(spec)     # HTMX.Node — embed in HTMXObjects/Oxygen apps. Aliased as `vdraw(spec)`.
to_html(spec)     # standalone HTML string
to_vegalite(spec) # raw Vega-Lite JSON Dict
```

A `VegaSpec` (the result of `data * mapping * visual * config`) auto-renders in `text/html`-aware contexts via `Base.show`, so you can also just return the `spec` directly from notebooks or HTMX route handlers.

## Where to next

| Page | What it covers |
|------|----------------|
| [Getting Started](getting-started.md) | Quick example end-to-end, the algebra (`*`, `+`, `dims`), faceting, mark types |
| [Translation Guide](translation.md)   | How AoG specs are lowered to Vega-Lite — mappings, layers, scales, the deep-merge contract |
| [Gallery](gallery.md)                 | Worked examples — scatter, ribbons, faceting, uncertainty, dashboards |
| [FAQ / Gotchas](faq.md)               | Aliases (`vdraw`, `vdata`), deep-merge surprises, faceting + select, legend binding caveats, interactivity wiring |
| [API Reference](api.md)               | Full export list, organised by use case (tidybayes-style `lineribbon` / `pointinterval` / `dotinterval` / `gradient_interval` / `ribbon` live here) |

## Installation

AlgebraOfVega is not yet registered. Install from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/nsiccha/AlgebraOfVega.jl")
```
