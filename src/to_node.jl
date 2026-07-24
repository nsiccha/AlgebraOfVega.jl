"""
    _layer_array(vl::Dict)

Return the mutable layer array of a (possibly faceted) Vega-Lite spec, or `nothing`
if the spec is single-view. Faceted specs nest layers under `spec.spec.layer`; flat
specs use `spec.layer`.
"""
function _layer_array(vl::Dict)
    inner = _as_dict(get(vl, "spec", nothing))
    if !isnothing(inner) && haskey(inner, "layer")
        return inner["layer"]
    elseif haskey(vl, "layer")
        return vl["layer"]
    end
    return nothing
end

"""
    _facet_fields(vl::Dict)

Return the list of partition field names declared on a Vega-Lite spec via
`facet.row/column`, top-level `encoding.row/column`, or sublayer `encoding.row/column`.
"""
# Push the `field` key from a Dict-shaped channel encoding, if present.
_push_field!(args...) = nothing
function _push_field!(fields, ch_enc::Dict)
    haskey(ch_enc, "field") && push!(fields, ch_enc["field"])
end

function _push_channel_fields!(fields, container, channels)
    d = _as_dict(container)
    isnothing(d) && return
    for ch in channels
        _push_field!(fields, _as_dict(get(d, ch, nothing)))
    end
end

function _facet_fields(vl::Dict)
    fields = String[]
    _push_channel_fields!(fields, get(vl, "facet", nothing), ("row", "column"))
    _push_channel_fields!(fields, get(vl, "encoding", nothing), ("row", "column"))
    layers = _layer_array(vl)
    if layers !== nothing
        for l in layers
            _push_channel_fields!(fields, get(l, "encoding", nothing), ("row", "column", "color"))
        end
    end
    unique(fields)
end

"""
    _broadcast_cross_source_layers!(vl::Dict)

ggplot-style "broadcast across all facet panels". AoV merges layered data into a
single `spec.data.values` with a `__src` discriminator column when outer faceting
is needed (see `layers_to_vl`). When a facet field is absent from some rows
(typically annotation/overlay layers like dose VLines that have no health/vessel
columns), Vega-Lite renders them in an "undefined" facet panel.

This pass replicates each row that lacks the facet field across the unique values
of that field, so every cross-source row appears in every facet panel. Layer-level
`__src` filters still route rows to the correct mark, so replication is safe.

Idempotent: rows that already contain the field are untouched, so caller-side
replication keeps working unchanged.
"""
function _broadcast_cross_source_layers!(vl::Dict)
    fields = _facet_fields(vl)
    isempty(fields) && return vl

    # Find the data object whose `values` carry the merged rows. May be at the
    # outer spec or, for faceted layouts, at `spec.spec.data`.
    data_obj = _data_with_values(_as_dict(get(vl, "data", nothing)))
    if isnothing(data_obj)
        inner = _as_dict(get(vl, "spec", nothing))
        isnothing(inner) || (data_obj = _data_with_values(_as_dict(get(inner, "data", nothing))))
    end
    isnothing(data_obj) && return vl
    vals = _as_vec(data_obj["values"])
    isnothing(vals) && return vl

    for field in fields
        # Collect unique values from rows that already have this field
        uniques = Any[]
        seen = Set{Any}()
        for v in vals
            _collect_field_value!(uniques, seen, v, field)
        end
        isempty(uniques) && continue

        new_vals = Vector{Any}()
        for v in vals
            _replicate_or_keep!(new_vals, v, field, uniques)
        end
        vals = new_vals
    end
    data_obj["values"] = vals
    vl
end

_data_with_values(d::Dict) = haskey(d, "values") ? d : nothing
_data_with_values(_) = nothing

_as_vec(v::AbstractVector) = v
_as_vec(_) = nothing

_norm_string_list(v::AbstractVector) = string.(v)
_norm_string_list(::Nothing) = String[]
_norm_string_list(s::AbstractString) = isempty(s) ? String[] : [string(s)]
_norm_string_list(v) = [string(v)]

_to_string_vec(v::AbstractVector) = string.(v)
_to_string_vec(v) = [string(v)]

_dim_pair(d::Pair) = string(first(d)) => string(last(d))
_dim_pair(d) = string(d) => string(d)

_dim_first(d::Pair) = string(first(d))
_dim_first(d) = string(d)

_collect_field_value!(args...) = nothing
function _collect_field_value!(uniques, seen, v::Dict, field)
    haskey(v, field) || return
    u = v[field]
    if !(u in seen)
        push!(seen, u)
        push!(uniques, u)
    end
end

# When `v` lacks the facet field, replicate it across `uniques`. Otherwise keep as-is.
_replicate_or_keep!(new_vals, v, args...) = (push!(new_vals, v); nothing)
function _replicate_or_keep!(new_vals, v::Dict, field, uniques)
    if haskey(v, field)
        push!(new_vals, v)
    else
        for u in uniques
            nv = copy(v)
            nv[field] = u
            push!(new_vals, nv)
        end
    end
end

_as_vl_dict(d::Dict) = copy(d)
_as_vl_dict(s) = to_vegalite(s)

_as_number(n::Number) = n
_as_number(_) = nothing

# Look up a key in a per-signal entry. NamedTuple uses Symbol keys, Dict uses String.
_sig_get(sig::NamedTuple, key::Symbol) = getproperty(sig, key)
_sig_get(sig, key::Symbol) = sig[string(key)]
_sig_get(sig::NamedTuple, key::Symbol, default) = get(sig, key, default)
_sig_get(sig, key::Symbol, default) = get(sig, string(key), default)

"""
    to_node(spec; id, width, height, actions, signals)

Convert a spec to an HTMX `Node` containing a div + script that calls `vegaEmbed`.
Requires vega/vega-lite/vega-embed scripts to be loaded (use `vega_head()` in page head).

## Keyword arguments
- `id`: element ID (auto-generated if not provided)
- `width`, `height`: override spec dimensions
- `actions`: show Vega action links (default false)
- `signals`: vector of signal→HTMX wirings. Each entry is a NamedTuple or Dict:
  `(signal="brush", url="/on_brush", target="#detail")` or with optional `swap`, `debounce`.
- `fit_width`: when `true` (default) set `width: "container"` for single-view specs and
  apply numeric responsive widths for layered/faceted specs.
"""
function to_node(spec; id=nothing, width=nothing, height=nothing, actions=false, signals=nothing, fit_width=true)
    vl = _as_vl_dict(spec)
    !isnothing(width) && (vl["width"] = width)
    !isnothing(height) && (vl["height"] = height)
    # Only apply fit_width defaults if no explicit width was set (via config or kwarg)
    has_explicit_width = !isnothing(_as_number(get(vl, "width", nothing)))
    inner_spec = _as_dict(get(vl, "spec", nothing))
    has_explicit_inner_width = !isnothing(inner_spec) && haskey(inner_spec, "width")
    if fit_width && !has_explicit_width && !has_explicit_inner_width && !haskey(vl, "hconcat") && !haskey(vl, "vconcat")
        # Detect faceting: explicit facet key, nested spec, or row/column encoding channels
        is_faceted = haskey(vl, "facet") || haskey(vl, "spec") || _has_encoding_facet(vl)
        is_layered = haskey(vl, "layer") || is_faceted || haskey(vl, "concat")
        # VL composite marks (boxplot, errorbar, errorband) internally create layers —
        # "width: container" and "autosize: fit" don't work for them
        is_composite = _is_composite_mark(vl)
        if !is_layered && !is_composite
            # "width": "container" only works for true single-view specs
            vl["width"] = "container"
            vl["autosize"] = Dict("type" => "fit", "contains" => "padding")
        elseif is_faceted && haskey(vl, "spec")
            # Inject _aov hint for responsive JS resizing
            n_facet_cols = _count_facet_cols(vl)
            vl["_aov"] = Dict{String,Any}("nFacetCols" => n_facet_cols)
            inner = vl["spec"]
            if !haskey(inner, "width")
                inner["width"] = 400  # fallback, JS overrides
            end
        else
            # Layered/composite: mark for responsive JS resizing
            vl["_aov"] = Dict{String,Any}()
            if !haskey(vl, "width")
                vl["width"] = 400  # fallback, JS overrides
            end
        end
    end
    _broadcast_cross_source_layers!(vl)
    json = JSON.json(vl)
    id = _sanitize_id(something(id, "vega-" * string(abs(hash(json)), base=16)))

    # Queue embed for deferred execution (after layout is computed)
    embed_opts = "{actions: $actions}"
    signal_js = ""
    if !isnothing(signals)
        for sig in signals
            sname = _sig_get(sig, :signal)
            surl = _sig_get(sig, :url)
            starget = _sig_get(sig, :target, "body")
            sswap = _sig_get(sig, :swap, "innerHTML")
            sdebounce = _sig_get(sig, :debounce, 300)
            signal_js *= "AoV.signalToHtmx('$id', '$sname', '$surl', '$starget', '$sswap', $sdebounce);\n"
        end
    end

    h.div(; class="aov-plot-area")(
        h.div(; id=id, class="u-w-full"),
        h.script(Raw("AoV.embed('$id', $json, $embed_opts).then(function(){$signal_js});")),
    )
end

"""
    update_data(id, table; name="source_0")

Return an `h.script` node that updates an existing Vega view's dataset.
Useful for HTMX responses that should update a plot without re-rendering.
"""
function update_data(id, table; name="source_0")
    id = _sanitize_id(id)
    rows = Tables.rowtable(table)
    data = [Dict{String,Any}(string(k) => v for (k, v) in pairs(nt)) for nt in rows]
    json = JSON.json(data)
    h.script(Raw("AoV.updateData('$id', $json, '$name');"))
end

_CHANNEL_LABELS = Dict("color" => "Color", "row" => "Row", "column" => "Column", "detail" => "Ungrouped", "off" => "Pooled")

"""
    resolve_channels(dimensions; color_default, row_default, column_default, detail_default, pinned, fixed, channels)

Compute which dimension field maps to which visual channel, returning kwargs
ready to splice into `mapping()` and `lineribbon()`. This is the single source
of truth for channel resolution — both `mapping_controls` and server-side spec
construction should use this.

Returns a NamedTuple with:
- `color_kw`: NamedTuple to splat into `mapping(; color_kw...)`
- `row_kw`: NamedTuple to splat into `mapping(; row_kw...)`
- `column_kw`: NamedTuple to splat into `mapping(; column_kw...)`  (from non-fixed column defaults)
- `fixed_kw`: NamedTuple to splat into `mapping(; fixed_kw...)` (from fixed channels)
- `detail`: `Vector{Symbol}` for `lineribbon(; detail)`
- `color_fields`, `row_fields`, `column_fields`, `detail_fields`: raw field name vectors
- `dim_label_map`: `Dict{String,String}` field → human label
- `dims`: filtered dimension pairs
- `defaults`: `Dict{String,Vector{String}}` channel → field names (including pinned auto-fill)
"""
function resolve_channels(dimensions;
    color_default=String[], row_default=String[], column_default=String[], detail_default=String[],
    off_default=String[],
    x_default=String[], y_default=String[],
    channels=[:color, :row, :column, :detail],
    pinned::Symbol=:color,
    fixed=Dict{Symbol,Any}(),
    extra_assigned::AbstractVector=String[])

    color_default = _norm_string_list(color_default)
    row_default = _norm_string_list(row_default)
    column_default = _norm_string_list(column_default)
    detail_default = _norm_string_list(detail_default)
    # `off` (label "Pooled") is a picker channel that maps to NO encoding: its
    # dims are removed from the mark so their values pool. Tracked in `defaults`
    # so the generic pinned-absorb loop excludes off-dims from the catch-all.
    off_default = _norm_string_list(off_default)
    x_default = _norm_string_list(x_default)
    y_default = _norm_string_list(y_default)
    # x/y are single-select; keep only the first field if multiple are passed.
    length(x_default) > 1 && (x_default = x_default[1:1])
    length(y_default) > 1 && (y_default = y_default[1:1])
    defaults = Dict("color" => color_default, "row" => row_default,
                     "column" => column_default, "detail" => detail_default,
                     "off" => off_default,
                     "x" => x_default, "y" => y_default)
    extra_assigned_norm = String[string(f) for f in extra_assigned]

    dims = [_dim_pair(d) for d in dimensions]

    # Normalize fixed
    fixed_norm = Dict{String,Vector{String}}()
    for (k, v) in fixed
        fixed_norm[string(k)] = _to_string_vec(v)
    end

    # Auto-add fixed fields to dims if not already present
    dim_fields = Set(first.(dims))
    for fs in values(fixed_norm)
        for f in fs
            if !(f in dim_fields)
                push!(dims, f => join(uppercasefirst.(split(f, "_")), " "))
                push!(dim_fields, f)
            end
        end
    end

    # Editable channels (not fixed)
    editable = [ch for ch in channels if !haskey(fixed_norm, string(ch))]

    # Label lookup
    dim_label_map = Dict(first(d) => last(d) for d in dims)
    _pretty(f) = get(dim_label_map, f, join(uppercasefirst.(split(f, "_")), " "))

    # Pinned channel absorbs all unassigned dims
    pinned_str = string(pinned)
    assigned_elsewhere = Set{String}()
    for ch in editable
        ch_str = string(ch)
        ch_str == pinned_str && continue
        for f in get(defaults, ch_str, String[])
            push!(assigned_elsewhere, f)
        end
    end
    for fs in values(fixed_norm)
        for f in fs; push!(assigned_elsewhere, f); end
    end
    # Positional (x/y) and any other fields the caller flags as "already used"
    # elsewhere in the plot. Even when :x/:y are not picker channels, their
    # positional fields should not get absorbed into the pinned catch-all.
    for f in extra_assigned_norm
        push!(assigned_elsewhere, f)
    end
    defaults[pinned_str] = [first(d) for d in dims if !(first(d) in assigned_elsewhere)]

    # Build kwargs for a channel's field list.
    # AoG mapping() uses :col (not :column) for column faceting.
    # x/y are positional in AoG — they aren't re-composed here; the JS
    # remapEncoding path rewrites encoding.x.field / encoding.y.field on
    # the VL spec directly when the user swaps them via the picker.
    _aog_key(ch) = ch == :column ? :col : ch
    function _channel_kw(ch_sym, fields)
        isempty(fields) && return (;)
        ch_sym in (:x, :y) && return (;)
        k = _aog_key(ch_sym)
        if length(fields) == 1
            return (; k => Symbol(fields[1]) => _pretty(fields[1]))
        end
        combo = Symbol("__aov_$(ch_sym)")
        combo_label = join([_pretty(f) for f in fields], " / ")
        return (; k => combo => combo_label)
    end

    color_fields = get(defaults, "color", String[])
    row_fields = get(defaults, "row", String[])
    column_fields = get(defaults, "column", String[])
    detail_fields = get(defaults, "detail", String[])
    off_fields = get(defaults, "off", String[])
    x_fields = get(defaults, "x", String[])
    y_fields = get(defaults, "y", String[])

    color_kw = _channel_kw(:color, color_fields)
    row_kw = _channel_kw(:row, row_fields)
    column_kw = _channel_kw(:column, column_fields)
    detail = Symbol.(detail_fields)

    # When a channel uses a combo (2+ fields), the individual fields must also
    # appear in detail so they survive the AoG summary into the VL spec data.
    # (The combo column carries the visual encoding; detail preserves the components.)
    for fields in (color_fields, row_fields, column_fields)
        length(fields) > 1 && for f in fields
            s = Symbol(f)
            s in detail || push!(detail, s)
        end
    end

    # Fixed channels → kwargs
    fixed_kw_parts = NamedTuple[]
    for (ch_str, fs) in fixed_norm
        ch_sym = Symbol(ch_str)
        ch_sym in (:color, :row, :column) || continue  # detail handled differently
        kw = _channel_kw(ch_sym, fs)
        push!(fixed_kw_parts, kw)
    end
    # Also add fixed detail fields
    if haskey(fixed_norm, "detail")
        append!(detail, Symbol.(fixed_norm["detail"]))
    end
    fixed_kw = isempty(fixed_kw_parts) ? (;) : merge(fixed_kw_parts...)

    (; color_kw, row_kw, column_kw, fixed_kw, detail,
       color_fields, row_fields, column_fields, detail_fields, off_fields,
       x_fields, y_fields,
       dim_label_map, dims, defaults, fixed=fixed_norm, pinned, channels,
       extra_assigned=extra_assigned_norm)
end

"""
    apply_combo!(df, fields, combo_col=:__aov_combo)

Build a synthetic combo column on `df` by joining values of `fields` with " / ".
No-op if `length(fields) <= 1`. **Silently skips entirely if any field is
missing from `df`** — leaving the combo column unset on this layer so the
downstream cross-source broadcast pass can replicate the layer across every
unique combo value (this is how secondary layers like dose VLines or
observation scatters fan out across model facets). Returns `df`.
"""
function apply_combo!(df, fields, combo_col=:__aov_combo)
    length(fields) <= 1 && return df
    syms = Symbol.(fields)
    all(s -> hasproperty(df, s), syms) || return df
    df[!, combo_col] = [join([string(r[s]) for s in syms], " / ") for r in eachrow(df)]
    df
end

"""
    apply_combos!(df, resolved)

Build all synthetic combo columns (`__aov_color`, `__aov_row`, `__aov_column`)
on `df` for the channels in `resolved`. Per-layer: each channel's combo column
is built only if `df` has every component field; otherwise it's silently
skipped so the broadcast pass replicates the layer.

Returns `df`. **Does not refine `resolved`** — for global stripping of
absent / single-valued dims (which fixes static-render labels and the picker
catch-all), call `refine_channels(resolved, dfs...)` before building the
spec instead.
"""
function apply_combos!(df, resolved)
    apply_combo!(df, resolved.color_fields, :__aov_color)
    apply_combo!(df, resolved.row_fields, :__aov_row)
    apply_combo!(df, resolved.column_fields, :__aov_column)
    df
end

"""
    refine_channels(resolved, tables...)

Return a new `resolved` with dimensions stripped if they are absent from
**every** `table` or have ≤1 unique value in every table that has them.
Same treatment for fixed-channel assignments. Use this once before building
your spec so that:

- the static server-side render's auto-generated row/col/color labels only
  reference dims that actually vary,
- the pinned catch-all channel doesn't auto-absorb meaningless dims,
- `mapping_controls`' picker reflects the same set.

Per-layer combo construction is still done by `apply_combos!` against the
returned (refined) `resolved`. Layers that don't have every component of a
combo column will have it left unset, and the broadcast pass will replicate
them across the surviving facet panels.
"""
function refine_channels(resolved::NamedTuple, tables...)
    isempty(tables) && return resolved
    # A field is "useful" iff some table has it with >1 unique value.
    cols_per = [Set(Symbol.(Tables.columnnames(t))) for t in tables]
    _useful = function(field)
        sym = Symbol(field)
        for (i, t) in enumerate(tables)
            sym in cols_per[i] || continue
            length(unique(Tables.getcolumn(t, sym))) > 1 && return true
        end
        false
    end
    useful_dims = filter(d -> _useful(first(d)), resolved.dims)
    useful_fixed = Dict{String,Vector{String}}()
    for (ch, fs) in resolved.fixed
        kept = filter(_useful, fs)
        isempty(kept) || (useful_fixed[ch] = kept)
    end
    unchanged = length(useful_dims) == length(resolved.dims) &&
                length(useful_fixed) == length(resolved.fixed) &&
                all(length(useful_fixed[k]) == length(resolved.fixed[k]) for k in keys(resolved.fixed))
    unchanged && return resolved
    resolve_channels(useful_dims;
        color_default=get(resolved.defaults, "color", String[]),
        row_default=get(resolved.defaults, "row", String[]),
        column_default=get(resolved.defaults, "column", String[]),
        detail_default=resolved.detail_fields,
        off_default=get(resolved.defaults, "off", String[]),
        x_default=get(resolved.defaults, "x", String[]),
        y_default=get(resolved.defaults, "y", String[]),
        channels=resolved.channels,
        pinned=resolved.pinned,
        fixed=useful_fixed,
        extra_assigned=get(resolved, :extra_assigned, String[]))
end

"""
    _source_tables_from_spec(spec)

Return a `Vector` of all layer source tables in `spec`. Walks `VegaSpec` →
AoG drawable → layers and collects each layer's unwrapped `.data`. Skips
`nothing` and `Pregrouped` layers. Multi-layer specs (e.g. `dose_layer + spec`)
all contribute — uniqueness of a dim is taken across any layer that has it.
"""
_spec_drawable(s::VegaSpec) = s.drawable
_spec_drawable(s) = s

_wrap_with_config(spec::VegaSpec, drawable) = VegaSpec(drawable, spec.config)
_wrap_with_config(_, drawable) = drawable

_layer_iter(d::AlgebraOfGraphics.Layers) = d.layers
_layer_iter(d::AlgebraOfGraphics.Layer) = (d,)
_layer_iter(_) = ()

_drop_pregrouped(::AlgebraOfGraphics.Pregrouped) = nothing
_drop_pregrouped(t) = t

_source_tables_from_spec(::Nothing) = Any[]
_source_tables_from_spec(::Dict) = Any[]
function _source_tables_from_spec(spec)
    out = Any[]
    for layer in _layer_iter(_spec_drawable(spec))
        t = _drop_pregrouped(extract_data(layer))
        isnothing(t) || push!(out, t)
    end
    out
end
