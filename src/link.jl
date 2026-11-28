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
#
# `on=:click` (snag `click-a-map-key-a85f71a9`, design decision `0n1b5vy`)
# also makes a click or long press on a mark SELECT its key for the group: a
# sticky selection, kept per group by the runtime (`AoV.select`, an
# `aov:select` event on `document`), which the figures declared with
# `config(select=(; field, group))` follow (below). Hovering still dims as
# before. `address=false` keeps the selection out of the page address.

"""Link-group options parsed from `config(link=…)`."""
struct LinkOptions
    group::String
    key::String
    on::Symbol        # :hover (the default) or :click
    address::Bool     # with on=:click: the selection is kept in the page address
end
LinkOptions(group::String, key::String) = LinkOptions(group, key, :hover, true)

const _LINK_KEYS = (:group, :key, :on, :address)
const _LINK_REQUIRED = (:group, :key)

_link_options(o::LinkOptions) = o
function _link_options(nt::NamedTuple)
    unknown = [k for k in keys(nt) if k ∉ _LINK_KEYS]
    isempty(unknown) || throw(ArgumentError(
        "config(link=…): unknown option$(length(unknown) > 1 ? "s" : "") $(join(repr.(unknown), ", ")); the options are $(join(_LINK_KEYS, ", "))."))
    all(k -> haskey(nt, k), _LINK_REQUIRED) || throw(ArgumentError(
        "config(link=…) needs the group name and the key column, e.g. `config(link=(; group=\"probes\", key=:kenn))`."))
    nt.group isa Union{Symbol,AbstractString} && !isempty(string(nt.group)) || throw(ArgumentError(
        "config(link=…): `group` names the link group, a non-empty string; got $(repr(nt.group))."))
    nt.key isa Union{Symbol,AbstractString} && !isempty(string(nt.key)) || throw(ArgumentError(
        "config(link=…): `key` is the column whose value identifies an item, e.g. `key=:kenn`; got $(repr(nt.key))."))
    on = get(nt, :on, :hover)
    on in (:hover, :click) || throw(ArgumentError(
        "config(link=…): `on` is `:hover` (the default: hovering an item highlights it in the group) or `:click` " *
        "(a click or long press also selects its key for the figures that follow the group with `config(select=(; field, group))`); got $(repr(on))."))
    address = get(nt, :address, true)
    address isa Bool || throw(ArgumentError(
        "config(link=…): `address` is `true` (the default: the selection is kept in the page address) or `false`; got $(repr(address))."))
    !address && on !== :click && throw(ArgumentError(
        "config(link=…): `address=false` keeps a click selection out of the page address, so it needs `on=:click`."))
    LinkOptions(string(nt.group), string(nt.key), on, address)
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
    if opts.on === :click
        link["on"] = "click"
        opts.address || (link["address"] = false)
    end
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

# --- Following a click selection: config(select=(; field, group, initial)) ---
#
# A figure that follows link group `group` draws only the rows whose `field`
# is one of the keys a click selected there (`config(link=(; …, on=:click))`
# on the map), or `initial` until a click. `config(select=:field)` (a
# dropdown, `add_select_filters!`) filters the same way; this form takes the
# value from the group instead. The lowering is a Vega-Lite variable
# parameter `aov_select` (the selected keys, as text) and a filter first in
# every unit's transforms, as `config(frame=…)` lowers: the runtime sets the
# parameter on the live view (`AoV.select`, `_showSelect`), so a selection is
# no re-embed and the scales nobody pinned refit to the shown rows. Rows
# without the field (a reference line's table) pass the filter. With a
# `by_url(rows, "…/{field}.json")` address the page carries only the initial
# keys' rows, and the runtime fetches each selected key's rows from its
# address (`_aov.select.keyed`).

const _SELECT_PARAM = "aov_select"

"""Options parsed from `config(select=(; field, group, initial))`."""
struct SelectGroupOptions
    field::String
    group::String
    initial::Vector{String}
end

const _SELECT_GROUP_KEYS = (:field, :group, :initial)

# `config(select=…)`: a column or columns keep their dropdown meaning
# (`add_select_filters!`); a NamedTuple follows a link group's click selection.
_select_option(o::SelectGroupOptions) = o
_select_option(x) = x
function _select_option(nt::NamedTuple)
    unknown = [k for k in keys(nt) if k ∉ _SELECT_GROUP_KEYS]
    isempty(unknown) || throw(ArgumentError(
        "config(select=(; …)): unknown option$(length(unknown) > 1 ? "s" : "") $(join(repr.(unknown), ", ")); the options are $(join(_SELECT_GROUP_KEYS, ", "))."))
    haskey(nt, :field) && haskey(nt, :group) || throw(ArgumentError(
        "config(select=(; …)) follows a link group's click selection and needs the key column and the group, " *
        "e.g. `config(select=(; field=:cell, group=\"cells\", initial=\"A1\"))`; for a dropdown write `config(select=:field)`."))
    nt.field isa Union{Symbol,AbstractString} && !isempty(string(nt.field)) || throw(ArgumentError(
        "config(select=(; …)): `field` is the column whose value a click selects, e.g. `field=:cell`; got $(repr(nt.field))."))
    nt.group isa Union{Symbol,AbstractString} && !isempty(string(nt.group)) || throw(ArgumentError(
        "config(select=(; …)): `group` names the link group whose clicks the figure follows, a non-empty string; got $(repr(nt.group))."))
    initial = get(nt, :initial, nothing)
    vals = initial === nothing ? Any[] : initial isa AbstractVector ? collect(Any, initial) : Any[initial]
    SelectGroupOptions(string(nt.field), string(nt.group), String[_select_initial_text(v) for v in vals])
end
_select_initial_text(v::AbstractString) = String(v)
_select_initial_text(v::Union{Symbol,Integer}) = string(v)
_select_initial_text(v) = throw(ArgumentError(
    "config(select=(; …)): `initial` names keys as strings or integers (or a vector of them); got $(repr(v))."))

# A key as the selection compares it: its text, as Vega's `toString` writes it.
_select_key_text(v::AbstractString) = String(v)
_select_key_text(v) = string(v)

"""
    _apply_select_group!(spec, drawable, opts::SelectGroupOptions) -> spec

Lower `config(select=(; field, group, initial))` onto the finished spec: the
`aov_select` parameter, seeded with `initial`, a filter first in every unit,
and `_aov.select` for the runtime. Runs last in `to_vegalite(::VegaSpec)`, as
`_apply_frame!` does, so every unit copy carries the filter and the parameter
does not switch off AoV's automatic interactivity.
"""
function _apply_select_group!(spec::Dict, drawable, opts::SelectGroupOptions)
    field, layers = opts.field, _frame_layers(drawable)
    what = "config(select=(; field=:$field, group=$(repr(opts.group))))"
    tables = [t for t in (_frame_table(l, field) for l in layers) if !isnothing(t)]
    isempty(tables) && throw(ArgumentError(
        "$what: no layer's table has a `$field` column. `field` names the column whose value a click on the " *
        "group's map selects, the same value the map's `config(link=(; group, key, on=:click))` keys its items by."))
    for l in layers
        isnothing(_frame_table(l, field)) && continue
        why = _frame_unsupported(l)
        isnothing(why) || throw(ArgumentError(
            "$what: one layer is $why, whose marks AoV computes in Julia and which therefore carry no $field " *
            "to select by. Summarise per $field yourself and draw the summary with the `bands=` form " *
            "(`lineribbon(bands=…)`, `pointinterval(bands=…)`), or drop the $field column from that layer's table to draw it for every key."))
    end
    for t in tables
        T = Base.nonmissingtype(eltype(Tables.getcolumn(t, Symbol(field))))
        T <: Union{AbstractFloat,TimeType} && throw(ArgumentError(
            "$what: a selection compares keys as text, so the `$field` column holds strings or integers; it holds $T."))
    end
    f = _vl_json(field)
    filter = "!isValid(datum[$f]) || indexof($_SELECT_PARAM, toString(datum[$f])) >= 0"
    _each_frame_unit(spec) do unit
        rest = something(_as_vec(get(unit, "transform", nothing)), Any[])
        unit["transform"] = Any[Dict{String,Any}("filter" => filter); rest...]
    end
    params = something(_as_vec(get(spec, "params", nothing)), Any[])
    spec["params"] = Any[params...; Dict{String,Any}("name" => _SELECT_PARAM, "value" => copy(opts.initial))]
    sel = Dict{String,Any}("field" => field, "group" => opts.group, "initial" => copy(opts.initial),
        "param" => _SELECT_PARAM)
    keyed = _keyed_by_url!(spec, layers, opts)
    isempty(keyed) || (sel["keyed"] = keyed)
    get!(spec, "_aov", Dict{String,Any}())["select"] = sel
    spec
end

# The `{name}` placeholders of a `by_url` address.
_url_placeholders(url::AbstractString) = [m.captures[1] for m in eachmatch(r"\{([A-Za-z_][A-Za-z0-9_]*)\}", url)]

# Every data object of a `by_url` table whose address names `{field}`: in
# place of the address, the rows of the initial keys under a dataset name of
# its own (`aov_keyed_<i>`), and one `{dataset, url}` entry per place for the
# runtime, which swaps in the rows each selected key's address answers. While
# rows are written inline (`vsave`, report images) the data is all rows,
# which the parameter filters, so nothing is replaced.
function _keyed_by_url!(spec::Dict, layers, opts::SelectGroupOptions)
    _rows_inline() && return Any[]
    addressed = Dict{String,Any}()
    for l in layers
        t = extract_data(l)
        _is_by_url(t) && opts.field in _url_placeholders(_by_url_address(t)) || continue
        addressed[_by_url_address(t)] = t
    end
    keyed = Any[]
    isempty(addressed) && return keyed
    rows = Dict(url => data_to_vl(_rows_with_keys(_by_url_columns(t), opts.field, opts.initial))["values"]
                for (url, t) in addressed)
    function walk(node)
        if node isa AbstractDict
            url = get(node, "url", nothing)
            if url isa AbstractString && haskey(addressed, url)
                name = "aov_keyed_$(length(keyed) + 1)"
                empty!(node)
                node["name"] = name
                node["values"] = deepcopy(rows[url])
                push!(keyed, Dict{String,Any}("dataset" => name, "url" => String(url)))
                return
            end
            for (k, v) in node
                k == "_aov" || walk(v)
            end
        elseif node isa AbstractVector
            foreach(walk, node)
        end
    end
    walk(spec)
    keyed
end

# The columns of the rows whose `field` is one of `keys` (as text).
function _rows_with_keys(cols, field::String, keys::Vector{String})
    col = Tables.getcolumn(cols, Symbol(field))
    want = Set(keys)
    idx = [i for i in eachindex(col) if !_frame_value_missing(col[i]) && _select_key_text(col[i]) in want]
    names = Tuple(Tables.columnnames(cols))
    NamedTuple{names}(Tuple(Tables.getcolumn(cols, n)[idx] for n in names))
end

# A `by_url` address with a `{column}` placeholder is fetched per selected
# key, so it needs the figure to follow a selection on that column.
function _check_keyed_addresses(drawable, opts)
    for l in _frame_layers(drawable)
        t = extract_data(l)
        _is_by_url(t) || continue
        url = _by_url_address(t)
        for p in _url_placeholders(url)
            Symbol(p) in Tables.columnnames(t) || continue
            opts isa SelectGroupOptions && opts.field == p && continue
            throw(ArgumentError(
                "by_url: the address \"$url\" names `{$p}`, a column, which the browser fills in with each selected key. " *
                "Such an address needs the figure to follow a click selection on that column: " *
                "`config(select=(; field=:$p, group=\"…\", initial=…))` with the map's `config(link=(; group=\"…\", key=:$p, on=:click))`."))
        end
    end
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
