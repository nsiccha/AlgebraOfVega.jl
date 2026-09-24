# plot_size.jl — structural figure-size estimator (Plan A; decision `1dmk88u`).
#
# `plot_size(spec) → (; width, height)` predicts a Vega-Lite spec's rendered
# size in the spec's OWN px units, from spec *structure* alone — no render, no
# new deps. It relates directly to the spec's numeric `width`/`height` and to a
# vl-convert render of the same spec.
#
# Why it exists: a consumer (Bruno's report PDF export) needs to paginate a
# figure that renders too tall for a page WITHOUT rediscovering LaTeX's
# `\maxdimen` overflow per-figure. The split of responsibility (decision
# `15u664q`) is: **AoV measures; the consumer owns page policy** (papersize,
# margins, "how many panels fit", slicing, captions). AoV therefore knows
# nothing about A4 / margins / `\clearpage`.
#
# Two geometries dominate, both handled here:
#   • faceted:              height ≈ n_rows × (panel_h + spacing) + overhead
#   • single categorical-y: height ≈ n_categories × step         + overhead
#
# Chrome overhead (axis / title / facet-header) is ESTIMATED — so the estimate
# is meant to be padded conservatively by the consumer. It clears the real bar
# ("never overflow") once padded, and may pack slightly loosely. Escalate to a
# probe-render (Plan B, vl-convert) only if real figures pack too loosely.

# --- Vega-Lite default geometry (config.view.* / config.facet.*) --------------
# Mirror Vega-Lite's own defaults; a spec that overrides them in `config` is
# honoured via `_size_cfg` below.
const _VL_CONTINUOUS_LEN = 200.0  # config.view.continuousWidth / continuousHeight
const _VL_DISCRETE_STEP  = 20.0   # config.view.step — px per band on a discrete axis
const _VL_FACET_SPACING  = 20.0   # config.facet.spacing — px between adjacent panels

# --- Estimated chrome overhead (tunable; the consumer pads these) -------------
const _SIZE_AXIS_OVERHEAD  = 40.0  # one shared x/y axis: ticks + labels + axis title
const _SIZE_TITLE_OVERHEAD = 30.0  # top-level `title` text band
const _SIZE_FACET_HEADER   = 20.0  # facet header strip (column headers / row labels)

const _SIZE_DISCRETE_TYPES = ("nominal", "ordinal")

# Read a nested numeric `config` override (e.g. config.view.step), falling back
# to the Vega-Lite default when the spec doesn't set it.
function _size_cfg(spec::Dict, path::Tuple, default::Float64)
    node = spec
    for k in path
        d = _as_dict(node)
        isnothing(d) && return default
        node = get(d, k, nothing)
    end
    n = _as_number(node)
    isnothing(n) ? default : Float64(n)
end

# Collect every embedded `data.values` row across the spec (top-level + nested
# `spec` + every `layer` sublayer), so facet/category cardinality can be counted
# even when data is attached per-sublayer (multi-source specs) rather than at
# the top level.
function _size_collect_rows!(rows::Vector{Any}, node)
    d = _as_dict(node)
    isnothing(d) && return rows
    data = _as_dict(get(d, "data", nothing))
    if !isnothing(data)
        vals = get(data, "values", nothing)
        vals isa AbstractVector && append!(rows, vals)
    end
    _size_collect_rows!(rows, get(d, "spec", nothing))
    layers = get(d, "layer", nothing)
    if layers isa AbstractVector
        for sub in layers
            _size_collect_rows!(rows, sub)
        end
    end
    rows
end
_size_collect_rows(spec::Dict) = _size_collect_rows!(Any[], spec)

# Number of distinct present values of `field` across the collected rows. A
# self-contained spec always embeds its facet/category field, so this mirrors
# how many panels/bands Vega-Lite itself will draw.
function _size_field_cardinality(rows, field)
    seen = Set{Any}()
    for r in rows
        rd = _as_dict(r)
        isnothing(rd) && continue
        haskey(rd, field) && push!(seen, rd[field])
    end
    length(seen)
end

# A positional channel's encoding dict (`"x"` / `"y"`), taken from the panel's
# own `encoding` first, then the first layered sublayer that carries it.
function _size_positional_channel(panel::Dict, ch::String)
    enc = _as_dict(get(panel, "encoding", nothing))
    if !isnothing(enc)
        c = _as_dict(get(enc, ch, nothing))
        !isnothing(c) && haskey(c, "field") && return c
    end
    layers = get(panel, "layer", nothing)
    if layers isa AbstractVector
        for sub in layers
            senc = _as_dict(get(_as_dict(sub), "encoding", nothing))
            isnothing(senc) && continue
            c = _as_dict(get(senc, ch, nothing))
            !isnothing(c) && haskey(c, "field") && return c
        end
    end
    nothing
end

_size_is_discrete(ch) = !isnothing(ch) && get(ch, "type", nothing) in _SIZE_DISCRETE_TYPES

# Estimate a panel's length along one axis. Precedence:
#   1. an explicit numeric `width`/`height` on the panel;
#   2. a discrete (nominal/ordinal) positional channel → n_categories × step;
#   3. Vega-Lite's continuous default (200).
function _size_panel_length(panel::Dict, dim_key::String, pos_ch::String, rows, step::Float64)
    explicit = _as_number(get(panel, dim_key, nothing))
    isnothing(explicit) || return Float64(explicit)
    ch = _size_positional_channel(panel, pos_ch)
    if _size_is_discrete(ch)
        n = _size_field_cardinality(rows, ch["field"])
        n > 0 && return n * step
    end
    _VL_CONTINUOUS_LEN
end

# Resolve the panel grid: how many rows (stacked vertically → height) and
# columns (laid out horizontally → width) of panels the spec facets into.
# Handles both the `facet` operator (single-field wrap, or row/column channels)
# and the `encoding.row`/`encoding.column` shorthand. Returns
# `(n_rows, n_cols, faceted)`.
function _size_facet_grid(spec::Dict, rows)
    facet = _as_dict(get(spec, "facet", nothing))
    enc   = _as_dict(get(spec, "encoding", nothing))
    # Facet channels live under the `facet` operator, or (shorthand) under `encoding`.
    src = !isnothing(facet) ? facet : (_has_encoding_facet(spec) ? enc : nothing)
    isnothing(src) && return (1, 1, false)

    # Single-field facet operator (`{facet:{field}, columns:k}`) → wrap grid.
    if !isnothing(facet) && haskey(facet, "field")
        n = max(_size_field_cardinality(rows, facet["field"]), 1)
        cols = _as_number(get(spec, "columns", nothing))
        isnothing(cols) && return (1, n, true)   # VL default: a single row of panels
        c = max(round(Int, cols), 1)
        return (cld(n, c), min(c, n), true)
    end

    # row / column channels (operator or encoding-shorthand form).
    _card(ch) = (!isnothing(ch) && haskey(ch, "field")) ?
        max(_size_field_cardinality(rows, ch["field"]), 1) : 1
    n_rows = _card(_as_dict(get(src, "row", nothing)))
    n_cols = _card(_as_dict(get(src, "column", nothing)))
    (n_rows, n_cols, true)
end

# The per-panel spec: the inner `spec` of a `facet` operator, else the unit spec
# itself (encoding-shorthand facet, or a plain single view).
_size_panel(spec::Dict) = something(_as_dict(get(spec, "spec", nothing)), spec)

"""
    plot_size(spec) → (; width, height)

Estimate the rendered size of a Vega-Lite `spec`, in the spec's own px units,
from its structure alone — no rendering, no extra dependencies. `spec` may be a
VL spec `Dict` (as produced by [`to_vegalite`](@ref)) or a `Layer` / `Layers` /
`VegaSpec` (lowered via `to_vegalite` first). The result destructures as
`w, h = plot_size(spec)` and exposes `.width` / `.height` (`Float64`, px).

The model:

- **faceted** — `height ≈ n_rows × (panel_h + spacing) + overhead`, `width`
  symmetrically over `n_cols`. `n_rows`/`n_cols` come from the facet fields'
  cardinality (distinct values in the embedded data) and the `columns` /
  row-column layout; it covers the `facet` operator (single-field wrap and
  row/column channels) and the `encoding.row`/`encoding.column` shorthand.
- **single categorical axis** — a nominal/ordinal `y` (or `x`) with no explicit
  size gives `n_categories × step`, so a tall category list is measured.
- **plain continuous** — an explicit numeric `width`/`height`, else Vega-Lite's
  200px continuous default.

Chrome overhead (axis, title, facet header) is *estimated*: this is a fast,
deterministic structural predictor (Plan A, decision `1dmk88u`), so a consumer
that paginates on the result should pad conservatively. It exists so a consumer
(e.g. a PDF export) can decide how to split a too-tall figure while owning page
policy itself — `plot_size` measures, it does not know about pages (decision
`15u664q`).
"""
function plot_size(spec::AbstractDict)
    top::Dict = spec isa Dict ? spec : Dict{String,Any}(string(k) => v for (k, v) in spec)
    rows    = _size_collect_rows(top)
    step    = _size_cfg(top, ("config", "view", "step"), _VL_DISCRETE_STEP)
    spacing = _size_cfg(top, ("config", "facet", "spacing"), _VL_FACET_SPACING)

    n_rows, n_cols, faceted = _size_facet_grid(top, rows)
    panel = _size_panel(top)

    panel_h = _size_panel_length(panel, "height", "y", rows, step)
    panel_w = _size_panel_length(panel, "width",  "x", rows, step)

    height = n_rows * panel_h + max(n_rows - 1, 0) * spacing + _SIZE_AXIS_OVERHEAD
    width  = n_cols * panel_w + max(n_cols - 1, 0) * spacing + _SIZE_AXIS_OVERHEAD

    haskey(top, "title") && (height += _SIZE_TITLE_OVERHEAD)
    if faceted
        height += _SIZE_FACET_HEADER          # column-header / title strip above the grid
        n_cols > 1 && (width += _SIZE_FACET_HEADER)  # row-label strip beside the grid
    end
    (; width = Float64(width), height = Float64(height))
end

plot_size(x::Union{Layer,Layers,VegaSpec}) = plot_size(to_vegalite(x))
