# --- The `data * mapping * visual` algebra ---
#
# AoV owns the VALUE layer of AlgebraOfGraphics' algebra — `Layer`/`Layers`,
# `data`, `mapping`, `visual`, the selector helpers, the analysis constructors
# and the plot-type vocabulary — so the Vega-Lite path loads without Makie.
# AlgebraOfGraphics cannot load without Makie's whole rendering stack, which
# made up most of `using AlgebraOfVega` for consumers that never render with
# Makie (snag aov-load-cost-ma-f778daf2; Bruno decision 1sw34ux). No package
# offers this value layer without Makie, so AoV keeps its own copy. Spellings,
# field layouts and constructor defaults mirror AlgebraOfGraphics 0.13
# (definitions adapted from AlgebraOfGraphics.jl, MIT license), so specs read
# and lower as before. The static path converts these values to
# AlgebraOfGraphics/Makie ones in `ext/AlgebraOfVegaMakieExt.jl`.

"""
    AlgebraOfVega.PlotTypes

The plot-type vocabulary named in `visual(...)`: `Scatter`, `Lines`, `Band`,
`BarPlot`, … (plus the unexported `Text` and `Density`). Each name is a
`Plot{f}` token, where `f` is the name of the Makie plotting function of the
same plot type (`Scatter === Plot{:scatter}`). The Vega-Lite path maps a token
to a mark; the static path (Makie extension) maps it to the Makie plot type of
the same name, and `visual` also accepts Makie's own plot types once Makie is
loaded.

`AlgebraOfVega.Makie` is a compatibility alias of this module, so the spelling
`visual(AlgebraOfVega.Makie.Text)` keeps working; it is not the Makie package.
"""
module PlotTypes

"""
    Plot{f}

Plot-type token for the Makie plot type whose plotting function is named `f`
(`Plot{:scatter}` ↔ `Makie.Scatter`). `Plot{:plot}` is the unspecified default
of `visual()`.
"""
struct Plot{F} end

const Scatter = Plot{:scatter}
const Lines = Plot{:lines}
const ScatterLines = Plot{:scatterlines}
const BarPlot = Plot{:barplot}
const Heatmap = Plot{:heatmap}
const BoxPlot = Plot{:boxplot}
const Band = Plot{:band}
const HLines = Plot{:hlines}
const VLines = Plot{:vlines}
const HSpan = Plot{:hspan}
const VSpan = Plot{:vspan}
const Hist = Plot{:hist}
const Density = Plot{:density}
const Errorbars = Plot{:errorbars}
const Stairs = Plot{:stairs}
const Contour = Plot{:contour}
const Violin = Plot{:violin}
const RainClouds = Plot{:rainclouds}
const Rangebars = Plot{:rangebars}
const CrossBar = Plot{:crossbar}
const ECDFPlot = Plot{:ecdfplot}
# Like Makie, `Text` and `Density` are not exported: `Text` would clash with
# `Base.Text`, and AoV's `density()` analysis owns the lowercase name.
const Text = Plot{:text}

export Scatter, Lines, ScatterLines, BarPlot, Heatmap, BoxPlot,
    Band, HLines, VLines, HSpan, VSpan, Hist, Errorbars, Stairs,
    Contour, Violin, RainClouds, Rangebars, CrossBar, ECDFPlot

end # module PlotTypes

using .PlotTypes
using .PlotTypes: Plot, Density as MakieDensity

"""Compatibility alias of [`AlgebraOfVega.PlotTypes`](@ref) — not the Makie package."""
const Makie = PlotTypes

# The name of a plot type in messages, as `Makie.plotsym` gives it: the type's
# own name (`:VLines` for `VLines`, `:Text`), and `:plot` for the unspecified
# `Plot{:plot}`. A token without a `PlotTypes` name (one built from a Makie
# plot type AoV does not list) capitalizes its function name.
function _plot_type_names()
    out = Dict{Type,Symbol}()
    for n in names(PlotTypes; all=true)
        isdefined(PlotTypes, n) || continue
        t = getfield(PlotTypes, n)
        t isa Type && t <: Plot && t !== Plot && (out[t] = n)
    end
    out
end
const _PLOTSYMS = _plot_type_names()
_plotsym(::Type{Plot{:plot}}) = :plot
_plotsym(P::Type{Plot{F}}) where {F} = get(_PLOTSYMS, P, Symbol(uppercasefirst(string(F))))

"""
    Automatic

Marker for an option left to its default (AoG's `Makie.automatic`).
"""
struct Automatic end
const automatic = Automatic()

const NamedArguments = Dictionary{Symbol, Any}

# --- Layer / Layers ---

"""
    AbstractAlgebraic

Objects that combine with `+` and `*`: [`Layer`](@ref) and [`Layers`](@ref).
"""
abstract type AbstractAlgebraic end

"""
    Layer(transformation, data, positional, named)

One layer of a visualization: a data source, positional and named selectors,
and a transformation chain (`visual`, analyses). Built by multiplying the
outputs of [`data`](@ref), [`mapping`](@ref), [`visual`](@ref) and the analysis
constructors; `*` combines layers, `+` collects them into [`Layers`](@ref).
"""
Base.@kwdef struct Layer <: AbstractAlgebraic
    transformation::Any = identity
    data::Any = nothing
    positional::Vector{Any} = Any[]
    named::NamedArguments = NamedArguments()
end

"""Create a `Layer` whose transformation chain is `f`."""
transformation(f) = Layer(transformation = f)

struct Columns{T}
    columns::T
end

struct Pregrouped end

"""
    data(table)

Create a [`Layer`](@ref) with its data set to a Tables.jl-compatible `table`;
multiply with [`mapping`](@ref) to select its columns. `data(Pregrouped())`
marks pregrouped input (see [`pregrouped`](@ref)).
"""
data(df) = Layer(data = Columns(Tables.columns(df)))
data(p::Pregrouped) = Layer(data = p)

"""
    mapping(positional...; named...)

Create a [`Layer`](@ref) with positional and named column selectors. A selector
is a column name or index, optionally paired with modifiers and a label:
`:x => "X label"`, `:g => sorter("b", "a") => "Group"`, `:k => nonnumeric`,
`direct(values)`, `dims(1)`.
"""
mapping(args...; kwargs...) = Layer(positional = Any[_selector(a) for a in args],
    named = NamedArguments(Symbol[k for k in keys(kwargs)], Any[_selector(v) for v in values(kwargs)]))

# Selector values from another vocabulary are normalized onto AoV's when a
# mapping (or `scales`) is built — the Makie extension maps AlgebraOfGraphics'
# own helpers (`AlgebraOfGraphics.sorter(...)`, `AlgebraOfGraphics.nonnumeric`,
# …) and `Makie.pseudolog10` here, so code mixing them with AoV specs keeps
# its sort/type/scale on both paths. AoV's own values pass through.
_selector(x) = x
_selector(p::Pair) = _selector(first(p)) => _selector(last(p))

"""
    pregrouped(positional...; named...)

Equivalent to `data(Pregrouped()) * mapping(positional...; named...)`.
"""
pregrouped(args...; kwargs...) = data(Pregrouped()) * mapping(args...; kwargs...)

⨟(f, g) = f === identity ? g : g === identity ? f : g ∘ f

function Base.:*(l::Layer, l′::Layer)
    transformation = l.transformation ⨟ l′.transformation
    data = isnothing(l′.data) ? l.data : l′.data
    positional = vcat(l.positional, l′.positional)
    named = merge(l.named, l′.named)
    return Layer(; transformation, data, positional, named)
end

"""
    Layers(layers::Vector{Layer})

A list of [`Layer`](@ref)s, as produced by `+`. Adding or multiplying `Layers`
yields `Layers`.
"""
struct Layers <: AbstractAlgebraic
    layers::Vector{Layer}
end

Base.convert(::Type{Layers}, l::Layer) = Layers([l])

Base.getindex(layers::Layers, i::Int) = layers.layers[i]
Base.length(layers::Layers) = length(layers.layers)
Base.eltype(::Type{Layers}) = Layer
Base.iterate(layers::Layers, args...) = iterate(layers.layers, args...)

function Base.:+(a::AbstractAlgebraic, a′::AbstractAlgebraic)
    layers::Layers, layers′::Layers = a, a′
    return Layers(vcat(layers.layers, layers′.layers))
end

function Base.:*(a::AbstractAlgebraic, a′::AbstractAlgebraic)
    layers::Layers, layers′::Layers = a, a′
    return Layers([layer * layer′ for layer in layers for layer′ in layers′])
end

"""
    zerolayer()

An empty `Layers`: a zero of the layer algebra (`l * zerolayer()` is empty,
`l + zerolayer()` is `l`).
"""
zerolayer() = Layers(Layer[])

# --- visual ---

struct Visual
    plottype::Type{<:Plot}
    attributes::NamedArguments
    target
end

Visual(plottype::Type{<:Plot} = Plot{:plot}; kwargs...) = Visual(plottype, NamedArguments(kwargs), nothing)

"""
    visual(plottype=Plot{:plot}; attributes...)

Create a [`Layer`](@ref) that draws with `plottype` (`Scatter`, `Lines`, `Band`,
…; see [`AlgebraOfVega.PlotTypes`](@ref)) and the given visual attributes.
"""
visual(plottype::Type{<:Plot} = Plot{:plot}; kwargs...) = transformation(Visual(plottype; kwargs...))

# Several `visual(...)` terms on one layer, combined as AlgebraOfGraphics applies
# them to its processed layer (`Visual(::ProcessedLayer)`, in chain order): a
# specific plot type replaces the unspecified `Plot{:plot}` (`Makie.plottype`),
# and a later term's attributes win (`merge`).
function _combine_visuals(visuals)
    plottype, attributes = Plot{:plot}, NamedArguments()
    for v in visuals
        v.plottype === Plot{:plot} || (plottype = v.plottype)
        attributes = merge(attributes, v.attributes)
    end
    Visual(plottype, attributes, nothing)
end

# --- Selector helpers ---

to_string(s) = string(s)
to_string(s::AbstractString) = s

struct Sorted{T}
    idx::UInt32
    value::T
end
Sorted(idx::Integer, value) = Sorted(convert(UInt32, idx), value)

Base.hash(s::Sorted, h::UInt) = hash(s.value, hash(s.idx, hash(:Sorted, h)))
Base.:(==)(s1::Sorted, s2::Sorted) = isequal(s1.idx, s2.idx) && isequal(s1.value, s2.value)
Base.print(io::IO, s::Sorted) = print(io, s.value)
Base.isless(s1::Sorted, s2::Sorted) = isless((s1.idx, s1.value), (s2.idx, s2.value))

struct Renamer{U, L}
    uniquevalues::U
    labels::L
end

# `dims(2)` and up yield indices like `CartesianIndex(1, 4)`, which are non-1 in
# at most one dimension by construction: drop the ones, error on two non-ones.
function linearize_cartesian_index(i::CartesianIndex)
    t = Tuple(i)
    return reduce(t; init = 1) do a, b
        a == 1 ? b : b == 1 ? a : error("Can't linearize $(i) because it has two indices that are not one")
    end
end
linearize_cartesian_index(x) = x

function (r::Renamer{Nothing})(x)
    lx = linearize_cartesian_index(x)
    i = LinearIndices(r.labels)[lx]
    return Sorted(i, r.labels[i])
end

function (r::Renamer)(x)
    for i in keys(r.uniquevalues)
        cand = @inbounds r.uniquevalues[i]
        if isequal(cand, x)
            label = r.labels[i]
            return Sorted(i, label)
        end
    end
    throw(KeyError(x))
end

renamer(args::Pair...) = renamer(args)

"""
    renamer(arr::Union{AbstractArray, Tuple})

Rename a categorical variable, as in `renamer(["a" => "Label A", "b" => "Label B"])`
(or the vararg form `renamer("a" => "Label A", "b" => "Label B")`). The pair
order is the category order. Without pairs, `arr` lists labels for the
category indices (useful with `dims`).
"""
function renamer(arr::Union{AbstractArray, Tuple})
    ispairs = all(x -> isa(x, Pair), arr)
    k, v = ispairs ? (map(first, arr), map(last, arr)) : (nothing, arr)
    return Renamer(k, v)
end

function sorter(ks...)
    vs = map(to_string, ks)
    return Renamer(ks, vs)
end

"""
    sorter(ks)

Reorder a categorical variable, as in `sorter(["low", "medium", "high"])` (or
`sorter("low", "medium", "high")`). `ks` lists every category, in order.
"""
function sorter(ks::Union{AbstractArray, Tuple})
    vs = map(to_string, ks)
    return Renamer(ks, vs)
end

struct NonNumeric{T}
    x::T
end

"""
    nonnumeric(x)

Treat `x` as categorical: printed and sorted like `x`, but never on a continuous
scale (`mapping(:k => nonnumeric)`).
"""
nonnumeric(x) = NonNumeric(x)

Base.print(io::IO, n::NonNumeric) = print(io, n.x)
Base.isless(n1::NonNumeric, n2::NonNumeric) = isless(n1.x, n2.x)

struct Verbatim{T}
    x::T
end

"""
    verbatim(x)

Use `x` in the plot as is, without rescaling (`mapping(text = :label => verbatim)`).
"""
verbatim(x) = Verbatim(x)

Base.getindex(v::Verbatim) = v.x
Base.print(io::IO, v::Verbatim) = print(io, v.x)

struct DirectData{T}
    data::T
end

"""
    direct(x)

Use `x` directly as data in a `mapping` over a table, without a column lookup;
a non-array `x` is expanded to the table's row count.
"""
direct(x) = DirectData(x)

struct Presorted{T}
    x::T
    i::UInt16
end
Presorted(x) = Presorted(x, 0x0000)

"""
    presorted(x)

Inside a selector pair, keep a categorical column in its original data order
instead of sorting it: `mapping(:some_column => presorted)`.
"""
presorted(x) = Presorted(x)

Base.show(io::IO, p::Presorted) = print(io, p.x)
Base.isless(p::Presorted, p2::Presorted) = isless(p.i, p2.i)
Base.isequal(p::Presorted, p2::Presorted) = isequal(p.x, p2.x)
Base.:(==)(p::Presorted, p2::Presorted) = p.x == p2.x
Base.hash(p::Presorted) = hash(p.x)

struct DimsSelector{N}
    dims::NTuple{N, Int}
end

"""
    dims(args...)

Select dimensions of a layer's shape as a categorical variable, as in
`mapping([:x1, :x2, :x3], col = dims(1))`.
"""
dims(args...) = DimsSelector(args)

# --- Scales ---

struct ScaleID
    id::Symbol
end

"""
    scale(id::Symbol)

Assign a custom scale id to a mapped variable (`mapping(color = :g => scale(:c2))`).
"""
scale(id::Symbol) = ScaleID(id)

Base.broadcastable(s::ScaleID) = Ref(s)

struct Scales
    dict::Dictionary{Symbol, Dictionary{Symbol, Any}}
end

"""
    scales(; kwargs...)

Scale properties, mirroring `AlgebraOfGraphics.scales`: each keyword names a
scale (`X`, `Y`, `Color`, `Marker`, `Row`, `Col`, `Layout`, …) and maps to a
NamedTuple (or other `Symbol`-keyed dict-like) of its properties. Pass it as
`config(scales=scales(...))` or `to_vegalite(spec, scales(...))`.
"""
function scales(; kwargs...)
    dict = Dictionary{Symbol, Dictionary{Symbol, Any}}()
    for (kw, value) in pairs(kwargs)
        props = _kwdict(value, kw)
        for k in keys(props)
            props[k] = _selector(props[k])
        end
        insert!(dict, kw, props)
    end
    return Scales(dict)
end

function _kwdict(prs, keyword::Symbol)::Dictionary{Symbol, Any}
    err = nothing
    dict = try
        _dict::Dictionary{Symbol, Any} = dictionary(pairs(prs))
    catch _err
        err = _err
    end
    if err !== nothing
        errmsg = sprint(showerror, err)
        throw(ArgumentError("Can't convert value passed via the keyword `$keyword` to a `Dictionary{Symbol,Any}`. If you intended to pass a single-element `NamedTuple`, check that you didn't write `$keyword = (key = value)` as this expression resolves to just `value`. Use either `$keyword = (; key = value)` or `$keyword = (key = value,)`. The invalid value that was passed was:\n\n$(repr(prs))\n\nThe underlying error message was:\n\n$errmsg"))
    end
    return dict
end

# --- Wrapped facet layouts ---

struct Wrap{T <: Union{Automatic, @NamedTuple{n::Int64, cols::Bool}}}
    size_restriction::T
    by_col::Bool
end

"""
    wrapped(; cols=automatic, rows=automatic, by_col=false)

A `Layout` scale `palette` (`scales(Layout=(; palette=wrapped(cols=3)))`) that
caps the columns (or rows) of a wrapped `layout=` facet, as AlgebraOfGraphics'
`wrapped`. Only one of `cols` and `rows` may be an integer. Vega-Lite fills a
wrapped facet row by row, so `by_col=true` is refused there.
"""
function wrapped(;
        cols::Union{Integer, Automatic} = automatic,
        rows::Union{Integer, Automatic} = automatic,
        by_col::Bool = false
    )
    return if cols !== automatic && rows !== automatic
        throw(ArgumentError("`cols` and `rows` can't both be fixed in a wrapped layout."))
    elseif cols === automatic && rows === automatic
        Wrap(automatic, by_col)
    elseif cols === automatic
        Wrap((n = rows, cols = false), by_col)
    else
        Wrap((n = cols, cols = true), by_col)
    end
end

"""
    symlog

Scale marker for an axis that is linear near zero and logarithmic farther away.
Pass as `scale=symlog` in an X or Y scale configuration. Unlike a logarithmic
axis, it can represent genuine zero values.

The optional `constant` sets the Vega-Lite linear region's half-width. The
Makie path (the `AlgebraOfVegaMakieExt` extension) draws `Makie.pseudolog10`
with its fixed unit region, so changing `constant` affects the browser path
only. As a function, `symlog(x) = sign(x) * log10(abs(x) + 1)`, the forward map
of `Makie.pseudolog10`; with Makie loaded, `scale=Makie.pseudolog10` is read as
`symlog`.
"""
struct SymLog end
(::SymLog)(x) = sign(x) * log10(abs(x) + 1)
const symlog = SymLog()

# --- Analyses (AoG's statistical transformations, as values) ---
#
# The Vega-Lite emitters read these fields; the Makie extension rebuilds the
# AlgebraOfGraphics analysis with the same fields for the static path.

Base.@kwdef struct DensityAnalysis{D, K, B}
    datalimits::D = automatic
    npoints::Int = 200
    kernel::K = automatic
    bandwidth::B = automatic
    direction::Union{Automatic, Symbol} = automatic
end

"""
    density(; datalimits, npoints=200, kernel, bandwidth, direction)

Kernel density estimate of the mapped variable (AlgebraOfGraphics' `density`).
"""
density(; options...) = transformation(DensityAnalysis(; options...))

struct HistogramAnalysis{plottype <: Plot, D, B}
    direction::Union{Automatic, Symbol}
    datalimits::D
    bins::B
    closed::Symbol
    normalization::Symbol
end

function HistogramAnalysis{plottype}(;
        direction::Union{Automatic, Symbol} = automatic,
        datalimits::D = automatic,
        bins::B = automatic,
        closed::Symbol = :left,
        normalization::Symbol = :none,
    ) where {plottype <: Plot, D, B}
    return HistogramAnalysis{plottype, D, B}(direction, datalimits, bins, closed, normalization)
end
HistogramAnalysis(; options...) = HistogramAnalysis{Plot{:plot}}(; options...)

"""
    histogram(plottype=Plot{:plot}; bins, datalimits, closed=:left, normalization=:none)

Histogram of the mapped variable (AlgebraOfGraphics' `histogram`).
"""
histogram(plottype::Type{<:Plot} = Plot{:plot}; options...) = transformation(HistogramAnalysis{plottype}(; options...))

Base.@kwdef struct LinearAnalysis{I}
    npoints::Int = 200
    dropcollinear::Bool = false
    interval::I = automatic
    level::Float64 = 0.95
end

"""
    linear(; npoints=200, dropcollinear=false, interval, level=0.95)

Linear regression fit, optionally with a confidence band (AlgebraOfGraphics' `linear`).
"""
linear(; options...) = transformation(LinearAnalysis(; options...))

Base.@kwdef struct SmoothAnalysis
    npoints::Int = 200
    span::Float64 = 0.75
    degree::Int = 2
    interval::Union{Symbol, Nothing} = :confidence
    level::Float64 = 0.95
end

"""
    smooth(; npoints=200, span=0.75, degree=2, interval=:confidence, level=0.95)

Local regression smoother (AlgebraOfGraphics' `smooth`).
"""
smooth(; options...) = transformation(SmoothAnalysis(; options...))

struct FrequencyAnalysis end

"""
    frequency()

Count the observations in each group (AlgebraOfGraphics' `frequency`).
"""
frequency() = transformation(FrequencyAnalysis())

struct ExpectationAnalysis end

"""
    expectation()

Mean of the last positional variable per group (AlgebraOfGraphics' `expectation`).
"""
expectation() = transformation(ExpectationAnalysis())
