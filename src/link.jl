# --- Link groups: config(link=(; group, key)) ---
#
# Plots and tables that show the same items join a named link group, and
# hovering one item in any member highlights it in the others. The lowering is
# metadata only, `_aov.link = {group, key}`; the runtime (`vendor/aov-runtime.js`,
# `_link`/`_announce`/`_watchLinks`) announces a hovered mark's key on
# `document` as an `htmxo:link` event and highlights the marks whose `key`
# field is one of the keys another member announces (one item's, or every
# member's of a table's group row). The event contract is shared with
# HTMXObjects' tables, so neither package calls the other.

"""Link-group options parsed from `config(link=…)`."""
struct LinkOptions
    group::String
    key::String
end

const _LINK_KEYS = (:group, :key)

_link_options(o::LinkOptions) = o
function _link_options(nt::NamedTuple)
    unknown = [k for k in keys(nt) if k ∉ _LINK_KEYS]
    isempty(unknown) || throw(ArgumentError(
        "config(link=…): unknown option$(length(unknown) > 1 ? "s" : "") $(join(repr.(unknown), ", ")); the options are $(join(_LINK_KEYS, ", "))."))
    all(k -> haskey(nt, k), _LINK_KEYS) || throw(ArgumentError(
        "config(link=…) needs the group name and the key column, e.g. `config(link=(; group=\"probes\", key=:kenn))`."))
    nt.group isa Union{Symbol,AbstractString} && !isempty(string(nt.group)) || throw(ArgumentError(
        "config(link=…): `group` names the link group, a non-empty string; got $(repr(nt.group))."))
    nt.key isa Union{Symbol,AbstractString} && !isempty(string(nt.key)) || throw(ArgumentError(
        "config(link=…): `key` is the column whose value identifies an item, e.g. `key=:kenn`; got $(repr(nt.key))."))
    LinkOptions(string(nt.group), string(nt.key))
end
_link_options(x) = throw(ArgumentError(
    "config(link=…) takes a NamedTuple naming the group and the key column, " *
    "e.g. `config(link=(; group=\"probes\", key=:kenn))`; got $(repr(x))."))

"""
    _apply_link!(spec, drawable, opts::LinkOptions) -> spec

Record the plot's link group under `_aov.link`. At least one layer's table must
have the key column; a layer without it (a base map) takes part in no link.
"""
function _apply_link!(spec::Dict, drawable, opts::LinkOptions)
    any(l -> !isnothing(_frame_table(l, opts.key)), _frame_layers(drawable)) || throw(ArgumentError(
        "config(link=(; group=$(repr(opts.group)), key=:$(opts.key))): no layer's table has a `$(opts.key)` column. " *
        "`key` names the column whose value identifies an item, the same value the other members of the group key their items by."))
    link = Dict{String,Any}("group" => opts.group, "key" => opts.key)
    kind = _link_temporal(drawable, opts.key)
    isnothing(kind) || (link["temporal"] = kind)
    get!(spec, "_aov", Dict{String,Any}())["link"] = link
    spec
end

# Whether the key column holds dates ("date") or date-times ("datetime"):
# Vega holds such a field as epoch milliseconds, so the runtime writes it back
# as Julia writes the value (`string(x)`, what a table keys its rows by)
# before comparing it with another member's key. `nothing` for other keys.
function _link_temporal(drawable, key::String)
    for l in _frame_layers(drawable)
        t = _frame_table(l, key)
        isnothing(t) && continue
        T = Base.nonmissingtype(eltype(Tables.getcolumn(t, Symbol(key))))
        T <: Dates.Date && return "date"
        T <: TimeType && return "datetime"
    end
    nothing
end

# --- Readout: config(readout=…) ---
#
# A figure with a line or area layer on a continuous x gets a readout in the
# browser: a rule at the nearest x under the pointer and one box listing
# every series' value there (`_readoutPlan` and friends in
# vendor/aov-runtime.js). `readout=false` turns it off, `readout=true` gives
# one to any figure with a continuous x. The lowering is `_aov.readout`.
_readout_option(b::Bool) = b
_readout_option(x) = throw(ArgumentError(
    "config(readout=…) is `true` (a readout for any figure with a continuous x) or `false` (none); got $(repr(x))."))

# --- Legend zoom: config(legend_zoom=true) ---
#
# Opt-in: selecting entries of a categorical colour legend also zooms each
# panel's continuous x and y axes to the marks of the selected entries
# (`_legendZoom*` in vendor/aov-runtime.js); clearing the selection brings
# back the full view. Off (the default), a legend selection only dims, and
# the spec is unchanged. The lowering is `_aov.legendZoom = true`.
_legend_zoom_option(b::Bool) = b
_legend_zoom_option(x) = throw(ArgumentError(
    "config(legend_zoom=…) is `true` (selecting colour legend entries zooms each panel's axes to their marks) or `false` (the default: a selection only dims); got $(repr(x))."))
