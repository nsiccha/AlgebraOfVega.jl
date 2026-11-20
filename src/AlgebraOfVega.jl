module AlgebraOfVega

using JSON, Tables, Statistics
using Dictionaries: Dictionary, dictionary
# Colour values (`RGBAf`, `parse(RGBA{Float32}, "red")`): the colour types Makie
# itself uses, so a colour reads the same on the Vega-Lite and the static path.
import Colors
using Dates: TimeType
import Dates
using SHA: sha256
using Base64: base64encode
import Downloads
using HTMX
# `Raw` marks complete, trusted JS/CSS bytes. HTMX 1.0 escapes ordinary string
# children (`&`, `"`, `'`, `<`, `>`), which mangles every `<script>`/`<style>`
# body AoV emits — so every such child MUST be wrapped in `Raw(...)`, through
# `_inline_script` / `_inline_style` below.
import HTMX: h, Raw

include("algebra.jl")

# Text inside an inline `<script>`/`<style>` must not spell a closing tag that
# ends the element early (`</script`, `</style`) or that a text-substituting
# proxy keys on (`</head>`, `</body>`, `</html>`: nginx `sub_filter`, injected
# analytics or livereload snippets rewrite every occurrence, splicing markup
# into the middle of the script). `<\/` reads as `</` in JS and CSS strings,
# template literals, regexes and comments, so a `</` before one of those tag
# names is written that way — and only there: a bare `</` can be a regex's `<`
# and its closing `/`, as in vega's `.replace(/</g, …)`. Every inline body AoV
# emits — its runtime, the vendored builds, spec and data JSON — goes through
# this rule (snag `serve-a-page-tha-ebb4d298`); the runtime applies the same
# one when it inlines files into a saved page (`AoV._inlineVendored`).
const _INLINE_CLOSING_TAG = r"</(?=(?:script|style|head|body|html)\b)"i
_inline_text(s::AbstractString) = replace(s, _INLINE_CLOSING_TAG => "<\\/")
_inline_script(js::AbstractString) = h.script(Raw(_inline_text(js)))
_inline_style(css::AbstractString) = h.style(Raw(_inline_text(css)))

# The AlgebraOfGraphics-spelled algebra (owned in algebra.jl)
export data, mapping, visual, dims
export density, histogram, linear, smooth, expectation, frequency
export renamer, sorter, nonnumeric, verbatim, presorted, direct
export scale, scales, pregrouped, wrapped
# Plot-type vocabulary (`PlotTypes`); `Text`/`Density` stay qualified, like Makie
export Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, HSpan, VSpan, Hist, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot

# AlgebraOfVega exports
export config, vdraw, sdraw, sdraw!, sdraw_file, vsave, vlspec, vdata
export locale_config
export by_url, rows_json
export to_vegalite, to_json, to_html, to_node, vega_head, vega_controls, plot_size
export plot_summary_md, PlotSummary, plot_summary_table
export vega_runtime, update_data, append_data, replace_data, remove_data, update_spec, embedded_spec, vega_cdn_urls, vega_sri_hashes, vega_vendor_dir, mapping_controls, resolve_channels, refine_channels, auto_remap_node
export with_plot_caption, draws_summary_table, cell_charts, vconcat
export clean_share_url, caption_share_button, caption_action_inject,
    with_caption_share, with_caption_download, summary_share_button
export PlotTexts, plot_texts
export symlog

"""
    sdraw(spec, path::AbstractString; alt=nothing, kwargs...)

Render an AoV spec statically through AlgebraOfGraphics and Makie, save it to
`path` (format inferred from the extension) and return an `h.img` node pointing
to `path`.

`alt` gives the image its alt text, a description of what the figure shows
(`<img src alt>`, Markdown carrying the alt). An accessible (PDF/UA) report
needs it on every figure; without `alt` the image has none.

Extra `kwargs` are passed to `Makie.save` (e.g. `px_per_unit=2` for retina).

Provided by the `AlgebraOfVegaMakieExt` extension: load AlgebraOfGraphics and a
Makie backend first (`import AlgebraOfGraphics, CairoMakie`).
"""
function sdraw end

"""
    sdraw!(position, spec)

Render an AoV spec into an existing Makie figure, layout position, or axis via
`AlgebraOfGraphics.draw!`. This is the static composition counterpart to
`sdraw_file`: create a `Figure`, place independently configured specs with
`sdraw!(fig[row, col], spec)`, then save the complete figure with `Makie.save`.

Each spec keeps its own `config(axis=...)`, `config(facet=...)`, and
`config(scales=...)` settings. `config(width=...)` and `config(height=...)` are
standalone-figure settings and are therefore ignored when drawing into an
existing layout. `mapping` display labels (`:x => "Label"`), including
`lineribbon`/`ribbon(bands=...)` x/y/colour/facet labels, are preserved on the
rebuilt static layers.

Like `AlgebraOfGraphics.draw!`, this does not add legends or colorbars — call
`AlgebraOfGraphics.legend!(position, grid)` with the returned grid afterwards
(see `aov-use` §1a for the composition pattern).

Provided by the `AlgebraOfVegaMakieExt` extension: load AlgebraOfGraphics and a
Makie backend first (`import AlgebraOfGraphics, CairoMakie`). Returns the result
of `AlgebraOfGraphics.draw!`.
"""
function sdraw! end

"""
    sdraw_file(spec, path::AbstractString; kwargs...)

Render an AoV spec to a file via `AlgebraOfGraphics.draw` and `Makie.save`.
Returns the path. Extra `kwargs` are passed to `Makie.save`.

Provided by the `AlgebraOfVegaMakieExt` extension: load AlgebraOfGraphics and a
Makie backend first (`import AlgebraOfGraphics, CairoMakie`).
"""
function sdraw_file end

const _MAKIE_EXT_FUNCTIONS = (sdraw, sdraw!, sdraw_file)

function __init__()
    # `sdraw*` without the extension: name what to load instead of a bare
    # MethodError.
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        exc.f in _MAKIE_EXT_FUNCTIONS || return
        isnothing(Base.get_extension(@__MODULE__, :AlgebraOfVegaMakieExt)) || return
        print(io, "\n`", nameof(exc.f), "` is the static Makie path, provided by the AlgebraOfVegaMakieExt extension: ",
            "load AlgebraOfGraphics and a Makie backend first, e.g. `import AlgebraOfGraphics, CairoMakie`.")
    end
end

"""
    with_plot_caption(plot_node, caption; plot_id, kwargs...)

Wrap a rendered plot or drawable in a figure with a caption and export menu.
Requires `using HTMXObjects`. Give the figure a stable `plot_id`.

Caption keywords select data previews, summary tables, channel controls,
localized `texts`, and download buttons. `static_image` and `alt` supply the
image and alternative text for a Markdown report. The interactive figure
remains available in the HTML view.
"""
function with_plot_caption end

"""
    draws_summary_table(table; value, outcome, group_cols=Symbol[], ci_level=0.95, digits=2, caption=nothing, kwargs...)

Build a median-and-interval table from long-format values grouped by
`group_cols` and `outcome`. `ci_level` specifies the central quantile mass;
`digits` controls display precision. Requires `using HTMXObjects`.
The interval's scientific interpretation depends on the supplied values.
"""
function draws_summary_table end

# Sanitize a user-supplied id so it is safe both as an HTML id attribute and
# as a CSS selector (querySelector('#'+id)). Dots, brackets, colons, etc. are
# valid HTML id chars but break CSS selector parsing — replace anything outside
# [A-Za-z0-9_-] with '-'. Idempotent (sanitized ids pass through unchanged).
_sanitize_id(id) = replace(string(id), r"[^A-Za-z0-9_-]" => "-")

# Introspect a spec for a draws-shaped analysis (PointInterval / GradientInterval
# / DotIntervalAnalysis) and return args for `draws_summary_table`, or `nothing`
# if the spec isn't a suitable candidate. Used by the `::VegaSpec` dispatch of
# `with_plot_caption` to auto-build a pretty summary table. Implemented later in
# this file once the analysis types and helpers are defined.
function _auto_summary_args end
# Tidybayes-style analysis exports
export pointinterval, gradient_interval, lineribbon, ribbon, dotinterval
export ribbon_view
export geoshape, geobox
# High-level widget/recipe exports
export ecdf_grid, ppc_overlay
# Dataset exports
export sample_cars, sample_tips, sample_stocks, sample_temperatures,
    sample_population, melt_population, sample_monthly_sales, melt_sales,
    sample_posterior_draws, sample_regression_predictions,
    sample_grouped_regression_predictions, sample_faceted_regression_predictions,
    sample_faceted_observations,
    classify_columns, table_to_rows, preaggregate
# Explorer exports
export default_explorer_datasets, explorer_widget, write_explorer_assets,
    explorer_controls_html, explorer_js, explorer_data_init_js

"""
    vdata(args...; kwargs...)

Alias for [`data`](@ref). Use when `data` clashes with a local variable
(e.g. an HTMXObjects struct field named `data`).
"""
vdata(args...; kwargs...) = data(args...; kwargs...)

include("datasets.jl")
include("explorer.jl")

include("vl_helpers.jl")
include("locales.jl")
include("plot_texts.jl")
include("mark_mapping.jl")
include("extract.jl")
include("by_url.jl")
include("bound_columns.jl")
include("analyses.jl")
include("analysis_to_vl.jl")
include("layer_to_vl.jl")
include("to_vegalite.jl")
include("ref_labels.jl")
include("ribbon_view.jl")
include("panel_labels.jl")
include("frame.jl")
include("link.jl")
include("js_runtime.jl")
include("to_node.jl")
include("cell_charts.jl")
include("plot_size.jl")
include("vconcat.jl")
include("auto_remap.jl")
include("plot_summary_table.jl")
include("to_html.jl")
include("vsave.jl")
include("caption_actions.jl")
include("widgets.jl")
include("static_prep.jl")
include("show.jl")

end # module
