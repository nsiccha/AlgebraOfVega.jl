# API Reference

The full set of exports, organised by use case. For walkthroughs see [Getting Started](getting-started.md), [Translation](translation.md), [Gallery](gallery.md), and the [FAQ](faq.md).

## Building specs

The same algebra as AlgebraOfGraphics — `data * mapping * visual` composed with `*` (intersection) and `+` (union).

```@docs
config
```

| Function   | Use                                                                          |
|------------|------------------------------------------------------------------------------|
| `data(df)` / `vdata(df)` | Wrap a tabular source. `vdata` is an alias for use when `data` clashes with a local field. |
| `mapping(:x, :y; color=:g)` | Map columns to channels (`x`, `y`, `color`, `linestyle`, `row`, `col`, …). |
| `visual(Mark; kwargs...)` | Pick the mark type (`Scatter`, `Lines`, `BarPlot`, …) and per-mark properties. |
| `dims(i)`               | Use the `i`-th group/dim as a channel value (AoG passthrough).               |
| `pregrouped(...)`       | Pass a pre-grouped data source (AoG passthrough).                            |

## Marks (re-exported from Makie/AoG)

`Scatter`, `Lines`, `ScatterLines`, `BarPlot`, `Heatmap`, `BoxPlot`, `Band`, `HLines`, `VLines`, `Hist`, `Errorbars`, `Stairs`, `Contour`, `Violin`, `RainClouds`, `Rangebars`, `CrossBar`, `ECDFPlot`.

## Statistical transforms (re-exported from AoG)

`density`, `histogram`, `linear`, `smooth`, `expectation`, `frequency`.

## Scale modifiers (re-exported from AoG)

`renamer`, `sorter`, `nonnumeric`, `verbatim`, `presorted`, `direct`, `scale`, `scales`. See AoG's [scale-modifier docs](https://aog.makie.org/stable/generated/scales/) for behaviour.

## Rendering and output

```@docs
to_node
to_html
to_json
to_vegalite
vlspec
```

| Function       | Output                                                                              |
|----------------|-------------------------------------------------------------------------------------|
| `to_node(spec)`| An [`HTMX.Node`](https://github.com/nsiccha/HTMX.jl) — embed in HTMX/Oxygen apps    |
| `vdraw(spec)`  | Alias for `to_node` — use when you want a "draw"-shaped name without clashing with AoG's `draw` |
| `to_html(spec)`| A standalone HTML string with the Vega CDN tags embedded                             |
| `to_json(spec)`| Pretty-printed Vega-Lite JSON                                                       |
| `to_vegalite(spec)` | Raw Vega-Lite spec as a `Dict{String,Any}`                                     |
| `sdraw(spec)` / `sdraw_file(spec, path)` | Static SVG renderers (uses `vega-lite` CLI under the hood) |

A `VegaSpec` also has `Base.show(io, MIME"text/html"(), spec)` and `Base.show(io, MIME"application/vnd.vegalite.v5+json"(), spec)` methods, so you can render it implicitly via any host that picks a MIME type (Pluto, IJulia, HTMX response handlers, …) without calling any of the functions above.

## Vega / HTMX runtime

```@docs
vega_head
vega_runtime
update_data
```

| Helper            | Purpose                                                                              |
|-------------------|--------------------------------------------------------------------------------------|
| `vega_head()`     | The `<script>` tags for Vega/Vega-Lite/Vega-Embed CDN — drop in your `<head>`        |
| `vega_runtime()`  | The AoV JS runtime — handles signal binding, `update_data`, etc.                     |
| `vega_controls()` | Optional HTML controls block (legend toggles, view reset, …)                          |
| `vega_cdn_urls()` | The current set of CDN URLs (override to pin versions or vendor locally)             |
| `update_data(id, new_rows)` | Push fresh data into a rendered spec by id (HTMX server-side handler returns `update_data(...)`) |

## Dynamic dashboard helpers

For interactive dashboards where the user picks columns, channels, or facets at runtime. `auto_remap_node` is the high-level entry point; the others are the building blocks.

```@docs
auto_remap_node
mapping_controls
resolve_channels
refine_channels
```

### Captioned plots (requires `using HTMXObjects`)

```@docs
with_plot_caption
draws_summary_table
```

## Tidybayes-style uncertainty analyses

```@docs
pointinterval
gradient_interval
lineribbon
ribbon
dotinterval
```

## High-level recipes

```@docs
ecdf_grid
ppc_overlay
```

## Sample datasets

Useful when writing examples or exploring the API:

`sample_cars`, `sample_tips`, `sample_stocks`, `sample_temperatures`, `sample_population` (+ `melt_population`), `sample_monthly_sales` (+ `melt_sales`), `sample_posterior_draws`, `sample_regression_predictions`, `sample_grouped_regression_predictions`, `sample_faceted_regression_predictions`, `sample_faceted_observations`, `classify_columns`, `table_to_rows`, `preaggregate`.

```@docs
preaggregate
```

## Explorer widget

A self-contained "click-to-build" UI for AoV specs, useful as a documentation entry point:

`default_explorer_datasets`, `explorer_widget`, `write_explorer_assets`, `explorer_controls_html`, `explorer_js`, `explorer_data_init_js`.
