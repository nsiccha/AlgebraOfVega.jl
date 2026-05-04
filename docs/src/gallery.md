---
aside: false
outline: false
---

<style>
/* Break the gallery embed out of VitePress's narrow content column. */
.VPDoc:has(.htmxo-embed) > .container > .content { max-width: none !important; }
.VPDoc:has(.htmxo-embed) .content-container { max-width: none !important; }

/* Override AoV's inline 4-column section grid with a docs-friendly
 * auto-fit layout: as many cards per row as fit at ≥420px each, so
 * plots have room to breathe. Drops to 1 col on phones. */
.htmxo-embed [style*="grid-template-columns"][style*="repeat"] {
    grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)) !important;
    gap: 0.75rem !important;
}

/* Inside each card, let the plot fill the available width.
 * AoV plots set `width:500` in the spec, so the actual size is still
 * 500px max; but the column width can grow beyond that and the plot
 * sits centred. Removing AoV's `overflow:hidden` keeps tooltips and
 * hover overlays visible at the card's edge. */
.htmxo-embed article {
    overflow: visible !important;
    min-width: 0;
}
.htmxo-embed article > div { overflow-x: auto; }
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
