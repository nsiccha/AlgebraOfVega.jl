# --- Static (Makie) rendering ---

"""
    _extract_drawable(spec)

Extract the AoG drawable (Layer/Layers) from a spec. Returns `(drawable, config)`.
"""
_extract_drawable(layer::AlgebraOfGraphics.Layer) = (layer, nothing)
_extract_drawable(layers::AlgebraOfGraphics.Layers) = (layers, nothing)
_extract_drawable(v::VegaSpec) = (v.drawable, v.config)

"""
    _draw_kwargs(cfg::Union{Config,Nothing})

Translate AoV Config properties into keyword arguments for `AlgebraOfGraphics.draw`.
"""
_merge_nt!(_, ::Nothing) = nothing
function _merge_nt!(kw, nt::NamedTuple)
    for (k, v) in pairs(nt)
        kw[k] = v
    end
end

_merge_axis_nt!(_, ::Nothing) = nothing
function _merge_axis_nt!(axis_kw, nt::NamedTuple)
    for (ak, av) in pairs(nt)
        ak === :clamp && continue  # VL-only, no Makie analogue
        axis_kw[ak] = av
    end
end

_independent_axes_syms(b::Bool) = b ? (:x, :y) : ()
_independent_axes_syms(s::Symbol) = (s,)
_independent_axes_syms(v) = (Symbol(a) for a in v)

_apply_log_scales!(axis_kw, ::Nothing) = nothing
function _apply_log_scales!(axis_kw, enc::Dict)
    for (ch, ch_props) in enc
        d = _as_dict(ch_props); isnothing(d) && continue
        scale_dict = get(d, "scale", get(d, :scale, nothing))
        isnothing(scale_dict) && continue
        scale_type = get(scale_dict, "type", get(scale_dict, :type, nothing))
        scale_type == "log" || continue
        if ch in (:y, "y")
            axis_kw[:yscale] = log10
        elseif ch in (:x, "x")
            axis_kw[:xscale] = log10
        end
    end
end

_is_faceted(drawable::AlgebraOfGraphics.Layer) =
    haskey(drawable.named, :col) || haskey(drawable.named, :row) || haskey(drawable.named, :layout)
_is_faceted(drawable::AlgebraOfGraphics.Layers) = any(_is_faceted, drawable.layers)
_is_faceted(_) = false

function _draw_kwargs(cfg::Union{Config,Nothing}; faceted=false)
    figure_kw = Dict{Symbol,Any}()
    facet_kw = Dict{Symbol,Any}()
    axis_kw = Dict{Symbol,Any}()
    scales_obj = nothing
    isnothing(cfg) && return (; figure=NamedTuple(), facet=NamedTuple(), axis=NamedTuple(), scales=nothing)
    props = cfg.properties
    if !faceted
        w = get(props, :width, nothing)
        h_val = get(props, :height, nothing)
        if !isnothing(w) || !isnothing(h_val)
            figure_kw[:size] = (something(w, 400), something(h_val, 400))
        end
    end
    # Translate VL encoding scale overrides to Makie axis scales (backwards compat)
    _apply_log_scales!(axis_kw, _as_dict(get(props, :encoding, nothing)))
    for (k, v) in props
        k in (:width, :height, :encoding) && continue  # handled above
        if k === :scales
            s = _as_scales(v); isnothing(s) || (scales_obj = s)
        elseif k === :facet
            _merge_nt!(facet_kw, _as_nt(v))
        elseif k === :axis
            _merge_axis_nt!(axis_kw, _as_nt(v))
        elseif k === :independent_scales
            @warn "AlgebraOfVega: `config(independent_scales=$(repr(v)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
            for ax in _independent_axes_syms(v)
                ax === :x && get!(facet_kw, :linkxaxes, :none)
                ax === :y && get!(facet_kw, :linkyaxes, :none)
            end
        end
    end
    (; figure=NamedTuple(figure_kw), facet=NamedTuple(facet_kw), axis=NamedTuple(axis_kw), scales=scales_obj)
end

"""
    _has_aov_analysis(layer::AlgebraOfGraphics.Layer)

Check if a layer uses an AoV-specific transformation (tidybayes analyses).
"""
_tidybayes_or_nothing(t::TidybayesAnalysis) = t
_tidybayes_or_nothing(_) = nothing

_analysis_in(t::TidybayesAnalysis) = t
function _analysis_in(t::ComposedFunction)
    a = _tidybayes_or_nothing(t.outer); isnothing(a) || return a
    _tidybayes_or_nothing(t.inner)
end
_analysis_in(_) = nothing

_get_analysis(layer::AlgebraOfGraphics.Layer) = _analysis_in(layer.transformation)

function _rows_to_columntable(rows::Vector{Dict{String,Any}})
    cols = collect(keys(rows[1]))
    col_syms = Tuple(Symbol.(cols))
    col_vals = Tuple([getindex.(rows, c) for c in cols])
    NamedTuple{col_syms}(col_vals)
end

function _ribbon_to_aog(summary_nt::NamedTuple, x_sym::Symbol, median_sym::Symbol,
    band_syms::Vector{Tuple{Symbol,Symbol}};
    show_line::Bool=true, color_kw=Dict{Symbol,Any}(), facet_kw=Dict{Symbol,Any}())
    opacities = range(0.2, 0.6, length=length(band_syms))
    result = nothing
    for (i, (lo_sym, hi_sym)) in enumerate(band_syms)
        band_layer = data(summary_nt) *
            mapping(x_sym, lo_sym, hi_sym; color_kw..., facet_kw...) *
            visual(Band; alpha=opacities[i])
        result = isnothing(result) ? band_layer : result + band_layer
    end
    if show_line
        line_layer = data(summary_nt) *
            mapping(x_sym, median_sym; color_kw..., facet_kw...) *
            visual(Lines)
        result = isnothing(result) ? line_layer : result + line_layer
    end
    result
end

function _extract_aog_facet_color_kw(layer)
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    _, facet_fields = _extract_facet_info(layer)
    facet_kw = Dict{Symbol,Any}()
    for ff in facet_fields
        sf = Symbol(ff)
        if haskey(layer.named, :col) && _field_name(layer.named[:col]) == ff
            facet_kw[:col] = sf
        elseif haskey(layer.named, :row) && _field_name(layer.named[:row]) == ff
            facet_kw[:row] = sf
        elseif haskey(layer.named, :layout) && _field_name(layer.named[:layout]) == ff
            facet_kw[:layout] = sf
        end
    end
    color_kw = isnothing(color_field) ? Dict{Symbol,Any}() :
        Dict{Symbol,Any}(:color => Symbol(color_field))
    (; color_field, facet_fields, facet_kw, color_kw)
end

"""
    _lineribbon_to_aog(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer)

Convert a LineRibbonAnalysis layer to pure AoG Band + Lines layers.
"""
function _lineribbon_to_aog(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    (; color_field, facet_fields, facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    detail_strs = string.(a.detail_fields)
    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs;
        color_field, facet_fields, detail_fields=detail_strs)
    summary_nt = _rows_to_columntable(summary)

    sorted_probs = sort(a.probs, rev=true)
    band_syms = Tuple{Symbol,Symbol}[(Symbol(_vl_prob_field("lo", p)), Symbol(_vl_prob_field("hi", p))) for p in sorted_probs]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol("__median__"), band_syms;
        show_line=a.show_line, color_kw, facet_kw)
end

function _precomputed_ribbon_to_aog(a::PrecomputedRibbonAnalysis, layer::AlgebraOfGraphics.Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    median_col = _field_name(layer.positional[2])
    (; facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    summary_nt = Tables.columntable(table)
    band_syms = Tuple{Symbol,Symbol}[(first(b), last(b)) for b in a.bands]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol(median_col), band_syms;
        show_line=a.show_line, color_kw, facet_kw)
end

"""
    _fix_visual_attrs(layer::AlgebraOfGraphics.Layer)

Remap VL-style visual attributes to Makie equivalents (e.g. size → markersize).
Returns the layer unchanged if no visual or no remapping needed.
"""
function _fix_visual_attrs(layer::AlgebraOfGraphics.Layer)
    vis = extract_visual(layer)
    isnothing(vis) && return layer
    attrs = Dict(pairs(vis.attributes))
    changed = false
    if haskey(attrs, :size) && !haskey(attrs, :markersize)
        attrs[:markersize] = pop!(attrs, :size)
        changed = true
    end
    if haskey(attrs, :strokeWidth) && !haskey(attrs, :linewidth)
        attrs[:linewidth] = pop!(attrs, :strokeWidth)
        changed = true
    end
    if haskey(attrs, :strokeDash) && !haskey(attrs, :linestyle)
        v = pop!(attrs, :strokeDash)
        attrs[:linestyle] = _to_linestyle(v)
        changed = true
    end
    if haskey(attrs, :opacity) && !haskey(attrs, :alpha)
        attrs[:alpha] = pop!(attrs, :opacity)
        changed = true
    end
    !changed && return layer
    new_vis = AlgebraOfGraphics.Visual(vis.plottype; attrs...)
    # Rebuild layer with new visual in the transformation
    new_t = _swap_visual(layer.transformation, new_vis)
    AlgebraOfGraphics.Layer(new_t, layer.data, layer.positional, layer.named)
end

_to_linestyle(v::AbstractVector{<:Real}) = Makie.Linestyle(collect(Float64, v))
_to_linestyle(v) = v

_swap_visual(::AlgebraOfGraphics.Visual, new_vis) = new_vis
_swap_visual(t::ComposedFunction{<:AlgebraOfGraphics.Visual}, new_vis) = new_vis ∘ t.inner
_swap_visual(t::ComposedFunction, new_vis) = t.outer ∘ new_vis
_swap_visual(_, new_vis) = new_vis

_convert_drawable(d::AlgebraOfGraphics.Layers) = _to_aog_drawable(d)
_convert_drawable(d::AlgebraOfGraphics.Layer) = _convert_single_layer(d)
_convert_drawable(d) = d

_aog_from_analysis(a::LineRibbonAnalysis, l) = _lineribbon_to_aog(a, l)
_aog_from_analysis(a::PrecomputedRibbonAnalysis, l) = _precomputed_ribbon_to_aog(a, l)
_aog_from_analysis(a, _) = error("sdraw does not yet support $(typeof(a)) — use vdraw for this plot type")

function _convert_single_layer(l::AlgebraOfGraphics.Layer)
    a = _get_analysis(l)
    isnothing(a) && return _fix_visual_attrs(l)
    _aog_from_analysis(a, l)
end

function _to_aog_drawable(layers::AlgebraOfGraphics.Layers)
    converted = map(_convert_single_layer, layers.layers)
    result = nothing
    for c in converted
        result = isnothing(result) ? c : result + c
    end
    result
end

"""
    sdraw(spec, path::AbstractString; kwargs...)

Render an AoG spec via AlgebraOfGraphics.draw → Makie → file.
Saves the figure to `path` (format inferred from extension) and returns
an `h.img` node pointing to `path`.

Requires a Makie backend (e.g. CairoMakie) to be loaded.

Extra `kwargs` are passed to `Makie.save` (e.g. `px_per_unit=2` for retina).
"""
function sdraw(spec, path::AbstractString; kwargs...)
    sdraw_file(spec, path; kwargs...)
    h.img(; src=path)
end

"""
    sdraw_file(spec, path::AbstractString; kwargs...)

Render an AoG spec to a file via AlgebraOfGraphics.draw → Makie.save.
Returns the path. Extra `kwargs` are passed to `Makie.save`.
"""
function sdraw_file(spec, path::AbstractString; kwargs...)
    drawable, cfg = _extract_drawable(spec)
    drawable = _convert_drawable(drawable)
    kw = _draw_kwargs(cfg; faceted=_is_faceted(drawable))
    fg = isnothing(kw.scales) ?
        AlgebraOfGraphics.draw(drawable; figure=kw.figure, facet=kw.facet, axis=kw.axis) :
        AlgebraOfGraphics.draw(drawable, kw.scales; figure=kw.figure, facet=kw.facet, axis=kw.axis)
    Makie.save(path, fg; kwargs...)
    path
end
