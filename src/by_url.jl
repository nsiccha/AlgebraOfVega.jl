# by_url.jl — a layer's rows read by the browser from an address
# (snag `odl-s-framed-reg-a3e457ca`, design decision `0wiwrsc`).
#
# `data(by_url(rows, url))` draws `rows`, but the Vega-Lite AoV emits names
# `url` where the rows would stand: `{"url": url, "format": {"type": "json"}}`.
# The browser fetches them once, and every page that draws the same rows
# carries ~100 bytes instead of them (a static export writes one file per
# address). Julia keeps the rows for everything it reads from them: column
# types, the checks AoV runs, `sdraw` and `vsave`.
#
# `by_url` is a Tables.jl table, so AlgebraOfGraphics' own `data(...)` takes it
# unchanged (no AoV method on `data`): `Tables.columns` returns an
# `AddressedColumns`, which AoG keeps in `Layer.data`, and `data_to_vl` — the
# one writer of a layer's raw rows — dispatches on it. A layer whose drawn rows
# AoV computes in Julia (a summary, a merged faceted dataset, the picker's
# combined columns) cannot be read from the address; those paths refuse it
# through `_refuse_by_url`.

struct ByURL{T}
    rows::T
    url::String
    function ByURL(rows::T, url::String) where {T}
        isempty(url) && throw(ArgumentError("by_url: the address is empty; name the URL the rows are served at"))
        new{T}(rows, url)
    end
end

# The columns AoG stores in `Layer.data` for a `by_url` table: the rows' own
# columns, plus the address the browser reads them from. Field access goes
# through `getfield`: `Tables.AbstractColumns` turns `getproperty` into column
# lookups.
struct AddressedColumns{C} <: Tables.AbstractColumns
    columns::C
    url::String
end

"""
    by_url(rows, url)

The table `rows`, drawn by reading it from `url` instead of writing it into the
plot. Pass it to `data`:

```julia
data(by_url(stations, "/stationen?zeit=letzte")) * mapping(:lon, :lat; color=:nsv) * visual(Scatter)
```

The figure's Vega-Lite names the address in place of the rows,
`"data": {"url": url, "format": {"type": "json"}}`, so the browser fetches the
rows once and every plot that draws them from the same address stays small.
The address must answer exactly `rows_json(rows)`: serve that from a route (in
an HTMXObjects app, map the route's address with `static_url` so a static
export writes the file). A field that differs between plots of the same rows
(which region is opened) belongs in that layer's
`config(transform=[Dict("calculate" => "datum.AGS === '01002'", "as" => "in_selected")])`,
not in the rows, or every plot needs rows of its own.

`rows` stays in Julia for everything AoV reads from it: the encodings' types,
the checks on columns, `sdraw`, and `vsave`, which writes the rows into the
file. A captioned plot's "⬇ HTML" card carries the text the address answered,
so the saved file draws with no server.

A figure whose drawn rows AoV computes in Julia cannot be read from an address,
and is refused with an `ArgumentError`: `pointinterval`, `gradient_interval`,
`dotinterval`, `lineribbon`/`ribbon` (also with `bands=`), a faceted or
ridgeline `density()`, `cell_charts`, the channel picker (`auto_remap`), and a
faceted figure whose layers draw different tables. Pass such a layer its rows
without `by_url`.
"""
by_url(rows, url::AbstractString) = ByURL(rows, String(url))
by_url(rows::Union{ByURL,AddressedColumns}, url::AbstractString) = throw(ArgumentError(
    "by_url: these rows are already read from \"$(_by_url_address(rows))\"; give `by_url` the plain table"))
by_url(rows, url) = throw(ArgumentError(
    "by_url: the address must be a string, got $(typeof(url)); for example `by_url(rows, \"/stations.json\")`"))

_by_url_address(b::ByURL) = getfield(b, :url)
_by_url_address(c::AddressedColumns) = getfield(c, :url)
_by_url_columns(c::AddressedColumns) = getfield(c, :columns)

Tables.istable(::Type{<:ByURL}) = true
Tables.columnaccess(::Type{<:ByURL}) = true
Tables.columns(b::ByURL) = AddressedColumns(Tables.columns(getfield(b, :rows)), _by_url_address(b))
Tables.schema(b::ByURL) = Tables.schema(Tables.columns(b))

Tables.istable(::Type{<:AddressedColumns}) = true
Tables.columnaccess(::Type{<:AddressedColumns}) = true
Tables.columns(c::AddressedColumns) = c
Tables.columnnames(c::AddressedColumns) = Tables.columnnames(_by_url_columns(c))
Tables.getcolumn(c::AddressedColumns, i::Int) = Tables.getcolumn(_by_url_columns(c), i)
Tables.getcolumn(c::AddressedColumns, nm::Symbol) = Tables.getcolumn(_by_url_columns(c), nm)
Tables.getcolumn(c::AddressedColumns, ::Type{T}, i::Int, nm::Symbol) where {T} =
    Tables.getcolumn(_by_url_columns(c), T, i, nm)
Tables.schema(c::AddressedColumns) = Tables.schema(_by_url_columns(c))

Base.show(io::IO, b::ByURL) = print(io, "by_url(", typeof(getfield(b, :rows)), ", \"", _by_url_address(b), "\")")
Base.show(io::IO, c::AddressedColumns) = print(io, "AddressedColumns(\"", _by_url_address(c), "\")")

# The layer data Vega-Lite reads from the address, in place of `{"values": rows}`.
# While `_with_rows_inline` runs (`vsave`), the rows themselves: a file renders
# with no server to answer the address.
data_to_vl(c::AddressedColumns) = _rows_inline() ? data_to_vl(_by_url_columns(c)) :
    Dict{String,Any}("url" => _by_url_address(c), "format" => Dict{String,Any}("type" => "json"))

# Task-local, so a `vsave` never changes what a concurrent render emits.
_rows_inline() = get(task_local_storage(), :aov_by_url_inline, false)::Bool
_with_rows_inline(f) = task_local_storage(f, :aov_by_url_inline, true)

_is_by_url(t) = t isa AddressedColumns

# A path that writes rows AoV computes in Julia refuses a table read from an
# address: those rows are not the ones the address serves. `why` says what
# computes them; `fix` what to write instead.
function _refuse_by_url(table, why::AbstractString;
        fix::AbstractString="Pass this layer its table without `by_url`; its rows are then written into the plot.")
    _is_by_url(table) || return table
    throw(ArgumentError("$why, so they cannot be read from \"$(_by_url_address(table))\". $fix"))
end

"""
    rows_json(rows) -> String

The JSON a [`by_url`](@ref) address serves for `rows`: an array with one object
per row, exactly the rows the plot would otherwise carry in its Vega-Lite
(`NaN` and `±Inf` written as `null`, dates as Vega reads them). Serve it with
`Content-Type: application/json`:

```julia
@direct @get stationen(; zeit) = MIMEResponse("application/json", rows_json(station_rows(zeit)))
```
"""
rows_json(rows) = _vl_json(_with_rows_inline(() -> data_to_vl(Tables.columns(rows)))["values"])
