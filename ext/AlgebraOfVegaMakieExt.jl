module AlgebraOfVegaMakieExt

# The static (Makie) path of AlgebraOfVega. AoV owns its `data * mapping *
# visual` algebra (src/algebra.jl) so the Vega-Lite path never loads Makie; this
# extension, loaded once AlgebraOfGraphics and Makie are, converts those values
# to AlgebraOfGraphics/Makie ones and draws through `AlgebraOfGraphics.draw`.
# The backend-independent preparation (AoV-only analyses rebuilt as plain
# Band/Lines layers, VL-spelled attributes renamed, `config` → draw kwargs) lives
# in src/static_prep.jl; this module holds what needs Makie itself.

import AlgebraOfGraphics
import Makie
using AlgebraOfVega: AlgebraOfVega, Layer, Layers, AbstractAlgebraic, Visual,
    Columns, Pregrouped, Renamer, NonNumeric, Verbatim, DirectData, Presorted,
    DimsSelector, ScaleID, Scales, Automatic, SymLog, Wrap, NamedArguments, Dictionary,
    DensityAnalysis, HistogramAnalysis, LinearAnalysis, SmoothAnalysis,
    FrequencyAnalysis, ExpectationAnalysis, _LinestylePattern,
    _extract_drawable, _draw_kwargs, _is_faceted, _sdraw_check, _spec_layer_encodings,
    _static_drawable, _sdraw_scales, _hide_static_panel_headers, _static_img,
    _drawable_facet_fields, _panel_label_tables, _panel_label_map, _panel_key_part,
    _opaque_background
using AlgebraOfVega.PlotTypes: Plot

const AoG = AlgebraOfGraphics

# --- Plot types ---

# `Plot{:scatter}` ↔ `Makie.Scatter`: the token names the Makie plotting
# function, and the exported CamelCase binding (when it denotes the same type) is
# the canonical Makie spelling AoG was always given.
function _makie_plottype(::Type{Plot{S}}) where {S}
    isdefined(Makie, S) || error("AlgebraOfVega: Makie has no plotting function `$S` for plot type `Plot{:$S}`.")
    T = Makie.Plot{getfield(Makie, S)}
    sym = Makie.plotsym(T)
    isdefined(Makie, sym) && getfield(Makie, sym) == T ? getfield(Makie, sym) : T
end

# Makie's own plot types in `visual(...)`, `Makie.automatic` and `pseudolog10`
# are `AlgebraOfVegaMakiePlotTypesExt`, which needs Makie alone.

# AlgebraOfGraphics' own selector helpers inside an AoV `mapping`/`scales` are
# normalized onto AoV's (see `AlgebraOfVega._selector`).
AlgebraOfVega._selector(r::AoG.Renamer) = Renamer(r.uniquevalues, r.labels)
AlgebraOfVega._selector(n::AoG.NonNumeric) = NonNumeric(n.x)
AlgebraOfVega._selector(v::AoG.Verbatim) = Verbatim(v.x)
AlgebraOfVega._selector(d::AoG.DirectData) = DirectData(d.data)
AlgebraOfVega._selector(p::AoG.Presorted) = Presorted(p.x, p.i)
AlgebraOfVega._selector(d::AoG.DimsSelector) = DimsSelector(d.dims)
AlgebraOfVega._selector(s::AoG.ScaleID) = ScaleID(s.id)
AlgebraOfVega._selector(w::AoG.Wrap) = Wrap(AlgebraOfVega._selector(w.size_restriction), w.by_col)
AlgebraOfVega._selector(::typeof(AoG.nonnumeric)) = AlgebraOfVega.nonnumeric
AlgebraOfVega._selector(::typeof(AoG.verbatim)) = AlgebraOfVega.verbatim
AlgebraOfVega._selector(::typeof(AoG.presorted)) = AlgebraOfVega.presorted
AlgebraOfVega._selector(::typeof(AoG.direct)) = AlgebraOfVega.direct

# --- Makie-dependent leaves of the static preparation (src/static_prep.jl) ---

# The theme-following `:ink` on the static path: the active Makie theme's text colour.
AlgebraOfVega._static_text_color() = Makie.to_value(Makie.theme(:textcolor; default=:black))

function AlgebraOfVega._static_background(position, axis)
    if position isa Union{Makie.Axis,Makie.Axis3}
        return _opaque_background(Makie.to_value(position.backgroundcolor),
            Makie.to_value(position.parent.scene.backgroundcolor))
    end
    axis_type = get(axis, :type, Makie.Axis)
    theme = Makie.theme(nameof(axis_type); default=Makie.Attributes())
    color = get(axis, :backgroundcolor,
        haskey(theme, :backgroundcolor) ? Makie.to_value(theme[:backgroundcolor]) :
        axis_type === Makie.Axis3 ? :transparent : :white)
    figure = position isa Makie.Figure || isnothing(position) ? position : Makie.get_figure(position)
    under = isnothing(figure) ? Makie.to_value(Makie.theme(:backgroundcolor; default=:white)) :
        Makie.to_value(figure.scene.backgroundcolor)
    _opaque_background(color, under)
end

# Label each drawn panel's axes with its own title (src/panel_labels.jl). A panel's
# facet values come from AoG's facet scales: the position each value's panel takes in
# the grid AoG drew (`plotvalues`, a (row, column) pair for `layout=`, a row or a
# column index for `row=`/`col=`).
function _label_static_panels!(grid::AbstractMatrix, drawable, labels)
    (isempty(labels) || isempty(grid)) && return grid
    facets = _drawable_facet_fields(drawable)
    isempty(facets) && return grid
    scales = first(grid).categoricalscales
    scale(aes) = AoG.extract_single(aes, scales)
    found = [(ch, facets[ch], scale(aes)) for (ch, aes) in ((:layout, AoG.AesLayout),
        (:row, AoG.AesRow), (:col, AoG.AesCol)) if haskey(facets, ch)]
    found = [f for f in found if !isnothing(f[3])]
    isempty(found) && return grid
    fields = [f[2] for f in found]
    tables = _panel_label_tables(drawable)
    maps = Dict(col => (col in fields ? nothing :
        _panel_label_map(tables, Any[], fields, col, ch == "y" ? "ylabels" : "xlabels")) for (ch, col) in labels)
    for idx in CartesianIndices(grid)
        ae = grid[idx]
        isempty(ae.entries) && continue
        key = Any[]
        for (ch, _, sc) in found
            at = ch === :layout ? (idx[1], idx[2]) : ch === :row ? idx[1] : idx[2]
            k = findfirst(==(at), AoG.plotvalues(sc))
            isnothing(k) && break
            push!(key, AoG.datavalues(sc)[k])
        end
        length(key) == length(found) || continue
        for (ch, col) in labels
            label = col in fields ? key[findfirst(==(col), fields)] :
                get(maps[col], [_panel_key_part(v) for v in key], nothing)
            isnothing(label) && continue
            ch == "y" ? (ae.axis.ylabel = string(label)) : (ae.axis.xlabel = string(label))
        end
    end
    grid
end

# --- Values: AoV algebra → AlgebraOfGraphics ---

_makie(x) = x
_makie(::Automatic) = Makie.automatic
_makie(::SymLog) = Makie.pseudolog10
_makie(p::_LinestylePattern) = Makie.Linestyle(p.pattern)

# Selector values (mapping positionals/nameds, pair modifiers, scale props).
# Arrays are rebuilt only when they hold something to convert, so data columns
# passed directly to `mapping` reach AoG as the same objects.
_to_aog(x) = _makie(x)
_to_aog(p::Pair) = _to_aog(first(p)) => _to_aog(last(p))
_to_aog(t::Tuple) = map(_to_aog, t)
_to_aog(v::AbstractArray) = _converts(v) ? map(_to_aog, v) : v
_to_aog(r::Renamer) = AoG.Renamer(r.uniquevalues, r.labels)
_to_aog(n::NonNumeric) = AoG.NonNumeric(n.x)
_to_aog(v::Verbatim) = AoG.Verbatim(v.x)
_to_aog(d::DirectData) = AoG.DirectData(d.data)
_to_aog(p::Presorted) = AoG.Presorted(p.x, p.i)
_to_aog(d::DimsSelector) = AoG.DimsSelector(d.dims)
_to_aog(s::ScaleID) = AoG.ScaleID(s.id)
_to_aog(w::Wrap) = AoG.Wrap(_makie(w.size_restriction), w.by_col)
_to_aog(::typeof(AlgebraOfVega.nonnumeric)) = AoG.nonnumeric
_to_aog(::typeof(AlgebraOfVega.verbatim)) = AoG.verbatim
_to_aog(::typeof(AlgebraOfVega.presorted)) = AoG.presorted
_to_aog(::typeof(AlgebraOfVega.direct)) = AoG.direct
_to_aog(nt::NamedTuple) = map(_to_aog, nt)

_converts(x) = _to_aog(x) !== x
_converts(v::AbstractArray{<:Union{Number, AbstractString, Symbol, Missing, Nothing}}) = false
_converts(v::AbstractArray) = any(_converts, v)

_aog_named(d::NamedArguments) = NamedArguments(collect(keys(d)), Any[_to_aog(v) for v in d])

_to_aog(s::Scales) = AoG.Scales(Dictionary{Symbol, NamedArguments}(
    collect(keys(s.dict)), NamedArguments[_aog_named(props) for props in s.dict]))

_aog_data(x) = x
_aog_data(c::Columns) = AoG.Columns(c.columns)
_aog_data(::Pregrouped) = AoG.Pregrouped()

# Transformation chains keep their `∘` structure; analyses become AoG's with the
# same fields; any other callable passes through.
_aog_transformation(f) = f
_aog_transformation(f::ComposedFunction) = _aog_transformation(f.outer) ∘ _aog_transformation(f.inner)
_aog_transformation(v::Visual) = AoG.Visual(_makie_plottype(v.plottype), _aog_named(v.attributes), v.target)
_aog_transformation(a::DensityAnalysis) = AoG.DensityAnalysis(; datalimits=_makie(a.datalimits),
    npoints=a.npoints, kernel=_makie(a.kernel), bandwidth=_makie(a.bandwidth), direction=_makie(a.direction))
_aog_transformation(a::HistogramAnalysis{P}) where {P} = AoG.HistogramAnalysis{_makie_plottype(P)}(;
    direction=_makie(a.direction), datalimits=_makie(a.datalimits), bins=_makie(a.bins),
    closed=a.closed, normalization=a.normalization)
_aog_transformation(a::LinearAnalysis) = AoG.LinearAnalysis(; npoints=a.npoints,
    dropcollinear=a.dropcollinear, interval=_makie(a.interval), level=a.level)
_aog_transformation(a::SmoothAnalysis) = AoG.SmoothAnalysis(; npoints=a.npoints, span=a.span,
    degree=a.degree, interval=a.interval, level=a.level)
_aog_transformation(::FrequencyAnalysis) = AoG.FrequencyAnalysis()
_aog_transformation(::ExpectationAnalysis) = AoG.ExpectationAnalysis()

_to_aog(l::Layer) = AoG.Layer(_aog_transformation(l.transformation), _aog_data(l.data),
    Any[_to_aog(p) for p in l.positional], _aog_named(l.named))
_to_aog(ls::Layers) = AoG.Layers(AoG.Layer[_to_aog(l) for l in ls.layers])

# --- Static entry points ---

# The drawable, scales and draw keywords of `spec`, in AlgebraOfGraphics/Makie
# values, plus the authored drawable and the panel labels `_label_static_panels!`
# reads after drawing.
function _static_draw_args(spec, position)
    _sdraw_check(spec)
    authored, cfg = _extract_drawable(spec)
    kw = _draw_kwargs(cfg; faceted=_is_faceted(authored),
        layer_encodings=_spec_layer_encodings(spec))
    drawable = _static_drawable(authored, position, kw.axis)
    sc = _hide_static_panel_headers(_sdraw_scales(kw.scales, authored, cfg), authored, kw.panel_labels)
    scales = isnothing(sc) ? () : (_to_aog(sc),)
    (; drawable=_to_aog(drawable), scales, facet=_to_aog(kw.facet), axis=_to_aog(kw.axis),
        figure=_to_aog(kw.figure), authored, panel_labels=kw.panel_labels)
end

function AlgebraOfVega.sdraw!(position, spec)
    a = _static_draw_args(spec, position)
    grid = AoG.draw!(position, a.drawable, a.scales...; facet=a.facet, axis=a.axis)
    _label_static_panels!(grid, a.authored, a.panel_labels)
end

function AlgebraOfVega.sdraw_file(spec, path::AbstractString; kwargs...)
    a = _static_draw_args(spec, nothing)
    fg = AoG.draw(a.drawable, a.scales...; figure=a.figure, facet=a.facet, axis=a.axis)
    _label_static_panels!(fg.grid, a.authored, a.panel_labels)
    Makie.save(path, fg; kwargs...)
    path
end

function AlgebraOfVega.sdraw(spec, path::AbstractString; alt::Union{Nothing,AbstractString}=nothing, kwargs...)
    AlgebraOfVega.sdraw_file(spec, path; kwargs...)
    _static_img(path, alt)
end

# Drawing an AoV spec with AlgebraOfGraphics directly keeps working (scripts that
# combine `using AlgebraOfVega` with `AlgebraOfGraphics.draw`): the layers are
# converted structurally, exactly the values AoG was handed before AoV owned its
# algebra.
AoG.draw(d::AbstractAlgebraic, scales::Scales, args...; kwargs...) =
    AoG.draw(_to_aog(d), _to_aog(scales), args...; kwargs...)
AoG.draw(d::AbstractAlgebraic, args...; kwargs...) = AoG.draw(_to_aog(d), args...; kwargs...)
AoG.draw!(fig, d::AbstractAlgebraic, scales::Scales, args...; kwargs...) =
    AoG.draw!(fig, _to_aog(d), _to_aog(scales), args...; kwargs...)
AoG.draw!(fig, d::AbstractAlgebraic, args...; kwargs...) = AoG.draw!(fig, _to_aog(d), args...; kwargs...)

end # module
