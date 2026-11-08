# Changelog

All notable changes to AlgebraOfVega.jl are documented here, newest first.
Changes before 0.2.1 are recorded in the git history only.

Every landing that adds or changes public API (an export, a keyword, a method,
or documented behaviour a dependant can rely on) bumps the patch digit in
`Project.toml` and adds its entry under a new heading at the top of this file.
An entry that breaks something a dependant relies on says **Breaking:** and
what to change. The minor digit is the breaking one in
[semantic versioning](https://semver.org/) before 1.0.
A package or app that calls that API states the version as its floor, for
example `[compat] AlgebraOfVega = "0.2.1"`. An environment that pins an older
AlgebraOfVega commit is then refused when it resolves, with
`Unsatisfiable requirements detected for package AlgebraOfVega`, instead of
failing at run time with a `MethodError`.

## 0.2.23

- Bars on a log-scaled value axis are drawn. A `visual(BarPlot)` whose value axis
  is log (`scales(X=(; scale=log10))` or `Y`) starts each bar at half the smallest
  positive value it draws, in each facet panel, which is Makie's own default there,
  so `vdraw` and `vsave` draw what `sdraw` draws. A zero or negative value is left
  out of the bar layer, where Makie draws it as a bar of no length. Before, Vega-Lite
  stacked the bars from zero, the 0 entered the log axis and every bar's position was
  undefined: the figure showed its axes and labels and no bars, with no error. A bar
  given its own base (`fillto`, below) or `stack` keeps it. Bars that Vega-Lite
  aggregates, `frequency()`, `expectation()` and an unfaceted `histogram()`, were
  drawn before and still start at the axis edge, so their smallest bar has no length
  when it equals the axis minimum.
- `visual(BarPlot; direction=:x)` draws horizontal bars as in AlgebraOfGraphics: the
  first positional is where each bar stands (the y axis), the second how far it
  reaches (the x axis), and a lone positional is the length. Before, `direction` was
  ignored with a warning, so `mapping(:method, :seconds) * visual(BarPlot;
  direction=:x)` drew vertical bars. The value-first spelling
  `mapping(:seconds, :method) * visual(BarPlot; direction=:x)` drew horizontal bars
  only because `direction` was ignored. AlgebraOfGraphics draws it as bars standing
  at the `seconds` values with the categories' positions 1, 2, 3 as their lengths, so
  it is now an `ArgumentError` that names the spelling that draws the bars. Bar
  figures without `direction` are unchanged.
- `visual(BarPlot; fillto=b)` starts every bar at `b` (Vega-Lite `x2`/`y2` datum),
  and `mapping(...; fillto=:col)` each bar at its row's value, as in Makie. Before,
  a fixed `fillto` was ignored with a warning and a mapped one emitted a channel
  Vega-Lite does not read.

## 0.2.22

- `visual(...; inspectable=false)`, Makie's switch that hides a plot from its
  `DataInspector`, now lets the pointer through every mark the layer draws on the
  interactive plot. Hover, tooltips, `aov:click`, `aov:hover`, touch taps and long
  presses, and link groups reach the mark beneath, as Makie's `DataInspector` shows
  the plot beneath. The layer is drawn as before. Use it for labels and other marks
  drawn over the data, such as region names over a map's cells. Before, there was no
  way to make one layer let the pointer through: a name over a map showed its own
  tooltip, or none with `tooltip = []`, and never the cell's value beneath it. Vega-Lite
  has no mark property for this, so `to_vegalite` gives each such mark the style
  `aov-passive`, and AoV's runtime, its cell charts and a bare `to_html(spec)` page
  make those marks non-interactive. `sdraw` hands `inspectable` to Makie as before.
  `vsave` files are unchanged. Before 0.2.22, `inspectable` was left out of the
  interactive plot with a warning.

## 0.2.21

- Every label of a continuous colour's gradient legend lies within the gradient,
  so the canvas no longer cuts it. Before, on a horizontal gradient (`"orient" =>
  "bottom"` or `"top"`) with no y axis beside it, a lowest tick just inside the colour
  domain lost its first characters at the left edge and the legend stated a false
  number, with no error: `−3,35` read `3,35`, `−102,5 Tsd.` read `2,5 Tsd.`. A highest
  tick did the same at the right edge of a figure fitted to its column with an
  authored `gradientLength` close to that width.
- A label that hangs past an end of the gradient now moves just far enough to lie
  within it. This also applies where nothing was cut, such as beside a y axis. A
  label's width is estimated at 0.54 em per character, which errs wide for `.`, `,`
  and spaces, so a label that fits by less than that error also moves a few pixels
  in. A moved label can bring Vega's `labelOverlap` to drop its neighbour. Every
  other label draws as before, and so does a vertical gradient.
- `to_vegalite` adds `legend.encoding.labels.dx` to each continuous colour, fill or
  stroke encoding. An authored `dx` and `legend: null` are kept.

## 0.2.20

- A data table in a captioned plot's preview, or one `AoV.showPlotData` writes,
  scrolls in a frame of its own when it is wider or longer than its place, at most
  70% of the window high, so its horizontal scrollbar stays in reach. Before, a
  wide table widened the whole page and lay over whatever sat beside the figure. A
  heading above a table stays in view, a `summary_table=` table the caller wrote
  gets the same frame, and a grid or flex column around the figure keeps its width.
- While it scrolls, the frame is a tab stop named "Scrollable table: <title>", as a
  plot's frame is. The word is the new `plot_texts` text `scrollable_table` (German
  "Scrollbare Tabelle").

## 0.2.19

- A captioned plot's ⬇ CSV and "Show data" give every dataset that draws values,
  on a figure without facets too. Before, such a figure gave only its first
  layer's rows, so observations under a model line lost the line, and a map whose
  first layer was its region names exported only those names. The rule also holds
  for a merged faceted dataset's sources:
  - A dataset counts when a mark that is not text reads a column on a channel that
    shows values, such as position, colour or size. A name label, an uncoloured
    region or outline and geometry looked up by key do not count. A figure with
    nothing that counts gives what it draws.
  - One dataset keeps the file name `<plot>.csv`. Several give one file each, named
    by source, `<plot>__s1.csv`, `<plot>__s2.csv`, … in layer order, or through
    `layer_labels`, as on a faceted figure. Browsers may ask before they save
    several files from one click.
  - So a figure without facets that has two value layers now gives two files,
    under new names, where it gave one under the plot's name, and a faceted
    figure's text layer no longer gets a file when other layers draw values.

## 0.2.18

- New `plot_summary_table(vl; ci, sigfigs, texts, labels)`: a figure's automatic
  summary as Tables.jl tables, the rows and labels its captioned plot's "Show
  summary" pane shows, for code that renders its own table. It works from the
  Vega-Lite `to_vegalite` returns, also after JSON and back, and is `nothing` for
  a figure without an interval or ribbon summary. For this, `to_vegalite` records
  what a summary needs under a new top-level key, `_aovSummary`, on those figures.
- The "Show summary" pane sorts its rows along their key columns. Before, they
  came in the hash order of Julia's summary computation, which differs between
  Julia versions.
- The "Show summary" pane finds the summary of a figure whose interval or ribbon
  layer is not the first, such as observations layered under a ribbon. Before, it
  listed the first layer's rows raw.
- The "Show data" and "Show summary" panes and the CSV download leave out the
  internal rows that keep a sparse row × column grid's empty cells in place. Before,
  they read as data, with a real row's values on a combination that has no data.

## 0.2.17

- `AoV.dispose` and `AoV.disposeWithin` free the Vega view of a plot whose
  element stays in the page. Before, such a plot kept its whole view (data,
  dataflow and scenegraph) reachable through its drawing: Vega's listeners on
  the canvas, the svg nodes' scenegraph items and the actions menu's export
  links all hold the finalized view. Now the drawing is swapped for a static
  copy that shows the same last frame (a new `<canvas>` with the same pixels, or
  a clone of the `<svg>`), and the actions menu is removed. Code that kept a
  reference to the old `<canvas>` or `<svg>` across `dispose` now holds a
  detached node; look the drawing up again after `dispose`. A plot whose
  element has left the page is unaffected.

## 0.2.16

- A plot element keeps no Vega view but its current one. Before, every plot
  element kept the view of its first embed reachable for as long as it stayed
  in the page: a live plot held two views (data, dataflow and scenegraph) after
  any re-embed (a container resize, a picker change, a theme switch,
  `update_spec`), and a plot released with `AoV.dispose` / `AoV.disposeWithin`
  whose element stayed in the page kept one. A long report that releases its
  offscreen plots and keeps their snapshots ran Chromium out of memory at
  4 GB of JS heap. Touch input is unchanged.

## 0.2.15

- `locale_config(:de)` supplies the standard d3 German (`de-DE`) number and
  time locale. It composes with plots and other `config` terms using `*`.
  `locale_config(:en)` (also the default) explicitly selects US English.
  Both use bundled upstream definitions, including the German nonbreaking
  space before `€` and `Mrz` for abbreviated March. Axis/legend settings,
  date format patterns and caption texts remain separately configurable.

## 0.2.14

- `data(by_url(rows, url))` draws `rows` read by the browser from `url`. The
  plot's Vega-Lite carries `"data": {"url": url, "format": {"type": "json"}}`
  instead of the rows, so pages that draw the same rows share one file.
  `rows_json(rows)` is the JSON the address serves. Julia keeps the rows for
  the encodings' types, AoV's checks, `sdraw` and `vsave`, which writes them
  into the file. Layers sharing one `by_url` table share it, faceted too.
- A layer whose drawn rows AoV computes in Julia refuses a `by_url` table with
  an `ArgumentError`: the interval and ribbon analyses (`bands=` included), a
  faceted or ridgeline `density()`, `cell_charts`, the channel picker, and a
  faceted figure whose layers draw different tables.
- A captioned plot's "⬇ HTML" card carries the text of every data URL its plot
  loads (a `by_url` table, a `geoshape(url)` geometry), and the saved file reads
  them from there. Before, the saved file loaded them from their addresses
  again, so it drew them only where those addresses still answered.

## 0.2.13

- A resolve of AlgebraOfVega's own project now gets an HTMXObjects that its
  extension can load. `[sources.HTMXObjects]` names `rev = "devibe"`. Without a
  rev it followed GitHub's default branch, whose 0.1.0 has no `CaptionSpec`, so
  the extension failed to load and `with_plot_caption` raised a `MethodError`.
- `[compat]` states HTMXObjects' floor, `0.1.1`. An environment with an older
  HTMXObjects is now refused when it resolves, with `Unsatisfiable requirements
  detected for package HTMXObjects`, instead of failing at run time on a commit
  that lacks `CaptionSpec`. HTMXObjects stayed stamped 0.1.0 until 2026-10-27, so
  the floor also refuses older commits the extension can load: an app that pins
  one moves that pin in the same run that takes this version.

## 0.2.12

- `config(transform=…)` on one summand of a `+` sum stays on that summand's
  layers, and each summand may carry its own: `a * config(transform=T) + b`
  runs `T` on `a`'s rows only, as `config(encoding=…)` does. Before, the later
  summand's transform replaced the earlier one's, without a word.
- A transform on the whole figure, `(a + b) * config(transform=T)`, reaches
  every layer, also one with its own table, and runs before a layer's own.
  Before, it reached only layers that share the figure's table, so on a map it
  reached none.
- A transform keeps what AoV generated: on a lone `geoshape` or `density()` it
  runs before the lookup or density. Before, it replaced them, and the map
  painted nothing.
- `config(transform=…)` takes one transform as well as a list, and `nothing`
  emits none. Any other value is an `ArgumentError`.
- A figure that wanted a summand's transform on its other layers too writes
  `(a + b) * config(transform=T)`. A figure's filter on a column that a layer's
  table lacks now removes that layer's rows, so write it on the layers that have
  the column, `a * config(transform=T) + b`.

## 0.2.11

- A plot that scrolls inside its frame is a named tab stop for the keyboard:
  while it is wider than the frame, the frame takes the focus under the name
  "Scrollable plot", followed by the caption's or spec's title, and the arrow
  keys scroll it. A plot that fits adds no tab stop. `plot_texts` has the new
  text `scrollable` (German "Scrollbare Grafik"); as with the frame player, a
  plot without `texts=` uses the English word.

## 0.2.10

- `with_plot_caption` and the captioned `to_html` show a figure's downloads in
  one "⬇ Export ▾" menu instead of a button per format, so they leave the
  caption's title its room. The menu holds the same CSV, PNG, SVG and HTML
  downloads and works with the keyboard, a mouse and touch, in light and dark,
  and in a saved "⬇ HTML" page. A scroll box or sticky pane around the figure
  does not clip it. Markdown and PDF output do not change.
- `download_menu=false` shows a button per format, as before. A figure with a
  single download keeps a plain button. Share, `extra_actions`, the ribbon
  switch and `with_caption_download` links stay in the caption row.
- `plot_texts` gains `download`, the menu button's word (`"⬇ Export"`). Pass
  `plot_texts(:de; download="⬇ Herunterladen")` for your own.
- The format buttons keep their words and stay inside `.caption-actions`, but
  are no longer its direct children and no longer carry `caption-action`. A
  stylesheet or test that reads `.caption-actions > button` or `.caption-action`
  to find them selects `.caption-actions button` instead, or passes
  `download_menu=false`.

## 0.2.9

- `scales(Color=…)` also reaches a mapped `strokecolor=`, as AlgebraOfGraphics'
  one `Color` scale does: `colormap`, `colorrange`, `categories`, `palette`,
  `scale`, `lowclip`, `highclip` and `nan_color`. So
  `mapping(:k; color=:v, strokecolor=:v) * geoshape(geo) * visual(; strokeWidth=0.7)`
  strokes each cell in its own fill colour, which removes the hairlines between
  adjacent polygons. A continuous stroke on the fill's column adds no legend: the
  two draw the fill's colour bar, with or without a `Color` scale. Before, the
  scale reached the fill only: the stroke kept Vega-Lite's default colours and a
  second legend, and a figure with only a stroke lost the scale without a word.
- The `Color` scale's kinds count a mapped stroke, as they count a colour: a
  figure with only a categorical `strokecolor=` refuses `colormap`/`colorrange`
  with an `ArgumentError`, as AlgebraOfGraphics does (use `palette`), and a
  numeric stroke beside a categorical colour takes them.

## 0.2.8

- A plot whose rows change in the browser (`append_data`, `update_data`,
  `replace_data`, `remove_data`, and `update_spec` when only the rows differ)
  is laid out again for its new rows, as a render of the same rows is: the
  room around the plot grows to fit the axis labels, so the axis titles and
  labels stay inside the figure. Before, the figure kept the layout of the
  rows it was drawn with: a plot drawn from a typed-empty table, the §11b
  streaming pattern, lost both axis titles once its first rows arrived and
  cut off the left of its y labels, and rows with wider labels than the first
  ones were cut off the same way. A plot sized to its container that the new
  labels widen past its column is narrowed to fit, as at its first render.

## 0.2.7

- `visual(...; stroke = :ink)` (or Makie's `strokecolor = :ink`) and
  `visual(...; fill = :ink)` paint that side of the mark in the theme-following
  ink, as `color = :ink` paints the mark: the page's text colour in the
  browser, and `#333` in `vsave` files and bare `to_vegalite` exports. The
  other side keeps its own colour, so `visual(; fill = nothing, stroke = :ink)`
  draws a map outline in the ink with no fill. `sdraw` takes
  `strokecolor = :ink` as the Makie theme's text colour. Before, only
  `color = :ink` was understood: `stroke = :ink` and `fill = :ink` reached
  Vega-Lite as the colour name `"ink"`, which is no CSS colour, so that side
  was not painted in any colour the figure asked for, with no warning.

## 0.2.6

- `config(facet = (; linkxaxes = :none, linkyaxes = :none))` unlinks the axes
  of facet panels and does nothing on a figure without a facet, as in
  AlgebraOfGraphics, so one config can serve faceted and unfaceted figures.
  Before, an unfaceted figure with several layers (a `lineribbon` and its
  bands, `Scatter` + `Lines`) got `resolve.scale.y = "independent"` beside
  its layers, and Vega-Lite gave every layer its own y scale and axis: a band
  filled the plot, the y axis stopped short of the data, and extra y axes
  stacked at the right edge. The deprecated `config(independent_scales = …)`
  follows the same rule. A remap that adds or removes a facet in the browser
  (the channel picker, `AoV.remapEncoding`) now adds or removes the unlinked
  axes with it; removing a facet used to leave the same per-layer axes.

## 0.2.5

- A configured spec takes further algebra terms. A `visual(...)`, `data(...)`
  or `mapping(...)` term multiplied onto a spec that already carries
  `config(...)` reaches its layers as AlgebraOfGraphics distributes `*` over
  `+`, and each summand keeps its own `config(encoding = …)` override:
  `(a * config(encoding = E) + b) * visual(; clip = true)` draws exactly like
  `a * visual(; clip = true) * config(encoding = E) + b * visual(; clip = true)`.
  The term may stand on either side, and may itself carry a config
  (`layer * (visual(...) * config(...))`); configs still merge left to right,
  the later one winning a conflicting key. So library code can add a mark
  property to an app's layers that show their own tooltip, and a config
  written before the algebra terms applies like one written last. Before,
  such a product threw
  `MethodError: no method matching *(::AlgebraOfVega.VegaSpec, ::AlgebraOfGraphics.Layer)`.

## 0.2.4

- Plots answer touch input. On the default canvas renderer a finger tap
  used to report no mark at all: no `aov:click` (so no map drill-down on a
  phone), no `aov:hover`, and a tooltip only while a finger dragged over the
  mark, under the finger. Now a **tap** on a data mark opens its tooltip
  above the finger and hovers its row (`aov:hover`, `config(link=…)`
  groups); both stay after the finger lifts, follow the tapped spot when the
  page scrolls, and end (`aov:hoverend`) on a tap on empty plot space, a
  press outside the plot, a finger drag on the plot, or when the spot leaves
  the window. A **long press** (about half a second, the finger held still)
  is the mark's click: one `aov:click`, whose `detail.event` is the
  `touchstart`, with the context menu over the mark suppressed. A tap never
  sends `aov:click`, so the tooltip can be read before an app acts on the
  mark. Scrolling and pinch zoom that start on a plot keep working. Mouse
  input is unchanged.

## 0.2.3

- A spec's HTML fragment (`to_html(spec)`, which is also the spec's
  `text/html` `show` and so what HTMXObjects' `SemanticPlot` writes) draws
  when it is inserted into a page that has already loaded, such as an htmx
  swap into a page without `vega_head()`. The browser runs a swapped inline
  script before the Vega `<script src>` tags above it have downloaded, so the
  first such figure used to stay empty with only a
  `ReferenceError: vegaEmbed is not defined` in the console. The embed now
  waits for its own Vega scripts. If one of them fails to load, the plot's
  container and the console say which, and name `vega_head()`.

## 0.2.2

- A `geoshape` layer that leaves `projection=` out draws through the map's
  projection: the one another geoshape layer of the same map sets, else
  `:mercator` as before. The default is now `automatic` instead of
  `:mercator`. A choropleth fitted with
  `projection=(; type="mercator", fit=region)` plus an outline geoshape with no
  `projection=` now draws, where it was refused with
  `got mercator, mercator.`; setting the projection once is enough, and
  repeating it on every geoshape still works and emits the same spec.
- Two geoshape layers that set different projections are still refused, and
  the `ArgumentError` now names the properties they differ in, lists each
  layer's projection (a GeoJSON `fit` by its GeoJSON type) and says how to
  fix it.
- A table column can show a small chart in each row, on a scale the whole
  column shares: `cell_charts(spec)`. `spec` is a figure faceted by the table's
  row key, for example
  `data(rows) * mapping(:klasse, :n; layout=:vb_nr) * visual(BarPlot)`. With
  HTMXObjects loaded, `cells = cell_charts(spec; texts=table_texts(:de))` gives
  `cells[key]`, the `<td>` of that row: its total, then a 120×24 px chart with
  no axes or legend and a tooltip on each mark (`config(width=…, height=…)`
  sets the size). The cell sorts and exports to CSV by its total, and the
  Markdown view (and so a `pdf_report`) shows it as text, such as
  `4 (200–499: 3; 1000–2499: 1)`. The browser parses the column's chart once
  and gives each cell a light view of its own rows, drawing the cells near the
  viewport first.
  `config(facet=(; linkyaxes=:none))` lets each cell fit its own y axis, and
  `total=`, `label=` and `text=` replace the total, its shown text and the
  Markdown text.

## 0.2.1

- Two configs compose into one. For two `config(...)` terms `a` and `b`,
  `a * b` is the config that `spec * a * b` applies (object-valued properties
  deep-merged, the right one winning a conflicting key), so
  `spec * (a * b) == spec * a * b`. An app extends a shared config with its
  own settings once, `const GERMAN = SHARED * config(config = …)`, and uses
  `spec * GERMAN` wherever it used `spec * SHARED`. Before, `Config * Config`
  threw a `MethodError`.
