# --- Shared helpers for interval analysis → VL ---

# The interval analyses reduce the value column with `quantile`, so it must hold
# real numbers. A categorical column here almost always means the positional
# mappings were written in the OTHER orientation's order: `:horizontal`
# summarizes positional 1 and takes its group from `y=` (positional 2 is not
# consumed), while `:vertical` expects `mapping(category, value)` and summarizes
# positional 2. Without this guard that mistake surfaces as
# `MethodError: no method matching isfinite(::String)` from inside Statistics,
# which names neither the column nor the fix.
function _check_interval_value_column(table, value_field::String, orientation::Symbol)
    Symbol(value_field) in Tables.columnnames(table) || return nothing
    col = Tables.getcolumn(table, Symbol(value_field))
    eltype(col) <: Union{Real,Missing} && return nothing
    any(x -> x isa Real, col) && return nothing
    hint = orientation === :horizontal ?
        "with orientation=:horizontal the value column is the FIRST positional mapping and the category comes from `y=` — write `mapping(<value>, y=:$value_field)`, or keep `mapping(:$value_field, <value>)` and pass `orientation=:vertical`" :
        "with orientation=:vertical the value column is the SECOND positional mapping — write `mapping(:$value_field, <value>)`"
    error("interval analysis: value column \"$value_field\" has non-numeric eltype $(eltype(col)) and cannot be reduced with `quantile`; $hint.")
end

function _extract_interval_fields(layer, orientation::Symbol=:horizontal; default_value="value")
    table = extract_data(layer)
    if orientation === :horizontal
        value_sel = length(layer.positional) >= 1 ? layer.positional[1] : nothing
        value_field = isnothing(value_sel) ? default_value : _field_name(value_sel)
        value_label = isnothing(value_sel) ? default_value : _field_label(value_sel)
        group_field = haskey(layer.named, :y) ? _field_name(layer.named[:y]) : nothing
        group_label = haskey(layer.named, :y) ? _field_label(layer.named[:y]) : nothing
    elseif orientation === :vertical
        length(layer.positional) >= 2 || error("interval analysis with orientation=:vertical expects `mapping(category, value)` — two positional mappings; got $(length(layer.positional))")
        group_field = _field_name(layer.positional[1])
        group_label = _field_label(layer.positional[1])
        value_field = _field_name(layer.positional[2])
        value_label = _field_label(layer.positional[2])
    else
        error("orientation must be :horizontal or :vertical, got :$orientation")
    end
    _check_interval_value_column(table, value_field, orientation)
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)
    (; table, value_field, value_label, group_field, group_label,
       color_field, color_label, facet, facet_fields, orientation)
end

_interval_axes(orientation::Symbol) = orientation === :vertical ?
    (value_axis="y", value2_axis="y2", group_axis="x", offset_key="xOffset") :
    (value_axis="x", value2_axis="x2", group_axis="y", offset_key="yOffset")

function _add_group_color_encoding!(enc, group_field, color_field, group_axis::String, offset_key::String;
                                      group_label=nothing, color_label=nothing, show_axis_title=true)
    if !isnothing(group_field)
        g_enc = Dict{String,Any}("field" => group_field, "type" => "nominal")
        !show_axis_title && (g_enc["axis"] = Dict{String,Any}("title" => nothing))
        !isnothing(group_label) && group_label != group_field && (g_enc["title"] = group_label)
        enc[group_axis] = g_enc
    end
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        enc["color"] = color_enc
        !isnothing(group_field) && (enc[offset_key] = Dict{String,Any}("field" => color_field, "type" => "nominal"))
    elseif !isnothing(group_field)
        enc["color"] = Dict{String,Any}("field" => group_field, "type" => "nominal", "legend" => nothing)
    end
    enc
end

function _interval_point_layer(group_field, color_field, group_axis::String, offset_key::String;
                                 point_field::String="__point__", value_axis::String="x",
                                 mark_opts...)
    pt_enc = Dict{String,Any}(
        value_axis => Dict{String,Any}("field" => point_field, "type" => "quantitative"),
    )
    if !isnothing(group_field)
        pt_enc[group_axis] = Dict{String,Any}("field" => group_field, "type" => "nominal")
    end
    if !isnothing(color_field) && !isnothing(group_field)
        pt_enc[offset_key] = Dict{String,Any}("field" => color_field, "type" => "nominal")
    end
    # White-filled median dot with a dark stroke. The stroke is load-bearing, not
    # cosmetic: the interval `rule` behind this dot collapses to nothing when its
    # width is ~0 (lo==hi — a near-constant series, or one degenerate group inside
    # a wide shared domain), leaving the dot on vega's default WHITE background. A
    # bare white dot then vanishes. white-fill + dark-ring stays visible on ANY
    # background (fill covers dark, ring covers light). Callers may override via
    # mark_opts (splatted last).
    mark = Dict{String,Any}("type" => "point", "filled" => true,
        "stroke" => "#333", "strokeWidth" => 1.5,
        (string(k) => v for (k,v) in pairs(mark_opts))...)
    Dict{String,Any}("mark" => mark, "encoding" => pt_enc)
end

function _interval_tooltips(value_label, group_field, color_field, probs;
                              point_field::String="__point__")
    tt = Dict{String,Any}[Dict{String,Any}("field" => point_field, "type" => "quantitative", "title" => "$value_label (estimate)")]
    !isnothing(group_field) && push!(tt, Dict{String,Any}("field" => group_field, "type" => "nominal"))
    !isnothing(color_field) && color_field != group_field && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    widest = maximum(probs)
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("lo", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% lo"))
    push!(tt, Dict{String,Any}("field" => _vl_prob_field("hi", widest), "type" => "quantitative", "title" => "$(round(Int, widest*100))% hi"))
    tt
end

# --- Analysis → Vega-Lite spec ---

function analysis_to_vl(a::PointIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = length(sorted_probs) == 1 ? [8.0] : range(1.5, 8, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         value_axis=ax.value_axis, size=80, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::PrecomputedIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)

    col_names = Set(string.(Tables.columnnames(table)))
    value_field in col_names || error("Pre-aggregated pointinterval: point column \"$value_field\" not found in table. Available: $(sort(collect(col_names)))")
    for (lo, hi) in a.bands
        los, his = string(lo), string(hi)
        los in col_names || error("Pre-aggregated pointinterval: band column \"$los\" not found in table. Available: $(sort(collect(col_names)))")
        his in col_names || error("Pre-aggregated pointinterval: band column \"$his\" not found in table. Available: $(sort(collect(col_names)))")
    end

    summary = table_to_rows(table)
    stroke_widths = length(a.bands) == 1 ? [8.0] : range(1.5, 8, length=length(a.bands))

    layers = Dict{String,Any}[]
    for (i, (lo, hi)) in enumerate(a.bands)
        lo_col, hi_col = string(lo), string(hi)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => lo_col, "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => hi_col),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         point_field=value_field, value_axis=ax.value_axis,
                                         size=80, color="white"))

    widest_lo = string(first(a.bands[1]))
    widest_hi = string(last(a.bands[1]))
    tt = Dict{String,Any}[
        Dict{String,Any}("field" => value_field, "type" => "quantitative", "title" => "$value_label (estimate)"),
    ]
    !isnothing(group_field) && push!(tt, Dict{String,Any}("field" => group_field, "type" => "nominal"))
    !isnothing(color_field) && color_field != group_field && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    push!(tt, Dict{String,Any}("field" => widest_lo, "type" => "quantitative", "title" => widest_lo))
    push!(tt, Dict{String,Any}("field" => widest_hi, "type" => "quantitative", "title" => widest_hi))
    _add_analysis_tooltips!(layers, tt)

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::GradientIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)
    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    opacities = range(0.2, 0.7, length=length(sorted_probs))

    layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative", "title" => value_label),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
            "opacity" => Dict{String,Any}("value" => opacities[i]),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label, show_axis_title=false)
        push!(layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => 14),
            "encoding" => enc,
        ))
    end

    push!(layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                         value_axis=ax.value_axis, size=50, color="white"))
    _add_analysis_tooltips!(layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

    spec = Dict{String,Any}("data" => Dict{String,Any}("values" => summary), "layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function _ribbon_tooltips(x_field, x_label, median_col, color_field, band_cols, band_labels)
    widest_lo, widest_hi = band_cols[1]
    widest_label = isnothing(band_labels) ? "" : band_labels[1]
    lo_title = widest_label == "" ? widest_lo : "$(widest_label) lo"
    hi_title = widest_label == "" ? widest_hi : "$(widest_label) hi"
    tt = Dict{String,Any}[
        Dict{String,Any}("field" => x_field, "type" => "quantitative", "title" => x_label),
        Dict{String,Any}("field" => median_col, "type" => "quantitative", "title" => "median"),
    ]
    !isnothing(color_field) && push!(tt, Dict{String,Any}("field" => color_field, "type" => "nominal"))
    push!(tt, Dict{String,Any}("field" => widest_lo, "type" => "quantitative", "title" => lo_title))
    push!(tt, Dict{String,Any}("field" => widest_hi, "type" => "quantitative", "title" => hi_title))
    tt
end

# Build the "single-x glyph" layers for a lineribbon. An `area` band and the median
# `line` are both interpolated ALONG x, so a group with a single x value has zero
# x-extent and renders nothing. The glyph replaces it with a vertical pointinterval:
# each band → a `rule` (y=lo→y2=hi) with the same widest-thin→narrowest-thick
# strokeWidth ramp as analysis_to_vl(::PointIntervalAnalysis), the median → a stroked
# white `point` (matching _interval_point_layer). Grouped series get an `xOffset` by
# color so they don't stack on the same x. `filter_expr` (a VL predicate string)
# scopes these layers to just the single-x rows when overlaid on a normal ribbon —
# so multi-x groups keep their area/line and only single-x groups get the glyph.
# (decisions `1ipps5p`, `1liuv2o`.)
function _ribbon_glyph_layers(x_field, x_label, y_label, median_col, band_cols;
        color_field=nothing, color_label=nothing, filter_expr=nothing)
    stroke_widths = length(band_cols) == 1 ? [8.0] : range(1.5, 8, length=length(band_cols))
    x_enc() = let e = Dict{String,Any}("field" => x_field, "type" => "quantitative")
        x_label != x_field && (e["title"] = x_label); e
    end
    _ft() = Dict{String,Any}[Dict{String,Any}("filter" => filter_expr)]
    layers = Dict{String,Any}[]
    for (i, (lo_col, hi_col)) in enumerate(band_cols)
        enc = Dict{String,Any}(
            "x" => x_enc(),
            "y" => Dict{String,Any}("field" => lo_col, "type" => "quantitative", "title" => y_label),
            "y2" => Dict{String,Any}("field" => hi_col),
        )
        if !isnothing(color_field)
            c = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (c["title"] = color_label)
            enc["color"] = c
            enc["xOffset"] = Dict{String,Any}("field" => color_field, "type" => "nominal")
        end
        l = Dict{String,Any}("mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i]), "encoding" => enc)
        isnothing(filter_expr) || (l["transform"] = _ft())
        push!(layers, l)
    end
    pt_enc = Dict{String,Any}(
        "x" => x_enc(),
        "y" => Dict{String,Any}("field" => median_col, "type" => "quantitative", "title" => y_label),
    )
    !isnothing(color_field) && (pt_enc["xOffset"] = Dict{String,Any}("field" => color_field, "type" => "nominal"))
    pt = Dict{String,Any}(
        "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 60,
            "color" => "white", "stroke" => "#333", "strokeWidth" => 1.5),
        "encoding" => pt_enc,
    )
    isnothing(filter_expr) || (pt["transform"] = _ft())
    push!(layers, pt)
    layers
end

# Tag each summary row with `__single_x__`: does its drawing group (color × facet ×
# detail — the fields that split one line/area) collapse to a single x value? Such
# groups render nothing as area/line, so they get the glyph overlay instead. Returns
# whether ANY group is single-x — only then is tagging applied + the overlay added,
# so plots with no single-x group are emitted byte-identically to before. (`1liuv2o`.)
function _mark_single_x_groups!(summary, x_field, group_fields)
    counts = Dict{Any,Set{Any}}()
    for row in summary
        haskey(row, x_field) || continue
        key = Tuple(get(row, f, nothing) for f in group_fields)
        push!(get!(Set{Any}, counts, key), row[x_field])
    end
    any(length(xs) == 1 for xs in values(counts)) || return false
    for row in summary
        key = Tuple(get(row, f, nothing) for f in group_fields)
        row["__single_x__"] = length(get(counts, key, Set{Any}())) == 1
    end
    true
end

function _ribbon_to_vl(
    summary::Vector{<:Dict{String}},
    x_field::String, x_label::String, y_label::String,
    median_col::String,
    band_cols::Vector{Tuple{String,String}};
    color_field::Union{String,Nothing}=nothing,
    color_label::Union{String,Nothing}=nothing,
    detail_fields::Vector{String}=String[],
    facet=nothing, show_line::Bool=true, is_sublayer::Bool=false,
    band_labels::Union{Vector{String},Nothing}=nothing,
    single_x_glyph::Bool=true, facet_fields::Vector{String}=String[]
)
    summary_data = Dict{String,Any}("values" => summary)
    # range(...; length=1) rejects distinct endpoints, so a single band
    # gets a fixed mid-gradient opacity (mirrors the stroke_widths idiom
    # in _interval_to_vl above). Two-or-more bands keep the gradient.
    opacities = length(band_cols) == 1 ? [0.4] : range(0.2, 0.6, length=length(band_cols))

    detail_enc = if !isempty(detail_fields)
        length(detail_fields) == 1 ?
            Dict{String,Any}("field" => detail_fields[1], "type" => "nominal") :
            [Dict{String,Any}("field" => f, "type" => "nominal") for f in detail_fields]
    else
        nothing
    end

    # NOTE: x is emitted `quantitative` on every band (area) + line layer below, and we
    # deliberately do NOT sort `summary` by x or set an `order`/`sort` — Vega-Lite orders a
    # line/area mark's vertices by the continuous (quantitative) positional field by default.
    # So `summary` row order is immaterial (compute path = Dict-order; bands= path = native
    # table order). Don't "fix" the unsorted summary or drop this reliance without adding an
    # explicit x `sort`, or lines scribble (verified fleet-wide + the TreeArrays interop, 2026-07).
    template_layers = Dict{String,Any}[]
    for (i, (lo_col, hi_col)) in enumerate(band_cols)
        x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
        x_label != x_field && (x_enc["title"] = x_label)
        enc = Dict{String,Any}(
            "x" => x_enc,
            "y" => Dict{String,Any}("field" => lo_col, "type" => "quantitative", "title" => y_label),
            "y2" => Dict{String,Any}("field" => hi_col),
        )
        !isnothing(detail_enc) && (enc["detail"] = deepcopy(detail_enc))
        mark = Dict{String,Any}("type" => "area", "opacity" => opacities[i], "line" => false)
        push!(template_layers, Dict{String,Any}("mark" => mark, "encoding" => enc, "_lr_layer" => true))
    end
    if show_line
        line_x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
        x_label != x_field && (line_x_enc["title"] = x_label)
        line_enc = Dict{String,Any}(
            "x" => line_x_enc,
            "y" => Dict{String,Any}("field" => median_col, "type" => "quantitative", "title" => y_label),
        )
        !isnothing(detail_enc) && (line_enc["detail"] = deepcopy(detail_enc))
        line_mark = Dict{String,Any}("type" => "line", "strokeWidth" => 2)
        push!(template_layers, Dict{String,Any}("mark" => line_mark, "encoding" => line_enc, "_lr_layer" => true))
    end

    layers = Dict{String,Any}[]
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        color_vals = sort(unique(row[color_field] for row in summary if haskey(row, color_field)))
        for gval in color_vals
            filter_expr = "datum[$(JSON.json(color_field))] === $(JSON.json(gval))"
            for tl in template_layers
                gl = deepcopy(tl)
                gl["transform"] = [Dict{String,Any}("filter" => filter_expr)]
                gl["encoding"]["color"] = copy(color_enc)
                push!(layers, gl)
            end
        end
    else
        append!(layers, template_layers)
    end

    # M2 single-x overlay: any group (color × facet × detail) that collapses to one x
    # renders nothing as area/line, so overlay a pointinterval glyph scoped to just
    # those rows via a `__single_x__` filter. Multi-x groups keep their ribbon; only
    # single-x groups become visible. Opt out with `single_x_glyph=false`. Subsumes the
    # old whole-plot fallback: an all-single-x plot is every group being single-x. The
    # glyph layers are intentionally NOT `_lr_layer`-tagged, so the interactive legend
    # rebuild (js_runtime `_aov.lineribbon`) preserves them untouched. (`1liuv2o`.)
    if single_x_glyph
        group_fields = String[]
        !isnothing(color_field) && push!(group_fields, color_field)
        append!(group_fields, facet_fields)
        append!(group_fields, detail_fields)
        if _mark_single_x_groups!(summary, x_field, group_fields)
            append!(layers, _ribbon_glyph_layers(x_field, x_label, y_label, median_col, band_cols;
                color_field, color_label, filter_expr="datum.__single_x__"))
        end
    end

    _add_analysis_tooltips!(layers, _ribbon_tooltips(x_field, x_label, median_col, color_field, band_cols, band_labels))

    spec = Dict{String,Any}("data" => summary_data, "layer" => layers)
    if !isnothing(color_field)
        aov = get!(Dict{String,Any}, spec, "_aov")
        aov["lineribbon"] = Dict{String,Any}("templateLayers" => template_layers)
    end
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function analysis_to_vl(a::LineRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)

    detail_strs = string.(a.detail_fields)
    summary = compute_ribbon_summary(table, x_field, y_field, group_field, a.probs; color_field, facet_fields, detail_fields=detail_strs)

    sorted_probs = sort(a.probs, rev=true)
    band_cols = Tuple{String,String}[(_vl_prob_field("lo", p), _vl_prob_field("hi", p)) for p in sorted_probs]
    band_labels = String["$(round(Int, p*100))%" for p in sorted_probs]

    _ribbon_to_vl(summary, x_field, x_label, y_label, "__median__", band_cols;
        color_field, color_label, detail_fields=detail_strs,
        facet, show_line=a.show_line, is_sublayer, band_labels,
        single_x_glyph=a.single_x_glyph, facet_fields)
end

function analysis_to_vl(a::PrecomputedRibbonAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : error("Pre-aggregated lineribbon requires at least one positional mapping (x)")
    x_label = _field_label(layer.positional[1])
    length(layer.positional) >= 2 || error("Pre-aggregated lineribbon requires a second positional mapping (median column)")
    median_col = _field_name(layer.positional[2])
    y_label = _field_label(layer.positional[2])
    haskey(layer.named, :group) && error("Pre-aggregated lineribbon (bands=...) should not have group= in mapping — data is already aggregated")
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    facet, facet_fields = _extract_facet_info(layer)
    detail_strs = string.(a.detail_fields)

    col_names = Set(string.(Tables.columnnames(table)))
    median_col in col_names || error("Pre-aggregated lineribbon: median column \"$median_col\" not found in table. Available: $(sort(collect(col_names)))")
    for (lo, hi) in a.bands
        los, his = string(lo), string(hi)
        los in col_names || error("Pre-aggregated lineribbon: band column \"$los\" not found in table. Available: $(sort(collect(col_names)))")
        his in col_names || error("Pre-aggregated lineribbon: band column \"$his\" not found in table. Available: $(sort(collect(col_names)))")
    end

    summary = table_to_rows(table)
    band_cols = Tuple{String,String}[(string(first(b)), string(last(b))) for b in a.bands]

    _ribbon_to_vl(summary, x_field, x_label, y_label, median_col, band_cols;
        color_field, color_label, detail_fields=detail_strs,
        facet, show_line=a.show_line, is_sublayer,
        single_x_glyph=a.single_x_glyph, facet_fields)
end

function analysis_to_vl(a::DotIntervalAnalysis, layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    (; table, value_field, value_label, group_field, group_label, color_field, color_label, facet, facet_fields) = _extract_interval_fields(layer, a.orientation)
    ax = _interval_axes(a.orientation)
    detail_strs = string.(a.detail_fields)

    vals = Tables.getcolumn(table, Symbol(value_field))
    key_fields = String[f for f in [group_field, color_field, facet_fields..., detail_strs...] if !isnothing(f)]
    idx_groups = _group_indices(_key_columns(table; fields=key_fields), length(vals))

    # Quantile dots
    dot_rows = Dict{String,Any}[]
    for (key, idxs) in idx_groups
        v = sort!(vals[idxs])
        n = length(v)
        ki_base = 0
        gk = isnothing(group_field) ? nothing : key[ki_base += 1]
        ck = isnothing(color_field) ? nothing : key[ki_base += 1]
        for i in 1:a.n_dots
            q = quantile(v, (i - 0.5) / a.n_dots; sorted=true)
            row = Dict{String,Any}("quantile" => q)
            !isnothing(gk) && (row[group_field] = gk)
            !isnothing(ck) && (row[color_field] = ck)
            ki = ki_base
            for ff in facet_fields
                row[ff] = key[ki += 1]
            end
            for ff in detail_strs
                row[ff] = key[ki += 1]
            end
            push!(dot_rows, row)
        end
    end

    summary = compute_interval_summary(table, value_field, group_field, a.probs, a.point; color_field, facet_fields, detail_fields=detail_strs)

    # Dot layer
    dot_enc = Dict{String,Any}(
        ax.value_axis => Dict{String,Any}("field" => "quantile", "type" => "quantitative", "title" => value_label,
                                           "bin" => Dict{String,Any}("maxbins" => 40)),
        "size" => Dict{String,Any}("aggregate" => "count", "legend" => nothing),
    )
    _add_group_color_encoding!(dot_enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                group_label, color_label, show_axis_title=false)

    layers = Dict{String,Any}[
        Dict{String,Any}(
            "data" => Dict{String,Any}("values" => dot_rows),
            "mark" => Dict{String,Any}("type" => "circle", "opacity" => 0.6, "size" => 30),
            "encoding" => dot_enc,
        )
    ]

    # Interval sublayers
    sorted_probs = sort(a.probs, rev=true)
    stroke_widths = length(sorted_probs) == 1 ? [5.0] : range(1.5, 5, length=length(sorted_probs))
    interval_layers = Dict{String,Any}[]
    for (i, prob) in enumerate(sorted_probs)
        enc = Dict{String,Any}(
            ax.value_axis => Dict{String,Any}("field" => _vl_prob_field("lo", prob), "type" => "quantitative"),
            ax.value2_axis => Dict{String,Any}("field" => _vl_prob_field("hi", prob)),
        )
        _add_group_color_encoding!(enc, group_field, color_field, ax.group_axis, ax.offset_key;
                                    group_label, color_label)
        push!(interval_layers, Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "rule", "strokeWidth" => stroke_widths[i], "color" => "#333"),
            "encoding" => enc,
        ))
    end

    push!(interval_layers, _interval_point_layer(group_field, color_field, ax.group_axis, ax.offset_key;
                                                   value_axis=ax.value_axis,
                                                   size=50, color="white"))
    _add_analysis_tooltips!(interval_layers, _interval_tooltips(value_label, group_field, color_field, a.probs))

    push!(layers, Dict{String,Any}(
        "data" => Dict{String,Any}("values" => summary),
        "layer" => interval_layers,
    ))

    spec = Dict{String,Any}("layer" => layers)
    if !is_sublayer
        spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
    end
    _wrap_with_facet!(spec, facet)
    spec
end

function density_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "value"
    y_field = haskey(layer.named, :y) ? _field_name(layer.named[:y]) : nothing

    vis = extract_visual(layer)
    opacity = 0.4
    if !isnothing(vis)
        attrs = vis.attributes
        if haskey(attrs, :opacity)
            opacity = attrs[:opacity]
        end
    end

    if !isnothing(y_field)
        # Faceted density
        spec = Dict{String,Any}(
            "data" => data_to_vl(table),
            "facet" => Dict{String,Any}("field" => y_field, "type" => "nominal",
                                         "header" => Dict{String,Any}("title" => nothing, "labelFontSize" => 14)),
            "columns" => 1,
            "spec" => Dict{String,Any}(
                "width" => 500, "height" => 60,
                "layer" => [
                    Dict{String,Any}(
                        "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
                        "transform" => [Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])],
                        "encoding" => Dict{String,Any}(
                            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
                            "y" => Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing),
                        ),
                    ),
                ],
            ),
        )
        if !is_sublayer
            spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
        end
        return spec
    else
        # Check for color grouping
        color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
        color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
        density_transform = Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])
        if !isnothing(color_field)
            density_transform["groupby"] = [color_field]
        end

        encoding = Dict{String,Any}(
            "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
            "y" => Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing),
        )
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            encoding["color"] = color_enc
        end

        spec = Dict{String,Any}(
            "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
            "transform" => [density_transform],
            "encoding" => encoding,
        )
        if !isnothing(table)
            spec["data"] = data_to_vl(table)
        end
        if !is_sublayer
            spec["\$schema"] = "https://vega.github.io/schema/vega-lite/v5.json"
        end
        return spec
    end
end

"""
    compute_linear_ci(xs, ys, npoints=100, level=0.95)

Compute linear regression line + confidence interval band.
Returns a vector of Dicts with fields: x, y_hat, y_lo, y_hi.
Uses t-distribution approximation for CI of the mean response.
"""
function compute_linear_ci(xs::AbstractVector, ys::AbstractVector; npoints=100, level=0.95)
    n = length(xs)
    mx, my = sum(xs)/n, sum(ys)/n
    sxx = sum((xi - mx)^2 for xi in xs)
    sxy = sum((xi - mx)*(yi - my) for (xi,yi) in zip(xs, ys))
    b1 = sxy / sxx
    b0 = my - b1 * mx
    residuals = [yi - (b0 + b1*xi) for (xi,yi) in zip(xs, ys)]
    s2 = sum(r^2 for r in residuals) / (n - 2)
    s = sqrt(s2)
    # Approximate t critical value (for large n, close to z)
    alpha = 1 - level
    # Simple approximation: use 1.96 for 0.95, scale for other levels
    z = alpha < 0.01 ? 2.576 : alpha < 0.05 ? 1.96 : alpha < 0.10 ? 1.645 : 1.28
    xmin, xmax = minimum(xs), maximum(xs)
    xgrid = range(xmin, xmax, length=npoints)
    rows = Dict{String,Any}[]
    for xp in xgrid
        yhat = b0 + b1*xp
        se = s * sqrt(1/n + (xp - mx)^2 / sxx)
        push!(rows, Dict{String,Any}("x" => xp, "y_hat" => yhat, "y_lo" => yhat - z*se, "y_hi" => yhat + z*se))
    end
    rows
end

"""
    linear_to_vl(layer; is_sublayer=false)

Translate AoG's `linear()` to Vega-Lite's `regression` transform + line mark.
When `interval` is set, computes regression CI in Julia and renders as area+y2.
"""
function linear_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    analysis = extract_transformation(layer, AlgebraOfGraphics.LinearAnalysis)
    has_band = !isnothing(_resolved_band_interval(analysis))

    reg_transform = Dict{String,Any}(
        "regression" => y_field,
        "on" => x_field,
        "method" => "linear",
    )
    if !isnothing(color_field)
        reg_transform["groupby"] = [color_field]
    end

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
    else
        line_mark["color"] = "firebrick"
    end

    line_layer = Dict{String,Any}(
        "mark" => line_mark,
        "transform" => [reg_transform],
        "encoding" => encoding,
    )

    if has_band && !isnothing(table)
        level = !isnothing(analysis) && hasproperty(analysis, :level) ? analysis.level : 0.95
        xs_all = Tables.getcolumn(table, Symbol(x_field))
        ys_all = Tables.getcolumn(table, Symbol(y_field))
        colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
        color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

        ci_rows = Dict{String,Any}[]
        for ck in color_keys
            mask = isnothing(colors) ? trues(length(xs_all)) : [c == ck for c in colors]
            ci = compute_linear_ci(xs_all[mask], ys_all[mask]; level)
            if !isnothing(ck)
                for row in ci
                    row[color_field] = ck
                end
            end
            append!(ci_rows, ci)
        end

        band_x_enc = Dict{String,Any}("field" => "x", "type" => "quantitative")
        x_label != x_field && (band_x_enc["title"] = x_label)
        band_y_enc = Dict{String,Any}("field" => "y_lo", "type" => "quantitative")
        y_label != y_field && (band_y_enc["title"] = y_label)
        band_enc = Dict{String,Any}(
            "x" => band_x_enc,
            "y" => band_y_enc,
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            band_enc["color"] = color_enc
        end
        band_layer = Dict{String,Any}(
            "mark" => band_mark,
            "encoding" => band_enc,
            "data" => Dict{String,Any}("values" => ci_rows),
        )
        spec = Dict{String,Any}("layer" => [band_layer, line_layer])
    else
        spec = line_layer
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    spec
end

"""
    compute_smooth_ci(xs, ys; bandwidth=0.75, npoints=100, level=0.95)

Compute a local smoothing confidence band using a moving-window approach.
At each grid point, uses a weighted local mean +/- t*SE within the bandwidth window.
"""
function compute_smooth_ci(xs::AbstractVector, ys::AbstractVector; bandwidth=0.75, npoints=100, level=0.95)
    n = length(xs)
    xmin, xmax = minimum(xs), maximum(xs)
    xrange = xmax - xmin
    half_w = bandwidth * xrange / 2
    xgrid = range(xmin, xmax, length=npoints)
    alpha = 1 - level
    z = alpha < 0.01 ? 2.576 : alpha < 0.05 ? 1.96 : alpha < 0.10 ? 1.645 : 1.28

    rows = Dict{String,Any}[]
    for xp in xgrid
        # Tricube weights
        weights = Float64[]
        vals = Float64[]
        for (xi, yi) in zip(xs, ys)
            u = abs(xi - xp) / half_w
            if u < 1
                w = (1 - u^3)^3
                push!(weights, w)
                push!(vals, yi)
            end
        end
        nw = length(vals)
        if nw < 3
            continue
        end
        tw = sum(weights)
        wmean = sum(w*v for (w,v) in zip(weights, vals)) / tw
        wvar = sum(w*(v - wmean)^2 for (w,v) in zip(weights, vals)) / tw
        se = sqrt(wvar / nw)
        push!(rows, Dict{String,Any}("x" => xp, "y_hat" => wmean, "y_lo" => wmean - z*se, "y_hi" => wmean + z*se))
    end
    rows
end

"""
    smooth_to_vl(layer; is_sublayer=false)

Translate AoG's `smooth()` to Vega-Lite's `loess` transform + line mark.
When `interval` is set, computes smooth CI in Julia and renders as area+y2.
"""
function smooth_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    analysis = extract_transformation(layer, AlgebraOfGraphics.SmoothAnalysis)
    bandwidth = !isnothing(analysis) ? analysis.span : 0.75
    has_band = !isnothing(_resolved_band_interval(analysis))

    loess_transform = Dict{String,Any}(
        "loess" => y_field,
        "on" => x_field,
        "bandwidth" => bandwidth,
    )
    if !isnothing(color_field)
        loess_transform["groupby"] = [color_field]
    end

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)
    line_mark = Dict{String,Any}("type" => "line")
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
    else
        line_mark["color"] = "firebrick"
    end

    line_layer = Dict{String,Any}(
        "mark" => line_mark,
        "transform" => [loess_transform],
        "encoding" => encoding,
    )

    if has_band && !isnothing(table)
        level = !isnothing(analysis) && hasproperty(analysis, :level) ? analysis.level : 0.95
        xs_all = Tables.getcolumn(table, Symbol(x_field))
        ys_all = Tables.getcolumn(table, Symbol(y_field))
        colors = isnothing(color_field) ? nothing : Tables.getcolumn(table, Symbol(color_field))
        color_keys = isnothing(colors) ? [nothing] : sort(unique(colors))

        ci_rows = Dict{String,Any}[]
        for ck in color_keys
            mask = isnothing(colors) ? trues(length(xs_all)) : [c == ck for c in colors]
            ci = compute_smooth_ci(xs_all[mask], ys_all[mask]; bandwidth, level)
            if !isnothing(ck)
                for row in ci
                    row[color_field] = ck
                end
            end
            append!(ci_rows, ci)
        end

        band_x_enc = Dict{String,Any}("field" => "x", "type" => "quantitative")
        x_label != x_field && (band_x_enc["title"] = x_label)
        band_y_enc = Dict{String,Any}("field" => "y_lo", "type" => "quantitative")
        y_label != y_field && (band_y_enc["title"] = y_label)
        band_enc = Dict{String,Any}(
            "x" => band_x_enc,
            "y" => band_y_enc,
            "y2" => Dict{String,Any}("field" => "y_hi"),
        )
        band_mark = Dict{String,Any}("type" => "area", "opacity" => 0.2, "line" => false)
        if !isnothing(color_field)
            color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
            !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
            band_enc["color"] = color_enc
        end
        band_layer = Dict{String,Any}(
            "mark" => band_mark,
            "encoding" => band_enc,
            "data" => Dict{String,Any}("values" => ci_rows),
        )
        spec = Dict{String,Any}("layer" => [band_layer, line_layer])
    else
        spec = line_layer
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    spec
end

"""
    histogram_to_vl(layer; is_sublayer=false)

Translate AoG's `histogram()` to Vega-Lite's bar mark with bin + count aggregation.
"""
function histogram_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"

    # Read the HistogramAnalysis struct so bins / datalimits / normalization
    # from `histogram(; bins=N, datalimits=…, normalization=…)` actually
    # reach the emitted VL spec.
    ha = extract_transformation(layer, AlgebraOfGraphics.HistogramAnalysis)
    bin_params, count_op = _histogram_bin_config(ha)

    # Collect facet (row/col) and other named channels separately. Row/col
    # land in a `facet` dict that is hoisted via _wrap_with_facet! so
    # `config(facet=(; linkxaxes=:none))`'s `resolve.scale.<axis>` lands in
    # scope.
    facet = Dict{String,Any}()
    other_named = Dict{Symbol,Any}()
    for (name, sel) in pairs(layer.named)
        if name === :row || name === :col
            facet_ch = name === :col ? "column" : "row"
            facet[facet_ch] = selector_to_field(sel)
            haskey(facet[facet_ch], "type") || (facet[facet_ch]["type"] = "nominal")
            continue
        end
        other_named[name] = sel
    end

    # When facet is present, emit bin + aggregate as transforms inside the
    # inner spec. VL runs those per-facet-cell, so each facet row/column
    # gets its own bin extents (matches AoG/Makie behavior under
    # linkxaxes=:none). Without facet, keep the simple encoding.x.bin=true
    # path since there's only one scale.
    color_sel = get(other_named, :color, nothing)
    color_field = isnothing(color_sel) ? nothing : _field_name(color_sel)

    if !isempty(facet)
        groupby = String["__bin_lo__", "__bin_hi__"]
        isnothing(color_field) || push!(groupby, color_field)
        transforms = Dict{String,Any}[
            Dict{String,Any}("bin" => bin_params, "field" => x_field,
                             "as" => ["__bin_lo__", "__bin_hi__"]),
            Dict{String,Any}("aggregate" => [Dict{String,Any}("op" => count_op, "as" => "__count__")],
                             "groupby" => groupby),
        ]
        x_enc = Dict{String,Any}("field" => "__bin_lo__", "bin" => "binned", "type" => "quantitative")
        x_label != x_field && (x_enc["title"] = x_label)
        encoding = Dict{String,Any}(
            "x" => x_enc,
            "x2" => Dict{String,Any}("field" => "__bin_hi__"),
            "y" => Dict{String,Any}("field" => "__count__", "type" => "quantitative"),
        )
        for (name, sel) in other_named
            ch = aog_named_to_vl_channel(name)
            isnothing(ch) && continue
            encoding[ch] = selector_to_field(sel)
        end
        !isnothing(table) && infer_types!(encoding, table)
        spec = Dict{String,Any}(
            "transform" => transforms,
            "mark" => "bar",
            "encoding" => encoding,
        )
        !isnothing(table) && (spec["data"] = data_to_vl(table))
        _wrap_with_facet!(spec, facet)
        return spec
    end

    # Non-faceted path: single global bin scale. Use encoding-level bin
    # when possible; fall back to a transform when bin_params carries
    # structured config (since `encoding.x.bin` also accepts a Dict).
    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative", "bin" => bin_params)
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
        "y" => Dict{String,Any}("aggregate" => count_op, "type" => "quantitative"),
    )
    for (name, sel) in other_named
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end
    !isnothing(table) && infer_types!(encoding, table)

    spec = Dict{String,Any}(
        "mark" => "bar",
        "encoding" => encoding,
    )
    !isnothing(table) && (spec["data"] = data_to_vl(table))
    spec
end

# Translate a HistogramAnalysis's struct config into (bin_params, count_op)
# for use in the VL bin transform / encoding.
#
# - `bins::Integer` → `{"maxbins": N}`
# - `bins::AbstractVector` → `{"step": step, "extent": [first, last]}` —
#   only handles uniformly-spaced vectors; non-uniform bins aren't expressible
#   declaratively in VL, so we fall back to step=first-diff.
# - `datalimits::Tuple{<:Real,<:Real}` → adds `"extent": [lo, hi]` (a
#   function like `extrema` stays automatic — the inner-spec per-facet
#   transform handles per-group extents already).
# - `normalization ∈ (:probability, :pdf, :density, :none)` → maps to the
#   VL aggregate operator (`count` vs VL's built-in `sum` with weights is
#   not sufficient for true density / pdf; emit a warning for those).
function _histogram_bin_config(ha)
    bp = Dict{String,Any}()
    count_op = "count"
    isnothing(ha) && return (true, count_op)

    # bins
    _apply_bins!(bp, ha.bins)

    # datalimits
    _apply_datalimits!(bp, ha.datalimits)

    # normalization: VL's aggregate only supports count/sum natively.
    # Non-count normalizations need a post-aggregate calculate transform;
    # not implemented yet. Emit a one-shot warning so the user knows the
    # y-axis is raw counts instead of the requested normalization.
    norm = hasproperty(ha, :normalization) ? ha.normalization : :none
    if norm !== :none && norm !== :count
        @warn "AlgebraOfVega: histogram(; normalization=$(repr(norm))) not yet wired into VL — rendering as raw counts. Open an issue if you need this." maxlog=1
    end

    bin_params = isempty(bp) ? true : bp
    (bin_params, count_op)
end

"""
    frequency_to_vl(layer; is_sublayer=false)

Translate AoG's `frequency()` to a Vega-Lite bar chart with `aggregate: "count"`.
"""
function frequency_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"

    x_enc = Dict{String,Any}("field" => x_field, "type" => "nominal")
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
        "y" => Dict{String,Any}("aggregate" => "count", "type" => "quantitative"),
    )

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    if !isnothing(table)
        infer_types!(encoding, table)
    end

    spec = Dict{String,Any}("mark" => "bar", "encoding" => encoding)
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    spec
end

"""
    expectation_to_vl(layer; is_sublayer=false)

Translate AoG's `expectation()` to a Vega-Lite bar chart with `aggregate: "mean"`.
"""
function expectation_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    y_field = length(layer.positional) >= 2 ? _field_name(layer.positional[2]) : "y"
    y_label = length(layer.positional) >= 2 ? _field_label(layer.positional[2]) : "y"

    x_enc = Dict{String,Any}("field" => x_field, "type" => "nominal")
    x_label != x_field && (x_enc["title"] = x_label)
    y_enc = Dict{String,Any}("field" => y_field, "aggregate" => "mean", "type" => "quantitative")
    y_label != y_field && (y_enc["title"] = y_label)
    encoding = Dict{String,Any}("x" => x_enc, "y" => y_enc)

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    if !isnothing(table)
        infer_types!(encoding, table)
    end

    spec = Dict{String,Any}("mark" => "bar", "encoding" => encoding)
    if !isnothing(table)
        spec["data"] = data_to_vl(table)
    end
    spec
end

# Returns `Val(:ecdf)` when the layer's visual targets `ECDFPlot`, else
# `nothing`. Replaces the old `_is_ecdf` Bool predicate + `&& return Val(:ecdf)`
# short-circuit; `_layer_handler` now returns the Maybe value directly. Three
# methods peel the wrappers: visual-or-nothing, then plottype-or-nothing.
_ecdf_dispatch_value(layer) = _ecdf_from_visual(extract_visual(layer))
_ecdf_from_visual(::Nothing) = nothing
_ecdf_from_visual(vis) = _ecdf_from_plottype(vis.plottype)
_ecdf_from_plottype(::Type{<:ECDFPlot}) = Val(:ecdf)
_ecdf_from_plottype(::Type) = nothing

"""
    ecdf_to_vl(layer; is_sublayer=false)

Translate AoG's `visual(ECDFPlot)` to a Vega-Lite spec using window transforms
for cumulative distribution. Produces a step line of the empirical CDF.

Supports `color=`, `linestyle=`, `group=`, and `detail=` grouping via
`groupby` on the window transforms (so each group gets its own ECDF
curve). `group=`/`detail=` produce a `detail` encoding so Vega draws
separate lines without coloring them differently -- useful when
overlaying many posterior-draw ECDFs and a per-draw color legend would
just be noise.
"""
function ecdf_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    table = extract_data(layer)
    x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "x"
    x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "x"
    color_field = haskey(layer.named, :color) ? _field_name(layer.named[:color]) : nothing
    color_label = haskey(layer.named, :color) ? _field_label(layer.named[:color]) : nothing
    linestyle_field = haskey(layer.named, :linestyle) ? _field_name(layer.named[:linestyle]) : nothing
    linestyle_label = haskey(layer.named, :linestyle) ? _field_label(layer.named[:linestyle]) : nothing
    # `group` and `detail` both partition without a visual channel; treat
    # them interchangeably (AoG accepts `group`, Vega-Lite uses `detail`).
    detail_key = haskey(layer.named, :detail) ? :detail :
                 haskey(layer.named, :group)  ? :group  : nothing
    detail_field = isnothing(detail_key) ? nothing : _field_name(layer.named[detail_key])
    detail_label = isnothing(detail_key) ? nothing : _field_label(layer.named[detail_key])

    # Window transforms for ECDF:
    # 1. Sort by x, count cumulative (per group)
    # 2. Count total (per group)
    # 3. Calculate ecdf = cumulative / total
    groupby_fields = String[]
    !isnothing(color_field) && push!(groupby_fields, color_field)
    !isnothing(linestyle_field) && push!(groupby_fields, linestyle_field)
    !isnothing(detail_field) && push!(groupby_fields, detail_field)

    sort_spec = [Dict{String,Any}("field" => x_field)]

    window1 = Dict{String,Any}(
        "window" => [Dict{String,Any}("op" => "count", "as" => "__cumulative_count__")],
        "sort" => sort_spec,
    )
    window2 = Dict{String,Any}(
        "window" => [Dict{String,Any}("op" => "count", "as" => "__total_count__")],
        "frame" => [nothing, nothing],
    )
    if !isempty(groupby_fields)
        window1["groupby"] = groupby_fields
        window2["groupby"] = groupby_fields
    end

    calc = Dict{String,Any}(
        "calculate" => "datum.__cumulative_count__ / datum.__total_count__",
        "as" => "__ecdf__",
    )

    x_enc = Dict{String,Any}("field" => x_field, "type" => "quantitative", "sort" => "ascending")
    x_label != x_field && (x_enc["title"] = x_label)
    encoding = Dict{String,Any}(
        "x" => x_enc,
        "y" => Dict{String,Any}("field" => "__ecdf__", "type" => "quantitative", "title" => "Cumulative Proportion"),
    )
    if !isnothing(color_field)
        color_enc = Dict{String,Any}("field" => color_field, "type" => "nominal")
        !isnothing(color_label) && color_label != color_field && (color_enc["title"] = color_label)
        encoding["color"] = color_enc
    end
    if !isnothing(linestyle_field)
        ls_enc = Dict{String,Any}("field" => linestyle_field, "type" => "nominal")
        !isnothing(linestyle_label) && linestyle_label != linestyle_field && (ls_enc["title"] = linestyle_label)
        encoding["strokeDash"] = ls_enc
    end
    if !isnothing(detail_field)
        d_enc = Dict{String,Any}("field" => detail_field, "type" => "nominal")
        !isnothing(detail_label) && detail_label != detail_field && (d_enc["title"] = detail_label)
        encoding["detail"] = d_enc
    end

    # Auto tooltip
    tt = vl_tooltips(encoding)
    !isempty(tt) && (encoding["tooltip"] = tt)

    vis = extract_visual(layer)
    mark = Dict{String,Any}("type" => "line", "interpolate" => "step-after")
    if !isnothing(vis)
        merge!(mark, visual_attrs_to_mark_props(vis))
    end

    # Detect per-group x cardinality. A group with only 1 unique x is a
    # point-mass distribution -- the empirical CDF is a vertical jump
    # from 0 to 1 at that x. Vega-Lite's `line` mark with all rows at
    # the same x renders to nothing visible (zero horizontal extent),
    # even with `step-after` interpolation. So for such groups we emit
    # a `rule` mark (true 1D vertical from y=0 to y=1) instead. Bypasses
    # the window transforms entirely -- duplicate rows in the data are
    # harmless because the rule paints the same pixels.
    degen_keys, normal_keys = _ecdf_partition_groups(table, x_field, groupby_fields)
    all_degen   = !isempty(degen_keys) && isempty(normal_keys)
    has_normal  = !isempty(normal_keys)
    has_degen   = !isempty(degen_keys)

    rule_layer = nothing
    if has_degen
        rule_enc = copy(encoding)
        rule_enc["y"]  = Dict{String,Any}("datum" => 0,
                                          "type"  => "quantitative",
                                          "title" => "Cumulative Proportion")
        rule_enc["y2"] = Dict{String,Any}("datum" => 1)
        delete!(rule_enc, "tooltip")  # __ecdf__ doesn't exist on this layer
        # rebuild tooltip from x + groupby only
        rt = vl_tooltips(rule_enc)
        !isempty(rt) && (rule_enc["tooltip"] = rt)
        rule_mark = Dict{String,Any}("type" => "rule")
        !isnothing(vis) && merge!(rule_mark, visual_attrs_to_mark_props(vis))
        rule_layer = Dict{String,Any}(
            "mark"     => rule_mark,
            "encoding" => rule_enc,
        )
        # Filter to degenerate groups only (single-field groupby case);
        # multi-field groupby falls back to no filter when mixed (rare;
        # current BRM use cases only ever group by `:draw`).
        if has_normal && length(groupby_fields) == 1
            rule_layer["transform"] = [Dict{String,Any}(
                "filter" => Dict{String,Any}(
                    "field"  => groupby_fields[1],
                    "oneOf"  => collect(degen_keys),
                ),
            )]
        end
    end

    line_layer = nothing
    if has_normal || !has_degen  # no-data case still gets the line spec
        line_enc = encoding
        line_layer = Dict{String,Any}(
            "mark"      => mark,
            "transform" => [window1, window2, calc],
            "encoding"  => line_enc,
        )
        if has_degen && length(groupby_fields) == 1
            pushfirst!(line_layer["transform"], Dict{String,Any}(
                "filter" => Dict{String,Any}(
                    "field"  => groupby_fields[1],
                    "oneOf"  => collect(normal_keys),
                ),
            ))
        end
    end

    spec = if all_degen
        rule_layer
    elseif !has_degen
        line_layer
    else
        Dict{String,Any}("layer" => [rule_layer, line_layer])
    end

    if !isnothing(table)
        spec["data"] = data_to_vl(table)
        # Infer types on every encoding actually present in the final
        # spec -- when `all_degen`, `encoding` belongs to the discarded
        # line layer and inferring types on it would be a no-op for the
        # rule spec.
        for enc in (haskey(spec, "layer") ?
                    [l["encoding"] for l in spec["layer"]] :
                    [spec["encoding"]])
            infer_types!(enc, table)
        end
    end
    spec
end

# Inspect `table` and return (degenerate_keys, normal_keys) where the
# keys are the unique values of the single-field groupby case (or
# tuples for multi-field). "Degenerate" means the group has only 1
# unique x value -- visually a point-mass and broken for line marks.
# When `groupby_fields` is empty, treats the entire table as one group
# and returns ([nothing], []) if degenerate, ([], [nothing]) if not.
function _ecdf_partition_groups(table, x_field::AbstractString,
                                groupby_fields::Vector{String})
    isnothing(table) && return (Any[], Any[])
    rows = Tables.rows(table)
    xs_per_group = Dict{Any,Set{Any}}()
    if isempty(groupby_fields)
        xs = Set{Any}()
        for r in rows
            push!(xs, getproperty(r, Symbol(x_field)))
        end
        return length(xs) == 1 ? (Any[nothing], Any[]) :
                                 (Any[], Any[nothing])
    end
    one_field = length(groupby_fields) == 1
    f1 = Symbol(groupby_fields[1])
    for r in rows
        key = one_field ? getproperty(r, f1) :
              Tuple(getproperty(r, Symbol(f)) for f in groupby_fields)
        bucket = get!(xs_per_group, key) do; Set{Any}() end
        push!(bucket, getproperty(r, Symbol(x_field)))
    end
    degen, normal = Any[], Any[]
    for (k, xs) in xs_per_group
        push!(length(xs) == 1 ? degen : normal, k)
    end
    degen, normal
end
