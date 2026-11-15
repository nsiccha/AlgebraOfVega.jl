# bound_columns.jl — plots whose rows a page computes in the browser
#
# HTMXObjects' `bound(p; columns)`, inside an `@htmx` struct whose property `p`
# a `semantic_app` page computes in the browser (`@browser`), is a Tables.jl
# table that also names where its columns come from. Drawn as a layer's
# `data(...)`, its rows are written into the plot as usual. `to_node` finds the
# dataset that holds exactly those rows and marks the plot's area with the
# binding (`_bound_attrs`, HTMXObjects' `bound_columns_attrs`), so the page
# replaces that dataset with the columns the browser computes (the runtime's
# `htmxo:bound-columns` listener, `AoV.updateData`), and a static export reads
# the embedded rows as bound instead of stale.
#
# Only rows drawn as given can be replaced by the browser's columns. A figure
# whose rows AoV computes from the table in Julia is refused at render.

# The binding of a layer's table: `nothing` for an ordinary table. The
# HTMXObjects extension answers for its `BoundColumns`.
_bound_binding(_) = nothing

# The attributes that mark the element showing `binding`'s rows from the Vega
# dataset `dataset` (HTMXObjects extension).
function _bound_attrs end

# The rows `data_to_vl` wrote for a bound table, with what they were:
# `to_node` looks for the dataset holding exactly this vector. Keyed by
# identity (a `WeakKeyDict` would hash and compare every row), and weak, so a
# record goes with its lowered spec; stale ones are dropped at the next note.
const _BOUND_ROWS = Dict{UInt,Tuple{WeakRef,Any}}()
const _BOUND_ROWS_LOCK = ReentrantLock()

function _note_bound_rows!(vals::AbstractVector, table)
    binding = _bound_binding(table)
    isnothing(binding) && return
    rec = (; binding, n=length(vals), fields=Set{String}(string.(Tables.columnnames(table))))
    lock(_BOUND_ROWS_LOCK) do
        filter!(e -> !isnothing(last(e)[1].value), _BOUND_ROWS)
        _BOUND_ROWS[objectid(vals)] = (WeakRef(vals), rec)
    end
    nothing
end

# The record of the rows `vals`, `nothing` for rows no bound table wrote.
_bound_record(vals) = nothing
_bound_record(vals::AbstractVector) = lock(_BOUND_ROWS_LOCK) do
    e = get(_BOUND_ROWS, objectid(vals), nothing)
    (isnothing(e) || e[1].value !== vals) ? nothing : e[2]
end

# The dataset name a bound table's rows get when they are not the plot's
# top-level data (the top-level data is Vega-Lite's `source_0`, which the
# runtime's ribbon, picker and data operations default to). A plot drawing
# several bound tables names the second such dataset `aov_bound_2`, and so on.
const _BOUND_DATASET = "aov_bound"
_bound_dataset_name(k) = k == 1 ? _BOUND_DATASET : string(_BOUND_DATASET, "_", k)

# The bound tables a spec's layers draw (none for an already-lowered dict).
function _bound_tables(spec)
    layers = _spec_layers_or_nothing(_spec_drawable(spec))
    isnothing(layers) && return Any[]
    Any[b for b in (_bound_binding(extract_data(l)) for l in layers) if !isnothing(b)]
end

# Every `data` object of `vl` holding rows `data_to_vl` wrote for a bound table,
# with its path of keys from `vl`. `_aov` is not searched: the other drawing of
# a ribbon view lives there and reads the same dataset name.
_find_bound_data!(found, x, path) = nothing
function _find_bound_data!(found, x::AbstractVector, path)
    for (i, v) in pairs(x)
        _find_bound_data!(found, v, Any[path..., i])
    end
end
function _find_bound_data!(found, x::AbstractDict, path)
    for (k, v) in x
        k == "_aov" && continue
        if k == "data" && v isa AbstractDict
            vals = get(v, "values", nothing)
            rec = _bound_record(vals)
            isnothing(rec) || push!(found, (; rec..., vals, path=Any[path..., k]))
        else
            _find_bound_data!(found, v, Any[path..., k])
        end
    end
end

# Whether `vals` still are the table's rows exactly: as many, with the
# table's fields and no others. A pass that added rows (sparse facet pads) or
# fields to them drew something the browser's columns cannot replace.
_bound_rows_intact(rec) = length(rec.vals) == rec.n &&
    all(r -> r isa AbstractDict && length(r) == length(rec.fields) && all(k -> string(k) in rec.fields, keys(r)), rec.vals)

# A copy of `x` with `f` applied to the value at `path`; only the containers
# along the path are copied, so `x` (possibly the caller's) is left alone.
function _path_replace(f, x, path, i=1)
    y = copy(x)
    k = path[i]
    y[k] = i == length(path) ? f(x[k]) : _path_replace(f, x[k], path, i + 1)
    y
end

_data_with(d, key, value) = (c = copy(d); c[key] = value; c)

const _BOUND_LOWERED = "AoV computes the rows this figure draws from them in Julia: an interval or ribbon " *
    "summary of raw draws, a faceted or ridgeline `density()`, a faceted figure whose layers draw different " *
    "tables (merged into one dataset), or the channel picker's combined or broadcast columns. The browser's " *
    "columns cannot replace such rows. Refresh this figure from the server with `update_spec(id, spec)`, or " *
    "draw the bound columns as they are: plain marks, the analyses Vega-Lite computes (`linear()`, " *
    "`histogram()`, an unfaceted `density()`, …), or a summary the browser module computes, drawn with " *
    "`lineribbon(bands=…)`."

"""
Where the lowered `vl` draws the rows of bound tables: `nothing` for a figure
that draws none, else `(; vl, bindings, key)`. `vl` is the spec to embed (a
layer's bound rows get a dataset name of their own), `bindings` one
`(; binding, dataset)` per place the rows are drawn, in spec order, `dataset`
the Vega dataset holding them, and `key` the spec's JSON without the rows (a
stable default plot id). `sources` are the bound tables of the figure's layers;
a figure whose bound rows AoV changed in lowering, or computed other rows from,
is refused.
"""
function _bound_dataset(vl::AbstractDict, sources)
    found = Any[]
    _find_bound_data!(found, vl, Any[])
    isempty(sources) && isempty(found) && return nothing
    # Every bound table drawn as given, each where the browser's columns can
    # replace it: rows AoV changed, or a table it drew only through rows it
    # computed, cannot follow.
    all(_bound_rows_intact, found) && all(b -> any(r -> r.binding === b, found), sources) && !isempty(found) ||
        throw(ArgumentError("This figure draws `bound(…; columns)` rows, which the page computes in the browser, but " *
            _BOUND_LOWERED))
    # The top-level rows (`source_0`) first: the plot area carries them.
    sort!(found; by=rec -> rec.path != Any["data"])
    out, bindings, named = vl, Any[], 0
    for rec in found
        top = rec.path == Any["data"]
        dataset = top ? "source_0" : _bound_dataset_name(named += 1)
        top || (out = _path_replace(d -> _data_with(d, "name", dataset), out, rec.path))
        push!(bindings, (; rec.binding, dataset))
    end
    key = foldl((s, rec) -> _path_replace(d -> _data_with(d, "values", Any[]), s, rec.path), found; init=out)
    (; vl=out, bindings, key=_vl_json(_wire_spec(key)))
end
