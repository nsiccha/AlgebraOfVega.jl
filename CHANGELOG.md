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
