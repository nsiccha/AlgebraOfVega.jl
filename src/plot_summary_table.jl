# A figure's automatic summary as a table, for a consumer that renders its own:
# the rows and labels a captioned plot's "Show summary" pane shows.
#
# The pane is written in the browser from the live view's rows
# (`renderPrettySummary` / `_buildPrettyRows` in vendor/aov-runtime.js), because
# those rows change with the channel picker and `update_spec`. This file is the
# same computation for a lowered Vega-Lite spec, which is all a consumer may hold.
# LOCKSTEP with the runtime: test/plot_summary_table.jl compares the two, row by
# row, in Chrome.

# What the lowered rows alone cannot say: the value column's name (a raw-draws
# summary replaces it by `__point__`/`__median__`) and which columns hold a
# pre-aggregated figure's estimate and bands. `nothing` for a figure without an
# automatic summary. Recorded as `_aovSummary`, not under `_aov`: the runtime
# sizes a plot that carries `_aov` differently from one that does not.
function _summary_meta(spec)
    args = _auto_summary_args(spec)
    isnothing(args) && return nothing
    meta = Dict{String,Any}("value_label" => string(args.value))
    if args.kind === :precomputed_ribbon
        meta["point_col"] = args.point_col
        meta["bands"] = Any[Any[lo, hi, label] for (lo, hi, label) in args.bands]
    end
    meta
end

function _record_summary!(vl::AbstractDict, spec)
    meta = _summary_meta(spec)
    isnothing(meta) || (vl["_aovSummary"] = meta)
    vl
end

"""
    plot_summary_table(vl; ci=:outer, sigfigs=2, texts=plot_texts(), labels=nothing)
    plot_summary_table(spec; kwargs...)

Return summary data for a figure containing interval or ribbon analyses.
The result is a vector of named tuples with `table`, `caption`, and `label`
fields, or `nothing` when the figure has no supported summary. Each `table`
is a Tables.jl column table, ready for a separate table renderer.

`ci` selects the outer, inner, or nearest requested probability interval.
`sigfigs` controls numeric precision; `texts` supplies caption words;
`labels` maps source names to headings. The input may be a drawable or the
dictionary returned by `to_vegalite`.
"""
function plot_summary_table(vl::AbstractDict; ci=:outer, sigfigs::Integer=2,
                            texts::PlotTexts=_EN_PLOT_TEXTS, labels=nothing)
    1 <= sigfigs <= 100 || throw(ArgumentError("plot_summary_table: `sigfigs` must be between 1 and 100, got $sigfigs"))
    ci isa Real || string(ci) in ("outer", "inner") ||
        throw(ArgumentError("plot_summary_table: `ci` must be :outer, :inner or a probability, got $(repr(ci))"))
    meta = get(vl, "_aovSummary", nothing)
    meta isa AbstractDict || return nothing
    for rows in _inline_datasets(vl)
        tables = _summary_tables(rows, meta, ci, Int(sigfigs), texts, labels)
        isempty(tables) || return tables
    end
    nothing
end
plot_summary_table(spec::Union{VegaSpec,AlgebraOfGraphics.Layer,AlgebraOfGraphics.Layers}; kwargs...) =
    plot_summary_table(to_vegalite(spec); kwargs...)

# Every `data.values` of a Vega-Lite tree, in the order Vega-Lite numbers its
# sources (`source_0`, `source_1`, …), which is the order the runtime looks
# through them. `_aov` holds another lowering of the figure, not more data.
function _inline_datasets(vl::AbstractDict, found=Any[])
    d = get(vl, "data", nothing)
    if d isa AbstractDict
        values = get(d, "values", nothing)
        values isa AbstractVector && !isempty(values) && push!(found, values)
    end
    for k in ("layer", "hconcat", "vconcat", "concat")
        children = get(vl, k, nothing)
        children isa AbstractVector && foreach(c -> c isa AbstractDict && _inline_datasets(c, found), children)
    end
    inner = get(vl, "spec", nothing)
    inner isa AbstractDict && _inline_datasets(inner, found)
    found
end

# A dataset's summary tables, one for each source that has a summary. The
# `__aov_pad` rows are not data: they only keep a sparse facet grid's panels.
function _summary_tables(rows, meta, ci, sigfigs, texts, labels)
    real = [r for r in rows if r isa AbstractDict && get(r, "__aov_pad", nothing) !== true]
    out = NamedTuple{(:label, :caption, :table),Tuple{Union{Nothing,String},String,NamedTuple}}[]
    isempty(real) && return out
    for (source, group) in _split_by_source(real)
        built = _summary_rows(group, meta, ci, sigfigs, texts)
        isnothing(built) && continue
        label = isnothing(source) ? nothing :
                isnothing(labels) ? source : string(get(labels, source, source))
        push!(out, (; label, built.caption, built.table))
    end
    out
end

# `_splitBySource`: the rows by their `__src`, sources in order of first appearance.
function _split_by_source(rows)
    any(r -> haskey(r, "__src"), rows) || return Pair{Union{Nothing,String},Vector{Any}}[nothing => collect(Any, rows)]
    order = Union{Nothing,String}[]
    groups = Dict{Union{Nothing,String},Vector{Any}}()
    for r in rows
        source = haskey(r, "__src") ? string(r["__src"]) : nothing
        group = get!(groups, source) do
            push!(order, source)
            Any[]
        end
        push!(group, r)
    end
    Pair{Union{Nothing,String},Vector{Any}}[s => groups[s] for s in order]
end

# `_buildPrettyRows`. `nothing` when these rows hold no summary.
function _summary_rows(rows, meta, ci, sigfigs, texts)
    first_row = first(rows)
    point_col = let explicit = get(meta, "point_col", nothing)
        !isnothing(explicit) ? String(explicit) :
            haskey(first_row, "__point__") ? "__point__" :
            haskey(first_row, "__median__") ? "__median__" : nothing
    end
    (isnothing(point_col) || !haskey(first_row, point_col)) && return nothing

    bands = _summary_bands(first_row, get(meta, "bands", nothing))
    isempty(bands) && return nothing
    pick = _summary_pick(bands, ci)

    hidden = Set{String}([point_col, "__src"])
    for b in bands
        push!(hidden, b.lo, b.hi)
    end
    label = String(get(meta, "value_label", texts.value))
    visible = String[string(c) for c in keys(first_row)
                     if !(string(c) in hidden) && !startswith(string(c), "__") && string(c) != label]
    numeric = Dict(c => _summary_numeric_column(rows, c) for c in visible)
    keycols = vcat(sort!(filter(c -> !numeric[c], visible)), sort!(filter(c -> numeric[c], visible)))

    sorted = sort(rows; alg=MergeSort, lt=(a, b) -> _summary_row_less(a, b, keycols))
    cell(r, c) = _summary_value(get(r, c, nothing))
    names = (Symbol.(keycols)..., Symbol(label))
    columns = ([_summary_key_cell(cell(r, c), sigfigs) for r in sorted] for c in keycols)
    values = String[string(_summary_format(cell(r, point_col), sigfigs), " [",
                           _summary_format(cell(r, pick.lo), sigfigs), ", ",
                           _summary_format(cell(r, pick.hi), sigfigs), "]") for r in sorted]
    point = texts.median
    caption = isnothing(pick.prob) ? string(point, " [", pick.label, "]") :
        replace(texts.interval, "{point}" => point, "{width}" => pick.label)
    (; caption, table=NamedTuple{names}((columns..., values)))
end

# The bands, inner to outer: as given (outermost first, `bands=`), or read off
# the `lo_<prob>_`/`hi_<prob>_` columns of a raw-draws summary.
function _summary_bands(first_row, explicit)
    T = NamedTuple{(:lo, :hi, :label, :prob),Tuple{String,String,String,Union{Nothing,Float64}}}
    if explicit isa AbstractVector && !isempty(explicit)
        return T[(; lo=String(b[1]), hi=String(b[2]), label=String(b[3]), prob=nothing) for b in Iterators.reverse(explicit)]
    end
    bands = T[]
    for c in keys(first_row)
        m = match(r"^lo_(\d+(?:_\d+)?)_$", string(c))
        (isnothing(m) || !haskey(first_row, "hi_$(m[1])_")) && continue
        prob = parse(Float64, replace(m[1], '_' => '.'))
        push!(bands, (; lo="lo_$(m[1])_", hi="hi_$(m[1])_", label="$(floor(Int, prob * 100 + 0.5))%", prob))
    end
    sort!(bands; by=b -> b.prob)
end

function _summary_pick(bands, ci)
    if ci isa Real && !isnothing(first(bands).prob)
        return argmin(b -> abs(b.prob - ci), bands)
    end
    string(ci) == "inner" ? first(bands) : last(bands)
end

# What a row's value is once it is JSON, which is what the browser and a decoded
# spec hold: a non-finite number is `null`, a date is a string.
_summary_value(v::Nothing) = v
_summary_value(v::Bool) = v
_summary_value(v::AbstractString) = v
_summary_value(::Missing) = nothing
_summary_value(v::Real) = isfinite(v) ? v : nothing
_summary_value(v) = JSON.parse(_vl_json(v))

_summary_is_number(v) = v isa Real && !(v isa Bool)

# A column is numeric when its first value that is not empty is a number.
function _summary_numeric_column(rows, c)
    for r in rows
        v = _summary_value(get(r, c, nothing))
        (isnothing(v) || v == "") && continue
        return _summary_is_number(v)
    end
    false
end

function _summary_row_less(a, b, keycols)
    for c in keycols
        x, y = _summary_value(get(a, c, nothing)), _summary_value(get(b, c, nothing))
        if isnothing(x) || isnothing(y)
            isnothing(x) && isnothing(y) && continue
            return isnothing(y)     # empty values go last
        end
        if _summary_is_number(x) && _summary_is_number(y)
            x == y && continue
            return x < y
        end
        xs, ys = _summary_text(x), _summary_text(y)
        xs == ys && continue
        return xs < ys
    end
    false
end

# A key cell: a number rounded to `sigfigs`, staying an integer if it was one;
# an empty value is `missing`.
_summary_key_cell(::Nothing, sigfigs) = missing
_summary_key_cell(v, sigfigs) = v
_summary_key_cell(v::Bool, sigfigs) = v
_summary_key_cell(v::AbstractFloat, sigfigs) = _js_round(v, sigfigs)
_summary_key_cell(v::Integer, sigfigs) = round(Int, _js_round(v, sigfigs))

# The cell of a summary's value column, one number of it: `fmt` in `_buildPrettyRows`.
_summary_format(::Nothing, sigfigs) = ""
_summary_format(v, sigfigs) = _summary_text(v)
_summary_format(v::Real, sigfigs) = _js_number_string(_js_round(v, sigfigs))
_summary_format(v::Bool, sigfigs) = _summary_text(v)

# A cell as the browser writes it (`String(v)`).
_summary_text(::Union{Nothing,Missing}) = ""
_summary_text(v) = string(v)
_summary_text(v::Real) = _js_number_string(v)
_summary_text(v::Bool) = string(v)

# `parseFloat(x.toPrecision(p))`: the `p`-digit decimal nearest the double's exact
# value, a tie going to the larger magnitude. `round(x; sigdigits=p)` does neither:
# it rounds a tie to even and works on an inexact scaled value.
function _js_round(x::Real, p::Integer)
    f = Float64(x)
    (iszero(f) || !isfinite(f)) && return f
    exact = abs(Rational{BigInt}(f))
    pow10(k) = k >= 0 ? big(10)^k // big(1) : big(1) // big(10)^(-k)
    e = floor(Int, log10(abs(f)))
    while exact >= pow10(e + 1)
        e += 1
    end
    while exact < pow10(e)
        e -= 1
    end
    n = floor(BigInt, exact / pow10(e - p + 1) + big(1) // big(2))
    # Rounding the largest doubles up leaves the range; `parseFloat` says Infinity.
    copysign(something(tryparse(Float64, string(n, "e", e - p + 1)), Inf), f)
end

# `Number.prototype.toString`: the shortest digits that read back as the same
# double (Julia's `string` finds the same ones), in positional notation for
# 1e-6 ≤ |x| < 1e21 and exponent notation outside it.
function _js_number_string(x::Real)
    f = Float64(x)
    iszero(f) && return "0"
    isnan(f) && return "NaN"
    isinf(f) && return f > 0 ? "Infinity" : "-Infinity"
    mantissa, exponent = let parts = split(string(abs(f)), 'e')
        parts[1], length(parts) == 2 ? parse(Int, parts[2]) : 0
    end
    whole, fraction = split(mantissa, '.')
    digits = whole * fraction
    point = length(whole) + exponent        # value = 0.<digits> × 10^point
    stripped = lstrip(==('0'), digits)
    point -= length(digits) - length(stripped)
    digits = rstrip(==('0'), stripped)
    k = length(digits)
    body = if k <= point <= 21
        digits * "0"^(point - k)
    elseif 0 < point <= 21
        digits[1:point] * "." * digits[point+1:end]
    elseif -6 < point <= 0
        "0." * "0"^(-point) * digits
    else
        e = point - 1
        (k == 1 ? digits : digits[1:1] * "." * digits[2:end]) * "e" * (e >= 0 ? "+" : "-") * string(abs(e))
    end
    (f < 0 ? "-" : "") * body
end
