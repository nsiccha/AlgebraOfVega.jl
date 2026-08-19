# --- Public API: to_vegalite ---

"""
    to_vegalite(spec) -> Dict{String,Any}

Convert an AoG `Layer`, `Layers`, or `VegaSpec` to a Vega-Lite JSON dictionary.
Handles all translation: mark types, encodings, statistical transforms, config merging,
and auto-interactivity.
"""
function to_vegalite(layer::AlgebraOfGraphics.Layer)
    spec = layer_to_vl(layer)
    _apply_no_zero_default!(spec)
    _densify_facet_sort!(spec)
    spec
end

function to_vegalite(layers::AlgebraOfGraphics.Layers)
    spec = layers_to_vl(layers)
    _apply_no_zero_default!(spec)
    _densify_facet_sort!(spec)
    spec
end

# AoV default: don't auto-include zero on quantitative x/y axes (overrides VL's
# default `scale.zero=true`). Users opt back in via
# `config(scales=scales(Y=(; zero=true)))` or `encoding=Dict("y"=>Dict("scale"=>Dict("zero"=>true)))`.
_apply_no_zero_default!(_) = nothing
function _apply_no_zero_default!(spec::Dict)
    if haskey(spec, "encoding") && spec["encoding"] isa Dict
        for ch in ("x", "y")
            enc = get(spec["encoding"], ch, nothing)
            enc isa Dict || continue
            get(enc, "type", nothing) == "quantitative" || continue
            scale = get!(enc, "scale", Dict{String,Any}())
            scale isa Dict || continue
            haskey(scale, "zero") || (scale["zero"] = false)
        end
    end
    if haskey(spec, "layer")
        for sub in spec["layer"]; _apply_no_zero_default!(sub); end
    end
    if haskey(spec, "spec"); _apply_no_zero_default!(spec["spec"]); end
end

# Vega-Lite mis-binds faceted panels when a facet channel carries an explicit
# `sort` array AND the row×column cross-product is sparse (some cells have no
# data): VL fills the sorted header slots positionally, so a missing combination
# shifts real panels under the wrong header. (Third-party VL behaviour, not an
# AoV bug — repro in ~/scratch/heizung_shot: `with_sort` BROKEN vs `sort_dense`
# CORRECT; the `encoding.column` shorthand and the top-level `facet` operator
# forms fail identically, which is why the fix lives at the shared data level.)
# Densify the cross-product: for every missing (row, col) cell, append a filler
# row so the slot owns a cell. The filler is a CLONE of an existing row with its
# measure (y) nulled — cloning keeps a valid colour/x value so no `null` category
# leaks into the colour scale (a bare keys-only filler recolours the real series,
# verified), and the null measure means no mark is drawn in the genuinely-empty
# cell. Only fires when a facet `sort` is present and BOTH axes are faceted —
# unsorted specs and single-axis facets already render sparse data correctly.
_densify_facet_sort!(_) = nothing
function _densify_facet_sort!(spec::Dict)
    # Recurse into layered / faceted children first (mirrors _apply_no_zero_default!).
    # A layered spec (`+` overlay) or facet-operator spec carries its per-sublayer
    # encodings in `layer` / the inner `spec`, and — when sibling sublayers don't
    # share a liftable channel — the top level then has NO `encoding` of its own.
    if haskey(spec, "layer")
        for sub in spec["layer"]; _densify_facet_sort!(sub); end
    end
    if haskey(spec, "spec"); _densify_facet_sort!(spec["spec"]); end
    facet = _as_dict(get(spec, "facet", nothing))
    enc = _as_dict(get(spec, "encoding", nothing))
    # row/col channels: `facet` operator form vs `encoding` shorthand form. Guard the
    # source first — `get(nothing, ...)` has no method, so an encoding-less layered
    # spec would otherwise throw here.
    src = isnothing(facet) ? enc : facet
    isnothing(src) && return
    row_ch = _as_dict(get(src, "row", nothing))
    col_ch = _as_dict(get(src, "column", nothing))
    _has_sort(ch) = !isnothing(ch) && get(ch, "sort", nothing) isa AbstractVector
    (_has_sort(row_ch) || _has_sort(col_ch)) || return
    # Cross-product sparsity only exists when both axes are faceted.
    (isnothing(row_ch) || isnothing(col_ch)) && return
    row_field = get(row_ch, "field", nothing)
    col_field = get(col_ch, "field", nothing)
    (row_field isa AbstractString && col_field isa AbstractString) || return
    data = _as_dict(get(spec, "data", nothing))
    isnothing(data) && return
    vals = get(data, "values", nothing)
    (vals isa AbstractVector && !isempty(vals)) || return  # named datasets / urls: can't densify here
    donor = nothing
    for r in vals; r isa Dict && (donor = r; break); end
    isnothing(donor) && return
    # Positional measure fields to null so a filler draws no mark. `x` (the
    # independent axis) is left intact; nulling `y`/`y2`/`x2` covers the
    # line/area/point/bar marks faceted small-multiples use.
    inner_enc = isnothing(facet) ? enc : _as_dict(get(_as_dict(get(spec, "spec", nothing)), "encoding", nothing))
    measure_fields = String[]
    if !isnothing(inner_enc)
        for pc in ("y", "y2", "x2")
            ce = _as_dict(get(inner_enc, pc, nothing))
            isnothing(ce) && continue
            f = get(ce, "field", nothing)
            f isa AbstractString && push!(measure_fields, f)
        end
    end
    rowvals = unique(r[row_field] for r in vals if r isa Dict && haskey(r, row_field))
    colvals = unique(r[col_field] for r in vals if r isa Dict && haskey(r, col_field))
    present = Set((get(r, row_field, nothing), get(r, col_field, nothing)) for r in vals if r isa Dict)
    for rv in rowvals, cv in colvals
        (rv, cv) in present && continue
        filler = copy(donor)
        filler[row_field] = rv
        filler[col_field] = cv
        for mf in measure_fields; filler[mf] = nothing; end
        push!(vals, filler)
    end
    return
end

function _deep_merge_encoding!(target_enc::Dict, config_enc::Dict)
    for (ek, ev) in config_enc
        sek = string(ek)
        ev_dict = _as_dict(ev)
        target_dict = _as_dict(get(target_enc, sek, nothing))
        if !isnothing(ev_dict) && !isnothing(target_dict)
            merge!(target_dict, Dict{String,Any}(string(k2) => v2 for (k2, v2) in ev_dict))
        else
            target_enc[sek] = ev
        end
    end
end

# Recurse the merge into a child spec only when it's actually a Dict.
_merge_into_child!(args...) = nothing
_merge_into_child!(child::Dict, config_enc::Dict) = _merge_encoding_config!(child, config_enc)

function _merge_encoding_config!(spec::Dict, config_enc::Dict)
    if haskey(spec, "encoding")
        _deep_merge_encoding!(spec["encoding"], config_enc)
    end
    if haskey(spec, "layer")
        for sublayer in spec["layer"]
            _merge_into_child!(sublayer, config_enc)
        end
    end
    if haskey(spec, "spec")
        _merge_into_child!(spec["spec"], config_enc)
    end
end

# --- AoG scales / facet sugar (mirrors AlgebraOfGraphics.draw(spec, scales(...); facet=...)) ---

"""Translate an AoG scale transform function to a VL `scale` object, or `nothing` if unsupported."""
function _aog_scale_fn_to_vl(f)
    f === identity && return nothing
    f === log10 && return Dict{String,Any}("type" => "log")
    f === log2 && return Dict{String,Any}("type" => "log", "base" => 2)
    f === log && return Dict{String,Any}("type" => "log", "base" => ℯ)
    f === sqrt && return Dict{String,Any}("type" => "sqrt")
    f === symlog && return Dict{String,Any}("type" => "symlog")
    @warn "AlgebraOfVega: cannot translate scale function `$f` to a Vega-Lite scale; leaving axis untransformed. Supported: identity, log, log2, log10, sqrt, symlog." maxlog=1
    nothing
end

_aog_axis_key_to_vl_channel(k::Symbol) =
    k === :X ? "x" : k === :Y ? "y" : k === :Z ? "z" : nothing

# Per-channel scale options forwarded from a `scales(X=(; scale=..., nice=..., ...))`
# NamedTuple into the VL `encoding.<ch>.scale` dict. Maps Julia key → VL key.
# `constant` is the symlog linear-region half-width (VL default 1); it rides here
# like the other VL-side scale details (these keys are Vega-Lite-only — AoG's
# continuous X/Y/Z scale rejects them on the `sdraw`/Makie path).
const _SCALES_NT_FORWARD = (
    nice     = "nice",
    zero     = "zero",
    domain   = "domain",
    clamp    = "clamp",
    constant = "constant",
)

"""Translate an AoG `Scales` object into a VL encoding-override dict (X/Y/Z scales only).

Per-channel kwargs forwarded into the VL `scale` dict:
- `scale` — translated via `_aog_scale_fn_to_vl` (log/log2/log10/sqrt/symlog/identity)
- `nice`, `zero`, `domain`, `clamp`, `constant` — passed through verbatim
  (`constant` tunes the `symlog` linear-region half-width)

Channels with no forwardable kwargs are skipped (no `scale` key emitted)."""
function _scales_to_encoding_override(sc::AlgebraOfGraphics.Scales)
    override = Dict{String,Any}()
    for (axis_key, props) in pairs(sc.dict)
        ch = _aog_axis_key_to_vl_channel(axis_key)
        isnothing(ch) && continue
        vl_scale = Dict{String,Any}()
        scale_fn = get(props, :scale, nothing)
        if !isnothing(scale_fn)
            translated = _aog_scale_fn_to_vl(scale_fn)
            !isnothing(translated) && merge!(vl_scale, translated)
        end
        for (jl_key, vl_key) in pairs(_SCALES_NT_FORWARD)
            haskey(props, jl_key) || continue
            vl_scale[vl_key] = props[jl_key]
        end
        isempty(vl_scale) && continue
        override[ch] = Dict{String,Any}("scale" => vl_scale)
    end
    override
end

"""Merge a VL `resolve.scale` dict into `spec`, preserving any existing entries."""
function _merge_resolve_scale!(spec::Dict, resolve_scale::Dict)
    isempty(resolve_scale) && return
    resolve = get!(spec, "resolve", Dict{String,Any}())
    existing = get!(resolve, "scale", Dict{String,Any}())
    merge!(existing, resolve_scale)
end

"""Translate an AoG-style `facet=(; linkxaxes, linkyaxes)` NamedTuple into a VL `resolve.scale` dict."""
function _facet_nt_to_resolve_scale(nt)
    out = Dict{String,Any}()
    linkx = get(nt, :linkxaxes, nothing)
    linky = get(nt, :linkyaxes, nothing)
    (linkx === :none || linkx === false) && (out["x"] = "independent")
    (linky === :none || linky === false) && (out["y"] = "independent")
    out
end

"""
Translate an AoG-style `axis=(; limits=((xlo, xhi), (ylo, yhi)))` NamedTuple into a
VL encoding-override dict. `limits` entries may be `nothing` to skip an axis.
`clamp=true` adds `clamp: true` to every axis that has explicit limits.
"""
_as_pair(t::Tuple{Any,Any}) = t
_as_pair(_) = nothing

function _axis_nt_to_encoding_override(nt)
    override = Dict{String,Any}()
    limits = _as_pair(get(nt, :limits, nothing))
    isnothing(limits) && return override
    do_clamp = get(nt, :clamp, false) === true
    for (idx, ch) in enumerate(("x", "y"))
        lim = _as_pair(limits[idx])
        isnothing(lim) && continue
        scale_dict = Dict{String,Any}("domain" => [lim[1], lim[2]])
        do_clamp && (scale_dict["clamp"] = true)
        override[ch] = Dict{String,Any}("scale" => scale_dict)
    end
    override
end

# Narrow a config-prop to the type our sugar handlers expect, or `nothing`.
_as_scales(s::AlgebraOfGraphics.Scales) = s
_as_scales(_) = nothing
_as_nt(nt::NamedTuple) = nt
_as_nt(_) = nothing

# Sugar appliers — dispatch the work over the `val` type. The Any fallback is
# what fires when the prop key exists but the value isn't of the expected shape.
_apply_scales_sugar!(args...) = nothing
_apply_scales_sugar!(spec, s::AlgebraOfGraphics.Scales) =
    let override = _scales_to_encoding_override(s)
        isempty(override) || _merge_encoding_config!(spec, override)
    end

_apply_facet_sugar!(args...) = nothing
_apply_facet_sugar!(spec, nt::NamedTuple) =
    _merge_resolve_scale!(spec, _facet_nt_to_resolve_scale(nt))

_apply_axis_sugar!(args...) = nothing
_apply_axis_sugar!(spec, nt::NamedTuple) =
    let override = _axis_nt_to_encoding_override(nt)
        isempty(override) || _merge_encoding_config!(spec, override)
    end

# Sugar for VL resolve: independent_scales=true, =:x, =(:x,:y)
_independent_axes(val::Bool) = val === true ? ["x", "y"] : String[]
_independent_axes(val::Symbol) = [string(val)]
_independent_axes(val) = [string(v) for v in val]

_select_field_list(s::Symbol) = [s]
_select_field_list(v) = v

function to_vegalite(v::VegaSpec)
    spec = to_vegalite(v.drawable)
    select_fields = nothing
    if !isnothing(v.config)
        props = v.config.properties
        # First pass: apply AoG-style sugar (scales, facet) so user-supplied
        # `encoding=Dict(...)` in the second pass can still override on conflict.
        haskey(props, :scales) && _apply_scales_sugar!(spec, props[:scales])
        haskey(props, :facet) && _apply_facet_sugar!(spec, props[:facet])
        haskey(props, :axis) && _apply_axis_sugar!(spec, props[:axis])
        for (k, val) in props
            sk = string(k)
            # Deep-merge encoding so config adds to (not overwrites) auto-generated channels
            if sk == "encoding" && !isnothing(_as_dict(val))
                _merge_encoding_config!(spec, val)
            elseif sk in ("width", "height") && haskey(spec, "spec")
                # For faceted specs, width/height go into the inner spec
                spec["spec"][sk] = val
            elseif sk == "scales" && !isnothing(_as_scales(val))
                # Handled in first pass
            elseif sk == "facet" && !isnothing(_as_nt(val))
                # Handled in first pass
            elseif sk == "axis" && !isnothing(_as_nt(val))
                # Handled in first pass
            elseif sk == "independent_scales"
                @warn "AlgebraOfVega: `config(independent_scales=$(repr(val)))` is deprecated; use `config(facet=(; linkxaxes=:none, linkyaxes=:none))` to mirror AlgebraOfGraphics." maxlog=1
                axes = _independent_axes(val)
                _merge_resolve_scale!(spec, Dict{String,Any}(ax => "independent" for ax in axes))
            elseif sk == "font_scale"
                # Scale all default VL font sizes by val
                fs = Float64(val)
                cfg = get!(spec, "config", Dict{String,Any}())
                ax = get!(cfg, "axis", Dict{String,Any}())
                ax["labelFontSize"] = round(Int, 10 * fs)
                ax["titleFontSize"] = round(Int, 11 * fs)
                lg = get!(cfg, "legend", Dict{String,Any}())
                lg["labelFontSize"] = round(Int, 10 * fs)
                lg["titleFontSize"] = round(Int, 11 * fs)
                hd = get!(cfg, "header", Dict{String,Any}())
                hd["labelFontSize"] = round(Int, 10 * fs)
                hd["titleFontSize"] = round(Int, 11 * fs)
                tt = get!(cfg, "title", Dict{String,Any}())
                tt["fontSize"] = round(Int, 13 * fs)
            elseif sk == "max_width"
                # Store max width in _aov for JS to cap responsive sizing
                aov = get!(spec, "_aov", Dict{String,Any}())
                aov["maxWidth"] = val
            elseif sk == "select"
                # Collect select fields — processed after spec is built
                select_fields = _select_field_list(val)
            else
                spec[sk] = val
            end
        end
    end
    if !isnothing(select_fields)
        add_select_filters!(spec, v.drawable, select_fields)
    end
    add_auto_interactivity!(spec)
    spec
end

"""
    add_select_filters!(spec, drawable, fields)

Add dropdown filter widgets for the given fields. Extracts unique values from
the data and injects VL `params` with `bind: {input: "select"}` + expression filters.

Usage via config: `config(select=:origin)` or `config(select=[:origin, :cylinders])`.
Each field gets a dropdown with "All" + sorted unique values.
"""
_drawable_table(l::AlgebraOfGraphics.Layer) = extract_data(l)
function _drawable_table(ls::AlgebraOfGraphics.Layers)
    for l in ls.layers
        t = extract_data(l)
        isnothing(t) || return t
    end
    nothing
end
_drawable_table(_) = nothing

function add_select_filters!(spec::Dict{String,Any}, drawable, fields)
    table = _drawable_table(drawable)
    isnothing(table) && return spec

    params = get!(spec, "params", Dict{String,Any}[])
    transforms = get!(spec, "transform", Dict{String,Any}[])

    # For layered specs, transforms go at the top level (shared data)
    # For single-view specs, they also go at the top level
    for field in fields
        field_str = string(field)
        param_name = "select_$(field_str)"

        # Get unique values
        field in Tables.columnnames(table) || continue
        vals = sort(unique(Tables.getcolumn(table, field)))

        # Add param with dropdown binding
        push!(params, Dict{String,Any}(
            "name" => param_name,
            "value" => nothing,  # null = show all
            "bind" => Dict{String,Any}(
                "input" => "select",
                "options" => [nothing; vals],
                "labels" => ["All"; [string(v) for v in vals]],
                "name" => "$(field_str): ",
            ),
        ))

        # Add filter transform
        push!(transforms, Dict{String,Any}(
            "filter" => "$(param_name) === null || datum.$(field_str) === $(param_name)",
        ))
    end

    spec
end

"""
    add_auto_interactivity!(spec)

Add automatic client-side interactivity to a Vega-Lite spec:
- **Legend click filtering**: For single-view specs with top-level `color` encoding,
  adds `bind: "legend"` selection so clicking legend items toggles group visibility.
  Uses `empty: true` so all data is visible by default.
- **Nearest-point tooltip**: For `line`/`area` marks with tooltip, adds `nearest: true`
  so the tooltip snaps to the closest data point.

Skipped when:
- User already defined `params` via `config()` (don't override explicit interactivity)
- Spec is faceted (`haskey(spec, "facet")`)
- Color encoding is only in sublayers, not top-level (VL `bind: "legend"` silently
  breaks layered specs where color is per-sublayer — renders empty)

Also skips adding the opacity condition when the mark already has an intentional
`opacity` property — both for sublayers (e.g. CI band areas with `mark.opacity: 0.2`)
and for single-view marks (e.g. `visual(Lines; opacity=0.15)` on a top-level-colored
line ensemble). An explicit `mark.opacity` always wins; the auto legend-dim only applies
when the user hasn't set their own opacity.
"""
function add_auto_interactivity!(spec::Dict{String,Any})
    # Don't add interactivity if user already defined params (via config)
    has_user_params = haskey(spec, "params")

    # For faceted specs, add zoom/pan inside "spec" (per-cell), not at facet level
    if haskey(spec, "facet")
        inner = get(spec, "spec", nothing)
        if !isnothing(inner) && !haskey(inner, "params")
            # Find quantitative axes in inner sublayers
            inner_layers = get(inner, "layer", nothing)
            inner_enc = get(inner, "encoding", nothing)
            zoom_ch = String[]
            for ch in ("x", "y")
                is_quant = false
                if !isnothing(inner_enc) && haskey(inner_enc, ch)
                    is_quant = get(inner_enc[ch], "type", "") == "quantitative"
                elseif !isnothing(inner_layers)
                    for sl in inner_layers
                        sl_enc = get(sl, "encoding", nothing)
                        isnothing(sl_enc) && continue
                        if haskey(sl_enc, ch) && get(sl_enc[ch], "type", "") == "quantitative"
                            is_quant = true
                            break
                        end
                    end
                end
                is_quant && push!(zoom_ch, ch)
            end
            if !isempty(zoom_ch)
                grid_param = Dict{String,Any}(
                    "name" => "grid",
                    "select" => Dict{String,Any}("type" => "interval", "encodings" => zoom_ch),
                    "bind" => "scales",
                )
                if !isnothing(inner_layers) && !isempty(inner_layers)
                    sl_params = get!(inner_layers[1], "params", Dict{String,Any}[])
                    push!(sl_params, grid_param)
                else
                    inner["params"] = [grid_param]
                end
            end
        end
        return spec
    end

    has_user_params && return spec

    # Find the encoding — may be top-level or in sublayers
    enc = get(spec, "encoding", nothing)
    sublayers = get(spec, "layer", nothing)
    mark = get(spec, "mark", nothing)
    mark_type = _mark_type(mark)
    is_composite = _is_composite_mark(spec)

    # Skip all interactivity for composite marks (boxplot, errorbar, errorband)
    # — VL doesn't support selections on them
    is_composite && return spec

    # Check for aggregate encodings (count, mean, etc.) — zoom can't project on those
    function _has_aggregate(enc_dict, ch)
        isnothing(enc_dict) && return false
        d = _as_dict(get(enc_dict, ch, nothing))
        !isnothing(d) && haskey(d, "aggregate")
    end

    # Find color field from top-level encoding only.
    # Legend binding doesn't work reliably for layered specs where color is only in sublayers.
    color_field = nothing
    if !isnothing(enc)
        color_enc = _as_dict(get(enc, "color", nothing))
        isnothing(color_enc) || (color_field = get(color_enc, "field", nothing))
    end

    params = Dict{String,Any}[]

    # Zoom (scroll) + pan (drag) — only on quantitative non-aggregate axes
    zoom_encodings = String[]
    for ch in ("x", "y")
        is_quant = false
        has_agg = false
        if !isnothing(enc) && haskey(enc, ch)
            is_quant = get(enc[ch], "type", "") == "quantitative"
            has_agg = _has_aggregate(enc, ch)
        elseif !isnothing(sublayers)
            for sl in sublayers
                sl_enc = get(sl, "encoding", nothing)
                isnothing(sl_enc) && continue
                if haskey(sl_enc, ch) && get(sl_enc[ch], "type", "") == "quantitative"
                    is_quant = true
                    has_agg = _has_aggregate(sl_enc, ch)
                    break
                end
            end
        end
        is_quant && !has_agg && push!(zoom_encodings, ch)
    end
    if !isempty(zoom_encodings)
        grid_param = Dict{String,Any}(
            "name" => "grid",
            "select" => Dict{String,Any}("type" => "interval", "encodings" => zoom_encodings),
            "bind" => "scales",
        )
        if !isnothing(sublayers) && !isempty(sublayers)
            # For layered specs, put bind:scales on the first sublayer to avoid
            # VL duplicate signal error (grid_tuple created per view in layer array)
            sl_params = get!(sublayers[1], "params", Dict{String,Any}[])
            push!(sl_params, grid_param)
        else
            push!(params, grid_param)
        end
    end

    if !isnothing(color_field)
        # Legend click selection: toggle group visibility + hover highlight
        push!(params, Dict{String,Any}(
            "name" => "legend_selection",
            "select" => Dict{String,Any}("type" => "point", "fields" => [color_field]),
            "bind" => "legend",
        ))

        opacity_condition = Dict{String,Any}(
            "condition" => Dict{String,Any}("param" => "legend_selection", "empty" => true, "value" => 1),
            "value" => 0.15,
        )

        if !isnothing(sublayers)
            for sl in sublayers
                sl_enc = get(sl, "encoding", nothing)
                # Skip layers that already have opacity in encoding or mark
                sl_mark = _as_dict(get(sl, "mark", nothing))
                mark_has_opacity = !isnothing(sl_mark) && haskey(sl_mark, "opacity")
                if !isnothing(sl_enc) && !haskey(sl_enc, "opacity") && !mark_has_opacity
                    sl_enc["opacity"] = opacity_condition
                end
            end
        elseif !isnothing(enc) && !haskey(enc, "opacity")
            # Don't clobber an explicit mark.opacity (e.g. visual(Lines; opacity=0.15))
            # with the legend-binding opacity condition — mirrors the sublayer branch above,
            # which already skips marks carrying an intentional `opacity`. VL's encoding-level
            # opacity overrides mark-level, so injecting the condition here would silently drop
            # the user's explicit opacity (its empty-state value is 1 → full opacity).
            top_mark = _as_dict(mark)
            mark_has_opacity = !isnothing(top_mark) && haskey(top_mark, "opacity")
            if !mark_has_opacity
                enc["opacity"] = opacity_condition
            end
        end
    end

    # Nearest-point tooltip for point marks only.
    # VL doesn't support "nearest" for line or area marks.
    if mark_type == "point" && !isnothing(enc) && haskey(enc, "tooltip")
        push!(params, Dict{String,Any}(
            "name" => "hover_nearest",
            "select" => Dict{String,Any}("type" => "point", "on" => "pointerover", "nearest" => true),
        ))
    end

    if !isempty(params)
        spec["params"] = params
    end

    spec
end

# Also accept raw Dicts (passthrough)
to_vegalite(d::Dict) = d
