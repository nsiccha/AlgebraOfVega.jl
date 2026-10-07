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

## Select series from the color legend

Click a categorical color legend entry to highlight its series. Other groups dim
to 15% of their usual opacity; the data and axis ranges stay in place. Shift-click
adds another group, and clicking blank plot space clears the selection.

This works with layer-local color encodings, facets, uncertainty bands and
intervals, and per-column scale layouts, in live plots and standalone HTML.
Layers and facets sharing a color field share one selection. The channel picker
rebuilds that selection when color changes.

`interactive=false` disables automatic interaction. Explicit Vega-Lite `params`
remain authoritative, as do conditional or data-driven opacity encodings.
Continuous color scales, hidden legends, and Vega-Lite composite marks do not
receive automatic legend selections.

## Light and dark pages

Plots follow the page's light/dark choice. The runtime draws axes, legends,
facet headers, titles and unencoded text in the CSS `color` the plot element
inherits, on a transparent background, so a plot inside a dark Pico page (or a
dark card) reads as part of it. Mark colours — palettes, `scales(Color=...)`,
`visual(...; color=...)` — are unchanged. When the page switches theme
(`prefers-color-scheme`, or a `class` / `data-theme` / `style` change on
`<html>` or `<body>`) the plots re-render in place, keeping the channel-picker
assignment, `update_spec` data and streamed rows. After switching a theme some
other way (a class on a wrapper element), call `AoV.refreshTheme()`.

- Do not style the chrome with `currentColor` in `config(config=...)`: Vega's
  canvas renderer paints `currentColor` black. A spec's own `config` values
  still win over the theme, key by key.
- Do not invert the canvas with a CSS `filter` — it recolours the palette too.
- PNG/SVG downloads of a plot are painted on the page background behind it.
- `vega_head(theme=:none)` (page) or `config(theme=:none)` (one plot) keeps
  Vega's own look: white background, black text.

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

## CDN versions and offline rendering

`vega_head()` injects tags for the exact-pinned trio in `vega_cdn_urls()` (a `Vector` of three URL strings — Vega, Vega-Lite, Vega-Embed in that order), with subresource-integrity hashes (`vega_sri_hashes()`), so a CDN-side release can never change rendering with zero repo diff. Override `vega_version=` / `vegalite_version=` / `vega_embed_version=` only with `source=:cdn` (a custom version opts out of SRI, since the hash would not match).

For offline use, AoV vendors the same builds under `vendor/`: `vega_head(; source=:vendor, base="/vendor")` emits same-origin tags (serve `vega_vendor_dir()` at `base` from your app), and `source=:inline` inlines the bytes. `to_html(...; source=:inline)` writes a standalone file that renders with no network at all.

AoV's own runtime (`aov-runtime.js`) and stylesheet (`aov.css`), about 96 KB, are inlined into every page by default. With the vendor mount, `vega_head(; source=:vendor, base="/vendor", runtime=:linked)` loads them from that directory too, so each full page carries a few hundred bytes of tags that the browser caches. Every vendor URL ends in `?v=<content hash>`, which changes exactly when the file does, so the mount may use a far-future cache lifetime — with HTMXObjects: `staticfiles(vega_vendor_dir(), "vendor"; headers=["Cache-Control" => "public, max-age=31536000, immutable"])`. Page settings (`zoom`, `max_width`, `actions`, `theme`) stay a small inline script. A captioned plot's "⬇ HTML" download inlines the vendored files the page loaded, so the saved card still renders with no server and no CDN.

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
