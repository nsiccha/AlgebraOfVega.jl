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
sdraw
sdraw_file
sdraw!
vlspec
```

| Function       | Output                                                                              |
|----------------|-------------------------------------------------------------------------------------|
| `to_node(spec)`| An [`HTMX.Node`](https://github.com/nsiccha/HTMX.jl) — embed in HTMX/Oxygen apps    |
| `vdraw(spec)`  | Alias for `to_node` — use when you want a "draw"-shaped name without clashing with AoG's `draw` |
| `to_html(spec)`| A standalone HTML string with the Vega tags embedded (`source=:inline` for fully offline) |
| `to_json(spec)`| Pretty-printed Vega-Lite JSON                                                       |
| `to_vegalite(spec; interactive=true)` | Raw Vega-Lite spec as a `Dict{String,Any}`; pass `interactive=false` to omit AoV-generated parameters |
| `sdraw(spec, path; kwargs...)` | Save through AoG/Makie and return an `HTMX.Node` image pointing to `path` |
| `sdraw_file(spec, path; kwargs...)` | Save through AoG/Makie and return `path`; keywords pass to `Makie.save` |
| `sdraw!(position, spec)` | Draw into an existing Makie figure/layout position for static composition |

The static functions require a loaded Makie backend such as CairoMakie. Compose
panels with independently configured axes by drawing each spec into its own
layout position and saving the parent figure:

```julia
using CairoMakie

fig = Figure(size=(900, 400))
sdraw!(fig[1, 1], mean_spec)
sdraw!(fig[1, 2], sd_spec)  # may carry its own log-y scale
save("adaptive-centering.png", fig; px_per_unit=2)
```

`interactive=false` disables only automatic zoom, legend, and nearest-point
parameters. Explicit `config(params=...)` or `config(select=...)` remains
explicitly requested output.

A `VegaSpec` also has `Base.show(io, MIME"text/html"(), spec)` and `Base.show(io, MIME"application/vnd.vegalite.v5+json"(), spec)` methods, so you can render it implicitly via any host that picks a MIME type (Pluto, IJulia, HTMX response handlers, …) without calling any of the functions above.

## Vega / HTMX runtime

```@docs
vega_head
vega_runtime
update_data
append_data
replace_data
update_spec
```

| Helper            | Purpose                                                                              |
|-------------------|--------------------------------------------------------------------------------------|
| `vega_head()`     | The head tags for Vega/Vega-Lite/Vega-Embed plus AoV's runtime and stylesheet — drop in your `<head>` (`source=:cdn`/`:vendor`/`:inline`; `runtime=:linked` with `:vendor` loads AoV's runtime by cacheable URL too; `theme=:host`/`:none`, see the FAQ's light/dark section) |
| `vega_runtime()`  | The AoV JS runtime, inline — handles signal binding, `update_data`, etc. (source: `aov-runtime.js` in `vega_vendor_dir()`) |
| `vega_controls()` | Optional HTML controls block (legend toggles, view reset, …)                          |
| `vega_cdn_urls()` | The exact-pinned CDN URLs (Vega, Vega-Lite, Vega-Embed in order)                      |
| `vega_sri_hashes()` | The subresource-integrity hashes for the pinned CDN URLs, in the same order        |
| `vega_vendor_dir()` | Directory holding the vendored trio and AoV's runtime/stylesheet — serve it from your app for `source=:vendor` |
| `update_data(id, new_rows)` | Replace a rendered plot's raw rows by id (HTMX server-side handler returns `update_data(...)`) |
| `append_data(id, rows; max_rows)` | Add rows to a rendered spec by id, keeping the existing ones (optionally a sliding window of `max_rows`) |
| `replace_data(id, rows; key)` | Replace the rows of the groups `rows` carries (same `key` column values), keeping every other group's rows |
| `update_spec(id, spec; auto_remap)` | Refresh a rendered plot from a new spec — new data and/or layers — re-lowered like a first render; keeps the picker assignment, and zoom when only data changed |

### Incremental plots

Plots whose data or layers arrive over time are rendered once with a stable `id`
and then updated by fragments pushed from the server. With an HTMXObjects `@ws`
route and htmx's [WebSocket extension](https://htmx.org/extensions/ws/), each
message is an HTML fragment that htmx swaps in by `id`:

```julia
# In the page (with the htmx-ext-ws script loaded):
to_node(spec; id="live-plot"),
h.div(; hx_ext="ws", ws_connect="/feed")(h.div(; id="live-sink")),

# In the @htmx struct:
@ws feed() = for chunk in chunks
    fragment = h.div(; id="live-sink")(append_data("live-plot", chunk))
    HTTP.WebSockets.send(__ws__, repr(MIME"text/html"(), fragment))
end
```

Send `update_spec("live-plot", new_spec)` instead to add layers. Rows added with
`append_data`/`update_data`/`replace_data` survive the plot's responsive
re-embeds; a new spec from `update_spec` brings its own data. The gallery's
*Streaming Data* and *Layers One by One* demos show both.

When one group of the rows is refined in stages — one scenario's provisional
bands, re-sent as its draws accumulate — send only that group's rows with
`replace_data(id, rows; key=:scenario)`: the rows whose `key` values `rows`
carries are replaced and the other groups' rows stay in the view (`key` may be a
vector of columns). A coloured `lineribbon`/`ribbon` draws each colour group as
its own layers; a group that a data change brings first gets its layers then
(the plot re-embeds once, resetting zoom), so an empty first render can be
filled group by group. A ribbon layered with other layers
(`lineribbon(...) + visual(Scatter)`) cannot grow layers this way and logs a
console warning: send `update_spec` when a group first appears there.

The rows travel column by column, not as one JSON object per row: a regular
coordinate (a range such as `range(0, 28, length=6721)`, also repeated once per
series in a long table) is sent as three numbers, a constant column (a series
label) once, sorted labels as runs, and every other column as one flat array.
The runtime rebuilds the same rows with the same values — a coordinate is sent
as a sequence only when the browser's arithmetic reproduces every value
exactly. Any Tables.jl source works, lazy columns included (a `Fill` label,
a range, a `TreeData` reduction); nothing builds a row table on the server.
The inline datasets `to_node`/`update_spec` embed use the same form. For a
one-series time course of 6721 points this is 126 KB instead of 454 KB.

`append_data`/`update_data` insert rows verbatim, so they fit only plots whose
embedded dataset is raw rows. A plot AoV lowered server-side — an interval or
ribbon summary (`pointinterval`, `lineribbon`, …), a faceted `density`, a
merged multi-layer dataset — is refreshed from new raw rows with `update_spec`,
which recomputes the lowering. For a channel-picker plot pass the picker's
keywords as `auto_remap` (the `(; dims, fixed, pinned, off)` given to
`auto_remap_node` or `with_plot_caption`):

```julia
update_spec("ladder-plot", data(new_rows) * mapping(:value; y=:model, color=:family, col=:metric) *
    pointinterval(); auto_remap=(; dims=["family" => "Family"], fixed=Dict(:column => "metric")))
```

The reader's picker assignment is re-applied to the refreshed spec. When only
the data changed, the new datasets are swapped into the live view (zoom/pan,
legend selection and canvas survive); a structural change — new facet panels,
layers, encodings or size — re-embeds the plot in place. Raw rows that lack a
field placing or selecting the plot's marks (e.g. a summary's `lo_*`/`hi_*`
bounds or a merged dataset's `__src`) are refused with a console error and the
plot is left unchanged.

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
