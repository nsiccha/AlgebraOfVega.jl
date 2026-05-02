# FAQ / Gotchas

Common surprises and how to handle them.

## Aliases for clashing names

A few exports have aliases so you can avoid clashes with locals (especially when working inside HTMXObjects structs that often have a `data` field or a `draw` method already in scope):

| Canonical | Alias    | When to reach for the alias                                              |
|-----------|----------|--------------------------------------------------------------------------|
| `data`    | `vdata`  | Your struct/closure has a field named `data`                             |
| `draw`    | `vdraw`  | `draw` is also exported by AlgebraOfGraphics or shadowed in your scope   |
| `vlspec`  | —        | Use to construct a raw Vega-Lite spec wrapper directly (no AoG needed)   |

Both aliases call straight through to the canonical implementation — no behavioural difference.

## Legend binding limitation

Vega-Lite supports binding legend selections to a parameter (so clicking a legend entry filters the visible marks). AlgebraOfVega wires this up automatically when there's exactly **one** non-position channel (e.g. just `color`). With **two or more** non-position channels (e.g. `color=:a, linestyle=:b`), legend binding is currently **not** generated — you'll see a warning and you'll need to filter via a custom Vega-Lite param.

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
| Precomputed `(lo, mid, hi)` columns | `lineribbon(...; bands = [(0.5, :lo50, :hi50), (0.95, :lo95, :hi95)])` (or `ribbon(...; bands=…)`) — skips the draw-based estimator |

See [Uncertainty Visualisation](uncertainty.md) for full examples.

## CDN versions

`vega_head()` injects CDN tags pinned to the versions in `vega_cdn_urls()`. If you want to vendor Vega locally or pin specific versions, override `vega_cdn_urls()` (it returns a `NamedTuple` with `vega`, `vegalite`, `embed` fields) and AoV will inject your URLs instead.

## "My spec doesn't render and I get no error"

Vega-Lite is forgiving — it'll silently render a blank chart for a malformed spec. Two debugging moves:

1. **`println(to_json(spec))`** — inspect the actual Vega-Lite JSON being emitted.
2. Open browser DevTools, paste the JSON into the [Vega Editor](https://vega.github.io/editor/#/edited) — it produces actionable errors in a way the embed runtime doesn't.

## HTMX + `update_data` doesn't refresh

`update_data(id, new_rows)` works only when the rendered spec was given the same `id` (set via `config(id=...)`). If you don't set an explicit `id`, AoV assigns a hash-derived one — but the update handler can't guess it. In a dashboard, always set `config(id="my-plot-1")` for any spec you intend to update from a server endpoint.
