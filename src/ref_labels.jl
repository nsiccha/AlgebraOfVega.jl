# --- Labels of reference lines and periods: `mapping(:t; text=:name) * visual(VLines)` ---
#
# A reference line or period (an issue time, a forecast window, a threshold)
# names itself through AoG's `text` mapping on its own layer:
#
#     data(events) * mapping(:t; text=:name) * visual(VLines; linestyle=:dash)
#     data(periods) * mapping(:from, :to; text=:name) * visual(VSpan; alpha=0.1)
#     data(limits) * mapping(:level; text=:name) * visual(HLines)
#
# The label of a vertical reference (VLines, VSpan) stands just above the plot
# area at its line (a span's start), left-aligned. Labels close together go into
# rows, as AP4's results page stacks them, so they never overprint: the runtime
# measures the drawn labels and gives each the first row where it clears the
# label before it (`_layoutRefLabels`, vendor/aov-runtime.js), through the
# `aov_ref_rows` parameter the labels' height reads. A label whose line is zoomed
# out of view is hidden. A horizontal reference (HLines, HSpan) is labelled at
# the plot's right end, just above its line. Labels let the pointer through
# (`aov-passive`) and take the line's colour, or the page ink.
#
# Makie's `vlines`/`vspan` have no text, so `sdraw` leaves these labels out, with
# a warning (src/sdraw.jl).

const _REF_ROWS_PARAM = "aov_ref_rows"
const _REF_ROW_HEIGHT = 14
const _REF_KEY = "__aov_ref_key"
const _REF_Y = "__aov_ref_y"

_apply_ref_labels!(spec) = spec
function _apply_ref_labels!(spec::Dict)
    found = Ref(false)
    _ref_label_node!(spec, found)
    if found[]
        params = get!(spec, "params", Any[])
        any(p -> p isa AbstractDict && get(p, "name", nothing) == _REF_ROWS_PARAM, params) ||
            push!(params, Dict{String,Any}("name" => _REF_ROWS_PARAM, "value" => Dict{String,Any}()))
    end
    spec
end

# The kind of reference a unit draws, with the channel its label stands on:
# `(:vertical, "x")` for a VLines rule or a VSpan rect, `(:horizontal, "y")` for
# HLines/HSpan; `nothing` for any other unit or one without a `text` field.
function _ref_kind(unit::AbstractDict)
    enc = get(unit, "encoding", nothing)
    enc isa AbstractDict || return nothing
    text = get(enc, "text", nothing)
    text isa AbstractDict && haskey(text, "field") || return nothing
    t = _mark_type(get(unit, "mark", nothing))
    has(ch) = get(enc, ch, nothing) isa AbstractDict && haskey(enc[ch], "field")
    if t == "rule"
        has("x") && !has("y") && return (:vertical, "x")
        has("y") && !has("x") && return (:horizontal, "y")
    elseif t == "rect"
        has("x") && has("x2") && !has("y") && return (:vertical, "x")
        has("y") && has("y2") && !has("x") && return (:horizontal, "y")
    end
    nothing
end

function _ref_label_node!(node::Dict, found)
    sub = get(node, "layer", nothing)
    if sub isa AbstractVector
        out = Any[]
        for u in sub
            push!(out, u)
            u isa Dict || continue
            if haskey(u, "mark")
                label = _ref_label_unit!(u)
                isnothing(label) || (push!(out, label); found[] = true)
            else
                _ref_label_node!(u, found)
            end
        end
        node["layer"] = out
    elseif haskey(node, "mark") && !isnothing(_ref_kind(node))
        # A figure of one reference layer: its unit becomes the first of two layers.
        unit = Dict{String,Any}(k => pop!(node, k) for k in ("mark", "encoding", "transform", "params") if haskey(node, k))
        label = _ref_label_unit!(unit)
        node["layer"] = Any[unit, label]
        found[] = true
    end
    inner = get(node, "spec", nothing)
    inner isa Dict && _ref_label_node!(inner, found)
    for key in ("hconcat", "vconcat", "concat")
        subs = get(node, key, nothing)
        subs isa AbstractVector && foreach(s -> s isa Dict && _ref_label_node!(s, found), subs)
    end
    nothing
end

# The label unit of reference unit `u` (its `text` channel moves there), or
# `nothing` when `u` draws no labelled reference.
function _ref_label_unit!(u::Dict)
    kind = _ref_kind(u)
    isnothing(kind) && return nothing
    dir, ch = kind
    enc = u["encoding"]
    text = pop!(enc, "text")
    mark = get(u, "mark", nothing)
    m = mark isa AbstractDict ? mark : Dict{String,Any}()
    styles = String["aov-passive", "aov-ref-label"]
    haskey(m, "style") && _AOV_INK in _style_list(m["style"]) && pushfirst!(styles, _AOV_INK)
    label_mark = Dict{String,Any}("type" => "text", "fontSize" => 11, "clip" => false, "style" => styles)
    c = get(m, "color", nothing)
    c isa AbstractString && (label_mark["color"] = c)
    transform = Any[deepcopy(t) for t in get(u, "transform", Any[])]
    at = deepcopy(enc[ch])
    delete!(at, "axis")
    label_enc = Dict{String,Any}("text" => text, ch => at)
    if dir === :vertical
        f = "datum[" * _vl_json(at["field"]) * "]"
        n = "datum[" * _vl_json(text["field"]) * "]"
        row = "$(_REF_ROWS_PARAM)[datum.$(_REF_KEY)]"
        push!(transform,
            Dict{String,Any}("calculate" => "$f + '|' + $n", "as" => _REF_KEY),
            Dict{String,Any}("calculate" => "-4 - $(_REF_ROW_HEIGHT) * max(0, isValid($row) ? $row : 0)", "as" => _REF_Y))
        label_enc["y"] = Dict{String,Any}("field" => _REF_Y, "type" => "quantitative", "scale" => nothing, "axis" => nothing)
        # A label whose line is zoomed out of view (row -1) is hidden.
        label_enc["opacity"] = Dict{String,Any}("condition" => Dict{String,Any}(
            "test" => "$row === -1", "value" => 0), "value" => 1)
        merge!(label_mark, Dict{String,Any}("align" => "left", "baseline" => "bottom", "dx" => 3))
    else
        label_enc["x"] = Dict{String,Any}("value" => Dict{String,Any}("expr" => "width"))
        merge!(label_mark, Dict{String,Any}("align" => "right", "baseline" => "bottom", "dx" => -3, "dy" => -2))
    end
    label = Dict{String,Any}("mark" => label_mark, "encoding" => label_enc)
    haskey(u, "data") && (label["data"] = u["data"])
    isempty(transform) || (label["transform"] = transform)
    label
end
