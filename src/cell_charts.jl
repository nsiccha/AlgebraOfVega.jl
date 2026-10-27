# --- Cell charts: one small chart per table row (`cell_charts`) ---
#
# A table column of small charts (a breakdown per row: firms per size class,
# floor area per building function) is a small-multiples figure faceted by the
# table's row key, `mapping(:klasse, :n; layout=:vb_nr)`, whose panels sit in the
# table's cells instead of a grid. AoV lowers the figure once, without the facet
# and stepping one frame per key (`config(frame=…)`, src/frame.jl). The runtime
# fixes every scale to what all keys share (its frame plan), parses the column's
# Vega once and gives each cell a light view of its own key's rows
# (`AoV.cellColumn` / `AoV.cell`, vendor/aov-runtime.js). The `<td>`s (total,
# sort value, Markdown text) are built in the HTMXObjects extension, which owns
# the table's number format.

"""
    CellColumn

The lowered column `cell_charts` builds its cells from: the column's id, the key
column, its Vega-Lite (no facet, one frame per key), the cell size, every key in
the order the data first holds it, and per key the rows of the first layer, the
`category => value` parts and the total.
"""
struct CellColumn
    id::String
    field::String
    vl::Dict{String,Any}
    width::Int
    height::Int
    keys::Vector{Any}
    rows::Dict{Any,Vector{Any}}
    parts::Dict{Any,Vector{Pair{Any,Float64}}}
    totals::Dict{Any,Float64}
end

const _CELL_SIZE = (width=120, height=24)

# A cell's size, and what it leaves out: axes, legends, the frame around the
# plot area and the padding. Prepended to the figure's own config, so an
# authored key wins.
_cell_chrome(width, height) = config(; width, height, padding=0, config=Dict{String,Any}(
    "axis" => Dict{String,Any}("disable" => true),
    "legend" => Dict{String,Any}("disable" => true),
    "view" => Dict{String,Any}("stroke" => nothing)))

_cell_layers(l::AlgebraOfGraphics.Layer) = [l]
_cell_layers(ls::AlgebraOfGraphics.Layers) = ls.layers
_cell_layers(x) = throw(ArgumentError(
    "cell_charts: expected a figure (`data(...) * mapping(...) * visual(...)`, optionally `* config(...)`); got $(typeof(x))."))

_cell_drawable(l::AlgebraOfGraphics.Layer, layers) = only(layers)
_cell_drawable(::AlgebraOfGraphics.Layers, layers) = AlgebraOfGraphics.Layers(layers)

# `layer` without its `layout=` mapping (the table's row key).
function _cell_unfacet(layer::AlgebraOfGraphics.Layer)
    haskey(layer.named, :layout) || return layer
    named = [k => v for (k, v) in pairs(layer.named) if k !== :layout]
    m = AlgebraOfGraphics.mapping(layer.positional...; named...)
    AlgebraOfGraphics.Layer(layer.transformation, layer.data, m.positional, m.named)
end

# The key column: the `layout=` mapping, the same in every layer that has one.
function _cell_key_field(layers)
    fields = unique(_field_name(l.named[:layout]) for l in layers if haskey(l.named, :layout))
    isempty(fields) && throw(ArgumentError(
        "cell_charts: map the table's row key with `layout=`, e.g. `mapping(:klasse, :n; layout=:vb_nr)`: " *
        "each value of it becomes one cell."))
    length(fields) == 1 || throw(ArgumentError(
        "cell_charts: the layers map different row keys with `layout=` ($(join(fields, ", "))); a column has one key."))
    for l in layers, ch in (:row, :col)
        haskey(l.named, ch) && throw(ArgumentError(
            "cell_charts: a cell chart has no `$ch=` facet; its panels are the table's rows (`layout=:$(only(fields))`)."))
    end
    only(fields)
end

_cell_value_missing(v) = ismissing(v) || isnothing(v)
_cell_value_missing(v::Number) = !isfinite(v)

# The categories of the main layer in the order the chart draws them: a
# `sorter`'s order, otherwise ascending as Vega-Lite sorts a nominal axis.
function _cell_category_order(sel, cats)
    order = _selector_sort(sel)
    present = unique(c for c in cats if !_cell_value_missing(c))
    isnothing(order) || return Any[[c for c in order if any(isequal(c), present)];
                                   [c for c in present if !any(isequal(c), order)]]
    try
        sort!(Any[present...])
    catch
        Any[present...]
    end
end

# Per key: the main layer's rows, and its `category => value` parts. With a value
# positional (`mapping(:klasse, :n)`) a category's value is the sum of its rows'
# values; with only a category (`mapping(:klasse) * frequency()`) it is the number
# of rows. A cell's total is the sum of its parts.
function _cell_parts(layer, field::String)
    t = extract_data(layer)
    rows = Dict{Any,Vector{Any}}()
    order = Any[]
    for r in Tables.rowtable(t)
        k = getproperty(r, Symbol(field))
        _cell_value_missing(k) && continue
        haskey(rows, k) || push!(order, k)
        push!(get!(rows, k, Any[]), r)
    end
    pos = layer.positional
    parts = Dict{Any,Vector{Pair{Any,Float64}}}()
    if isempty(pos)
        for (k, rs) in rows
            parts[k] = Pair{Any,Float64}[]
        end
        return order, rows, parts, Dict{Any,Float64}(k => Float64(length(rs)) for (k, rs) in rows)
    end
    cat = Symbol(_field_name(first(pos)))
    val = length(pos) >= 2 ? Symbol(_field_name(pos[2])) : nothing
    cols = Tables.columnnames(t)
    cat in cols || throw(ArgumentError("cell_charts: the data has no column $(repr(cat))."))
    isnothing(val) || val in cols || throw(ArgumentError("cell_charts: the data has no column $(repr(val))."))
    numeric = !isnothing(val) && Base.nonmissingtype(eltype(Tables.getcolumn(t, val))) <: Real
    cats = _cell_category_order(first(pos), Tables.getcolumn(t, cat))
    for (k, rs) in rows
        sums = Dict{Any,Float64}()
        for r in rs
            c = getproperty(r, cat)
            _cell_value_missing(c) && continue
            v = numeric ? getproperty(r, val) : 1
            _cell_value_missing(v) && continue
            sums[c] = get(sums, c, 0.0) + Float64(v)
        end
        parts[k] = Pair{Any,Float64}[c => sums[c] for c in cats if haskey(sums, c)]
    end
    totals = Dict{Any,Float64}(k => sum(last, p; init=0.0) for (k, p) in parts)
    order, rows, parts, totals
end

# The position axes on which the figure's own config sets `zero`.
function _cell_authored_zero(cfg)
    out = Set{String}()
    isnothing(cfg) && return out
    props = cfg.properties
    sc = _as_scales(get(props, :scales, nothing))
    if !isnothing(sc)
        for (name, ch) in ((:X, "x"), (:Y, "y"))
            p = get(sc.dict, name, nothing)
            !isnothing(p) && haskey(p, :zero) && push!(out, ch)
        end
    end
    enc = _as_dict(get(props, :encoding, nothing))
    if !isnothing(enc)
        for ch in ("x", "y")
            e = _as_dict(get(enc, ch, nothing))
            s = isnothing(e) ? nothing : _as_dict(get(e, "scale", nothing))
            !isnothing(s) && haskey(s, "zero") && push!(out, ch)
        end
    end
    out
end

_cell_mark_type(m::AbstractString) = m
_cell_mark_type(m::AbstractDict) = string(get(m, "type", ""))
_cell_mark_type(_) = ""

# A breakdown's bars start at zero, so bar lengths compare across cells: the
# value axis of every bar takes `zero=true` (with the scale it shares), unless
# the figure sets `zero` itself. AoV's no-zero default exists for scatter-like
# figures, where Makie draws no zero either.
function _cell_bars_from_zero!(vl::Dict, authored::Set{String})
    for ch in ("x", "y")
        ch in authored && continue
        bars = IdDict{Any,Bool}()
        _each_frame_unit(vl) do unit
            _cell_mark_type(get(unit, "mark", nothing)) == "bar" || return
            enc = _as_dict(get(unit, "encoding", nothing))
            e = isnothing(enc) ? nothing : _as_dict(get(enc, ch, nothing))
            isnothing(e) || (bars[e] = true)
        end
        isempty(bars) && continue
        for group in _shared_scale_groups(vl, ch)
            any(e -> haskey(bars, e), group) || continue
            for e in group
                scale = get!(e, "scale", Dict{String,Any}())
                scale isa Dict && get(scale, "zero", nothing) === false && (scale["zero"] = true)
            end
        end
    end
    vl
end

_cell_size(props, k::Symbol, default) = (v = get(props, k, nothing); v isa Real ? round(Int, v) : default)

"""
    _cell_column(spec, scales=nothing; id=nothing) -> CellColumn

Lower a figure faceted by the table's row key (`layout=:key`) for
`cell_charts`: the same figure without the facet, its axes, legend, frame and
padding left out (an authored `config(config=…)` key wins), bars from zero, at
`config(width=…, height=…)` or 120×24 px, stepping one frame per key.
"""
function _cell_column(spec, scales=nothing; id=nothing)
    v = spec isa VegaSpec ? spec : vlspec(spec)
    layers = _cell_layers(v.drawable)
    field = _cell_key_field(layers)
    props = isnothing(v.config) ? Dict{Symbol,Any}() : v.config.properties
    haskey(props, :frame) && throw(ArgumentError(
        "cell_charts: a cell shows one row key and steps no frames; drop `config(frame=…)`."))
    main = findfirst(l -> !isnothing(_frame_table(l, field)), layers)
    isnothing(main) && throw(ArgumentError(
        "cell_charts(… layout=:$field): no layer's data has a column \"$field\"."))
    # Without its facet, a layer's per-key marks are what one frame shows: an
    # unfaceted density() is a Vega-Lite transform that runs per cell.
    unfaceted = [_cell_unfacet(l) for l in layers]
    for l in unfaceted
        isnothing(_frame_table(l, field)) && continue
        what = _frame_unsupported(l)
        isnothing(what) || throw(ArgumentError(
            "cell_charts(… layout=:$field): one layer is $what, whose marks AoV computes in Julia, so its " *
            "rows carry no $field to put in a cell. Summarise per $field yourself and draw the summary with " *
            "the `bands=` form (`lineribbon(bands=…)`, `pointinterval(bands=…)`)."))
    end
    width = _cell_size(props, :width, _CELL_SIZE.width)
    height = _cell_size(props, :height, _CELL_SIZE.height)
    # `config(facet=(; linkyaxes=:none))` unlinks a facet's panels; here the
    # panels are cells, so each cell fits that axis to its own rows. The figure
    # itself has no facet left to resolve.
    own = sort!(collect(keys(_facet_nt_to_resolve_scale(something(_as_nt(get(props, :facet, nothing)), (;))))))
    cfg = isnothing(v.config) ? nothing : Config(Dict{Symbol,Any}(k => x for (k, x) in props if k !== :facet))
    figure = _cell_chrome(width, height) *
        VegaSpec(_cell_drawable(v.drawable, unfaceted), cfg, v.layer_encodings) *
        config(frame=Symbol(field))
    vl = isnothing(scales) ? to_vegalite(figure; interactive=false) : to_vegalite(figure, scales; interactive=false)
    _cell_bars_from_zero!(vl, _cell_authored_zero(v.config))
    get!(vl, "_aov", Dict{String,Any}())["cells"] = Dict{String,Any}("own" => own)
    order, rows, parts, totals = _cell_parts(layers[main], field)
    cid = _sanitize_id(something(id, "aov-cells-" * string(hash(_vl_json(vl)), base=16)))
    CellColumn(cid, field, vl, width, height, order, rows, parts, totals)
end

"""
    cell_charts(spec[, scales]; texts=table_texts(), sigdigits=3, id=nothing,
                total=nothing, label=nothing, text=nothing) -> CellCharts

A column of small charts for a table, one per row: each table cell shows its
row's total and a small chart (no axes or legend; a tooltip on each mark), and
every cell of the column shares one scale, so the rows compare at a glance.
`spec` is a figure faceted by the table's row key with `layout=`; its panels
become the cells:

```julia
# one row per (site, size class): vb_nr, klasse, n
cells = cell_charts(data(site_classes) *
    mapping(:klasse => sorter(class_labels) => "Größenklasse", :n => "Betriebe"; layout=:vb_nr) *
    visual(BarPlot); texts=table_texts(:de))
h.tr(h.td(r.name), cells[r.vb_nr])
```

`cells[key]` is the `<td>` of the row `key`:
- the total, written as the table writes numbers (`texts`, `sigdigits`), and
  the chart, drawn in the browser by the AoV runtime (`vega_head()`): the
  cells near the viewport first, the others while the browser is idle (and
  at once when the page prints);
- `data-sort-value` and `data-htmxo-number` = the total, so the table sorts by
  it and its ⬇ CSV writes it;
- in the page's Markdown view (and so a `pdf_report`) the breakdown as text
  instead of the chart: `19 (200–499: 13; 500–999: 2)`, zero parts left out.

The column's figure is written as any AoV figure (`sorter`, labels,
`visual(BarPlot; color=…)`, `scales(...)`); `config(width=…, height=…)` sets the
cell size (default 120×24 px). Every scale is shared across the column's cells,
as AoG links a facet's axes; `config(facet=(; linkyaxes=:none))` lets each cell
fit its own y axis (`linkxaxes` its x axis). Bars start at zero unless the
figure sets `zero` itself. A key that has no rows gets an empty chart and a
total of 0.

The total is the sum of the value positional (`mapping(:klasse, :n)`), or the
number of rows with only a category (`mapping(:klasse) * frequency()`). Replace
it with `total = rows -> number`, its shown text with `label = x -> string`, and
the Markdown text with `text = rows -> string` (`rows` are the key's rows of the
first layer, as NamedTuples). `id` names the column (default: a hash of its
figure). Implementation lives in the `AlgebraOfVegaHTMXObjectsExt` extension.
"""
function cell_charts end
