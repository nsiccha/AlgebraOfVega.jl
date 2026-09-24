# --- Extract components from AoG Layer ---

extract_visual(layer::AlgebraOfGraphics.Layer) =
    extract_transformation(layer, AlgebraOfGraphics.Visual)

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
    mark_type = !isnothing(vis) ? plottype_to_mark(vis.plottype) : "boxplot"
    extra_props = !isnothing(vis) ? merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis)) : Dict{String,Any}()
    mark = if isempty(extra_props)
        mark_type
    else
        merge(Dict{String,Any}("type" => mark_type), extra_props)
    end

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

function visual_attrs_to_mark_props(vis::AlgebraOfGraphics.Visual)
    props = Dict{String,Any}()
    # Only a true Scatter becomes a Vega point mark, where `size` is an area.
    # (ScatterLines lowers to a line mark, where `size` is a stroke width.)
    scatter = vis.plottype <: Scatter
    for (k, v) in pairs(vis.attributes)
        sk = string(k)
        # Map Makie attribute names to Vega mark properties
        if k === :opacity || k === :fillOpacity
            props["opacity"] = v
        elseif k === :color
            props["color"] = string(v)
        elseif k === :strokeDash || k === :linestyle
            dash = _linestyle_to_strokedash(v)
            isnothing(dash) || (props["strokeDash"] = dash)
        elseif k === :marker
            props["shape"] = _marker_to_shape(v)
        elseif k === :markersize
            props["size"] = (scatter && v isa Real) ? _markersize_to_vl_size(v) : v
        elseif k === :size
            props["size"] = v
        elseif k === :strokeWidth || k === :linewidth
            props["strokeWidth"] = v
        else
            props[sk] = v
        end
    end
    props
end
