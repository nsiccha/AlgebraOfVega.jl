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

function visual_attrs_to_mark_props(vis::AlgebraOfGraphics.Visual)
    props = Dict{String,Any}()
    for (k, v) in pairs(vis.attributes)
        sk = string(k)
        # Map Makie attribute names to Vega mark properties
        if k === :opacity || k === :fillOpacity
            props["opacity"] = v
        elseif k === :color
            props["color"] = string(v)
        elseif k === :strokeDash || k === :linestyle
            props["strokeDash"] = v
        elseif k === :markersize || k === :size
            props["size"] = v
        elseif k === :strokeWidth || k === :linewidth
            props["strokeWidth"] = v
        else
            props[sk] = v
        end
    end
    props
end
