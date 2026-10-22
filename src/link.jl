# --- Link groups: config(link=(; group, key)) ---
#
# Plots and tables that show the same items join a named link group, and
# hovering one item in any member highlights it in the others. The lowering is
# metadata only, `_aov.link = {group, key}`; the runtime (`vendor/aov-runtime.js`,
# `_link`/`_announce`/`_watchLinks`) announces a hovered mark's key on
# `document` as an `htmxo:link` event and highlights the marks whose `key`
# field equals a key another member announces. The event contract is shared
# with HTMXObjects' tables, so neither package calls the other.

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
    get!(spec, "_aov", Dict{String,Any}())["link"] =
        Dict{String,Any}("group" => opts.group, "key" => opts.key)
    spec
end
