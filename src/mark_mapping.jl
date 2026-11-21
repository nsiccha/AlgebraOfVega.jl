# --- Makie → Vega-Lite mark mapping ---

"""Makie plot type → VL mark string. Checked via `<:`, order matters for subtypes.

`VSpan`/`HSpan` are `rect`s positioned on one axis only (`x`/`x2` or `y`/`y2`,
`_plain_layer_to_vl`): Vega-Lite draws a rect with no encoding on the other axis
across the whole plot, as Makie draws a span across the whole axis."""
_MARK_MAP = [
    Scatter => "point", Lines => "line", ScatterLines => "line",
    BarPlot => "bar", Heatmap => "rect", BoxPlot => "boxplot",
    Violin => "area", Band => "area", HLines => "rule", VLines => "rule",
    VSpan => "rect", HSpan => "rect",
    Hist => "bar", MakieDensity => "area", Errorbars => "errorbar",
    Stairs => "line", ECDFPlot => "line", Contour => "rect",
    Rangebars => "errorbar", CrossBar => "errorbar", PlotTypes.Text => "text",
]

function plottype_to_mark(T::Type)
    for (PT, mark) in _MARK_MAP
        T <: PT && return mark
    end
    error("Unsupported plot type for Vega-Lite: $T")
end

"""Extra VL mark properties that depend on Makie plot type (e.g. ScatterLines → point=true)."""
_MARK_PROPS = [
    Scatter => Dict{String,Any}("filled" => true),
    ScatterLines => Dict{String,Any}("point" => true),
    Stairs => Dict{String,Any}("interpolate" => "step-after"),
]

function plottype_to_mark_props(T::Type)
    for (PT, props) in _MARK_PROPS
        T <: PT && return props
    end
    Dict{String,Any}()
end

"""
Vega-Lite composite mark → the parts it draws, each with whether Vega-Lite
draws it by default (its `config.<mark>.<part>` default).
"""
_COMPOSITE_PARTS = Dict{String,Vector{Pair{String,Bool}}}(
    "errorbar" => ["rule" => true, "ticks" => false],
    "errorband" => ["band" => true, "borders" => false],
    "boxplot" => ["box" => true, "median" => true, "outliers" => true, "rule" => true, "ticks" => false],
)

_COMPOSITE_MARKS = Set(keys(_COMPOSITE_PARTS))

# Vega-Lite drops a composite mark's own `style`: each part it draws gets the
# style `"<mark>-<part>"` (or the part's own), and only `color`, `opacity` and
# `clip` carry over from the composite. So a style on a composite —
# `visual(Rangebars; color=:ink)`'s `aov-ink` — moves onto every drawn part,
# after the part's style so it wins, and the composite keeps none. A part
# switched off (`false`/`nothing`) stays off, and one left at its default is
# styled only when Vega-Lite draws it by default.
_style_composite_parts(mark) = mark
function _style_composite_parts(mark::Dict)
    parts = get(_COMPOSITE_PARTS, _mark_type(mark), nothing)
    (isnothing(parts) || !haskey(mark, "style")) && return mark
    out = copy(mark)
    styles = _style_list(pop!(out, "style"))
    for (part, drawn) in parts
        p = get(out, part, drawn)
        (isnothing(p) || p === false) && continue
        props = p === true ? Dict{String,Any}() :
            Dict{String,Any}(string(k) => v for (k, v) in pairs(p))
        props["style"] = vcat(_style_list(get(props, "style", "$(_mark_type(mark))-$part")), styles)
        out[part] = props
    end
    out
end

_style_list(style::AbstractVector) = string.(style)
_style_list(style) = [string(style)]

_mark_type(m::String) = m
_mark_type(m::Dict) = get(m, "type", "")
_mark_type(_) = ""

_layer_mark_type(sl::Dict) = _mark_type(get(sl, "mark", nothing))
_layer_mark_type(_) = ""

function _is_composite_mark(vl::Dict)
    _mark_type(get(vl, "mark", nothing)) in _COMPOSITE_MARKS && return true
    # Check sublayers for composite marks (e.g. layered boxplots)
    for sl in get(vl, "layer", [])
        _layer_mark_type(sl) in _COMPOSITE_MARKS && return true
    end
    false
end

# --- AoG aesthetic name → Vega-Lite channel ---

"""AoG aesthetic name → VL encoding channel. Returns `nothing` for `:stack` (handled separately)."""
_CHANNEL_MAP = Dict{Symbol,Union{String,Nothing}}(
    :color => "color", :strokecolor => "stroke", :marker => "shape",
    :markersize => "size", :linewidth => "strokeWidth", :linestyle => "strokeDash",
    :dodge_x => "xOffset", :dodge_y => "yOffset",
    :col => "column", :row => "row", :layout => "facet",
    :group => "detail", :stack => nothing,
)

aog_named_to_vl_channel(name::Symbol) = get(_CHANNEL_MAP, name, string(name))

# Vega-Lite's encoding channels: the names the vendored vega-lite 5.23.0 does
# not drop as "not a valid encoding channel" (checked by compiling one encoding
# per name). Vega-Lite drops any other encoding key with only a console warning,
# so a mapping keyword that lowered to one would draw the figure without it: a
# `dodge=` mapping drew stacked bars where AlgebraOfGraphics draws grouped ones
# (snag `aov-emits-aog-do-6019d128`).
const _VL_ENCODING_CHANNELS = Set{String}([
    "x", "y", "x2", "y2", "xOffset", "yOffset", "xError", "xError2", "yError", "yError2",
    "longitude", "latitude", "longitude2", "latitude2", "theta", "theta2", "radius", "radius2",
    "color", "fill", "stroke", "opacity", "fillOpacity", "strokeOpacity", "strokeWidth",
    "strokeDash", "size", "angle", "shape", "text", "tooltip", "href", "url", "description",
    "detail", "key", "order", "row", "column", "facet",
])

# The plot types with AlgebraOfGraphics' own `dodge` mapping (its
# `aesthetic_mapping`): a bar dodges along the axis it stands on (`direction`),
# a box plot, violin or crossbar along its category axis (`orientation`). On
# every other plot type AoG's dodge is `dodge_x`/`dodge_y`.
const _NativeDodge = Union{BarPlot, BoxPlot, Violin, CrossBar}
_native_dodge(plot_type) = plot_type isa Type && plot_type <: _NativeDodge

# A layer without a plot type of its own draws AoG's default, a scatter.
_layer_type_name(plot_type) =
    plot_type isa Type && plot_type <: Plot && plot_type !== Plot{:plot} ? string(_plotsym(plot_type)) : "Scatter"

"""
    _named_vl_channel(name, plot_type) -> Union{String,Nothing}

The Vega-Lite channel the `mapping(...)` keyword `name` lowers to on a layer of
`plot_type` (`_CHANNEL_MAP`, else a Vega-Lite channel name as written), or
`nothing` for one lowered elsewhere (`stack`). A keyword that lowers to no
Vega-Lite channel is an `ArgumentError` naming it, as AlgebraOfGraphics refuses
a mapped attribute outside the plot type's aesthetic mapping.
"""
function _named_vl_channel(name::Symbol, plot_type)
    ch = aog_named_to_vl_channel(name)
    (isnothing(ch) || ch in _VL_ENCODING_CHANNELS) && return ch
    type = _layer_type_name(plot_type)
    if name === :dodge
        throw(ArgumentError("mapping(...; dodge=…) on a $type layer: AlgebraOfGraphics has `dodge` only on " *
            "BarPlot, BoxPlot, Violin and CrossBar. Dodge a $type layer with `dodge_x=` (along x) or `dodge_y=` (along y)."))
    end
    throw(ArgumentError("mapping(...; $name=…) on a $type layer lowers to no Vega-Lite encoding channel, " *
        "so the figure would be drawn without it. AlgebraOfVega lowers the AlgebraOfGraphics keywords " *
        join(sort!(string.(collect(keys(_CHANNEL_MAP)))), ", ") * ", `dodge` on BarPlot, BoxPlot, Violin and CrossBar, " *
        "`fillto` on BarPlot, and passes a Vega-Lite channel name (x2, y2, size, opacity, order, tooltip, …) as written."))
end

"""
    _named_encodings!(encoding, named, plot_type, mark, table; base_channel=nothing)

Write a layer's `mapping(...)` keywords `named` into `encoding` as their
Vega-Lite channels (`_named_vl_channel`) and type them from `table`.
`base_channel` is where a bar's `fillto` goes (its `x2` or `y2`).

AlgebraOfGraphics' `dodge` on a plot type that dodges natively (`_NativeDodge`)
lowers once the positions are typed, to the offset channel of the axis the marks
stand on: `xOffset` for vertical bars and boxes, `yOffset` for horizontal ones
(`direction=:x`, or a value-first mapping Vega-Lite draws horizontally). Those
are the channels `dodge_x` and `dodge_y` lower to, so `dodge` draws as they do,
and as in AoG a layer may not dodge one axis twice.
"""
function _named_encodings!(encoding::Dict, named, plot_type, mark, table; base_channel=nothing)
    dodge = nothing
    for (name, sel) in pairs(named)
        if name === :dodge && _native_dodge(plot_type)
            dodge = sel
            continue
        end
        ch = name === :fillto && !isnothing(base_channel) ? base_channel : _named_vl_channel(name, plot_type)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end
    infer_types!(encoding, table)
    isnothing(dodge) && return encoding
    ch = _vl_bar_orient(mark, encoding) == "horizontal" ? "yOffset" : "xOffset"
    if haskey(encoding, ch)
        same = Symbol[n for n in keys(named) if n !== :dodge && aog_named_to_vl_channel(n) == ch]
        other = isempty(same) ? ch : string(first(same))
        throw(ArgumentError("mapping(...): `dodge` and `$other` both dodge this $(_layer_type_name(plot_type)) layer along " *
            "$(ch[1]); use only one, as AlgebraOfGraphics requires."))
    end
    encoding[ch] = selector_to_field(dodge)
    infer_types!(encoding, table)
    encoding
end

# --- Column selector → Vega-Lite field spec ---

selector_to_field(sel::Symbol) = Dict{String,Any}("field" => string(sel))
selector_to_field(sel::Int) = Dict{String,Any}("field" => "column_$sel")
# AoG's direct scalar is data repeated for every table row, not a pixel or
# fixed mark property. A datum encoding keeps scales and survives row updates
# without adding a synthetic column to a bound or addressed table.
selector_to_field(sel::DirectData{<:Union{Number,AbstractString,Symbol,TimeType}}) =
    Dict{String,Any}("datum" => sel.data, "type" => vl_type((sel.data,)))
function selector_to_field(sel::Pair)
    src, dst = sel
    field = selector_to_field(src)
    _apply_selector_modifier!(field, dst)
    field
end
selector_to_field(sel) = Dict{String,Any}("value" => sel)

# Apply one Pair-destination modifier to a field dict. Handles string labels,
# nested labels (`=> :fn => "Label"`), and AoG scale-type modifiers like
# `nonnumeric` that must force the VL encoding `type` so downstream
# infer_types! doesn't re-derive from the column eltype.
_apply_selector_modifier!(field::Dict{String,Any}, _) = field
_apply_selector_modifier!(field::Dict{String,Any}, dst::AbstractString) = (field["title"] = dst; field)
# nonnumeric: force categorical. Without this, an Int column used for
# color ends up as quantitative, which won't merge with sibling layers
# (e.g. ECDFPlot) that hardcode nominal → dual color legends.
_apply_selector_modifier!(field::Dict{String,Any}, ::typeof(nonnumeric)) = (field["type"] = "nominal"; field)
# sorter(ks) / renamer(ks => …) → AoG `Renamer` whose `uniquevalues` is the
# explicit data-domain order. On a facet channel (row/col) this becomes a
# Vega-Lite `sort` array so the facet headers follow the requested order.
# `data_to_vl` emits raw column values (no relabeling on the VL path), so the
# sort domain must be the raw `uniquevalues`, not the display `labels`.
# A keyless `renamer([...])` has `uniquevalues === nothing` → no sort to apply.
function _apply_selector_modifier!(field::Dict{String,Any}, r::Renamer)
    r.uniquevalues !== nothing && (field["sort"] = collect(r.uniquevalues))
    field
end
function _apply_selector_modifier!(field::Dict{String,Any}, dst::Pair)
    _apply_selector_modifier!(field, first(dst))
    _apply_selector_modifier!(field, last(dst))
    field
end

_field_name(sel) = string(sel)
_field_name(sel::Pair) = string(first(sel))

# The display label is the last explicit string in a selector's modifier chain
# (`:x => "L"` OR the nested `:x => sorter(...) => "L"`), falling back to the raw
# field name when no relabel is given. The nested-`Pair` recursion is load-bearing:
# without it an analysis path reads `:x => fn => "L"` as its field name and silently
# drops "L". Plain layers avoid this by going through `_apply_selector_modifier!`.
_field_label(sel) = _field_name(sel)
function _field_label(sel::Pair)
    lbl = _selector_label(last(sel))
    isnothing(lbl) ? _field_name(sel) : lbl
end
_selector_label(x::AbstractString) = x
_selector_label(x::Pair) = _selector_label(last(x))
_selector_label(_) = nothing

# The explicit categorical order from a selector's `sorter`/`renamer` modifier
# anywhere in its `:x => mod => ...` chain, as a VL `sort` array (or `nothing`).
# Mirrors `_apply_selector_modifier!`'s `Renamer` branch so analyses that rebuild
# encodings from field names still order colour/group exactly like plain layers do.
_selector_sort(sel) = nothing
_selector_sort(r::Renamer) =
    r.uniquevalues === nothing ? nothing : collect(r.uniquevalues)
function _selector_sort(sel::Pair)
    s = _selector_sort(first(sel))
    isnothing(s) ? _selector_sort(last(sel)) : s
end

# --- Vega-Lite type inference ---

function vl_type(col)
    T = eltype(col)
    T = Base.nonmissingtype(T)
    if T <: TimeType
        "temporal"
    elseif T <: Number
        "quantitative"
    elseif T <: AbstractString || T <: Symbol
        "nominal"
    else
        "nominal"
    end
end

_infer_enc_type!(args...) = nothing
function _infer_enc_type!(enc::Dict, table)
    haskey(enc, "field") && !haskey(enc, "type") || return
    field = Symbol(enc["field"])
    if field in Tables.columnnames(table)
        enc["type"] = vl_type(Tables.getcolumn(table, field))
    end
end

function infer_types!(encoding::Dict, table)
    isnothing(table) && return encoding
    for (_, enc) in encoding
        _infer_enc_type!(enc, table)
    end
    encoding
end
