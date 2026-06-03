# --- Makie → Vega-Lite mark mapping ---

"""Makie plot type → VL mark string. Checked via `<:`, order matters for subtypes."""
_MARK_MAP = [
    Scatter => "point", Lines => "line", ScatterLines => "line",
    BarPlot => "bar", Heatmap => "rect", BoxPlot => "boxplot",
    Violin => "area", Band => "area", HLines => "rule", VLines => "rule",
    Hist => "bar", MakieDensity => "area", Errorbars => "errorbar",
    Stairs => "line", ECDFPlot => "line", Contour => "rect",
    Rangebars => "errorbar", CrossBar => "errorbar", Makie.Text => "text",
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
    ScatterLines => Dict{String,Any}("point" => true, "filled" => true),
    Stairs => Dict{String,Any}("interpolate" => "step-after"),
]

function plottype_to_mark_props(T::Type)
    for (PT, props) in _MARK_PROPS
        T <: PT && return props
    end
    Dict{String,Any}()
end

_COMPOSITE_MARKS = Set(["boxplot", "errorbar", "errorband"])

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

# --- Column selector → Vega-Lite field spec ---

selector_to_field(sel::Symbol) = Dict{String,Any}("field" => string(sel))
selector_to_field(sel::Int) = Dict{String,Any}("field" => "column_$sel")
function selector_to_field(sel::Pair)
    src, dst = sel
    field = selector_to_field(src)
    _apply_selector_modifier!(field, dst)
    field
end
selector_to_field(sel) = Dict{String,Any}("value" => sel)  # DirectData, Presorted, etc.

# Apply one Pair-destination modifier to a field dict. Handles string labels,
# nested labels (`=> :fn => "Label"`), and AoG scale-type modifiers like
# `nonnumeric` that must force the VL encoding `type` so downstream
# infer_types! doesn't re-derive from the column eltype.
_apply_selector_modifier!(field::Dict{String,Any}, _) = field
_apply_selector_modifier!(field::Dict{String,Any}, dst::AbstractString) = (field["title"] = dst; field)
# nonnumeric: force categorical. Without this, an Int column used for
# color ends up as quantitative, which won't merge with sibling layers
# (e.g. ECDFPlot) that hardcode nominal → dual color legends.
_apply_selector_modifier!(field::Dict{String,Any}, ::typeof(AlgebraOfGraphics.nonnumeric)) = (field["type"] = "nominal"; field)
# sorter(ks) / renamer(ks => …) → AoG `Renamer` whose `uniquevalues` is the
# explicit data-domain order. On a facet channel (row/col) this becomes a
# Vega-Lite `sort` array so the facet headers follow the requested order.
# `data_to_vl` emits raw column values (no relabeling on the VL path), so the
# sort domain must be the raw `uniquevalues`, not the display `labels`.
# A keyless `renamer([...])` has `uniquevalues === nothing` → no sort to apply.
function _apply_selector_modifier!(field::Dict{String,Any}, r::AlgebraOfGraphics.Renamer)
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
_field_label(sel) = _field_name(sel)
_field_label(sel::Pair{<:Any,<:AbstractString}) = last(sel)

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
