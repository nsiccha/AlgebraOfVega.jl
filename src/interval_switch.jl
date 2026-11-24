# --- The "Show intervals" switch (`_aov.intervals`) ---
#
# Every figure that draws interval marks beside other marks offers the reader
# a pressed/unpressed "Show intervals" button, shown by default (principle
# `stack-ux-default`; Bruno decision `0whc4na`, todo `0no7hcn`). Turning it off
# hides only the interval marks, and an axis whose range they set refits to the
# marks still drawn.
#
# The interval units are tagged `_aovInterval` where they are made:
# - plain `Rangebars`, `Errorbars` and `Band` layers (`_apply_layer_intervals!`,
#   beside the other layer-wide passes);
# - the rules of `pointinterval`, `pointinterval(bands=…)`, `gradient_interval`
#   and `dotinterval` (so also the Intervals drawing of a ribbon), a ribbon's
#   bands and single-x glyph rules, and the `interval=` bands of `linear()` and
#   `smooth()` (src/analysis_to_vl.jl).
# `_apply_interval_switch!`, a finish pass on both drawings of a ribbon, marks
# a figure `_aov.intervals = true` when it has tagged units and at least one
# other drawn mark. The runtime (`_withIntervals` and friends in
# vendor/aov-runtime.js) adds a top-level `aov_intervals` param and a filter on
# each tagged unit to the copy it embeds, so the button only sets a signal:
# zoom, legend selection and the rest of the view stay. `vsave`, `sdraw` and
# report images draw every interval.
const _AOV_INTERVAL = "_aovInterval"

_interval_plot(layer) = (vis = extract_visual(layer);
    !isnothing(vis) && vis.plottype <: Union{Errorbars, Rangebars, Band} && isnothing(_layer_handler(layer)))
function _apply_layer_intervals!(units::AbstractVector, layers::AbstractVector)
    for (us, layer) in zip(units, layers)
        _interval_plot(layer) && foreach(_tag_interval!, us)
    end
end
# Tag every unit (a node with a mark) of a lowered layer.
_tag_interval!(x) = x
_tag_interval!(v::AbstractVector) = (foreach(_tag_interval!, v); v)
function _tag_interval!(d::AbstractDict)
    haskey(d, "mark") && (d[_AOV_INTERVAL] = true)
    for k in ("layer", "spec", "hconcat", "vconcat", "concat")
        haskey(d, k) && _tag_interval!(d[k])
    end
    d
end

# The number of interval units and of other drawn units in a lowered spec. A
# helper unit that never draws (a sparse facet's bounds sublayer, opacity 0)
# is neither.
function _interval_unit_counts(spec)
    n = Ref(0); others = Ref(0)
    function walk(x)
        x isa AbstractVector && return foreach(walk, x)
        x isa AbstractDict || return
        if haskey(x, "mark")
            if get(x, _AOV_INTERVAL, false) === true
                n[] += 1
            elseif !_never_drawn(x)
                others[] += 1
            end
        end
        for k in ("layer", "spec", "hconcat", "vconcat", "concat")
            haskey(x, k) && walk(x[k])
        end
    end
    walk(spec)
    (; intervals=n[], others=others[])
end
_never_drawn(unit) = (op = get(get(unit, "encoding", Dict()), "opacity", nothing);
    op isa AbstractDict && get(op, "value", nothing) == 0 &&
        (!haskey(op, "condition") || get(op["condition"], "value", nothing) == 0))

function _apply_interval_switch!(spec::AbstractDict)
    c = _interval_unit_counts(spec)
    c.intervals > 0 && c.others > 0 && (get!(spec, "_aov", Dict{String,Any}())["intervals"] = true)
    spec
end
_apply_interval_switch!(spec) = spec

"""
    intervals_switch(spec[, scales]; auto_remap=nothing) -> (; offered, why_not)

Whether the browser draws `spec` with a "Show intervals" switch, the pressed
button that hides and shows its interval marks: `Rangebars`, `Errorbars`,
`Band`, the rules of `pointinterval`, `gradient_interval` and `dotinterval`,
the bands of `lineribbon`/`ribbon` (in both drawings of its Ribbons | Intervals
switch) and the `interval=` bands of `linear()`/`smooth()`. It is offered,
shown, on every figure that draws such marks beside other marks.

`why_not` is `nothing` when it is offered, else `:no_intervals` (no interval
marks) or `:only_intervals` (nothing would be left to show). Pass the same
`scales` and `auto_remap` options as to `vdraw`/`auto_remap_node`.
"""
function intervals_switch(spec, sc...; auto_remap::Union{Nothing,NamedTuple}=nothing)
    vl = to_vegalite(spec, sc...; auto_remap)
    get(get(vl, "_aov", Dict()), "intervals", false) === true && return (; offered=true, why_not=nothing)
    c = _interval_unit_counts(vl)
    (; offered=false, why_not=c.intervals == 0 ? :no_intervals : :only_intervals)
end
