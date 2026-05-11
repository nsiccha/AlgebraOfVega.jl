# FAQ / Gotchas

Common surprises and how to handle them.

## Aliases for clashing names

A few exports have aliases so you can avoid clashes with locals (especially when working inside HTMXObjects structs that often have a `data` field):

| Canonical  | Alias    | When to reach for the alias                                              |
|------------|----------|--------------------------------------------------------------------------|
| `data`     | `vdata`  | Your struct/closure has a field named `data`                             |
| `to_node`  | `vdraw`  | You want a `draw`-shaped name without clashing with AoG's `draw` (which works on Makie figures, not VegaSpec) |
| `vlspec`   | —        | Use to construct a raw Vega-Lite spec wrapper directly (no AoG needed)   |

Both aliases call straight through to the canonical implementation — no behavioural difference.

::: warning AoG's `draw` does not work on `VegaSpec`
AlgebraOfGraphics's `draw` is for Makie figures and will error on a `VegaSpec`. Use `to_node(spec)` (or its alias `vdraw(spec)`) instead, or rely on the `Base.show` MIME hooks.
:::

## Legend binding limitation

Vega-Lite supports binding legend selections to a parameter (so clicking a legend entry filters the visible marks). AlgebraOfVega wires this up automatically when **color is encoded at the top level**. If color is only present on sublayers (the layered-spec case), the binding may not behave as expected — fall back to a custom Vega-Lite param.

## Faceting + `select=` interactions

`config(select=:origin)` adds a client-side dropdown that filters the data frame *before* it reaches any layer. When you also use faceting (`row=` / `col=` channels), the filter applies to *all* facets — there's no per-facet dropdown. If you want per-facet interaction, use `mapping_controls` + `auto_remap_node` instead.

## Deep-merged encoding

When you pass `config(encoding = (; x = (; scale = (; type = "log"))))`, AoV **deep-merges** that into the encoding dict it generated from `mapping(...)`. So you can override (or add to) any auto-generated channel without re-specifying it from scratch:

```julia
data(df) * mapping(:x, :y) * visual(Scatter) *
config(encoding = (;
    x = (; scale = (; type = "log")),
    tooltip = [(; field=:x), (; field=:y), (; field=:group)],   # extra tooltip fields
))
```

If the override doesn't take effect, the most likely cause is a typo in a channel name or a Symbol-vs-String mismatch — the merge is exact.

## When to use `pregrouped()`

AoG's `pregrouped(xs, ys, ...)` is the right hook when your data is already in nested-vector shape (one element per group). AoV passes through to AoG's own grouping behaviour. Use it when you have e.g. a `Vector{Vector{Float64}}` of curves and don't want to flatten + tag with a group column first.

## `lineribbon` vs `ribbon` vs precomputed bands

| You have | Use |
|----------|-----|
| Long-format draws (one row per draw × x) | `lineribbon` — computes intervals from draws |
| Long-format draws + you want only the band (no centre line) | `ribbon` |
| Precomputed `lo`/`hi` columns | `lineribbon(...; bands=[:lo50 => :hi50, :lo95 => :hi95])` (or `ribbon(...; bands=…)`) — `bands` is a vector of `lo => hi` Pairs of column names; skips the draw-based estimator |

See the [API Reference](api.md#tidybayes-style-uncertainty-analyses) for the full docstring set and the [Gallery](gallery.md) for worked examples.

## CDN versions

`vega_head()` injects CDN tags pinned to the versions in `vega_cdn_urls()` (a `Vector` of three URL strings — Vega, Vega-Lite, Vega-Embed in that order). To vendor Vega locally or pin specific versions, build your own `<script>` tags from your URLs of choice and inject them in your page `<head>` directly.

## "My spec doesn't render and I get no error"

Vega-Lite is forgiving — it'll silently render a blank chart for a malformed spec. Two debugging moves:

1. **`println(to_json(spec))`** — inspect the actual Vega-Lite JSON being emitted.
2. Open browser DevTools, paste the JSON into the [Vega Editor](https://vega.github.io/editor/#/edited) — it produces actionable errors in a way the embed runtime doesn't.

## HTMX + `update_data` doesn't refresh

`update_data(id, new_rows)` works only when the rendered spec was given the same `id`. The `id` is a kwarg to `to_node`, not `config`:

```julia
to_node(spec; id="my-plot-1")            # render with stable id
update_data("my-plot-1", new_rows)       # later, push new rows from a route handler
```

If you don't set an explicit `id`, AoV assigns one automatically — but the update handler can't guess it. Always set an explicit `id` for any spec you intend to update from a server endpoint.
