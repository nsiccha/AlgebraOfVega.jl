# --- Core translation: dispatch-based layer_to_vl ---

"""Analysis types to check in `_layer_handler`, in priority order."""
_ANALYSIS_TYPES = Type[
    TidybayesAnalysis,
    AlgebraOfGraphics.DensityAnalysis,
    AlgebraOfGraphics.FrequencyAnalysis,
    AlgebraOfGraphics.ExpectationAnalysis,
    AlgebraOfGraphics.LinearAnalysis,
    AlgebraOfGraphics.SmoothAnalysis,
    AlgebraOfGraphics.HistogramAnalysis,
]

"""Find the dispatch key for a layer: an analysis object, Val(:ecdf), or nothing (plain layer)."""
function _layer_handler(layer::AlgebraOfGraphics.Layer)
    for T in _ANALYSIS_TYPES
        a = extract_transformation(layer, T)
        !isnothing(a) && return a
    end
    _ecdf_dispatch_value(layer)
end

# Dispatch: each handler type → its *_to_vl function
_layer_to_vl(a::TidybayesAnalysis, layer; kw...) = analysis_to_vl(a, layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.DensityAnalysis, layer; kw...) = density_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.FrequencyAnalysis, layer; kw...) = frequency_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.ExpectationAnalysis, layer; kw...) = expectation_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.LinearAnalysis, layer; kw...) = linear_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.SmoothAnalysis, layer; kw...) = smooth_to_vl(layer; kw...)
_layer_to_vl(::AlgebraOfGraphics.HistogramAnalysis, layer; kw...) = histogram_to_vl(layer; kw...)
_layer_to_vl(::Val{:ecdf}, layer; kw...) = ecdf_to_vl(layer; kw...)
_layer_to_vl(::Nothing, layer; kw...) = _plain_layer_to_vl(layer; kw...)

function layer_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    if is_pregrouped(layer)
        spec = pregrouped_to_vl(layer; is_sublayer)
    else
        handler = _layer_handler(layer)
        spec = _layer_to_vl(handler, layer; is_sublayer)
    end
    !is_sublayer && (spec["\$schema"] = VL_SCHEMA)
    spec
end

"""Translate a plain (non-analysis, non-pregrouped) AoG layer to VL."""
function _plain_layer_to_vl(layer::AlgebraOfGraphics.Layer; is_sublayer=false)
    spec = Dict{String,Any}()

    table = extract_data(layer)
    !isnothing(table) && (spec["data"] = data_to_vl(table))

    # Visual / mark (default to Scatter like AoG)
    vis = extract_visual(layer)
    if !isnothing(vis)
        mark_type = plottype_to_mark(vis.plottype)
        extra_props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
        spec["mark"] = isempty(extra_props) ? mark_type :
            merge(Dict{String,Any}("type" => mark_type), extra_props)
    else
        spec["mark"] = "point"
    end

    # Encoding from positional + named
    encoding = Dict{String,Any}()

    plot_type = !isnothing(vis) ? vis.plottype : Nothing
    positional_channels = if !isnothing(vis) && plot_type <: HLines
        ["y"]
    elseif !isnothing(vis) && plot_type <: VLines
        ["x"]
    elseif !isnothing(vis) && plot_type <: Union{Rangebars, Errorbars}
        ["x", "y", "y2"]
    else
        ["x", "y"]
    end
    for (i, sel) in enumerate(layer.positional)
        i <= length(positional_channels) || break
        encoding[positional_channels[i]] = selector_to_field(sel)
    end

    for (name, sel) in pairs(layer.named)
        ch = aog_named_to_vl_channel(name)
        isnothing(ch) && continue
        encoding[ch] = selector_to_field(sel)
    end

    !isnothing(table) && infer_types!(encoding, table)

    # Auto-tooltip
    if !isempty(encoding) && !haskey(encoding, "tooltip")
        tt = vl_tooltips(encoding)
        !isempty(tt) && (encoding["tooltip"] = tt)
    end

    !isempty(encoding) && (spec["encoding"] = encoding)
    spec
end

function layers_to_vl(layers::AlgebraOfGraphics.Layers)
    # Check if any layer is faceted density (density with y group) — needs special handling
    has_faceted_density = false
    facet_field = nothing
    shared_table = nothing
    shared_data = nothing

    for l in layers.layers
        is_pregrouped(l) && continue
        table = extract_data(l)
        if !isnothing(table) && isnothing(shared_table)
            shared_data = data_to_vl(table)
            shared_table = table
        end
        dens = extract_transformation(l, AlgebraOfGraphics.DensityAnalysis)
        if !isnothing(dens) && haskey(l.named, :y)
            has_faceted_density = true
            facet_field = string(l.named[:y])
        end
    end

    if has_faceted_density && !isnothing(facet_field)
        return _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    end

    # Check if any layer is an analysis type (produces own summarized data)
    has_analysis = any(l -> !isnothing(extract_transformation(l, TidybayesAnalysis)), layers.layers)

    spec = Dict{String,Any}("\$schema" => VL_SCHEMA)
    # Only share data at top level when no analysis layers are present
    if !has_analysis && !isnothing(shared_data)
        spec["data"] = shared_data
    end

    outer_facet = Dict{String,Any}()
    layer_specs = Dict{String,Any}[]

    for layer in layers.layers
        ls = layer_to_vl(layer; is_sublayer=true)

        if haskey(ls, "facet")
            # Faceted analysis spec — lift facet, flatten inner sublayers with their data
            merge!(outer_facet, ls["facet"])
            inner = ls["spec"]
            inner_data = get(ls, "data", get(inner, "data", nothing))
            for sl in get(inner, "layer", [inner])
                if !isnothing(inner_data) && !haskey(sl, "data")
                    sl["data"] = inner_data
                end
                push!(layer_specs, sl)
            end
        elseif haskey(ls, "layer")
            # Multi-layer (unfaceted analysis) — flatten sublayers with attached data
            sub_data = get(ls, "data", nothing)
            for sl in ls["layer"]
                if !isnothing(sub_data) && !haskey(sl, "data")
                    sl["data"] = sub_data
                end
                push!(layer_specs, sl)
            end
        else
            # Single layer
            if has_analysis && !haskey(ls, "data")
                # Mixed mode — ensure each layer carries its own data
                table = extract_data(layer)
                !isnothing(table) && (ls["data"] = data_to_vl(table))
            elseif !has_analysis
                table = extract_data(layer)
                if !isnothing(table) && table === shared_table
                    delete!(ls, "data")
                end
            end
            push!(layer_specs, ls)
        end
    end

    # Also collect facet from regular layer encodings (col=/row= → column/row channels)
    for ls in layer_specs
        enc = get(ls, "encoding", nothing)
        isnothing(enc) && continue
        haskey(enc, "column") && !haskey(outer_facet, "column") && (outer_facet["column"] = enc["column"])
        haskey(enc, "row") && !haskey(outer_facet, "row") && (outer_facet["row"] = enc["row"])
    end

    if !isempty(outer_facet)
        # VL facet only filters inherited (outer) data — per-sublayer data is NOT filtered.
        # Fix: merge all sublayer data into one outer dataset tagged with __source__,
        # then add filter transforms to each sublayer so they only see their own rows.
        merged_values = Dict{String,Any}[]
        src_id = 0
        seen_data = Dict{UInt,String}()  # objectid(values) → source tag

        # Re-include hoisted shared_data for sublayers that had their data removed
        hoisted_layers = filter(ls -> !haskey(ls, "data"), layer_specs)
        if !isnothing(shared_data) && !isempty(hoisted_layers)
            vals = get(shared_data, "values", nothing)
            if !isnothing(vals)
                src_id += 1
                tag = "_s$(src_id)"
                seen_data[objectid(vals)] = tag
                for row in vals
                    row["__src"] = tag
                end
                append!(merged_values, vals)
                for ls in hoisted_layers
                    existing = get(ls, "transform", Dict{String,Any}[])
                    pushfirst!(existing, Dict{String,Any}("filter" => "datum.__src === '$(tag)'"))
                    ls["transform"] = existing
                end
            end
        end

        for ls in layer_specs
            data = get(ls, "data", nothing)
            isnothing(data) && continue
            vals = get(data, "values", nothing)
            isnothing(vals) && continue
            oid = objectid(vals)
            tag = get(seen_data, oid, nothing)
            if isnothing(tag)
                src_id += 1
                tag = "_s$(src_id)"
                seen_data[oid] = tag
                for row in vals
                    row["__src"] = tag
                end
                append!(merged_values, vals)
            end
            # Replace per-sublayer data with a filter transform
            delete!(ls, "data")
            existing = get(ls, "transform", Dict{String,Any}[])
            pushfirst!(existing, Dict{String,Any}("filter" => "datum.__src === '$(tag)'"))
            ls["transform"] = existing
        end
        # Strip column/row from sublayer encodings — facet is at top level
        for ls in layer_specs
            enc = get(ls, "encoding", nothing)
            isnothing(enc) && continue
            delete!(enc, "column")
            delete!(enc, "row")
        end
        _harmonize_axis_types!(layer_specs)
        spec["data"] = Dict{String,Any}("values" => merged_values)
        spec["facet"] = outer_facet
        spec["spec"] = Dict{String,Any}("layer" => layer_specs)
    else
        _harmonize_axis_types!(layer_specs)
        spec["layer"] = layer_specs
    end

    spec
end

# For sibling sublayers that encode the same `field` on the same axis
# (x / y) but disagree on `type`, coerce all to the most conservative
# (nominal) type. Fixes the "Unrecognized scale name: child_layer_N_x"
# compile failure when e.g. a vertical pointinterval (group axis hardcoded
# nominal) is overlaid with a `visual(Scatter)` whose Int-column positional
# gets inferred as quantitative: VL emits per-layer band+linear scales that
# don't cross-reference.
#
# Nominal is the safe coercion: any value can be treated as a category,
# while quantitative requires numeric values — string categories can't be
# widened without data loss.
# Get `ls.encoding[axis]` as a Dict, or nothing if any step doesn't fit.
_axis_enc(ls::Dict, axis) = let enc = _as_dict(get(ls, "encoding", nothing))
    isnothing(enc) ? nothing : _as_dict(get(enc, axis, nothing))
end
_axis_enc(_, _) = nothing

function _harmonize_axis_types!(layer_specs::Vector{Dict{String,Any}})
    for axis in ("x", "y")
        # field → any sublayer has `type=nominal` for it
        nominal_fields = Set{String}()
        for ls in layer_specs
            ae = _axis_enc(ls, axis)
            isnothing(ae) && continue
            f = _as_str(get(ae, "field", nothing))
            isnothing(f) && continue
            get(ae, "type", nothing) == "nominal" && push!(nominal_fields, f)
        end
        isempty(nominal_fields) && continue
        for ls in layer_specs
            ae = _axis_enc(ls, axis)
            isnothing(ae) && continue
            f = _as_str(get(ae, "field", nothing))
            (!isnothing(f) && f in nominal_fields) || continue
            get(ae, "type", nothing) == "nominal" && continue
            ae["type"] = "nominal"
            # Drop scale config that's meaningless for nominal axes
            sc = _as_dict(get(ae, "scale", nothing))
            if !isnothing(sc)
                st = _as_str(get(sc, "type", nothing))
                if !isnothing(st) && st in ("log", "sqrt", "pow", "symlog")
                    delete!(sc, "type")
                end
                isempty(sc) && delete!(ae, "scale")
            end
        end
    end
    layer_specs
end

function _faceted_layers_to_vl(layers, facet_field, shared_table, shared_data)
    # For density + pointinterval combos: facet by group field, inner spec has layers
    inner_layers = Dict{String,Any}[]

    # Check if we have visual layers alongside density (raincloud-style) — need range scaling
    has_visual_layers = any(l -> begin
        isnothing(extract_transformation(l, AlgebraOfGraphics.DensityAnalysis)) && isnothing(extract_transformation(l, TidybayesAnalysis)) && !isnothing(extract_visual(l))
    end, layers.layers)

    for layer in layers.layers
        dens = extract_transformation(layer, AlgebraOfGraphics.DensityAnalysis)
        if !isnothing(dens)
            # Density sublayer (unfaceted version)
            x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
            x_label = length(layer.positional) >= 1 ? _field_label(layer.positional[1]) : "value"
            vis = extract_visual(layer)
            opacity = 0.4
            if !isnothing(vis) && haskey(vis.attributes, :opacity)
                opacity = vis.attributes[:opacity]
            end
            y_enc = Dict{String,Any}("field" => "dens", "type" => "quantitative", "title" => nothing, "axis" => nothing)
            if has_visual_layers
                y_enc["scale"] = Dict{String,Any}("range" => [0, 40])
            end
            push!(inner_layers, Dict{String,Any}(
                "mark" => Dict{String,Any}("type" => "area", "orient" => "vertical", "opacity" => opacity),
                "transform" => [Dict{String,Any}("density" => x_field, "as" => ["val", "dens"])],
                "encoding" => Dict{String,Any}(
                    "x" => Dict{String,Any}("field" => "val", "type" => "quantitative", "title" => x_label),
                    "y" => y_enc,
                ),
            ))
        else
            analysis = extract_transformation(layer, TidybayesAnalysis)
            if !isnothing(analysis)
                # Compute interval summary per-group using VL transforms instead
                x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
                probs = _analysis_probs(analysis)
                point_sym = hasproperty(analysis, :point) ? analysis.point : :median

                # Use VL quantile transforms for intervals within facet
                sorted_probs = sort(probs, rev=true)
                styles = _interval_styles(analysis, sorted_probs)

                for (i, prob) in enumerate(sorted_probs)
                    lo_p = (1 - prob) / 2
                    hi_p = 1 - lo_p
                    enc = Dict{String,Any}(
                        "x" => Dict{String,Any}("aggregate" => "min", "field" => "val", "type" => "quantitative"),
                        "x2" => Dict{String,Any}("aggregate" => "max", "field" => "val"),
                    )
                    style = styles[i]
                    _apply_opacity!(enc, style.opacity)
                    mark = Dict{String,Any}("type" => "rule", "strokeWidth" => style.stroke_width)
                    push!(inner_layers, Dict{String,Any}(
                        "mark" => mark,
                        "transform" => [
                            Dict{String,Any}("quantile" => x_field, "probs" => [lo_p, hi_p], "as" => ["prob", "val"]),
                            Dict{String,Any}("fold" => ["val"]),
                        ],
                        "encoding" => enc,
                    ))
                end

                # Median point
                push!(inner_layers, Dict{String,Any}(
                    "mark" => Dict{String,Any}("type" => "point", "filled" => true, "size" => 60, "color" => "white", "stroke" => "#333", "strokeWidth" => 1.5),
                    "transform" => [Dict{String,Any}("quantile" => x_field, "probs" => [0.5], "as" => ["prob", "val"])],
                    "encoding" => Dict{String,Any}(
                        "x" => Dict{String,Any}("field" => "val", "type" => "quantitative"),
                    ),
                ))
            else
                # Standard layer (e.g. visual(Scatter, BoxPlot)) inside facet
                # Strip the facet field from encoding — it's handled by facet, not y axis
                x_field = length(layer.positional) >= 1 ? _field_name(layer.positional[1]) : "value"
                vis = extract_visual(layer)
                if !isnothing(vis)
                    mark_type = plottype_to_mark(vis.plottype)
                    mark_props = merge(plottype_to_mark_props(vis.plottype), visual_attrs_to_mark_props(vis))
                    mark = isempty(mark_props) ? mark_type : merge(Dict{String,Any}("type" => mark_type), mark_props)

                    enc = Dict{String,Any}(
                        "x" => Dict{String,Any}("field" => x_field, "type" => "quantitative"),
                    )

                    if vis.plottype <: Scatter
                        # Add jitter for scatter inside facet (like original raincloud)
                        push!(inner_layers, Dict{String,Any}(
                            "mark" => mark,
                            "transform" => [Dict{String,Any}("calculate" => "-random() * 15 - 2", "as" => "jitter")],
                            "encoding" => merge(enc, Dict{String,Any}(
                                "y" => Dict{String,Any}("field" => "jitter", "type" => "quantitative",
                                                         "axis" => nothing, "scale" => Dict{String,Any}("range" => [0, 40])),
                            )),
                        ))
                    else
                        push!(inner_layers, Dict{String,Any}("mark" => mark, "encoding" => enc))
                    end
                end
            end
        end
    end

    spec = Dict{String,Any}(
        "\$schema" => VL_SCHEMA,
        "data" => shared_data,
        "facet" => Dict{String,Any}("field" => facet_field, "type" => "nominal",
                                     "header" => Dict{String,Any}("title" => nothing, "labelFontSize" => 14)),
        "columns" => 1,
        "spec" => Dict{String,Any}(
            "width" => 500, "height" => (has_visual_layers ? 70 : 60),
            "layer" => inner_layers,
        ),
    )
    spec
end
