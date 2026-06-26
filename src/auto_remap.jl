"""
    mapping_controls(id, dimensions; kwargs...)
    mapping_controls(id, resolved::NamedTuple; table=nothing, spec=nothing)

Client-side multi-select picker that remaps Vega-Lite encoding channels on an
already-rendered plot. Each channel (color, row, column, ungrouped/detail) is a
multi-select; selecting 2+ fields for one channel synthesises a combo column on
`spec.data.values`. One channel is always "pinned" — the catch-all that
auto-absorbs any dims not in another channel.

The first form (vector of dimensions) calls [`resolve_channels`](@ref) under
the hood; the second form accepts a pre-resolved NamedTuple (e.g. from
[`refine_channels`](@ref)) for callers that need to inspect / mutate the
resolution before rendering.

## Keyword arguments

- `id`: must match the `id` kwarg passed to `to_node(spec; id=...)`
- `dimensions`: vector of `Pair{String,String}` (field => label) or bare strings/symbols
- `color_default`, `row_default`, `column_default`, `detail_default`: initial selections
  (vector or single string)
- `channels`: which channels to show (default `[:color, :row, :column, :detail]`)
- `pinned`: which channel is the catch-all (default `:color`)
- `fixed`: `Dict` of channel => field(s) that are always applied but not user-editable,
  e.g. `Dict(:column => :cylinders)`
- `table`: optional table for field validation
- `spec`: optional AoG spec — if provided, validates that all dimension fields survive
  into the VL data (warns if a field was dropped during AoG summary)

## Example

```julia
id = "my-plot"
h.div()(
    mapping_controls(id, ["origin" => "Origin", "cylinders" => "Cylinders"];
        color_default="origin", fixed=Dict(:column => :cylinders)),
    to_node(data(df) * mapping(:x, :y, color=:origin, col=:cylinders) * visual(Scatter); id=id),
)
```

For fully-automatic picker + plot construction, prefer [`auto_remap_node`](@ref).
"""
function mapping_controls(id, dimensions::AbstractVector; table=nothing, spec=nothing, kwargs...)
    resolved = resolve_channels(dimensions; kwargs...)
    mapping_controls(id, resolved; table, spec)
end

# === auto_remap_node ===========================================================
# `auto_remap_node(plot_id, spec; dims, fixed, pinned)` is the "fully
# automatic" remap entry point. The user builds a regular AoG spec —
# including their normal `mapping(:x, :y; color=…, row=…, col=…)` channel
# encodings and any `* config(…)` — and auto_remap_node handles channel
# resolution, refinement against the spec's actual data, cartesian-product
# broadcast across missing facet dims, combo-column construction, layer
# rewriting, and picker assembly.

# --- helpers ---

# Walk a spec down to the list of AoG Layers it contains.
_spec_layers_or_nothing(d::AlgebraOfGraphics.Layers) = collect(d.layers)
_spec_layers_or_nothing(d::AlgebraOfGraphics.Layer) = [d]
_spec_layers_or_nothing(_) = nothing

function _spec_layers(spec)
    drawable = _spec_drawable(spec)
    layers = _spec_layers_or_nothing(drawable)
    isnothing(layers) && error("auto_remap_node: unsupported spec drawable type $(typeof(drawable))")
    layers
end

function _auto_summary_args(spec)
    layers = _spec_layers_or_nothing(_spec_drawable(spec))
    isnothing(layers) && return nothing
    for layer in layers
        for T in (PointIntervalAnalysis, GradientIntervalAnalysis, DotIntervalAnalysis)
            a = extract_transformation(layer, T)
            isnothing(a) && continue
            table = extract_data(layer)
            isnothing(table) && return nothing
            if a.orientation === :vertical
                length(layer.positional) >= 2 || return nothing
                outcome = Symbol(_field_name(layer.positional[1]))
                value = Symbol(_field_name(layer.positional[2]))
                group_cols = Symbol[]
                for (k, v) in pairs(layer.named)
                    push!(group_cols, Symbol(_field_name(v)))
                end
            else
                (isempty(layer.positional) || !haskey(layer.named, :y)) && return nothing
                value = Symbol(_field_name(layer.positional[1]))
                outcome = Symbol(_field_name(layer.named[:y]))
                group_cols = Symbol[]
                for (k, v) in pairs(layer.named)
                    k == :y && continue
                    push!(group_cols, Symbol(_field_name(v)))
                end
            end
            return (; kind=:pointinterval, table, value, outcome, group_cols)
        end
        a = extract_transformation(layer, LineRibbonAnalysis)
        if !isnothing(a)
            table = extract_data(layer)
            (isnothing(table) || length(layer.positional) < 2) && return nothing
            x = Symbol(_field_name(layer.positional[1]))
            value = Symbol(_field_name(layer.positional[2]))
            group_cols = Symbol[x]
            for (k, v) in pairs(layer.named)
                k === :group && continue
                push!(group_cols, Symbol(_field_name(v)))
            end
            return (; kind=:lineribbon, table, value, group_cols)
        end
        a = extract_transformation(layer, PrecomputedRibbonAnalysis)
        if !isnothing(a)
            length(layer.positional) < 2 && return nothing
            value = Symbol(_field_name(layer.positional[2]))
            point_col = string(value)
            # bands as [(lo, hi, label)]: outermost first per AoV convention
            bands = Tuple{String,String,String}[
                (string(lo), string(hi), "$(string(lo))/$(string(hi))")
                for (lo, hi) in a.bands
            ]
            return (; kind=:precomputed_ribbon, value, point_col, bands)
        end
        a = extract_transformation(layer, PrecomputedIntervalAnalysis)
        if !isnothing(a)
            point_idx = a.orientation === :vertical ? 2 : 1
            length(layer.positional) >= point_idx || return nothing
            value = Symbol(_field_name(layer.positional[point_idx]))
            point_col = string(value)
            bands = Tuple{String,String,String}[
                (string(lo), string(hi), "$(string(lo))/$(string(hi))")
                for (lo, hi) in a.bands
            ]
            return (; kind=:precomputed_ribbon, value, point_col, bands)
        end
    end
    return nothing
end

# Read default channel assignments from layers' existing `.named` mappings.
# Returns a Dict("color"=>[...], "row"=>[...], "column"=>[...]).
function _layer_channel_defaults(layers)
    defaults = Dict("color"=>String[], "row"=>String[], "column"=>String[])
    for layer in layers
        for (k, v) in pairs(layer.named)
            ch = k === :col ? "column" : string(k)
            haskey(defaults, ch) || continue
            f = _field_name(v)
            f in defaults[ch] || push!(defaults[ch], f)
        end
    end
    defaults
end

# Union of positional field names across all layers. Used by the pinned
# catch-all in `resolve_channels` so positionally-assigned dims aren't
# absorbed by the combo even when :x/:y aren't picker-exposed channels.
function _layer_positional_fields(layers)
    out = String[]
    for layer in layers
        for v in layer.positional
            f = _field_name(v)
            (isnothing(f) || isempty(f)) && continue
            f in out || push!(out, f)
        end
    end
    out
end

# Per-axis defaults derived from positional mappings: positional[1] → x,
# positional[2] → y. Returns (x=String[], y=String[]) — each at most one
# field (single-select), unioned across layers.
function _layer_axis_defaults(layers)
    xs = String[]; ys = String[]
    for layer in layers
        if length(layer.positional) >= 1
            f = _field_name(layer.positional[1])
            !isnothing(f) && !isempty(f) && !(f in xs) && push!(xs, f)
        end
        if length(layer.positional) >= 2
            f = _field_name(layer.positional[2])
            !isnothing(f) && !isempty(f) && !(f in ys) && push!(ys, f)
        end
    end
    (; x=xs, y=ys)
end

# True if any layer carries a TidybayesAnalysis — for those, x/y picker
# channels are disabled because at least one axis is bound to computed
# summary columns (lo_*/hi_*/__point__/__median__). Per-axis refuse-tagging
# is a planned follow-up (see TODO in Claude/algebraofvega.md).
function _has_axis_blocker(layers)
    for layer in layers
        !isnothing(extract_transformation(layer, TidybayesAnalysis)) && return true
    end
    false
end

# Append a new column to a column-table (NamedTuple of vectors).
_with_added_column(cols::NamedTuple, name::Symbol, vals) =
    merge(cols, NamedTuple{(name,)}((vals,)))

# Build the synthetic combo columns on a NamedTuple column-table per
# `resolved`. Non-mutating: returns a new NamedTuple with the combo columns
# appended where buildable. A combo column is built only if every component
# field is present (mirror of `apply_combo!`'s silent-skip semantics).
function _with_combos(cols::NamedTuple, resolved)
    cur = cols
    for (fields, combo_col) in ((resolved.color_fields,  :__aov_color),
                                 (resolved.row_fields,    :__aov_row),
                                 (resolved.column_fields, :__aov_column))
        length(fields) <= 1 && continue
        syms = Symbol.(fields)
        all(s -> haskey(cur, s), syms) || continue
        # Vectorized fold: `string.(acc, " / ", col)` per extra field.
        combo_vals = string.(cur[syms[1]])
        for s in @view syms[2:end]
            combo_vals = string.(combo_vals, " / ", cur[s])
        end
        cur = _with_added_column(cur, combo_col, combo_vals)
    end
    cur
end

# Precompute the union of unique values per field across all layers'
# column-tables. Walks each (layer, field) pair exactly once, instead of
# once per consuming layer — critical when one layer has millions of rows.
function _global_field_uniques(all_cols::Vector, fields)
    out = Dict{Symbol,Vector{Any}}()
    for field in fields
        sym = Symbol(field)
        per_layer = Vector{Any}[]
        for cols in all_cols
            haskey(cols, sym) || continue
            u = unique(cols[sym])
            isempty(u) || push!(per_layer, collect(Any, u))
        end
        isempty(per_layer) && continue
        merged = length(per_layer) == 1 ? per_layer[1] : unique(reduce(vcat, per_layer))
        out[sym] = merged
    end
    out
end

# Broadcast `cols` across every field in `fields` that's absent from it.
# Performs ONE cartesian-product expansion against the joint product of
# all missing fields. Unique-value lookup is done via a precomputed
# `field_uniques` dict so we don't re-walk other layers per call.
function _broadcast_missing_fields(cols::NamedTuple, fields, field_uniques::Dict{Symbol,Vector{Any}})
    # Gather missing fields and their unique values (skip empties).
    missing_syms = Symbol[]
    missing_vals = Vector{Vector{Any}}()
    for field in fields
        sym = Symbol(field)
        haskey(cols, sym) && continue
        haskey(field_uniques, sym) || continue
        push!(missing_syms, sym)
        push!(missing_vals, field_uniques[sym])
    end
    isempty(missing_syms) && return cols

    nrows = length(first(cols))
    sizes = length.(missing_vals)
    total_combos = prod(sizes)

    # Each original row is replicated `total_combos` times in a contiguous
    # block; one allocation per existing column.
    inflated = map(c -> repeat(c, inner=total_combos), cols)

    # Build each new field column so that within every block of size
    # `total_combos`, every cartesian combination appears exactly once.
    # `inner_sz` tracks how many positions a single value of the current
    # field spans before cycling.
    added = NamedTuple()
    inner_sz = 1
    for (sym, vals) in zip(missing_syms, missing_vals)
        n_vals = length(vals)
        outer_sz = total_combos ÷ (inner_sz * n_vals)
        cycle = repeat(repeat(vals, inner=inner_sz), outer=outer_sz)
        col = repeat(cycle, outer=nrows)
        added = merge(added, NamedTuple{(sym,)}((col,)))
        inner_sz *= n_vals
    end

    merge(inflated, added)
end

# Patch the `detail_fields` of any TidybayesAnalysis in a transformation
# chain to `new_detail`. Walks through `ComposedFunction` recursively.
_with_detail(t::PointIntervalAnalysis, d) = PointIntervalAnalysis(t.probs, t.point, d, t.orientation)
_with_detail(t::GradientIntervalAnalysis, d) = GradientIntervalAnalysis(t.probs, t.point, d, t.orientation)
_with_detail(t::LineRibbonAnalysis, d) = LineRibbonAnalysis(t.probs, t.show_line, d)
_with_detail(t::PrecomputedRibbonAnalysis, d) = PrecomputedRibbonAnalysis(t.bands, t.show_line, d)
_with_detail(t::PrecomputedIntervalAnalysis, d) = PrecomputedIntervalAnalysis(t.bands, d, t.orientation)
_with_detail(t::DotIntervalAnalysis, d) = DotIntervalAnalysis(t.probs, t.n_dots, t.point, d, t.orientation)

_patch_detail(t::TidybayesAnalysis, new_detail) = _with_detail(t, Symbol.(new_detail))
_patch_detail(t::ComposedFunction, new_detail) =
    _patch_detail(t.outer, new_detail) ∘ _patch_detail(t.inner, new_detail)
_patch_detail(t, _) = t

# Collect channel keys (e.g. :color, :row, :col) that are statically set on
# any Visual in a transformation chain. These should NOT be overwritten by
# data-driven encodings from the resolved channel kws — e.g. a scatter
# layer with `visual(Scatter; color="black")` keeps its black points
# regardless of the picker's color channel.
_visual_static_channels(t::AlgebraOfGraphics.Visual) = Set{Symbol}(keys(t.attributes))
_visual_static_channels(t::ComposedFunction) =
    union(_visual_static_channels(t.outer), _visual_static_channels(t.inner))
_visual_static_channels(_) = Set{Symbol}()

# Rebuild a layer with a new dataframe and resolved channel kws merged in.
# User-supplied entries on managed channels (color/row/col/column) are
# dropped first, then resolved kws are merged on top — except where the
# layer's Visual has already set the same channel statically. lineribbon
# detail is patched on the transformation.
#
# Layer-fixed color preservation: if the layer has `color=<field>` on a field
# outside `dim_fields` (the set of remappable dims), the layer's own color
# encoding is preserved verbatim and the resolved color kw is NOT applied to
# this layer. Returns `(new_layer, keep_color_field)` where `keep_color_field`
# is `nothing` unless the layer has a preserved, non-remappable color field.
function _rebuild_layer(layer, new_df, resolved, dim_fields::Set{String})
    # Detect layer-fixed color: `color=` on a field outside `dim_fields`.
    # Such layers keep their original color encoding and skip resolved.color_kw.
    keep_color_field = nothing
    if haskey(layer.named, :color)
        cf = _field_name(layer.named[:color])
        if !(cf in dim_fields)
            keep_color_field = cf
        end
    end
    # Build merged named NamedTuple
    base = NamedTuple()
    for (k, v) in pairs(layer.named)
        # Keep the original :color if it's layer-fixed (outside dim_fields).
        if k === :color && !isnothing(keep_color_field)
            base = merge(base, NamedTuple{(:color,)}((v,)))
            continue
        end
        k in (:color, :row, :col, :column) && continue
        base = merge(base, NamedTuple{(k,)}((v,)))
    end
    # If the visual statically sets a channel (typically :color), drop the
    # data-driven encoding for that channel from this layer's mapping.
    static = _visual_static_channels(layer.transformation)
    _drop = (nt, k) -> k in static ? Base.structdiff(nt, NamedTuple{(k,)}) : nt
    extra = merge(resolved.fixed_kw, resolved.row_kw, resolved.color_kw, resolved.column_kw)
    for k in (:color, :row, :col, :column)
        extra = _drop(extra, k)
    end
    # For layer-fixed-color layers, strip resolved.color_kw so it doesn't
    # override the preserved original color.
    if !isnothing(keep_color_field) && haskey(extra, :color)
        extra = Base.structdiff(extra, NamedTuple{(:color,)})
    end
    # Preserve AoG scale-type modifiers (e.g. `nonnumeric`) from the user's
    # original named mapping on the resolved channel kw. Without this, a
    # layer built from `mapping(color=:flag => nonnumeric)` loses the
    # modifier when auto_remap rewrites the color channel, and the rebuilt
    # spec falls back to eltype-inferred type (Int → quantitative),
    # diverging from the direct-render path.
    extra = _preserve_selector_modifiers(extra, layer.named, keep_color_field)
    new_named = merge(base, extra)
    # Patch detail on the transformation chain
    new_t = _patch_detail(layer.transformation, resolved.detail)
    # Compose a fresh layer using AoG operators (so .data, .positional, .named
    # are constructed in the AoG-native shapes), then swap in the patched
    # transformation.
    composed = AlgebraOfGraphics.data(new_df) *
        AlgebraOfGraphics.mapping(layer.positional...; new_named...)
    new_layer = AlgebraOfGraphics.Layer(new_t, composed.data, composed.positional, composed.named)
    (new_layer, keep_color_field)
end

# Extract the scale-type modifier Function (e.g. `nonnumeric`) from a
# selector like `:field => nonnumeric` or `:field => nonnumeric => "Label"`.
# Returns `nothing` if none is present.
_selector_scale_modifier(_) = nothing
function _selector_scale_modifier(sel::Pair)
    _selector_scale_modifier_dst(first(sel), last(sel))
end
_selector_scale_modifier_dst(src, dst::Function) = dst
# A sorter/renamer `Renamer` on a facet channel carries the facet-header order;
# it is not `<:Function`, so capture it explicitly here. The type-agnostic
# `_attach_modifier` path re-attaches it to the resolved selector, and
# `_apply_selector_modifier!(::Renamer)` re-translates it into VL `sort` after
# the auto-remap picker rebuilds the layer.
_selector_scale_modifier_dst(src, dst::AlgebraOfGraphics.Renamer) = dst
_selector_scale_modifier_dst(src, dst::Pair) = _selector_scale_modifier(Pair(src, first(dst)))
_selector_scale_modifier_dst(args...) = nothing

# Splice a scale-type modifier into a resolved channel kw value. Resolved
# values come out of `_channel_kw` as `Symbol`, `:field => "Label"`, or
# `:field => :combo => "Label"` (for combos — but we skip combos as the
# combo column is a fresh string and carries the modifier implicitly).
_attach_modifier(v, ::Nothing) = v
_attach_modifier(v::Symbol, modifier) = Pair(v, modifier)
_attach_modifier(v::Pair, modifier) = _attach_modifier_pair(first(v), last(v), modifier)
_attach_modifier(v, modifier) = v

_attach_modifier_pair(src, dst::AbstractString, modifier) = Pair(src, Pair(modifier, dst))
_attach_modifier_pair(src, dst, modifier) = Pair(src, dst)

# For each managed channel (:color, :row, :column, :col) in `extra`, look
# up the user's original selector in `orig_named`; if it carried a scale
# modifier (`nonnumeric` etc.), splice it onto the resolved value so the
# VL-level type-inference sees it and emits the right encoding type.
function _preserve_selector_modifiers(extra::NamedTuple, orig_named, keep_color_field)
    isempty(extra) && return extra
    keys_in = keys(extra)
    updates = NamedTuple()
    for ch in keys_in
        ch in (:color, :row, :column, :col) || continue
        # keep_color_field layers already re-use the original selector verbatim,
        # so modifier propagation there is a no-op (extra.color was stripped).
        ch === :color && !isnothing(keep_color_field) && continue
        # Look up the user's original selector for this channel.
        orig_key = ch === :column ? :col : ch
        haskey(orig_named, orig_key) || continue
        mod = _selector_scale_modifier(orig_named[orig_key])
        isnothing(mod) && continue
        new_v = _attach_modifier(extra[ch], mod)
        new_v === extra[ch] && continue
        updates = merge(updates, NamedTuple{(ch,)}((new_v,)))
    end
    isempty(updates) ? extra : merge(extra, updates)
end

"""
    auto_remap_node(plot_id, spec; dims, fixed=Dict(), pinned=:row, axes=false)

Fully automatic interactive plot. Takes a "normal" AoG spec and produces an
`h.div(picker, plot_node)`. The user does not call `resolve_channels`,
`refine_channels`, `apply_combos!`, `mapping_controls`, or `to_node`; this
function does all of it.

# How channel info is sourced

- **Defaults** are read from each layer's existing `.named` mapping. If a
  layer says `mapping(:x, :y; color=:source, row=:study)`, then `color_default
  = "source"` and `row_default = "study"` automatically.
- **`dims`** is the user-supplied list of remappable dimensions, as
  `Vector{Pair{String,String}}` (field => human label). Labels here are the
  single source of truth for picker labels and combo titles.
- **`fixed`** assigns fields to channels that the picker shouldn't expose as
  remappable. Same shape as in `resolve_channels`. Labels for fixed fields
  are picked up from `dims` if present, otherwise snake_case → Title Case.
- **`pinned`** is the catch-all channel.
- **`axes=true`** opts in to X/Y axis channels in the picker. The layer's
  positional fields (`mapping(x, y, …)`) are automatically added to the
  picker's dim set — they become X/Y defaults AND are selectable on the
  other channels. Off by default because X/Y are single-select (no combo
  semantics) and usually the positional fields are not meant to be
  re-routed. When any layer carries a `TidybayesAnalysis`, X/Y stay
  hidden regardless of `axes` — analyses bind axes to computed columns.

# What it does internally

1. Walks `spec` to enumerate layers and their dataframes.
2. Reads channel defaults from layers' existing mappings.
3. Calls `resolve_channels(dims; defaults..., fixed, pinned)`.
4. `refine_channels(resolved, dfs...)` — strips dims absent or single-valued
   across every layer.
5. For each layer's df: cartesian-product broadcasts the df across the
   union of unique values for every row/color/column field it doesn't have
   (so partial-overlap layers like observation scatters land in every
   relevant pred panel), then `apply_combos!` builds `__aov_row`/etc.
6. Rebuilds each layer with the new (broadcast) df and resolved channel
   kws merged into its mapping. lineribbon/pointinterval/etc. detail is
   patched on the transformation.
7. Reassembles layers via `+`, preserves the original `VegaSpec` config,
   and wraps with `mapping_controls` + `to_node` in an `h.div`.

# Example

```julia
spec = data(filtered_pred) * mapping(:dose_mg => "Dose (mg)", :qoi => "";
            group=:draw, color=:source, row=:study) * lineribbon() +
       data(obs_rows) * mapping(:dose_mg => "Dose (mg)", :qoi => "") *
            visual(Scatter; size=30, opacity=0.8)
spec *= config(height=300, facet=(; linkxaxes=:none, linkyaxes=:none))

auto_remap_node("dose-response-plot", spec;
    dims=["source"=>"Source", "study"=>"Study", "outcome"=>"Outcome", "method"=>"Method"],
    fixed=Dict(:column => "assay"),
    pinned=:row)
```
"""
function auto_remap_node(plot_id, spec; kwargs...)
    controls, plot = _auto_remap_parts(plot_id, spec; kwargs...)
    h.div()(controls, plot)
end

# Same idea as `_remap_node_parts`: expose the (controls, plot_node) pair for
# composition with `with_plot_caption` et al.
function _auto_remap_parts(plot_id, spec; dims, fixed=Dict(), pinned::Symbol=:row,
                            axes::Bool=false, off=String[],
                            color=nothing, row=nothing, column=nothing, detail=nothing)
    layers = _spec_layers(spec)
    raw_dfs = [extract_data(l) for l in layers]
    any(isnothing, raw_dfs) && error("auto_remap_node: every layer must have associated data (no Pregrouped layers supported here)")
    # Materialize each layer's data as a NamedTuple of vectors so the rest
    # of the pipeline can stay non-mutating and uniform across input types
    # (DataFrame / DataFrameColumns / NamedTuple / etc).
    dfs = NamedTuple[Tables.columntable(d) for d in raw_dfs]

    # Positional fields — always feed into `extra_assigned` so the pinned
    # catch-all doesn't absorb them. When `axes=true` they also become
    # picker channel defaults + extra options on all channels.
    pos_all = _layer_positional_fields(layers)
    axis_defs = _layer_axis_defaults(layers)
    enable_axes = axes && !_has_axis_blocker(layers)

    # Build the effective dims list. When axes=true, any positional field
    # not already in `dims` is auto-added so x/y can have defaults AND the
    # same fields are pickable on color/row/column.
    effective_dims = if enable_axes
        dims_vec = Any[d for d in dims]
        listed = Set{String}(_dim_first(d) for d in dims_vec)
        for f in pos_all
            f in listed && continue
            push!(dims_vec, f => join(uppercasefirst.(split(f, "_")), " "))
            push!(listed, f)
        end
        dims_vec
    else
        dims
    end
    dim_fields = Set{String}(_dim_first(d) for d in effective_dims)
    defaults = _layer_channel_defaults(layers)
    defaults = Dict(ch => filter(f -> f in dim_fields, fs) for (ch, fs) in defaults)
    for (ch, val) in [("color", color), ("row", row), ("column", column), ("detail", detail)]
        isnothing(val) && continue
        defaults[ch] = filter(f -> f in dim_fields, _norm_string_list(val))
    end
    extra_assigned = filter(f -> f in dim_fields, pos_all)
    x_default = enable_axes ? filter(f -> f in dim_fields, axis_defs.x) : String[]
    y_default = enable_axes ? filter(f -> f in dim_fields, axis_defs.y) : String[]
    # `off` (Pooled) dims start absent from the encoding (opt-in; only the dims
    # the caller passes — never an auto-default). Restricted to remappable dims.
    off_default = filter(f -> f in dim_fields, String[string(f) for f in off])
    channels = enable_axes ? [:x, :y, :color, :row, :column, :detail, :off] :
                             [:color, :row, :column, :detail, :off]
    resolved = resolve_channels(effective_dims;
        color_default=defaults["color"],
        row_default=defaults["row"],
        column_default=defaults["column"],
        x_default, y_default, off_default,
        channels, pinned, fixed,
        extra_assigned)
    resolved = refine_channels(resolved, dfs...)

    # Cartesian-product fill missing facet fields, then build combo columns.
    bcast_fields = unique(vcat(resolved.color_fields, resolved.row_fields, resolved.column_fields))
    field_uniques = _global_field_uniques(dfs, bcast_fields)
    bcasted = [_broadcast_missing_fields(df, bcast_fields, field_uniques) for df in dfs]
    new_dfs = [_with_combos(df, resolved) for df in bcasted]

    rebuilt = [_rebuild_layer(layer, new_df, resolved, dim_fields) for (layer, new_df) in zip(layers, new_dfs)]
    new_layers = [r[1] for r in rebuilt]
    keep_color_fields = Set{String}(r[2] for r in rebuilt if !isnothing(r[2]))
    new_drawable = reduce(+, new_layers)
    new_spec = _wrap_with_config(spec, new_drawable)

    # Build VL, tag layers whose color field is layer-fixed so JS remapEncoding skips them.
    vl = to_vegalite(new_spec)
    isempty(keep_color_fields) || _tag_keep_color_layers!(vl, keep_color_fields)
    # If the resolved spec is non-faceted (e.g. `:basename` had a single unique
    # value and got refined out of `dims`), strip top-level
    # `resolve.scale.{x,y} == "independent"` entries inherited from the user's
    # config — they were authored to mean "independent across facet rows", but
    # on a flat layered spec VL would interpret them as "independent across
    # layers", which gives each band/point sublayer its own x/y axis (top-axes
    # stack-up bug).
    _scrub_independent_resolve_if_unfaceted!(vl)

    controls = isempty(resolved.dims) ? "" : mapping_controls(plot_id, resolved; spec=new_spec)
    plot = to_node(vl; id=plot_id)
    (controls, plot)
end

# Drop `resolve.scale.x|y == "independent"` entries when the spec is not
# faceted. Those entries are only meaningful for the facet operator; on a
# plain layered spec VL applies them per-layer, giving each sublayer its own
# x/y scale + axis (axes stack at the top of the chart).
function _scrub_independent_resolve_if_unfaceted!(vl::Dict)
    haskey(vl, "facet") && return
    haskey(vl, "spec") && !isnothing(_as_dict(vl["spec"])) && return
    # Encoding-faceted specs (row=/col= → encoding.row/encoding.column) are
    # genuinely faceted even with no top-level `facet` key and no nested `spec`.
    # Don't strip a legitimate `resolve.scale.{x,y} = "independent"` the user
    # authored via `config(facet=(; linkxaxes=:none, linkyaxes=:none))` — there it
    # really does mean "independent across facet rows/columns".
    _has_encoding_facet(vl) && return
    resolve = _as_dict(get(vl, "resolve", nothing))
    isnothing(resolve) && return
    scale = _as_dict(get(resolve, "scale", nothing))
    isnothing(scale) && return
    for ax in ("x", "y")
        get(scale, ax, nothing) == "independent" && delete!(scale, ax)
    end
    isempty(scale) && delete!(resolve, "scale")
    isempty(resolve) && delete!(vl, "resolve")
    return
end

# Walk a VL dict and mark any layer with `encoding.color.field ∈ keep_color_fields`
# with `_keep_color = true`, so the JS remapEncoding loop leaves it alone.
_tag_keep_color_layer!(args...) = nothing
function _tag_keep_color_layer!(l::Dict, keep_color_fields::Set{String})
    enc = _as_dict(get(l, "encoding", nothing)); isnothing(enc) && return
    color = _as_dict(get(enc, "color", nothing)); isnothing(color) && return
    f = _as_str(get(color, "field", nothing))
    !isnothing(f) && f in keep_color_fields && (l["_keep_color"] = true)
    return
end

function _tag_keep_color_layers!(vl::Dict, keep_color_fields::Set{String})
    # Faceted specs nest layers under "spec"; plain layered specs use top-level "layer".
    nested = haskey(vl, "spec") ? _as_dict(vl["spec"]) : nothing
    container = isnothing(nested) ? vl : nested
    layers = _as_vec(get(container, "layer", nothing))
    isnothing(layers) && return
    for l in layers
        _tag_keep_color_layer!(l, keep_color_fields)
    end
end

function mapping_controls(id, resolved::NamedTuple; table=nothing, spec=nothing)
    id = _sanitize_id(id)
    dims = resolved.dims
    defaults = resolved.defaults
    fixed_js = resolved.fixed
    dim_label_map = resolved.dim_label_map
    _prettify(f) = get(dim_label_map, f, join(uppercasefirst.(split(f, "_")), " "))
    pinned_str = string(resolved.pinned)

    # Validate dimension fields exist in the table if provided
    if !isnothing(table)
        col_names = Set(string.(Tables.columnnames(table)))
        for (field, label) in dims
            field in col_names || error("mapping_controls: dimension field \"$field\" (label \"$label\") not found in table. Available columns: $(sort(collect(col_names)))")
        end
        for (ch_str, fs) in fixed_js
            for f in fs
                f in col_names || error("mapping_controls: fixed channel :$ch_str field \"$f\" not found in table. Available columns: $(sort(collect(col_names)))")
            end
        end
    end

    # Filter out dimensions with ≤1 unique value in the source DataFrame(s)
    # the AoG spec wraps. This is the authoritative source — walking the
    # post-AoG VL spec drops fields that get collapsed into combo columns
    # (e.g. row_fields = ["vessel","diet"] → __aov_row) even though `detail`
    # preserves them for rendering. Multi-layer specs contribute all layers:
    # a dim is kept iff *some* layer has it with >1 unique values.
    src_tables = !isnothing(table) ? Any[table] : _source_tables_from_spec(spec)
    if !isempty(src_tables)
        dims = filter(dims) do (field, _)
            sym = Symbol(field)
            for t in src_tables
                sym in Tables.columnnames(t) || continue
                length(unique(Tables.getcolumn(t, sym))) > 1 && return true
            end
            false  # no layer has the column, or every layer has ≤1 unique → drop
        end
    end

    js_id = replace(id, "-" => "_")
    channels = resolved.channels
    # Separate editable channels (for JS logic) from fixed
    editable_channels = [ch for ch in channels if !haskey(fixed_js, string(ch))]

    # Ensure :detail then :off ("Pooled") are always last in the channel order
    # (for both editable and all). :off maps to no VL encoding — its dims are
    # removed from the mark so their values pool into one line.
    _tail = (:detail, :off)
    _order(chs) = vcat([c for c in chs if !(c in _tail)], [c for c in _tail if c in chs])
    editable_channels = _order(editable_channels)
    all_ch_strs = [string(ch) for ch in editable_channels]

    # Build unified channel UI: all channels (editable + fixed) rendered identically.
    # Fixed channels have disabled select + disabled radio.
    all_ui_channels = _order(channels)
    sel_size = string(clamp(length(dims), 2, 4))
    selects = map(all_ui_channels) do ch
        ch_str = string(ch)
        ch_label = get(_CHANNEL_LABELS, ch_str, uppercasefirst(ch_str))
        is_fixed = haskey(fixed_js, ch_str)
        is_pinned = !is_fixed && ch_str == pinned_str
        # x/y are single-select axis channels — no combo, no pin radio.
        is_axis = ch_str == "x" || ch_str == "y"
        # :off (Pooled) can't be the catch-all pin — its dims are removed from
        # the encoding, not absorbed — so its pin radio is disabled like x/y.
        is_no_pin = is_axis || ch_str == "off"
        # Determine which fields are selected
        default_set = if is_fixed
            Set(fixed_js[ch_str])
        else
            Set(get(defaults, ch_str, String[]))
        end
        options = if is_axis
            # Prepend an empty option so users can clear the axis (JS will
            # leave the layer untouched when the selected value is empty).
            vcat(
                h.option(; value="")(""),
                [let
                    sel = field in default_set ? (; value=field, selected="selected") : (; value=field)
                    h.option(; sel...)(label)
                end for (field, label) in dims],
            )
        else
            [let
                sel = field in default_set ? (; value=field, selected="selected") : (; value=field)
                h.option(; sel...)(label)
            end for (field, label) in dims]
        end
        sel_attrs = if is_axis
            # Single-select listbox (no `multiple`) sized to match the other
            # channels' multi-select listboxes so the row of channels lines up.
            (;
                id="aov-remap-$(ch_str)-$(id)",
                size=sel_size,
                onchange="_aovRemap_$(js_id)('$(ch_str)')",
            )
        else
            (;
                id="aov-remap-$(ch_str)-$(id)",
                multiple="multiple",
                size=sel_size,
                onchange="_aovRemap_$(js_id)('$(ch_str)')",
            )
        end
        if (!is_axis && is_pinned) || is_fixed
            sel_attrs = merge(sel_attrs, (; disabled="disabled"))
        end
        radio_attrs = (; type="radio", name="aov-pin-$(id)", value=ch_str,
            onchange="_aovPin_$(js_id)(this.value)")
        if is_pinned
            radio_attrs = merge(radio_attrs, (; checked="checked"))
        end
        if is_fixed || is_no_pin
            radio_attrs = merge(radio_attrs, (; disabled="disabled"))
        end
        # x/y and :off render the radio disabled (they can't be pinned — a
        # catch-all makes no sense on a single-select axis or on the pooled
        # channel) so the column layout stays consistent with color/row/column.
        h.div()(
            h.label(; class="u-flex-tight")(
                h.input(; radio_attrs...),
                ch_label * ": ",
            ),
            h.select(; sel_attrs...)(options...),
        )
    end

    dim_fields = JSON.json([first(d) for d in dims])
    dim_labels = JSON.json(Dict(first(d) => _prettify(first(d)) for d in dims))
    fixed_js_str = JSON.json(fixed_js)
    channels_json = JSON.json(all_ch_strs)

    js = h.script("""
    var _aovPin_$(js_id)_current = '$(pinned_str)';

    function _aovPin_$(js_id)(newPin) {
        var oldPin = _aovPin_$(js_id)_current;
        _aovPin_$(js_id)_current = newPin;
        // Enable old pinned, disable new pinned
        var oldSel = document.getElementById('aov-remap-' + oldPin + '-$(id)');
        var newSel = document.getElementById('aov-remap-' + newPin + '-$(id)');
        if (oldSel) oldSel.disabled = false;
        if (newSel) newSel.disabled = true;
        _aovRemap_$(js_id)('pin');
    }

    function _aovRemap_$(js_id)(changed) {
        var allDims = $(dim_fields);
        var labels = $(dim_labels);
        var channels = $(channels_json);
        var pinned = _aovPin_$(js_id)_current;

        // Read selections from each non-pinned channel
        function readChannel(ch) {
            var sel = document.getElementById('aov-remap-' + ch + '-$(id)');
            if (!sel) return [];
            return Array.from(sel.selectedOptions).map(function(o) { return o.value; });
        }

        var selections = {};
        channels.forEach(function(ch) {
            selections[ch] = (ch === pinned) ? [] : readChannel(ch);
        });

        // Pinned channel = all dims not in any other editable channel (or fixed)
        var fixed = $(fixed_js_str);
        var elsewhere = {};
        channels.forEach(function(ch) {
            if (ch === pinned) return;
            selections[ch].forEach(function(f) { elsewhere[f] = true; });
        });
        for (var k in fixed) { fixed[k].forEach(function(f) { elsewhere[f] = true; }); }
        selections[pinned] = allDims.filter(function(d) { return !elsewhere[d]; });

        // Update pinned select's visual state
        var pinnedSel = document.getElementById('aov-remap-' + pinned + '-$(id)');
        if (pinnedSel) {
            var pinnedSet = {};
            selections[pinned].forEach(function(f) { pinnedSet[f] = true; });
            Array.from(pinnedSel.options).forEach(function(o) {
                o.selected = !!pinnedSet[o.value];
            });
        }

        // Clone origSpec data for combo building
        var orig = AoV._origSpecs['$(id)'];
        if (!orig) return;
        var dataObj = orig.data || (orig.spec && orig.spec.data);
        var dataClone = dataObj ? JSON.parse(JSON.stringify(dataObj)) : null;

        // Validate: warn about dims not present in the spec data
        if (dataClone && dataClone.values && dataClone.values.length > 0) {
            var sampleRow = dataClone.values[0];
            var allSelected = [].concat(
                selections.color || [], selections.row || [],
                selections.column || [], selections.detail || []);
            allSelected.forEach(function(f) {
                if (!dataClone.values.some(function(r) { return Object.prototype.hasOwnProperty.call(r, f); })) {
                    console.warn('[AoV mapping_controls] dimension "' + f + '" (' + (labels[f] || f) +
                        ') is in the picker but not in the spec data — it was likely dropped during AoG summary. ' +
                        'Add it to the AoG mapping (e.g. color=:' + f + ' or lineribbon detail) so it survives into the VL spec.');
                }
            });
        }

        // Build synthetic combo field when 2+ fields selected for a channel.
        // Only sets the combo on rows that have ALL component fields — cross-source
        // rows (e.g. dose VLines) that lack them are left without the combo, so
        // _broadcastCrossSource can replicate them across all unique combo values.
        var comboTitles = {};
        function resolveChannel(fields, comboName) {
            if (fields.length === 0) return '';
            if (fields.length === 1) return fields[0];
            if (!dataClone || !dataClone.values) return fields[0];
            var title = fields.map(function(f) { return labels[f] || f; }).join(' / ');
            comboTitles[comboName] = title;
            dataClone.values.forEach(function(row) {
                var hasAll = fields.every(function(f) {
                    return Object.prototype.hasOwnProperty.call(row, f);
                });
                if (hasAll) {
                    row[comboName] = fields.map(function(f) {
                        return row[f] != null ? String(row[f]) : '';
                    }).join(' / ');
                }
            });
            return comboName;
        }

        var colorField  = resolveChannel(selections.color || [], '__aov_color');
        var rowField    = resolveChannel(selections.row || [], '__aov_row');
        var columnField = resolveChannel(selections.column || [], '__aov_column');
        var detailFields = selections.detail || [];
        // x/y are single-select: pick the one field (or empty string).
        var xField = (selections.x && selections.x[0]) || '';
        var yField = (selections.y && selections.y[0]) || '';

        // Merge dim labels into comboTitles so single fields also get pretty names
        for (var f in labels) { if (!comboTitles[f]) comboTitles[f] = labels[f]; }
        var mapping = {
            color: colorField,
            row: rowField,
            column: columnField,
            _dimensions: detailFields,
            _comboData: dataClone,
            _comboTitles: comboTitles
        };
        if (channels.indexOf('x') !== -1) mapping.x = xField;
        if (channels.indexOf('y') !== -1) mapping.y = yField;
        // Merge fixed channels (resolve combos for multi-field fixed)
        for (var k in fixed) {
            var fs = fixed[k];
            if (k === 'detail') {
                mapping._dimensions = mapping._dimensions.concat(fs);
            } else {
                mapping[k] = fs.length <= 1 ? (fs[0] || '') : resolveChannel(fs, '__aov_' + k);
            }
        }

        AoV.remapEncoding('$(id)', mapping);

        // URL persistence: comma-separated field lists + pin state
        var params = new URLSearchParams(window.location.search);
        channels.forEach(function(ch) {
            var key = 'aov_' + ch + '_$(id)';
            var fields = selections[ch];
            if (fields && fields.length > 0) params.set(key, fields.join(','));
            else params.delete(key);
        });
        params.set('aov_pin_$(id)', pinned);
        var qs = params.toString();
        history.replaceState(null, '', qs ? '?' + qs : window.location.pathname);
    }

    // Restore from URL params once the spec is embedded
    (function _aovRestore_$(js_id)() {
        if (!(typeof AoV !== 'undefined' && AoV._origSpecs && AoV._origSpecs['$(id)'])) {
            setTimeout(_aovRestore_$(js_id), 50);
            return;
        }
        var params = new URLSearchParams(window.location.search);
        var restored = false;
        var channels = $(channels_json);

        // Restore pin state first
        var pinVal = params.get('aov_pin_$(id)');
        if (pinVal && channels.indexOf(pinVal) !== -1 && pinVal !== _aovPin_$(js_id)_current) {
            var radio = document.querySelector('input[name="aov-pin-$(id)"][value="' + pinVal + '"]');
            if (radio) { radio.checked = true; _aovPin_$(js_id)(pinVal); }
        }
        var pinned = _aovPin_$(js_id)_current;

        // Restore channel selections (skip pinned — it's computed)
        channels.forEach(function(ch) {
            if (ch === pinned) return;
            var val = params.get('aov_' + ch + '_$(id)');
            if (val) {
                var fields = val.split(',');
                var sel = document.getElementById('aov-remap-' + ch + '-$(id)');
                if (sel) {
                    Array.from(sel.options).forEach(function(o) {
                        o.selected = fields.indexOf(o.value) !== -1;
                    });
                    restored = true;
                }
            }
        });
        if (restored) _aovRemap_$(js_id)('');
    })();
    """)

    hint = h.small(; class="u-text-muted u-mb-1")(
        "Assign dimensions to channels (multi-select). ",
        "The pinned channel (", h.strong("●"), ") auto-fills with unassigned dimensions. ",
        "Selecting 2+ dimensions in one channel combines them. ",
        "“Pooled” removes a dimension from the plot entirely — its values merge into one.",
    )

    h.div()(
        hint,
        h.div(; class="u-flex-wide u-flex-wrap u-mb-2")(
            selects..., js,
        ),
    )
end
