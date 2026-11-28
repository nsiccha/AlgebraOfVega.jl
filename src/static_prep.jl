# --- Static (Makie) rendering: the backend-free preparation ---
#
# `sdraw`/`sdraw!`/`sdraw_file` live in the `AlgebraOfVegaMakieExt` extension,
# which converts the AoV values prepared here into AlgebraOfGraphics/Makie ones
# and draws them. What needs Makie itself (the theme's text colour, the
# background under an axis, labelling the drawn panels) is there too.

"""
    _extract_drawable(spec)

Extract the AoG drawable (Layer/Layers) from a spec. Returns `(drawable, config)`.
"""
_extract_drawable(layer::Layer) = (layer, nothing)
_extract_drawable(layers::Layers) = (layers, nothing)
_extract_drawable(v::VegaSpec) = (v.drawable, v.config)

"""
    _draw_kwargs(cfg::Union{Config,Nothing})

Translate AoV Config properties into keyword arguments for `AlgebraOfGraphics.draw`
(values in AoV's vocabulary; the Makie extension converts them).
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

_is_faceted(drawable::Layer) =
    haskey(drawable.named, :col) || haskey(drawable.named, :row) || haskey(drawable.named, :layout)
_is_faceted(drawable::Layers) = any(_is_faceted, drawable.layers)
_is_faceted(_) = false

# The distinct `layout=` levels across the drawable's layer tables: the number of
# wrap-facet panels (0 without a `layout=` mapping or readable table).
_layout_levels(drawable::Layer) = length(_layout_values!(Set{Any}(), drawable))
_layout_levels(drawable::Layers) =
    length(foldl(_layout_values!, drawable.layers; init=Set{Any}()))
_layout_levels(_) = 0
function _layout_values!(seen::Set, layer::Layer)
    haskey(layer.named, :layout) || return seen
    tbl = extract_data(layer)
    field = Symbol(_field_name(layer.named[:layout]))
    (isnothing(tbl) || !(field in Tables.columnnames(tbl))) && return seen
    union!(seen, Tables.getcolumn(tbl, field))
end

# The Makie figure wraps a `layout=` facet into the columns of its Vega-Lite spec
# (`_apply_wrap_default!`): an authored `config(columns=N)`, else AoG's rule with the
# authored panel aspect. AoV's static path drops `width`/`height` on a faceted figure,
# so AoG alone would wrap with aspect 1; the count goes in as the `Layout` palette
# `wrapped(cols=k)` instead. An authored `Layout` palette is AoG's own and wins.
function _sdraw_scales(scales_obj, drawable, cfg)
    scales_obj = _static_ink_palette(scales_obj)
    n = _layout_levels(drawable)
    n > 0 || return scales_obj
    dict = isnothing(scales_obj) ? Dict{Symbol,Any}() :
        Dict{Symbol,Any}(k => (; pairs(v)...) for (k, v) in pairs(scales_obj.dict))
    layout = get(dict, :Layout, (;))
    haskey(layout, :palette) && return scales_obj
    props = isnothing(cfg) ? Dict{Symbol,Any}() : cfg.properties
    cols = _as_number(get(props, :columns, nothing))
    cols = isnothing(cols) ?
        _aog_wrap_columns(n, _panel_aspect(get(props, :width, nothing), get(props, :height, nothing))) :
        max(1, round(Int, cols))
    dict[:Layout] = merge(layout, (; palette=AlgebraOfVega.wrapped(; cols)))
    AlgebraOfVega.scales(; dict...)
end

function _draw_kwargs(cfg::Union{Config,Nothing}; faceted=false, layer_encodings=Any[])
    figure_kw = Dict{Symbol,Any}()
    facet_kw = Dict{Symbol,Any}()
    axis_kw = Dict{Symbol,Any}()
    scales_obj = nothing
    # A summand's encoding override (`VegaSpec.layer_encodings`) is per layer, but
    # a scale type in it sets the axis every layer shares — Vega-Lite merges it
    # into the shared scale the same way.
    for enc in layer_encodings
        _apply_log_scales!(axis_kw, _as_dict(enc))
    end
    panel_labels = Dict{String,String}()
    isnothing(cfg) && return (; figure=NamedTuple(), facet=NamedTuple(), axis=NamedTuple(axis_kw), scales=nothing, panel_labels)
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
            # Per-panel Y scales (a type, domain, clamp, … per facet panel) are
            # a Vega-Lite composition (a concat of one view per panel). Makie's
            # `draw(spec, scales(...))` has no per-facet-panel scale; rendering
            # one shared scale would silently drop the panels' own (a log type
            # the never-pre-log rule needs, a cut-off domain) — fail loud.
            if !isnothing(s) && !isnothing(_scales_panel_y_scales(s))
                error("AlgebraOfVega: per-panel Y scales (a `scales(Y=(; …))` key given as a `Dict` keyed by panel, e.g. `scale=Dict(...)` or `domain=Dict(...)`) are not supported on the static Makie path; render with `vdraw`/`to_vegalite` (a Vega-Lite concat of one view per facet column, row or wrapped panel), or write a file with `vsave`, instead.")
            end
        elseif k === :select && v isa SelectGroupOptions
            throw(ArgumentError("AlgebraOfVega: `config(select=(; field=:$(v.field), …))` follows a click selection in the browser, which a static Makie figure cannot; render with `vdraw`/`to_html`, write the initial key's figure with `vsave`, or filter the table to one key for a static figure."))
        elseif k === :frame
            throw(ArgumentError("AlgebraOfVega: `config(frame=…)` animations are not supported on the static Makie path; render with `vdraw`/`to_html`, or filter the table to one frame for a static figure."))
        elseif k === :facet
            nt = _as_nt(v)
            if !isnothing(nt)
                # `xlabels`/`ylabels` are AoV's (src/panel_labels.jl): AoG's `draw` gets
                # the panels' own labels instead (`_label_static_panels!`).
                merge!(panel_labels, _panel_label_opts(nt))
                _merge_nt!(facet_kw, _without_panel_label_keys(nt))
            end
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
    # Each panel keeps its own axis label: AoG spans one label over the grid, and hides
    # inner panels' decorations, only when every axis has the same one.
    for (ch, single, hide) in (("x", :singlexlabel, :hidexdecorations), ("y", :singleylabel, :hideydecorations))
        haskey(panel_labels, ch) || continue
        get!(facet_kw, single, false)
        get!(facet_kw, hide, false)
    end
    (; figure=NamedTuple(figure_kw), facet=NamedTuple(facet_kw), axis=NamedTuple(axis_kw), scales=scales_obj, panel_labels)
end

# The facet fields of an AoG drawable, by facet channel (`:layout`, `:row`, `:col`).
function _drawable_facet_fields(drawable)
    out = Dict{Symbol,String}()
    for l in something(_spec_layers_or_nothing(drawable), [])
        l isa Layer || continue
        for ch in (:layout, :row, :col)
            haskey(l.named, ch) && get!(out, ch, _field_name(l.named[ch]))
        end
    end
    out
end

const _STATIC_FACET_SCALES = (:layout => :Layout, :row => :Row, :col => :Col)

# A facet whose labels the panels' axes now show (`config(facet=(; ylabels=:panel))`
# with `:panel` its field) draws no facet labels, as the Vega-Lite figure leaves its
# header out: AoG's `legend=false` on that facet scale.
function _hide_static_panel_headers(scales_obj, drawable, labels)
    isempty(labels) && return scales_obj
    facets = _drawable_facet_fields(drawable)
    hidden = [name for (ch, name) in _STATIC_FACET_SCALES if get(facets, ch, nothing) in values(labels)]
    isempty(hidden) && return scales_obj
    dict = isnothing(scales_obj) ? Dict{Symbol,Any}() :
        Dict{Symbol,Any}(k => (; pairs(v)...) for (k, v) in pairs(scales_obj.dict))
    for name in hidden
        dict[name] = merge(get(dict, name, (;)), (; legend=false))
    end
    AlgebraOfVega.scales(; dict...)
end

"""
    _has_aov_analysis(layer::Layer)

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

_get_analysis(layer::Layer) = _analysis_in(layer.transformation)

function _rows_to_columntable(rows::Vector{Dict{String,Any}})
    cols = collect(keys(rows[1]))
    col_syms = Tuple(Symbol.(cols))
    col_vals = Tuple([getindex.(rows, c) for c in cols])
    NamedTuple{col_syms}(col_vals)
end

# Rebuild a bare field as an AoG selector, reattaching the display label the
# Vega-Lite path threads via `_field_label`. A label equal to the field name
# stays a bare `Symbol`, so unlabeled specs lower byte-identically to before.
_labeled_aog_field(field::AbstractString, label::AbstractString) =
    label != field ? (Symbol(field) => label) : Symbol(field)

function _ribbon_to_aog(summary_nt::NamedTuple, x_sym::Symbol, median_sym::Symbol,
    band_syms::Vector{Tuple{Symbol,Symbol}};
    show_line::Bool=true, color_kw=Dict{Symbol,Any}(), facet_kw=Dict{Symbol,Any}(),
    x_label::AbstractString=string(x_sym), y_label::AbstractString=string(median_sym),
    fixed_color=nothing)
    opacities = length(band_syms) == 1 ? [0.4] : range(0.2, 0.6, length=length(band_syms))
    # A fixed `visual(; color=…)` colours the bands and the median line; a colour
    # mapping wins, as on the Vega-Lite path (`_ribbon_to_vl`).
    fixed_kw = (isnothing(fixed_color) || !isempty(color_kw)) ? (;) :
        (; color=_static_color(fixed_color))
    x_sel = _labeled_aog_field(string(x_sym), x_label)
    median_sel = _labeled_aog_field(string(median_sym), y_label)
    result = nothing
    for (i, (lo_sym, hi_sym)) in enumerate(band_syms)
        band_layer = data(summary_nt) *
            mapping(x_sel, _labeled_aog_field(string(lo_sym), y_label),
                _labeled_aog_field(string(hi_sym), y_label); color_kw..., facet_kw...) *
            visual(Band; alpha=opacities[i], fixed_kw...)
        result = isnothing(result) ? band_layer : result + band_layer
    end
    if show_line
        line_layer = data(summary_nt) *
            mapping(x_sel, median_sel; color_kw..., facet_kw...) *
            visual(Lines; fixed_kw...)
        result = isnothing(result) ? line_layer : result + line_layer
    end
    result
end

function _extract_aog_facet_color_kw(layer)
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    _, facet_fields = _extract_facet_info(layer)
    facet_kw = Dict{Symbol,Any}()
    for ff in facet_fields
        if haskey(layer.named, :col) && _field_name(layer.named[:col]) == ff
            facet_kw[:col] = _labeled_aog_field(ff, _field_label(layer.named[:col]))
        elseif haskey(layer.named, :row) && _field_name(layer.named[:row]) == ff
            facet_kw[:row] = _labeled_aog_field(ff, _field_label(layer.named[:row]))
        elseif haskey(layer.named, :layout) && _field_name(layer.named[:layout]) == ff
            facet_kw[:layout] = _labeled_aog_field(ff, _field_label(layer.named[:layout]))
        end
    end
    color_kw = isnothing(color_field) ? Dict{Symbol,Any}() :
        Dict{Symbol,Any}(:color => _labeled_aog_field(color_field, color_label))
    (; color_field, color_label, facet_fields, facet_kw, color_kw)
end

"""
    _lineribbon_to_aog(a::LineRibbonAnalysis, layer::Layer)

Convert a LineRibbonAnalysis layer to pure AoG Band + Lines layers.
"""
function _lineribbon_to_aog(a::LineRibbonAnalysis, layer::Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    (; color_field, facet_fields, facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    detail_strs = string.(a.detail_fields)
    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs;
        color_field, facet_fields, detail_fields=detail_strs)
    summary_nt = _rows_to_columntable(summary)

    sorted_probs = sort(a.probs, rev=true)
    band_syms = Tuple{Symbol,Symbol}[(Symbol(_vl_prob_field("lo", p)), Symbol(_vl_prob_field("hi", p))) for p in sorted_probs]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol("__median__"), band_syms;
        show_line=a.show_line, color_kw, facet_kw, x_label, y_label,
        fixed_color=_analysis_fixed_color(layer, _ribbon_name(a); static=true))
end

function _precomputed_ribbon_to_aog(a::PrecomputedRibbonAnalysis, layer::Layer)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    median_col = _field_name(layer.positional[2])
    y_label = _field_label(layer.positional[2])
    (; facet_kw, color_kw) = _extract_aog_facet_color_kw(layer)

    summary_nt = Tables.columntable(table)
    band_syms = Tuple{Symbol,Symbol}[(first(b), last(b)) for b in a.bands]

    _ribbon_to_aog(summary_nt, Symbol(x_field), Symbol(median_col), band_syms;
        show_line=a.show_line, color_kw, facet_kw, x_label, y_label,
        fixed_color=_analysis_fixed_color(layer, _ribbon_name(a); static=true))
end

"""
    _fix_visual_attrs(layer::Layer)

Remap VL-style visual attributes to Makie equivalents (e.g. size → markersize).
Returns the layer unchanged if no visual or no remapping needed.

A VL-spelled `size` on a Scatter is a Vega area (px²); Makie `markersize` is a
length (px), so the value is converted back with `_vl_size_to_markersize` —
the inverse of the forward `_markersize_to_vl_size` — keeping one spec
visually identical on both renderers.

Each `visual(...)` term in the layer is rewritten in place, so AoG still
combines them as authored; whether the layer is a Scatter is read from their
combination (`extract_visual`).
"""
function _fix_visual_attrs(layer::Layer)
    vis = extract_visual(layer)
    isnothing(vis) && return layer
    scatter = vis.plottype <: Scatter
    t = _map_visuals(v -> _fix_visual(v, scatter), layer.transformation)
    t === layer.transformation && return layer
    Layer(t, layer.data, layer.positional, layer.named)
end

# One `visual(...)` term with its VL-style attributes renamed; the term itself
# when nothing needs it.
function _fix_visual(vis::Visual, scatter::Bool)
    attrs = Dict(pairs(vis.attributes))
    changed = false
    for k in (:color, :strokecolor)
        if get(attrs, k, nothing) === :ink
            attrs[k] = _static_color(:ink)
            changed = true
        end
    end
    if haskey(attrs, :size) && !haskey(attrs, :markersize)
        v = pop!(attrs, :size)
        # Only a true Scatter takes a marker size; other marks keep the value.
        attrs[:markersize] = (scatter && v isa Real) ?
            _vl_size_to_markersize(v) : v
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
    !changed && return vis
    Visual(vis.plottype, NamedArguments(attrs), vis.target)
end

# Static output has no CSS host, so the theme-following `:ink` becomes the
# active Makie theme's text colour (`_static_text_color`, AlgebraOfVegaMakieExt),
# which follows light/dark themes and is readable on exports. Any other colour
# is already a Makie colour.
_static_color(color) = color === :ink ? _static_text_color() : color
function _static_text_color end

# Resolve before converting analyses, so a ribbon's fixed colour takes the
# same destination surface as an ordinary visual. Never edit the authored layer.
function _background_visual(vis::Visual, color)
    attrs = Dict(pairs(vis.attributes))
    changed = false
    for k in (:color, :strokecolor, :stroke, :fill)
        get(attrs, k, nothing) === :background || continue
        pop!(attrs, k)
        attrs[k === :stroke ? :strokecolor : k === :fill ? :color : k] = color
        changed = true
    end
    changed || return vis
    Visual(vis.plottype, NamedArguments(attrs), vis.target)
end
function _background_drawable(layer::Layer, color)
    t = _map_visuals(v -> _background_visual(v, color), layer.transformation)
    t === layer.transformation && return layer
    Layer(t, layer.data, layer.positional, layer.named)
end
_background_drawable(layers::Layers, color) =
    Layers([_background_drawable(l, color) for l in layers.layers])
_background_drawable(d, color) = d

# The opaque colour of the surface a static figure draws on, from the Makie axis
# or figure it goes into (`AlgebraOfVegaMakieExt`).
function _static_background end

function _has_background(layer::Layer)
    vis = extract_visual(layer)
    !isnothing(vis) && any(k -> get(vis.attributes, k, nothing) === :background,
        (:color, :strokecolor, :stroke, :fill))
end
_has_background(layers::Layers) = any(_has_background, layers.layers)
_has_background(_) = false
_static_drawable(authored, position, axis) = _convert_drawable(_has_background(authored) ?
    _background_drawable(authored, _static_background(position, axis)) : authored)

# A `Color` palette's `:ink` entries (`scales(Color=(; palette=[:ink, …]))`, which
# `vdraw` draws in the page's text colour) take that text colour too; Makie
# itself has no colour named `ink`.
_static_ink_palette(s) = s
function _static_ink_palette(s::Scales)
    color = get(s.dict, :Color, nothing)
    (isnothing(color) || !haskey(color, :palette)) && return s
    pal = color[:palette]
    (pal isa Union{AbstractVector,Tuple} && any(c -> c === :ink, pal)) || return s
    dict = Dict{Symbol,Any}(k => (; pairs(v)...) for (k, v) in pairs(s.dict))
    dict[:Color] = merge(dict[:Color], (; palette=Any[_static_color(c) for c in pal]))
    AlgebraOfVega.scales(; dict...)
end

# A VL `strokeDash` pattern; the Makie extension draws it as `Makie.Linestyle`.
struct _LinestylePattern
    pattern::Vector{Float64}
end
_to_linestyle(v::AbstractVector{<:Real}) = _LinestylePattern(collect(Float64, v))
_to_linestyle(v) = v

# The transformation chain with `f` applied to every `visual(...)` term. An
# unchanged chain comes back `===` the original.
_map_visuals(f, v::Visual) = f(v)
function _map_visuals(f, t::ComposedFunction)
    outer, inner = _map_visuals(f, t.outer), _map_visuals(f, t.inner)
    outer === t.outer && inner === t.inner ? t : outer ∘ inner
end
_map_visuals(f, t) = t

_convert_drawable(d::Layers) = _to_aog_drawable(d)
_convert_drawable(d::Layer) = _convert_single_layer(d)
_convert_drawable(d) = d

_aog_from_analysis(a::LineRibbonAnalysis, l) = _lineribbon_to_aog(a, l)
_aog_from_analysis(a::PrecomputedRibbonAnalysis, l) = _precomputed_ribbon_to_aog(a, l)
_aog_from_analysis(a, _) = error("sdraw does not yet support $(typeof(a)) — use vdraw for this plot type, or vsave(spec, path) for a PDF/SVG/PNG file of it")

function _convert_single_layer(l::Layer)
    area = extract_transformation(l, MapAreaAnalysis)
    isnothing(area) || error(
        "sdraw does not support $(_map_term(area)) — a map has no Makie analogue in AlgebraOfVega; use vdraw for this plot type, or vsave(spec, path) for a PDF/SVG/PNG file of it")
    a = _get_analysis(l)
    isnothing(a) && return _fix_visual_attrs(_without_ref_text(l))
    _aog_from_analysis(a, l)
end

# A reference line's or period's `text` mapping names it in the browser
# (src/ref_labels.jl); Makie's `vlines`/`vspan`/`hlines`/`hspan` have no text,
# so the static figure leaves the labels out.
function _without_ref_text(l::Layer)
    vis = extract_visual(l)
    (isnothing(vis) || !(vis.plottype <: Union{VLines,VSpan,HLines,HSpan}) || !haskey(l.named, :text)) && return l
    @warn "sdraw: Makie draws no labels on $(_plotsym(vis.plottype)); the `text` mapping of this reference layer is left out (vdraw and vsave label it)." maxlog=1
    named = [k => v for (k, v) in pairs(l.named) if k !== :text]
    m = AlgebraOfVega.mapping(l.positional...; named...)
    Layer(l.transformation, l.data, m.positional, m.named)
end

function _to_aog_drawable(layers::Layers)
    converted = map(_convert_single_layer, layers.layers)
    result = nothing
    for c in converted
        result = isnothing(result) ? c : result + c
    end
    result
end
