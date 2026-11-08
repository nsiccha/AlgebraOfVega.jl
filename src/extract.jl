# --- Extract components from AoG Layer ---

# A layer's `visual(...)` terms, combined as AoG applies them to its processed
# layer (`Visual(::ProcessedLayer)`, in chain order): a specific plot type replaces
# the default `Plot{plot}`, and a later term's attributes win. So a library can add
# `visual(; clip=true)` to an app's `visual(Scatter)` layer. A single term is
# returned as it is; `nothing` when the layer has none.
function extract_visual(layer::AlgebraOfGraphics.Layer)
    visuals = _chain_parts(AlgebraOfGraphics.Visual, layer.transformation)
    isempty(visuals) && return nothing
    length(visuals) == 1 && return only(visuals)
    pl = foldl((pl, v) -> v(pl), visuals; init=AlgebraOfGraphics.ProcessedLayer())
    AlgebraOfGraphics.Visual(pl.plottype, pl.attributes, nothing)
end

# Every `T` in a transformation chain, in the order AoG applies them
# (`l * l′` composes `l′.transformation ∘ l.transformation`, so inner first).
_chain_parts(::Type{T}, t::T) where {T} = T[t]
_chain_parts(::Type{T}, t::ComposedFunction) where {T} =
    vcat(_chain_parts(T, t.inner), _chain_parts(T, t.outer))
_chain_parts(::Type{T}, _) where {T} = T[]

_unwrap_columns(cols::AlgebraOfGraphics.Columns) = cols.columns
_unwrap_columns(cols) = cols

function extract_data(layer::AlgebraOfGraphics.Layer)
    isnothing(layer.data) && return nothing
    _unwrap_columns(layer.data)
end

is_pregrouped(layer::AlgebraOfGraphics.Layer) = _layer_pregrouped(layer.data)
_layer_pregrouped(::Nothing) = false
_layer_pregrouped(data) = _columns_pregrouped(_unwrap_columns(data))
_columns_pregrouped(::AlgebraOfGraphics.Pregrouped) = true
_columns_pregrouped(_) = false

"""
    pregrouped_to_vl(layer; is_sublayer=false)

Translate a pregrouped AoG layer to Vega-Lite. Flattens grouped vectors
into long-form inline data with "x" (nominal) and "y" (quantitative) columns.
Handles renamer labels on the x axis.
"""
function pregrouped_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    pos = layer.positional

    # Extract x and y grouped data from positional args
    x_arg = pos[1]
    y_arg = length(pos) >= 2 ? pos[2] : nothing

    # Unwrap x: may be Pair(data, renamer) or raw data
    x_data, x_rename = _unwrap_x_arg(x_arg)

    # Collect ordered labels from renamer for sort order
    x_sort = _renamer_sort(x_rename)

    # Flatten grouped vectors into long-form rows
    rows = Dict{String,Any}[]
    n_groups = length(x_data)
    for i in 1:n_groups
        x_vals = x_data[i]
        for j in eachindex(x_vals)
            x_raw = x_vals[j]
            x_label = _apply_rename(x_rename, x_raw)
            row = Dict{String,Any}("x" => x_label)
            if !isnothing(y_arg)
                yval = y_arg[i][j]
                # Skip NaN/Inf values — they produce "infinite extent" VL warnings
                isnothing(_vl_safe(yval)) && continue
                row["y"] = yval
            end
            push!(rows, row)
        end
    end

    # Visual / mark
    vis = extract_visual(layer)
    mark = isnothing(vis) ? "boxplot" : _visual_mark(vis)

    # Encoding
    encoding = Dict{String,Any}()
    x_enc = Dict{String,Any}("field" => "x", "type" => "nominal")
    if !isnothing(x_sort)
        x_enc["sort"] = x_sort
    end
    encoding["x"] = x_enc
    if !isnothing(y_arg)
        encoding["y"] = Dict{String,Any}("field" => "y", "type" => "quantitative")
    end

    # Named mappings (color, etc.)
    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    # Auto tooltip
    tt = vl_tooltips(encoding)
    !isempty(tt) && (encoding["tooltip"] = tt)

    spec = Dict{String,Any}(
        "data" => Dict{String,Any}("values" => rows),
        "mark" => mark,
        "encoding" => encoding,
    )

    spec
end

_vl_safe(v) = v
_vl_safe(v::Number) = isfinite(v) ? v : nothing

# Pregrouped x-arg may arrive as `data => renamer` or as raw data
_unwrap_x_arg(x) = (x, nothing)
_unwrap_x_arg(x::Pair) = (first(x), last(x))

# Sort labels from a renamer (only AoG.Renamer carries an explicit order)
_renamer_sort(_) = nothing
_renamer_sort(r::AlgebraOfGraphics.Renamer) = [string(l) for l in r.labels]

# Map a raw x-tick value through the optional renamer before stringifying
_apply_rename(::Nothing, x_raw) = string(x_raw)
_apply_rename(r::AlgebraOfGraphics.Renamer, x_raw) = string(r(x_raw).value)
_apply_rename(f::Function, x_raw) = string(f(x_raw))

# Histogram bin spec: integer → maxbins; vector of edges → step + extent
_apply_bins!(_, _) = nothing
_apply_bins!(bp::Dict{String,Any}, n::Integer) = (bp["maxbins"] = Int(n); nothing)
function _apply_bins!(bp::Dict{String,Any}, edges::AbstractVector)
    length(edges) >= 2 || return nothing
    e = collect(float.(edges))
    bp["step"] = e[2] - e[1]
    bp["extent"] = [first(e), last(e)]
    nothing
end

# datalimits: only 2-tuple of Reals is meaningful
_apply_datalimits!(args...) = nothing
function _apply_datalimits!(bp::Dict{String,Any}, dl::Tuple{<:Real,<:Real})
    bp["extent"] = [float(dl[1]), float(dl[2])]
    nothing
end

function data_to_vl(table)
    isnothing(table) && return nothing
    rows = Tables.rowtable(table)
    vals = [
        Dict{String,Any}(string(k) => _vl_safe(v) for (k, v) in pairs(nt))
        for nt in rows
    ]
    Dict{String,Any}("values" => vals)
end

"""Vega-Lite `size` matching a scalar Makie Scatter `markersize`.

Makie `markersize` is a nominal length (px); Vega-Lite point `size` is an area,
and the Vega renderer draws points with diameter √size (SVG-measured: size=8 →
r=1.414, size=25 → r=2.5). Makie's default circle glyph spans 1/√2 of the
nominal box (Bezier radius 0.3525 in Makie `src/conversions.jl`; CairoMakie
render measures diameter ≈ 0.705 × markersize), so equal screen extent on both
sides needs `size = (ms/√2)² = ms²/2` — e.g. `markersize=8` → `32`, which Vega
draws 5.7px across, matching the static 5.6px dot. A VL-spelled `size` is
already in Vega units and passes through untouched.
"""
_markersize_to_vl_size(ms::Real) = float(ms)^2 / 2

"""Makie Scatter `markersize` matching a scalar Vega-Lite point `size`.

Inverse of `_markersize_to_vl_size`, for the static (`sdraw`) remap of
VL-spelled visual attributes. Non-positive input passes through: Makie itself
rejects it, and this remap must not invent a new throw site.
"""
function _vl_size_to_markersize(s::Real)
    f = float(s)
    (isfinite(f) && f > 0) ? sqrt(2 * f) : s
end

# Makie `linestyle` symbols → Vega-Lite `strokeDash` arrays (pixel dash/gap
# patterns). A Makie linestyle symbol is a first-class visual attribute, but
# Vega-Lite's `mark.strokeDash` takes `number[]` — a bare symbol serializes to a
# string ("dash") that Vega ignores, so the line renders solid. The static
# (`sdraw`) path renders these symbols natively through Makie, so converting
# here keeps the interactive (`vdraw`) path visually consistent with it. The
# ratios mirror Makie's own `line_diff_pattern` (dash=gap=3, dot=1), scaled ×2
# for on-screen visibility at a typical line width. A numeric array is already a
# VL dash spec and passes through unchanged; `:solid` (or any `nothing`) ⇒ the
# `strokeDash` property is omitted entirely (a solid line, VL's default).
_LINESTYLE_DASH = Dict{Symbol,Any}(
    :solid      => nothing,
    :dash       => [6, 6],
    :dot        => [2, 4],
    :dashdot    => [6, 6, 2, 6],
    :dashdotdot => [6, 6, 2, 4, 2, 6],
)

_linestyle_to_strokedash(v::Symbol) = get(_LINESTYLE_DASH, v, v)
_linestyle_to_strokedash(v) = v

# Makie `marker` symbols → Vega-Lite `shape` names (point-mark property). A
# fixed Makie marker is a first-class visual attribute, but Vega-Lite's
# `mark.shape` takes its own vocabulary (`"circle"`, `"square"`, `"cross"`,
# `"diamond"`, `"triangle-up"`, ...). Passing the AoG kwarg name through as
# `mark.marker` emits a property Vega-Lite ignores, so every fixed-marker
# layer rendered as a circle — while the static (`sdraw`) path renders the
# symbol natively through Makie, a silent vdraw/sdraw divergence. Symbols
# with a Vega counterpart are renamed; anything else passes through as its
# string form (Vega ignores unknown shapes the same way). A data-driven
# `mapping(...; marker=:field)` is untouched — it already becomes a `shape`
# encoding via `_CHANNEL_MAP`.
_MARKER_SHAPE = Dict{Symbol,String}(
    :circle    => "circle",
    :rect      => "square",
    :diamond   => "diamond",
    :cross     => "cross",
    :+         => "cross",
    :utriangle => "triangle-up",
    :dtriangle => "triangle-down",
    :ltriangle => "triangle-left",
    :rtriangle => "triangle-right",
)

_marker_to_shape(v::Symbol) = get(_MARKER_SHAPE, v, string(v))
_marker_to_shape(v) = v

# The mark properties Vega-Lite reads: the `MarkDef`, `BoxPlotDef`,
# `ErrorBarDef` and `ErrorBandDef` property names of the schema of the vendored
# Vega-Lite (5.23.0). A fixed `visual(...)` attribute under one of these names
# reaches the mark as written (the Vega-Lite spelling). Any other name is either
# translated in `visual_attrs_to_mark_props` or reported there: Vega-Lite drops a
# mark property it does not read without a word, so passing a Makie name such as
# `fontsize` through drew the mark as if it had never been set.
const _VL_MARK_PROPERTIES = Set{Symbol}([
    :align, :angle, :aria, :ariaRole, :ariaRoleDescription, :aspect, :band,
    :bandSize, :baseline, :binSpacing, :blend, :borders, :box, :clip, :color,
    :continuousBandSize, :cornerRadius, :cornerRadiusBottomLeft,
    :cornerRadiusBottomRight, :cornerRadiusEnd, :cornerRadiusTopLeft,
    :cornerRadiusTopRight, :cursor, :description, :dir, :discreteBandSize, :dx,
    :dy, :ellipsis, :extent, :fill, :fillOpacity, :filled, :font, :fontSize,
    :fontStyle, :fontWeight, :height, :href, :innerRadius, :interpolate,
    :invalid, :limit, :line, :lineBreak, :lineHeight, :median, :minBandSize,
    :opacity, :order, :orient, :outerRadius, :outliers, :padAngle, :point,
    :radius, :radius2, :radius2Offset, :radiusOffset, :rule, :shape, :size,
    :smooth, :stroke, :strokeCap, :strokeDash, :strokeDashOffset, :strokeJoin,
    :strokeMiterLimit, :strokeOffset, :strokeOpacity, :strokeWidth, :style,
    :tension, :text, :theta, :theta2, :theta2Offset, :thetaOffset, :thickness,
    :ticks, :time, :timeUnitBandPosition, :timeUnitBandSize, :tooltip, :type,
    :url, :width, :x, :x2, :x2Offset, :xOffset, :y, :y2, :y2Offset, :yOffset,
])

# The properties a Vega-Lite composite mark reads: the `ErrorBarDef`,
# `BoxPlotDef` and `ErrorBandDef` property names of the vendored Vega-Lite
# (5.23.0) schema, plus `style`, which `_style_composite_parts` moves onto the
# drawn parts. A composite builds its parts itself and carries only `color`,
# `opacity` and `clip` over to them, so any other mark property on it
# (`strokeWidth`, `strokeDash`, `stroke`, `width`, …) is dropped without a word,
# although the plain marks read it: `visual(Rangebars; linewidth=3.5)` drew the
# error bars at the default width (snag `aov-rangebars-li-830d8b72`).
const _COMPOSITE_MARK_PROPERTIES = Dict{String,Set{String}}(
    "errorbar" => Set(["clip", "color", "extent", "opacity", "orient", "rule", "size",
        "style", "thickness", "ticks", "type"]),
    "boxplot" => Set(["box", "clip", "color", "extent", "invalid", "median", "opacity",
        "orient", "outliers", "rule", "size", "style", "ticks", "type"]),
    "errorband" => Set(["band", "borders", "clip", "color", "extent", "interpolate",
        "opacity", "orient", "style", "tension", "type"]),
)

# The properties the composite mark of plot type `T` reads, or `nothing` when
# `T` draws a plain mark (or none, such as a bare `visual(; color=…)`).
function _composite_mark_properties(T::Type)
    for (PT, mark) in _MARK_MAP
        T <: PT && return get(_COMPOSITE_MARK_PROPERTIES, mark, nothing)
    end
    nothing
end

# Makie `Errorbars`/`Rangebars` attributes → Vega-Lite `errorbar` properties.
# Makie draws each bar as a line `linewidth` wide and, unless `whiskerwidth` is
# 0 (its default), a `whiskerwidth` × `linewidth` rectangle at both ends.
# Vega-Lite's error bar draws the same two parts, a `rule` and `ticks`, and
# reads their widths from its own properties: `thickness` is the rule's stroke
# width and the ticks' thickness, `size` the ticks' length. Makie dashes the bar
# (`linestyle`) but not the whiskers, so a dash goes onto the `rule` part. A
# method returns the properties, or `nothing` when the value has no Vega-Lite
# counterpart (it is then reported); `missing` means the attribute is not one
# translated here.
const _LINE_WIDTH_ATTRS = Union{Val{:linewidth}, Val{:strokewidth}, Val{:strokeWidth}}
_errorbar_mark_props(::Val, v) = missing
_errorbar_mark_props(::_LINE_WIDTH_ATTRS, v) = nothing
_errorbar_mark_props(::_LINE_WIDTH_ATTRS, v::Real) = Dict{String,Any}("thickness" => v)
_errorbar_mark_props(::Val{:whiskerwidth}, v) = nothing
_errorbar_mark_props(::Val{:whiskerwidth}, v::Real) = iszero(v) ? Dict{String,Any}() :
    Dict{String,Any}("size" => v, "ticks" => Dict{String,Any}())
function _errorbar_mark_props(::Union{Val{:linestyle}, Val{:strokeDash}}, v)
    dash = _linestyle_to_strokedash(v)
    isnothing(dash) ? Dict{String,Any}() : Dict{String,Any}("rule" => Dict{String,Any}("strokeDash" => dash))
end

# Merge one attribute's mark properties into the mark. A composite's part
# (`rule`, `ticks`, …) given as an object by two attributes, such as
# `linestyle` and a Vega-Lite `rule=(; strokeCap="round")`, keeps both.
function _merge_mark_props!(props::Dict{String,Any}, p::Dict{String,Any})
    for (k, v) in p
        old = get(props, k, nothing)
        props[k] = _is_part_object(old) && _is_part_object(v) ? merge(_part_dict(old), _part_dict(v)) : v
    end
    props
end
_is_part_object(x) = x isa AbstractDict || x isa NamedTuple
_part_dict(x) = Dict{String,Any}(string(k) => v for (k, v) in pairs(x))

# Makie `Text` attributes → Vega-Lite text-mark properties. A method returns the
# properties, or `nothing` when the value has no Vega-Lite counterpart (it is
# then reported); `missing` means the attribute is not one translated here.
_text_mark_props(::Val, v) = missing
_text_mark_props(::Val{:fontsize}, v) = nothing
_text_mark_props(::Val{:fontsize}, v::Real) = Dict{String,Any}("fontSize" => v)
# Makie turns text counter-clockwise by `rotation` radians; Vega turns it
# clockwise by `angle` degrees.
_text_mark_props(::Val{:rotation}, v) = nothing
_text_mark_props(::Val{:rotation}, v::Real) = Dict{String,Any}("angle" => -rad2deg(v))
# Makie's pixel `offset` points up; Vega's `dy` points down.
_text_mark_props(::Val{:offset}, v) = nothing
_text_mark_props(::Val{:offset}, v::Union{Tuple{Real,Real},AbstractVector{<:Real}}) =
    length(v) == 2 ? Dict{String,Any}("dx" => v[1], "dy" => -v[2]) : nothing
# Makie's `align = (horizontal, vertical)` anchors the text at its position;
# Vega-Lite splits it into `align` and `baseline`. A string is the Vega-Lite
# spelling of the horizontal half and passes as written.
const _TEXT_HALIGN = Dict{Symbol,String}(:left => "left", :center => "center", :right => "right")
const _TEXT_VALIGN = Dict{Symbol,String}(
    :top => "top", :center => "middle", :bottom => "bottom", :baseline => "alphabetic")
_text_mark_props(::Val{:align}, v) = nothing
_text_mark_props(::Val{:align}, v::AbstractString) = Dict{String,Any}("align" => v)
function _text_mark_props(::Val{:align}, v::Tuple{Symbol,Symbol})
    h, b = get(_TEXT_HALIGN, v[1], nothing), get(_TEXT_VALIGN, v[2], nothing)
    (isnothing(h) || isnothing(b)) ? nothing : Dict{String,Any}("align" => h, "baseline" => b)
end
# A font name is a family in both; a Makie font symbol names one of the theme's
# `fonts`, whose default set differs only in weight and style.
const _TEXT_FONT_STYLE = Dict{Symbol,Dict{String,Any}}(
    :regular     => Dict{String,Any}(),
    :bold        => Dict{String,Any}("fontWeight" => "bold"),
    :italic      => Dict{String,Any}("fontStyle" => "italic"),
    :bold_italic => Dict{String,Any}("fontWeight" => "bold", "fontStyle" => "italic"),
)
_text_mark_props(::Val{:font}, v) = nothing
_text_mark_props(::Val{:font}, v::AbstractString) = Dict{String,Any}("font" => v)
_text_mark_props(::Val{:font}, v::Symbol) =
    haskey(_TEXT_FONT_STYLE, v) ? copy(_TEXT_FONT_STYLE[v]) : nothing

_visual_name(vis::AlgebraOfGraphics.Visual) =
    vis.plottype === Makie.Plot{Makie.plot} ? "visual(...)" : "visual($(Makie.plotsym(vis.plottype)))"

function visual_attrs_to_mark_props(vis::AlgebraOfGraphics.Visual)
    props = Dict{String,Any}()
    # Only a true Scatter becomes a Vega point mark, where `size` is an area.
    # (ScatterLines lowers to a line mark, where `size` is a stroke width.)
    scatter = vis.plottype <: Scatter
    text = vis.plottype <: Makie.Text
    errorbars = vis.plottype <: Union{Errorbars, Rangebars}
    # A composite mark reads only its own properties (`_COMPOSITE_MARK_PROPERTIES`).
    composite = _composite_mark_properties(vis.plottype)
    inks = String[]
    ignored = Symbol[]
    for (k, v) in pairs(vis.attributes)
        sk = string(k)
        text_props = text ? _text_mark_props(Val(k), v) : missing
        errorbar_props = errorbars ? _errorbar_mark_props(Val(k), v) : missing
        p = Dict{String,Any}()  # this attribute's mark properties
        # Map Makie attribute names to Vega mark properties
        if v === :ink && haskey(_AOV_INK_ATTRS, k)
            push!(inks, _AOV_INK_ATTRS[k])
        elseif k === :inspectable && v isa Bool
            # Not a mark property: the layer's lowering styles every mark it
            # draws (`_apply_layer_passive!`).
        elseif !ismissing(errorbar_props)
            isnothing(errorbar_props) ? push!(ignored, k) : merge!(p, errorbar_props)
        elseif k === :opacity || k === :fillOpacity || k === :alpha
            p["opacity"] = v
        elseif k === :color
            p["color"] = string(v)
        elseif k === :strokecolor
            p["stroke"] = string(v)
        elseif k === :strokeDash || k === :linestyle
            dash = _linestyle_to_strokedash(v)
            isnothing(dash) || (p["strokeDash"] = dash)
        elseif k === :marker
            p["shape"] = _marker_to_shape(v)
        elseif k === :markersize
            p["size"] = (scatter && v isa Real) ? _markersize_to_vl_size(v) : v
        elseif k === :size
            p["size"] = v
        elseif k === :strokeWidth || k === :linewidth || k === :strokewidth
            p["strokeWidth"] = v
        elseif !ismissing(text_props)
            isnothing(text_props) ? push!(ignored, k) : merge!(p, text_props)
        elseif k in _VL_MARK_PROPERTIES
            p[sk] = v
        else
            push!(ignored, k)
        end
        # A property the composite mark does not read would be dropped by
        # Vega-Lite without a word, so it is reported with the rest.
        if !isnothing(composite) && any(!in(composite), keys(p))
            filter!(kv -> first(kv) in composite, p)
            k in ignored || push!(ignored, k)
        end
        _merge_mark_props!(props, p)
    end
    # Makie draws the whiskers in the bar's colour and opacity. Vega-Lite gives
    # an error bar's ticks its default mark colour at 0.7 opacity, while the
    # rule is black (`config.rule`), so the caps get the rule's look, as
    # Vega-Lite's own box-plot whisker ticks do (`color: "black", opacity: 1`).
    # A colour mapping still wins (an encoding beats a mark property), and a
    # fixed `color` or opacity on the mark reaches the ticks, so neither is set
    # over one.
    if errorbars && haskey(vis.attributes, :whiskerwidth) && get(props, "ticks", nothing) isa AbstractDict
        caps = Dict{String,Any}()
        haskey(props, "opacity") || (caps["opacity"] = 1)
        haskey(vis.attributes, :color) || (caps["color"] = "black")
        props["ticks"] = merge(caps, _part_dict(props["ticks"]))
    end
    mark_name = isnothing(composite) ? "no Vega-Lite mark counterpart" :
        "no counterpart on the Vega-Lite `$(plottype_to_mark(vis.plottype))` mark it draws"
    isempty(ignored) || @warn "AlgebraOfVega: `$(_visual_name(vis))` sets $(join(("`$k`" for k in ignored), ", ")) with $mark_name; vdraw and vsave ignore $(length(ignored) == 1 ? "it" : "them")." _id=(:aov_unread_visual_attrs, vis.plottype, Tuple(ignored)) maxlog=1
    if !isempty(inks)
        # A named style lets the host runtime resolve the inherited CSS colour
        # at embed time. Keep any caller-authored styles, with ink last so the
        # explicit `:ink` choice wins over their colour defaults.
        styles = get(props, "style", nothing)
        unique!(inks)
        props["style"] = isnothing(styles) && length(inks) == 1 ? only(inks) :
            vcat(isnothing(styles) ? String[] : _style_list(styles), inks)
    end
    props
end

# The Vega-Lite mark of a plain layer's `visual(...)`: the bare mark string when
# nothing qualifies it, else the mark dict with its plot-type defaults and
# visual attributes (a composite mark's style moved onto its drawn parts).
function _visual_mark(vis::AlgebraOfGraphics.Visual)
    mark_type = plottype_to_mark(vis.plottype)
    props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
    isempty(props) && return mark_type
    _style_composite_parts(merge(Dict{String,Any}("type" => mark_type), props))
end

# A fixed `visual(; color=…)` on an analysis that draws several marks of its own
# (`lineribbon`/`ribbon`: band areas, the median line, single-x glyph rules; the
# interval analyses: rules and `dotinterval`'s dots) colours all of them but the
# white median point, on every renderer that supports the analysis. Returns the
# authored colour value (a literal, or `:ink`), or `nothing` when the layer's
# visual sets none. The analysis owns every other mark property (graduated band
# opacities, line and rule widths), so any other visual attribute is reported
# rather than silently dropped.
function _analysis_fixed_color(layer::AlgebraOfGraphics.Layer, analysis::AbstractString)
    vis = extract_visual(layer)
    isnothing(vis) && return nothing
    # `inspectable` applies to every mark of the layer (`_apply_layer_passive!`).
    ignored = [k for k in keys(vis.attributes) if k !== :color && k !== :inspectable]
    isempty(ignored) || @warn "AlgebraOfVega: $analysis applies only a fixed `color` from `visual(...)`; ignoring $(join(("`$k`" for k in ignored), ", "))." maxlog=1
    haskey(vis.attributes, :color) ? vis.attributes[:color] : nothing
end

# The Vega-Lite mark properties of a fixed analysis colour: the same lowering as
# a plain mark's `visual(...; color=…)` (`:ink` becomes the theme-ink style).
_fixed_color_mark_props(::Nothing) = Dict{String,Any}()
_fixed_color_mark_props(color) =
    visual_attrs_to_mark_props(AlgebraOfGraphics.Visual(; color))
