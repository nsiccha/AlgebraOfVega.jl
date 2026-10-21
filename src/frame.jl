# --- Frame animation: config(frame=…) ---
#
# `config(frame=:year)` shows one frame (one value of the column) at a time,
# with a ▶/⏸ button and a slider the runtime draws next to the plot
# (`vendor/aov-runtime.js`, `_frame*`). The lowering here is data-only: a
# Vega-Lite variable parameter `aov_frame` holding the current frame value, a
# filter on every unit, and the frame list + player options under
# `_aov.frame`. Fixed scales across frames are the runtime's job: it runs the
# compiled view once per frame and pins every data-driven scale domain (and a
# map's projection fit) to the union, which holds for any mark Vega-Lite
# draws (stacked bars, VL density/regression transforms included).

const _FRAME_PARAM = "aov_frame"

"""Player options parsed from `config(frame=…)`."""
struct FrameOptions
    field::String
    order::Union{Nothing,Vector{Any}}   # a `sorter(…)` order of the frames
    interval::Float64   # seconds per frame
    loop::Bool
    start::Any          # a frame value, `:first` or `:last`
end

const _FRAME_KEYS = (:field, :interval, :loop, :start)

_frame_options(o::FrameOptions) = o
_frame_options(field::Union{Symbol,AbstractString,Pair}) = _frame_options((; field))
function _frame_options(nt::NamedTuple)
    unknown = [k for k in keys(nt) if k ∉ _FRAME_KEYS]
    isempty(unknown) || throw(ArgumentError(
        "config(frame=…): unknown option$(length(unknown) > 1 ? "s" : "") $(join(repr.(unknown), ", ")); the options are $(join(_FRAME_KEYS, ", "))."))
    haskey(nt, :field) || throw(ArgumentError(
        "config(frame=(; …)) needs the frame column as `field`, e.g. `config(frame=(; field=:year))`."))
    field = nt.field
    _frame_selector_ok(field) || throw(ArgumentError(
        "config(frame=…): `field` is a column name, optionally with a frame order " *
        "(`:month => sorter(\"Jan\", \"Feb\", …)`); got $(repr(field))."))
    interval = get(nt, :interval, 0.5)
    interval isa Real && isfinite(interval) && interval > 0 || throw(ArgumentError(
        "config(frame=…): `interval` is the seconds each frame shows, a positive number; got $(repr(interval))."))
    loop = get(nt, :loop, false)
    loop isa Bool || throw(ArgumentError("config(frame=…): `loop` is `true` or `false`; got $(repr(loop))."))
    order = _selector_sort(field)
    FrameOptions(_field_name(field), isnothing(order) ? nothing : Vector{Any}(order),
        Float64(interval), loop, get(nt, :start, :first))
end

_frame_selector_ok(::Union{Symbol,AbstractString}) = true
_frame_selector_ok(p::Pair) = first(p) isa Union{Symbol,AbstractString} && !isnothing(_selector_sort(p))
_frame_selector_ok(_) = false
_frame_options(x) = throw(ArgumentError(
    "config(frame=…) takes the frame column (`config(frame=:year)`) or a NamedTuple " *
    "(`config(frame=(; field=:year, interval=0.5, loop=false, start=:first))`); got $(repr(x))."))

_frame_layers(l::AlgebraOfGraphics.Layer) = [l]
_frame_layers(ls::AlgebraOfGraphics.Layers) = ls.layers

_frame_table(layer, field::String) = let t = extract_data(layer)
    !isnothing(t) && Symbol(field) in Tables.columnnames(t) ? t : nothing
end

# Layers whose marks AoV computes in Julia from the table's rows: their rows
# carry no frame value, so the frame filter cannot pick a frame's marks out of
# them. `nothing` for every layer whose rows reach Vega-Lite as they are
# (plain marks, geoshape maps, the `bands=` summaries, VL-transform analyses).
_frame_unsupported(layer) = _frame_unsupported(_layer_handler(layer), layer)
_frame_unsupported(::Any, layer) = nothing
_frame_unsupported(::TidybayesAnalysis, layer) = "an interval/ribbon summary computed from raw draws"
_frame_unsupported(::Union{PrecomputedRibbonAnalysis,PrecomputedIntervalAnalysis}, layer) = nothing
_frame_unsupported(::AlgebraOfGraphics.DensityAnalysis, layer) =
    haskey(layer.named, :y) || !isempty(first(_extract_facet_info(layer))) ?
        "a faceted or ridgeline density() (computed in Julia)" : nothing

_frame_value_missing(v) = ismissing(v) || isnothing(v)
_frame_value_missing(v::Number) = !isfinite(v)

function _frame_values(layers, field::String, order)
    vals = Any[]
    found = false
    for l in layers
        t = _frame_table(l, field)
        isnothing(t) && continue
        found = true
        for v in Tables.getcolumn(t, Symbol(field))
            _frame_value_missing(v) || push!(vals, v)
        end
    end
    if !found
        cols = unique!(reduce(vcat, (collect(string.(Tables.columnnames(t)))
            for t in (extract_data(l) for l in layers) if !isnothing(t)); init=String[]))
        throw(ArgumentError("config(frame=:$field): no layer's data has a column \"$field\" (columns: $(join(cols, ", ")))."))
    end
    isempty(vals) && throw(ArgumentError(
        "config(frame=:$field): the \"$field\" column holds no values, so there is no frame to show."))
    present = unique(vals)
    isnothing(order) && return sort!(present)
    unlisted = [v for v in present if !any(isequal(v), order)]
    isempty(unlisted) || throw(ArgumentError(
        "config(frame=:$field => sorter(…)): the sorter does not list $(join(repr.(first(unlisted, 5)), ", "))$(length(unlisted) > 5 ? ", …" : ""), which the \"$field\" column holds."))
    Any[v for v in order if any(isequal(v), present)]
end

_frame_start(vals, s::Symbol) =
    s === :first ? 0 : s === :last ? length(vals) - 1 : _frame_start_value(vals, s)
_frame_start(vals, s) = _frame_start_value(vals, s)
function _frame_start_value(vals, s)
    i = findfirst(isequal(s), vals)
    isnothing(i) && throw(ArgumentError(
        "config(frame=…): `start` is `:first`, `:last` or one of the frames; $(repr(s)) is not a frame (frames: $(join(repr.(first(vals, 5)), ", "))$(length(vals) > 5 ? ", …" : ""))."))
    i - 1
end

# Every primitive unit of a lowered spec (a node with a mark and no children).
function _each_frame_unit(f, node::AbstractDict)
    children = Any[]
    haskey(node, "spec") && push!(children, node["spec"])
    for key in ("layer", "hconcat", "vconcat", "concat")
        append!(children, something(_as_vec(get(node, key, nothing)), Any[]))
    end
    if isempty(children)
        haskey(node, "mark") && f(node)
    else
        foreach(c -> _each_frame_unit(f, c), children)
    end
    node
end

"""
    _apply_frame!(spec, drawable, opts::FrameOptions) -> spec

Lower `config(frame=…)` onto the finished Vega-Lite `spec`: the `aov_frame`
parameter (the current frame value), a filter first in every unit's
transforms, and `_aov.frame` for the runtime player. A row whose frame value is
missing, and a layer without the frame column (a base map, a reference line),
pass the filter, so they are drawn in every frame. Runs last in
`to_vegalite(::VegaSpec)`, after every lowering that copies units, so each copy
carries the filter, and after automatic interactivity, which a parameter would
otherwise switch off.
"""
function _apply_frame!(spec::Dict, drawable, opts::FrameOptions)
    layers = _frame_layers(drawable)
    for l in layers
        isnothing(_frame_table(l, opts.field)) && continue
        what = _frame_unsupported(l)
        isnothing(what) || throw(ArgumentError(
            "config(frame=:$(opts.field)): one layer is $what, whose marks AoV computes in Julia and " *
            "which therefore carry no $(opts.field) to step through. Summarise per $(opts.field) yourself " *
            "and draw the summary with the `bands=` form (`lineribbon(bands=…)`, `pointinterval(bands=…)`), " *
            "or drop the $(opts.field) column from that layer's table to show it in every frame."))
    end
    vals = _frame_values(layers, opts.field, opts.order)
    temporal = all(v -> v isa TimeType, vals)
    start = _frame_start(vals, opts.start)
    f = _vl_json(opts.field)
    test = temporal ? "time(datum[$f]) === time($_FRAME_PARAM)" : "datum[$f] === $_FRAME_PARAM"
    filter = "!isValid(datum[$f]) || $test"
    _each_frame_unit(spec) do unit
        rest = something(_as_vec(get(unit, "transform", nothing)), Any[])
        unit["transform"] = Any[Dict{String,Any}("filter" => filter); rest...]
    end
    wire = Any[_vl_safe(v) for v in vals]
    params = something(_as_vec(get(spec, "params", nothing)), Any[])
    spec["params"] = Any[params...; Dict{String,Any}("name" => _FRAME_PARAM, "value" => wire[start + 1])]
    aov = get!(spec, "_aov", Dict{String,Any}())
    aov["frame"] = Dict{String,Any}("field" => opts.field, "values" => wire,
        "temporal" => temporal, "interval" => round(Int, 1000 * opts.interval),
        "loop" => opts.loop, "start" => start)
    spec
end
