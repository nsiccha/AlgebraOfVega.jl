# Gallery

AlgebraOfVega includes a web gallery with 70+ examples. Run it locally:

```bash
~/github/nsiccha/Claude/start-web.sh AlgebraOfVega
# Opens at http://localhost:8092
```

Or start manually:

```bash
julia --project=web/app -i web/app/main.jl
```

## Sections

- **Interactive Filtering** — client-side dropdown filtering via `config(select=...)`
- **Basic** — scatter, bar, line, area, histogram, heatmap, boxplot
- **Composition** — layered plots, stacked/grouped bars, bubble charts
- **Interactive** — brush selection, click highlight, zoom/pan, sliders, dropdowns
- **AoG Examples** — reproductions from the [AlgebraOfGraphics docs](https://aog.makie.org/stable/): basic viz, additional marks, data manipulations, scales, statistical analyses, composition patterns, layout, applications
- **Uncertainty (tidybayes)** — point interval, half-eye, gradient interval, lineribbon, dotinterval, raincloud
- **HTMX Demos** — brush → server stats, server-side data update with animation

## Data Explorer

The `/explorer` page provides a fully client-side interactive plot builder. Select a dataset, then pick x, y, color, facet row, facet column, and mark type from dropdowns. The Vega-Lite spec is rebuilt in JavaScript with no server round-trips.

## Endpoints

- `/` — gallery index
- `/plot/{id}` — individual plot detail page
- `/spec/{id}` — raw Vega-Lite JSON
- `/standalone/{id}` — standalone HTML page
- `/explorer` — interactive data explorer
- `/flagged` — user-flagged plots
