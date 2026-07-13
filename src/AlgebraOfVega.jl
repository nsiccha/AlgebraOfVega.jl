module AlgebraOfVega

using AlgebraOfGraphics
import AlgebraOfGraphics: data, mapping, visual, dims,
    density, histogram, linear, smooth, expectation, frequency,
    Layer, Layers, ProcessedLayer, ProcessedLayers,
    renamer, sorter, nonnumeric, verbatim, presorted, direct,
    scale, scales, pregrouped
using Makie: Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, Hist, Density as MakieDensity, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot,
    Plot, plot
import Makie
using JSON, Tables, Statistics
using Dates: TimeType
using HTMX
import HTMX: h

include("tic.jl")

# Re-export AoG API
export data, mapping, visual, dims
export density, histogram, linear, smooth, expectation, frequency
export renamer, sorter, nonnumeric, verbatim, presorted, direct
export scale, scales, pregrouped
# Re-export Makie plot types users need
export Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, Hist, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot

# AlgebraOfVega exports
export config, vdraw, sdraw, sdraw_file, vlspec, vdata
export to_vegalite, to_json, to_html, to_node, vega_head, vega_controls, plot_size
export vega_runtime, update_data, vega_cdn_urls, mapping_controls, resolve_channels, refine_channels, auto_remap_node
export with_plot_caption, draws_summary_table

"""
    with_plot_caption(plot_node, caption; plot_id, kwargs...)

Wrap an AoV plot node (built via `to_node` or `auto_remap_node`) in a `<figure>`
with a caption header that includes a CSV-download button (and optionally a
lazy "Show data" details). Implementation lives in the
`AlgebraOfVegaHTMXObjectsExt` extension and requires `using HTMXObjects` to be
loaded; see that extension's docstring for the full kwargs.
"""
function with_plot_caption end

"""
    draws_summary_table(table; value, outcome, group_cols=Symbol[], ci_level=0.95, digits=2, caption=nothing, kwargs...)

Build a "median [lo, hi]" summary table from long-format draws data. Implementation
lives in the `AlgebraOfVegaHTMXObjectsExt` extension (requires `using HTMXObjects`).
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

Alias for `AlgebraOfGraphics.data`. Use when `data` clashes with a local variable
(e.g. an HTMXObjects struct field named `data`).
"""
vdata(args...; kwargs...) = data(args...; kwargs...)

include("datasets.jl")
include("explorer.jl")

include("vl_helpers.jl")
include("mark_mapping.jl")
include("extract.jl")
include("analyses.jl")
include("analysis_to_vl.jl")
include("layer_to_vl.jl")
include("to_vegalite.jl")
include("js_runtime.jl")
include("to_node.jl")
include("plot_size.jl")
include("auto_remap.jl")
include("to_html.jl")
include("widgets.jl")
include("sdraw.jl")
include("show.jl")

end # module
