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

## 0.2.46

- **A `cell_charts` column shows its shared x axis in the header.** When the
  cells share a continuous x (a value or a time, as in a column of intervals
  per row), the browser draws that axis once, at the bottom of the column's
  header cell. It uses the cells' own scale (the shared domain after nice and
  zero) and starts where their plot area starts, so a value's tick sits where
  the cells draw it. It has about one label per 60 px, flush at both ends, in
  the plot's look and host theme. The figure's own axis `values` or `format`
  are kept.
  - It is drawn on a canvas, so the header's text, which the table's sorting and
    CSV export read, is unchanged; the header keeps room for it in its bottom
    padding, below the sort caret.
  - It is realigned when the totals, the fonts or the column width change, and
    redrawn on a theme switch.
  - A categorical x, or an x the figure unlinks (`config(facet=(; linkyaxes=…))`),
    has no single axis and gets none. `cell_charts(…; axis=false)` leaves it out.
  - Before, the cells compared rows on one scale but showed no values.

## 0.2.45

- A layer drawn from HTMXObjects' `bound(p; columns)`, inside an `@htmx` struct
  whose property `p` a `semantic_app` page computes in the browser
  (`@browser`), follows the browser: `to_node`, `vdraw` and `with_plot_caption`
  mark the plot, and after each input change the page replaces the plot's rows
  with the columns the browser computed, with no request. So `export_site`
  exports a page whose AoV plots show browser-computed data, and the exported
  page keeps following its inputs offline. This works for plain marks, the
  analyses Vega-Lite computes, layers that draw the bound table beside other
  rows, panels of one table (`col=`, `row=`, `layout=`) and the channel picker
  when it leaves the rows as they are. A figure whose rows AoV computes from the
  table in Julia (an interval or ribbon summary of raw draws, a faceted or
  ridgeline `density()`, a faceted figure whose layers draw different tables,
  the picker's combined columns) raises an `ArgumentError` naming
  `update_spec`. Needs HTMXObjects 0.1.125.

## 0.2.44

- **`visual(...; label="Observed")`** gives a layer without a colour mapping a
  legend entry, as in AlgebraOfGraphics. The entry is drawn in the layer's own
  style: a stroke with the line's or rule's colour, dash and width, the point's
  own symbol and colour, a square at a band's or span's colour and opacity. The
  entries form an untitled legend after the mapped scales' legends, in layer
  order. Layers that share a label share one entry, drawn like their line (else
  their point).
  - `color=:ink` entries follow the page's light or dark ink.
  - In a faceted figure the labels share one legend, drawn like the first
    label's mark, each entry with its own dash or opacity, and it comes in layer
    order. Separate legends would repeat in every panel.
  - The readout names a labelled layer's series by its label (`Observed: 118.6`)
    where it used the y title.
  - A text layer gets no entry. A label whose entry would use a channel that a
    mapping already uses (`linestyle` or `alpha` mapped to a column) gets none,
    with a warning.
  - Before, AoV ignored `label` with a warning ("no Vega-Lite mark
    counterpart"). `sdraw` already passed it to AlgebraOfGraphics, which draws
    its own legend.

## 0.2.43

- **Interval and ribbon tooltips** (`pointinterval`, `gradient_interval`,
  `dotinterval`, `lineribbon`, `ribbon`, their `bands=` forms and a ribbon's
  interval drawing) show the estimate with its widest interval as one row:
  `Level (cm): median (95% interval)` reads `139.2 (134.8–144.4)`.
  - All three numbers are rounded at the second significant digit of the
    interval's width, as HTMXObjects' `IntervalEstimate` cells and the readout
    round them, in the plot's number locale: `locale_config(:de)` gives
    `139,2 (134,8–144,4)`.
  - A bound below zero is set off by a spaced dash: `−0.2 (−0.9 – 0.4)`.
  - With `bands=` the title names the columns: `Level (cm): q50 (q025–q975)`.
  - The row's field is `__aov_estimate`, a `calculate` on each layer that shows
    the tooltip, so it follows the rows after `update_data`.
  - Before, these tooltips listed `median`, `q025` and `q975` (or `95% lo` and
    `95% hi`) in separate rows, unrounded: `125.057600736`.
- **A temporal tooltip keeps its time of day** when the rows hold one. The
  field is written with `config.timeFormat` (Vega-Lite's default is
  `%b %d, %Y`) plus ` %H:%M`, or ` %H:%M:%S` with seconds. A date-only field
  and an authored `format` are unchanged. Before, an hourly series read
  `Mar 15, 2026` at every point.

## 0.2.42

- A data change that makes a plot's axis labels a few pixels wider or
  narrower now resizes the mounted view instead of embedding the plot again.
  `replace_data`, `remove_data`, `append_data` and `update_data` keep the
  view, its canvas, its zoom and hover state, as documented. The plot's width
  is corrected through its width signal (`width`, or a facet's
  `child_width`), so the drawing still fits its column.
- Before, a correction of more than 2 px re-embedded the plot. With the larger
  axis labels of 0.2.40, removing one group of a pinned-colour Band + Lines
  plot did that (y labels `-1 … 4` became `2.0 … 4.5`). The same happened
  already before 0.2.40 to plots whose labels changed more, for example
  removing a scenario from a faceted ribbon.
- A wrap count, and a horizontal concatenation, are still corrected by a new
  embed.

## 0.2.41

- A report built from a page's markdown draws each captioned figure itself.
  In HTMXObjects' `pdf_report(value, …)`, `dispatch(…; report=true)` and
  `to_markdown_string(x; report=true)`, `with_plot_caption` shows the caption
  and `<img src="data:image/svg+xml;base64,…" alt=…>`: the SVG that
  `vsave(spec, "x.svg")` writes (with the picker's `auto_remap` for a picker
  figure), rendered by the vl-convert tool while the report is written. Its
  alt text is the caption's title and short summary, or `alt`. The channel
  picker and the `PlotSummary` table are left out of the report. Before, a
  report showed the `PlotSummary` table unless the caller rendered each figure
  with `vsave` and passed it as `static_image`.
- Ordinary markdown reads (`?plain`, `?markdown`, `to_markdown_string(x)`) and
  the browser are unchanged, and render no image.
- `static_image=false` keeps the `PlotSummary` table in a report; a path, URL
  or `data:` URI is shown as before. `alt` no longer needs `static_image`.
  `static_image=true`, and `alt` with `static_image=false` or with a node
  that holds no AlgebraOfVega plot, are an `ArgumentError`. A report of a
  figure whose caption has no title is an `ArgumentError` naming `alt`.
- Needs HTMXObjects 0.1.121 (`report_view`, `page_report`), now the
  `[compat]` floor. `Base64` is a dependency.

## 0.2.40

- AoV's own look defaults, so a figure gets a quieter page look with no
  `config(config=…)`. Every figure looks a little different; each key below
  can be set back through `config(config=…)`.
  - **Type.** Axis labels are 11 px and axis titles 12 px in normal weight;
    legend and facet labels and titles are 12 px; a plot title is 14 px.
    Vega-Lite drew 10–11 px throughout, with bold axis titles. Neighbouring
    axis labels keep 4 px apart (`labelSeparation`).
  - **`config(font_scale=…)`** scales these sizes, so `font_scale=2` gives
    22 px axis labels, where it gave 20 px before.
  - **Tick counts.** An axis asks for 7 ticks on x and 5 on y. Vega-Lite asked
    for one per 40 px, so a plot 1,400 px wide got 35 ticks and grid lines.
    Vega rounds the count to a nice step: 0–100 gets 6 ticks. This holds for
    an authored size and, in the browser, for a plot sized to its container.
    An authored tick count is kept, and a binned axis keeps Vega-Lite's ticks
    at its bin edges.
  - **Log axes.** A log axis is labelled at 1, 2 and 5 times each power of ten
    when the plotted rows span at most two decades, and at the powers of ten
    beyond that. Vega-Lite labelled every multiple (`25 30 40 50 60 70 80 90100`)
    and drew a grid line at each.
    - The rows the figure carries, including a band's upper bound and both
      drawings of a ribbon, decide between the two; the axis carries the whole
      sequence and Vega draws the values inside its domain, so zooming,
      streamed rows and a data-only `update_spec` keep the same ticks.
    - An authored axis `values` or `tickCount` is kept.
    - Rows read from an address keep Vega-Lite's ticks.
    - When the channel picker moves the axis to another field, the values are
      dropped with it.

## 0.2.39

- A figure with a line or area layer on a continuous x (a time series, a
  ribbon, a curve over a sample size), and a ribbon's point-interval drawing,
  get a readout in the browser: while the pointer is over a plot area, a rule
  marks the nearest x that has data and one box lists every series there, a
  series with an interval as its median with the widest interval,
  `142 (138–148)`, rounded at the second significant digit of the interval's
  width, and a line or a single point as its value. In a faceted figure it
  follows the panel under the pointer, and the box stands in for the mark
  tooltip while it shows. `config(readout=false)` turns it off;
  `config(readout=true)` gives one to any figure with a continuous x (bars
  over time, a scatter).
- When a figure's `config(link=(; group, key))` key is its x field, the
  readout announces the x it shows to the link group, so the table row of
  that time lights, and another member's announcement of one x (a hovered
  table row) shows the readout there instead of dimming every line and band.
- A link group keyed by a `Date` or `DateTime` column now links. Vega holds
  such a field as epoch milliseconds, so a plot announced `"1773568800000"`
  where a table keys its rows by `string(t)`, `"2026-03-15T17:00:00"`: no
  row lit from a mark, and a hovered row dimmed every mark of the plot. The
  plot now announces and compares the key as Julia writes it
  (`_aov.link.temporal`).

## 0.2.38

- A categorical colour palette takes `:ink` as an entry:
  `scales(Color=(; categories=["reference", "other"], palette=[:ink, "#e03131"]))`
  draws the `reference` category in the page's text colour, as
  `visual(; color=:ink)` draws a fixed mark, while the other entries stay
  fixed. Its marks and its legend symbol follow light/dark switches, in every
  layer, both drawings of a ribbon and the channel picker. `vsave` and a bare
  `to_vegalite` export draw it in `#333`, `sdraw` in the Makie theme's text
  colour. Before, the entry reached Vega-Lite as the colour name `"ink"`,
  which no renderer draws as the page's ink.
- `lowclip=:ink`, `highclip=:ink` and `nan_color=:ink` on a `Color` scale are
  an `ArgumentError` naming the palette and fixed-mark forms. They reached
  Vega-Lite as the colour name `"ink"` before.

## 0.2.37

- New map term `geobox(boxes; key, projection)`: each table row draws the
  longitude/latitude box its key names, as one Vega-Lite `rect` placed by
  `longitude`/`latitude`/`longitude2`/`latitude2` through the map's
  projection. It is the counterpart of `geoshape` for a grid of cells, such
  as census grid squares: `data(rows) * mapping(:cell; color=:value) *
  geobox(boxes)`. `boxes` is a table with the key column and the columns
  `west`, `south`, `east` and `north` (degrees), given inline, as
  `by_url(table, url)`, or as the URL of its JSON rows (`rows_json`), so the
  boxes are loaded once and only the value rows travel with each figure.
  Everything a geoshape layer takes works the same: `color=` and
  `strokecolor=` on one colour scale and legend, `col=`/`row=`/`layout=`
  facets, `config(frame=…)`, a fixed `visual(...)`, the shared projection
  (its `fit` included), other layers on the map, tooltips, hover links,
  `aov:click`, pan and zoom, the CSV download and `vsave`. Boxes draw the
  same picture several times faster than the same cells as GeoJSON
  polygons: on a 16,129-cell map in headless Chrome, 201 instead of 656 ms
  to draw and 96 instead of 544 ms to redraw (a resize or a zoom step). A
  box is exact through projections that keep longitude and latitude lines
  straight and at right angles, such as the default Mercator.

## 0.2.36

- A drag that starts on a data mark no longer sends `aov:click`. Dragging pans
  every AoV x/y plot, and a pan moves the mark along with the pointer, so the
  release often landed on the same mark and Vega reported a click on it. A pan
  of a scatter clicked the point it started on. On a map that a page made
  pannable, 2 of 3 pans drilled into the region they started on. Now a mouse
  press whose pointer moves more than 4 px before release is a drag, not a
  click, even if the pointer comes back to its start. A pen gets 10 px, as a
  finger does for its long press. A click where the hand jitters by a pixel or
  two still reports the mark. Touch input is unchanged: a long press is the
  click and a tap is not. A double-click still sends two `aov:click`s.

## 0.2.35

- Every map pans and zooms by default, as x/y plots do. A figure drawn
  through a projection (a `geoshape`, with any longitude/latitude layers on
  it) zooms around the pointer on the mouse wheel and pans on a left-button
  drag. On touch, two fingers pinch-zoom and pan the map, while one finger
  still scrolls the page and taps and long presses keep their meaning. Every
  layer moves under the one projection, facet panels zoom together, and
  marks are cut at the map's frame only once it is zoomed or moved. While the
  map is zoomed or moved, a "Reset zoom" button over its top-left corner
  brings back the fitted view; it is not a double-click, which on a
  click-to-drill map would also be two `aov:click`s. The zoom survives the
  runtime's re-embeds (container resize, theme, `update_spec`). `AoV.resetZoom(id)`
  resets it from app code, and `plot_texts` has a new `reset_zoom` text
  ("Zoom zurücksetzen" in `:de`). `interactive=false`, a figure with its own
  `params`, and a projection placed with `scale`/`translate`/`extent`/`size`
  keep the map still. Previously wheel and drag did nothing on a map.

## 0.2.34

- A ribbon's Intervals drawing keeps its linear or log x axis even when some
  x values are close together. Previously a spacing heuristic changed the axis
  to equally spaced categories, losing the source scale and printing long raw
  numeric labels in narrow facets. The colour-group offsets still use 70% of
  the closest gap, and observations keep their true positions. Closely spaced
  marks can overlap; the numeric axis and its zoom remain available. This also
  works when colour groups are sampled at different x values.

## 0.2.33

- Fixed colours accept Makie's `(colour, alpha)` tuples and `Colorant` values on
  `vdraw` and `vsave`, including non-RGB colour spaces. For example,
  `visual(BarPlot; color=(:red, 0.1), strokecolor=:red, strokewidth=2)` draws a
  faint red fill with an opaque red outline, as `sdraw` does. The conversion
  also reaches fixed ribbon and interval colours, `fill`/`stroke`, categorical
  colour palettes, and `lowclip`/`highclip`/`nan_color`. Alpha stays in the
  colour and combines with the mark's own opacity. CSS strings, plain colour
  symbols and theme-following `:ink` keep their existing output. Previously,
  Julia's printed colour values reached Vega as unreadable CSS and could draw
  solid black.

## 0.2.32

- AoV's automatic tooltips name each mapped column by its mapping label, the name its
  axis, legend or facet header shows: hovering a cell of
  `mapping(:east => "East (km)", :north => "North (km)", :value => "Field value") * visual(Heatmap)`
  reads "East (km) | 55 | North (km) | 5 | Field value | −0.31", not
  "east | 55 | north | 5 | value | −0.31". This holds for plain marks of every kind, marks on
  a map, `visual(ECDFPlot)`, the interval analyses (`pointinterval`, `gradient_interval`,
  `dotinterval`, also with `bands=`), both drawings of a coloured `lineribbon`/`ribbon`,
  `geoshape` maps, and the colour field the channel picker moves in. An unlabelled column,
  and one labelled `""` (a facet header hidden with `row=:time => ""`), keeps its own name.
  A column mapped on two channels (`color=:v, strokecolor=:v`) is listed once.
  Vega keys a drawn item's tooltip by these names, so page or test code that reads one
  (`item.tooltip.value`) finds a labelled column under its label
  (`item.tooltip["Field value"]`). A tooltip written with
  `config(encoding=Dict(:tooltip => …))` is unchanged. Before, every automatic tooltip
  listed raw column names, so it disagreed with the axes and legend of its own figure.

## 0.2.31

- A `lineribbon`/`ribbon` **without** a `color=` mapping over at most 12 numeric x values
  (a dose ladder) gets the "Ribbons | Intervals" switch, as a coloured one does. Its
  interval drawing has one point-interval per x, at the true x on the ribbon's own linear
  or log axis (evenly spaced slots where the x values are too unevenly spaced on it), in
  the ribbon's one colour: its `visual(; color=…)`, `:ink` included, or the default mark
  colour. It starts as ribbons under `intervals=:auto`, because one group has no bands to
  overlap; `intervals=true` starts it as intervals. When a reader moves a field onto
  Colour in the channel picker, the intervals dodge by it. Before, such a figure drew
  ribbons only (web-sim's single-scenario dose views).
- `ribbon_view(spec)` no longer returns `why_not=:no_color`: such a figure is offered,
  with `start=:ribbons` and `score=0.0`. The score is `0.0` whenever no two colour groups
  share an x in a facet panel, a colour with one value included, and the switch's
  tooltip then leaves the overlap out.

## 0.2.30

- `mapping(:x, :y, :z) * visual(Heatmap)` draws as in AlgebraOfGraphics: the third
  positional colours each cell, with a colour legend and the value in the tooltip, and on
  a numeric axis each row is a cell on the grid of the distinct x and y values, reaching
  halfway to its neighbours (the first and last half a step beyond, a lone value ±0.5),
  as Makie draws it, cut at the plot frame as Makie cuts it (which matters under axis
  `limits` inside the outer cells). Each facet panel has its own grid. The edges are computed in the
  browser, so `update_data`/`append_data`, rows read `by_url` and `config(frame=…)` keep
  working, and the rows and their CSV download stay as given. A categorical axis keeps one
  band per value, and a heatmap coloured through `config(encoding=…)` (a 2D histogram
  binned there) is unchanged. Before, the third positional was dropped without a word,
  and each cell reached from the axis origin to its value, so the figure was one block of
  Vega's default blue with no legend.

## 0.2.29

- An interactive plot (`vdraw`, `to_node`, `with_plot_caption`, a bare `to_html(spec)`)
  draws every mark whole until the reader zooms or pans, as its `vsave` file does: text
  placed outside the plot frame shows, for example labels above a schedule's lines
  (`visual(Text; offset=(0, 12))`) or a direct label past the right edge, and Vega
  reserves room for it, so an authored `padding` takes effect. Once the reader zooms or
  pans, marks are cut at the frame only along the zoomed axes: zooming x alone cuts at
  the left and right edges and keeps what lies above and below the frame. A double-click
  reset draws everything whole again. A layer that authors `visual(...; clip=true)` keeps
  its clip. Before, AoV's automatic pan/zoom made Vega-Lite cut every mark at the frame
  from the start, so such labels were missing on the page while the `vsave` file showed
  them, with no warning. `sdraw` (Makie) still cuts them: Makie clips every plot in an
  axis to the axis area.
- A plot the runtime sizes to its column (layered, faceted) widens back to the column
  when a data change leaves it needing less room than its last size correction made,
  for example once no point sits on the edge of the axis any more. Before, the
  correction only ever narrowed the plot, so a figure filled row by row could end a few
  pixels narrower than the same rows drawn at once.

## 0.2.28

- `scales(Y=(; categories))` and `scales(X=(; categories))` fix a categorical axis's
  levels and their order, as in AlgebraOfGraphics, including a level no layer draws:
  a Gantt figure keeps a blank spacer row. They become `scale.domain` and `sort` on
  the nominal and ordinal encodings of that axis. Before, the key was dropped with
  the warning "unknown `Y` scale option `categories`". `categories` on a numeric axis
  is an `ArgumentError` naming the field, as in AlgebraOfGraphics; a function-valued
  `categories` is an `ArgumentError`; a `value => label` pair puts the value on the
  axis and warns that the label is not drawn yet. Write it without a `sorter` on the
  same column: AlgebraOfGraphics' own `draw`, and so `sdraw`, refuses the two together.
- An `X` or `Y` scale (`scale`, `domain`, `nice`, `zero`, `clamp`, `constant`) reaches
  only the layers drawn with that axis. Before, a `VLines` rule, which has no `y`, was
  given a `y` holding only the scale, and Vega-Lite dropped it with a console warning
  on every render. Layers that have the axis take the same scale as before.

## 0.2.27

- Makie's axis fractions draw on `vdraw` and `vsave`, as they already did on `sdraw`:
  `visual(VLines; ymin=0.0, ymax=0.9)` is a rule from the bottom of the plot to 90 %
  of its height, `visual(HLines; xmin, xmax)` the same along the width, and
  `visual(VSpan; ymin, ymax)` / `visual(HSpan; xmin, xmax)` a band over that part of
  the plot. The fractions are of each facet panel's or concat cell's own size, also
  after the plot is resized. Each lowers to the mark's own `y`/`y2` (`x`/`x2`),
  a Vega expression on the size of the group the mark is drawn in
  (`item.mark.group.height`). Makie's whole-axis default (0 and 1) adds nothing.
  Before, any other fraction was left out with a "no Vega-Lite mark counterpart"
  warning and the line or band spanned the whole axis. A value that is not one
  finite number (a vector, `NaN`) is still left out with that warning.

## 0.2.26

- `visual(...; fillOpacity=a)` fades only the fill, as Vega-Lite's `fillOpacity`
  does, so `visual(BarPlot; fillOpacity=0, stroke="red", strokeWidth=2)` draws a red
  frame with no fill. `strokeOpacity` already passed as written. Makie's `alpha` and
  Vega-Lite's `opacity` still fade the whole mark, outline included. Before,
  `fillOpacity` reached Vega-Lite as `opacity`, so the outline faded with the fill:
  an outline-only bar drew nothing, and a map background written
  `visual(; color=:ink, fillOpacity=0.08, stroke=…)` drew its borders at 8 %, with
  no warning. Such a background now draws its borders at full strength.
- On a box plot, `fillOpacity` is a property its Vega-Lite mark does not read, so it
  is left out with the warning that names it; before, it faded the whole box plot.
  Fade the box's fill with `box=(; fillOpacity=a)`, or the whole box plot with `alpha`.

## 0.2.25

- `visual(VSpan)` and `visual(HSpan)` draw on `vdraw` and `vsave`, as Makie's `vspan`
  and `hspan` do on `sdraw`: `mapping(:from, :to) * visual(VSpan)` is a band from
  `from` to `to` on x over the whole plot height, also over a nominal y, and `HSpan`
  the same on y over the whole width. Both lower to a Vega-Lite `rect` positioned on
  that one axis (`x`/`x2` or `y`/`y2`); the tooltip names both edges, and `color`,
  `alpha`, `strokecolor` and `strokewidth` apply as on other marks. Makie's whole-axis
  default `ymin = 0`, `ymax = 1` (`xmin`/`xmax` for `HSpan`) is accepted; another
  fraction is left out with a warning. `VSpan` and `HSpan` are exported with the
  other Makie plot types. Before, both failed with
  `Unsupported plot type for Vega-Lite`.

## 0.2.24

- Error bars take Makie's line attributes. `visual(Rangebars; linewidth=w)` and
  `visual(Errorbars; linewidth=w)` draw each bar `w` wide on `vdraw` and `vsave`, as
  `sdraw` does. `whiskerwidth=w` draws Makie's whiskers: a cap `w` long at both ends
  of each bar, as thick as the bar and in its colour (Makie's default `0` draws none).
  `linestyle` dashes the bar, not the whiskers, as in Makie. Before, `linewidth`
  reached Vega-Lite as `strokeWidth`, which its error bar does not read, so a thick
  50 % bar beside a thin 95 % bar drew both at the default width, with no warning;
  `whiskerwidth` was ignored with a warning.
- A `visual(...)` attribute that the Vega-Lite mark of a box plot or error bar does
  not read is left out with the warning that names it, as one with no Vega-Lite
  counterpart is. These marks take only their colour, opacity and own properties, so
  `visual(BoxPlot; strokewidth=2)` or `strokecolor` on `Rangebars` used to be dropped
  by Vega-Lite without a word. The drawing is unchanged.

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
