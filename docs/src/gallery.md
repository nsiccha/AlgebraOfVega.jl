---
aside: false
outline: false
---

<style>
.VPDoc:has(.htmxo-embed) > .container > .content { max-width: none !important; }
.VPDoc:has(.htmxo-embed) .content-container { max-width: none !important; }
</style>

# Gallery

AlgebraOfVega ships a web gallery with 100+ examples, all defined as
individual files under
[`examples/aov-gallery/`](https://github.com/nsiccha/AlgebraOfVega.jl/tree/main/examples/aov-gallery).
Each item is one `.jl` file with a `# title:` / `# description:` header
and the AoV spec body — read by `HTMXObjects.Gallery` at app startup.

::: tip Live and recorded
- **Local app:** [`http://localhost:8092`](http://localhost:8092) once
  started via `~/github/nsiccha/Claude/start-web.sh AlgebraOfVega` (or
  `julia --project=web/app -i web/app/main.jl`).
- **HTMXObjects companion:** the file-based gallery primitive itself
  lives in [HTMXObjects.jl](https://github.com/nsiccha/HTMXObjects.jl);
  a minimal `Gallery` / `GalleryItem` / `gallery_grid` demo is at
  [`http://localhost:8101/gallery_demo`](http://localhost:8101/gallery_demo)
  of the HTMXObjects web app (when running).
:::

## Live preview

The AoV gallery rendered inline below — fetched via HTMX
(`HX-Request: true` → AoV's `__page__` returns a body fragment that
drops into this page). VitePress proxies `/live-aov/*` to the running
AoV server (`AOV_DEV_TARGET=http://localhost:8092` by default) in dev,
and to recordings in production.

<div class="htmxo-embed" hx-get="/live-aov/" hx-trigger="load" hx-swap="innerHTML">
  <em>Loading AoV gallery from <code>/live-aov/</code> …</em>
</div>

Each plot's title links to a standalone page; the dropdown / brush /
zoom controls inside individual plots all work right here in the docs.

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
