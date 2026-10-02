# --- Public API: to_vegalite ---

"""
    to_vegalite(spec; interactive=true) -> Dict{String,Any}

Convert an AoG `Layer`, `Layers`, or `VegaSpec` to a Vega-Lite JSON dictionary.
Handles all translation: mark types, encodings, statistical transforms, config merging,
and, by default, auto-interactivity. Set `interactive=false` to suppress only the
parameters generated automatically by AoV; explicit `config(params=...)` and
`config(select=...)` remain in the output.
"""
function to_vegalite(layer::AlgebraOfGraphics.Layer; interactive::Bool=true)
    to_vegalite(vlspec(layer); interactive)
end

function to_vegalite(layers::AlgebraOfGraphics.Layers; interactive::Bool=true)
    to_vegalite(vlspec(layers); interactive)
end

# Lower the drawable before config and automatic interaction are applied. Bare
# drawables and configured specs share the same finalization path; adding params
# here would make generated selections look user-authored during config lowering.
_base_vegalite(drawable) = to_vegalite(drawable; interactive=false)
function _base_vegalite(layer::AlgebraOfGraphics.Layer)
    spec = layer_to_vl(layer)
    _apply_no_zero_default!(spec)
    _apply_no_truncate_default!(spec)
    _densify_facet_sort!(spec)
    spec
end

function _base_vegalite(layers::AlgebraOfGraphics.Layers)
    spec = layers_to_vl(layers)
    _apply_no_zero_default!(spec)
    _apply_no_truncate_default!(spec)
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

# AoV default: never silently truncate the LABELS of user-read guides. Vega-Lite
# clips legend / axis / facet-header labels to a pixel budget (`labelLimit` —
# default 160 px for legend labels, 180 px for axis and header labels), rendering
# anything longer as a trailing "…". Makie / `sdraw` never truncate, and the
# ecosystem never-truncate rule (ui layer-root primer, section `fe7b91fb`: never
# silently truncate/ellipsize content a human reads) forbids it — a translation
# layer must not clip legend/axis text a consumer passed in full. So default
# `labelLimit=0` ("no limit", per Vega's text-mark `limit` semantic:
# https://vega.github.io/vega/docs/marks/text/ — "default 0, indicating no
# limit") on every guide, unless a `labelLimit` is already present. Set on the
# TOP-LEVEL `config`, so it covers every guide in single / layered / faceted
# specs at once; a per-encoding `legend.labelLimit` / `axis.labelLimit` still
# wins, and `config(config=Dict("legend"=>Dict("labelLimit"=>160)))` opts a spec
# back into truncation. Scope is LABELS: titles use a separate `titleLimit`
# (legend default 180) and are left at Vega-Lite defaults.
const _NO_TRUNCATE_GUIDES = ("legend", "axis", "header")
_apply_no_truncate_default!(_) = nothing
function _apply_no_truncate_default!(spec::Dict)
    cfg = get!(spec, "config", Dict{String,Any}())
    cfg isa Dict || return spec
    for g in _NO_TRUNCATE_GUIDES
        guide = get!(cfg, g, Dict{String,Any}())
        guide isa Dict || continue
        haskey(guide, "labelLimit") || (guide["labelLimit"] = 0)
    end
    return spec
end

# Facet-densifier pad reuse: `_densify_facet_sort!` pads via the shared
# `_pad_sparse_hconcat_rows!` writer and suppresses via `_suppress_pad_marks!`
# (landed with the per-column-Y fix, `21b86b0`), passing valid-rows-only
# `rowvals` — a null-only value owns no facet slot. New in this commit: the
# composite-mark `detail` carry-through below, `_densify_needfields`, and the
# densifier rewire itself. Facet cells are fixed-size, so no bounds sublayer.
"""Carry the pad marker through composite-mark aggregation so the suppression
test still matches. A `boxplot` unit aggregates per group and the aggregate
datum keeps only the groupby keys plus computed stats — a bare
`datum.__aov_pad` condition then never matches and the pad box renders a
visible sliver. Adding `detail: {field: __aov_pad}` puts the marker in the
groupby (render-verified): pad groups carry `__aov_pad: true` and suppress,
while real rows share one `undefined` group whose boxes are byte-identical.
Runs only on filter-less composite-mark units, and only when pads were added
(see `_merge_pad_details!`)."""
function _merge_pad_detail!(enc::Dict)
    paddef = Dict{String,Any}("field" => _AOV_PAD_FIELD, "type" => "nominal")
    haskey(enc, "detail") || (enc["detail"] = paddef; return)
    cur = enc["detail"]
    if cur isa AbstractVector
        any(d -> (dd = _as_dict(d); dd isa Dict && get(dd, "field", nothing) == _AOV_PAD_FIELD), cur) && return
        if !(cur isa Vector{Any})
            cur = Vector{Any}(cur)
            enc["detail"] = cur
        end
        push!(cur, paddef)
        return
    end
    d = _as_dict(cur)
    if isnothing(d)
        # Shorthand field name: keep it as the first group key.
        enc["detail"] = Any[Dict{String,Any}("field" => cur), paddef]
        return
    end
    get(d, "field", nothing) == _AOV_PAD_FIELD && return
    enc["detail"] = Any[cur, paddef]
    return
end

"""Merge the pad-marker `detail` carry-through into filter-less composite-mark
units (same visit rule as `_suppress_pad_marks!`: `__src`-filtered sublayers
never see pads, so they are untouched). Primitive marks need no `detail` —
their suppression conditions match the raw row directly."""
function _merge_pad_details!(node)
    d = _as_dict(node)
    isnothing(d) && return
    layers = get(d, "layer", nothing)
    layers isa AbstractVector && for sub in layers
        _merge_pad_details!(sub)
    end
    _merge_pad_details!(get(d, "spec", nothing))
    if !(layers isa AbstractVector) && isnothing(_as_dict(get(d, "spec", nothing)))
        _sublayer_has_src_filter(d) && return
        _unit_is_composite(d) || return
        enc = _as_dict(get(d, "encoding", nothing))
        isnothing(enc) && return
        _merge_pad_detail!(enc)
    end
    return
end

function _unit_is_composite(unit::Dict)
    m = get(unit, "mark", nothing)
    m isa AbstractString && return m in _COMPOSITE_MARKS
    md = _as_dict(m)
    isnothing(md) && return false
    t = get(md, "type", nothing)
    return t isa AbstractString && t in _COMPOSITE_MARKS
end

"""First x/y field pair among the candidate encodings (the positional fields
whose validity decides whether a row survives Vega-Lite's hoisted invalid
filter), or `String[]` when no unit carries both (then every row counts as
valid and pads fall back to single clones)."""
function _densify_needfields(enc_dicts::AbstractVector)
    for e in enc_dicts
        ed = _as_dict(e)
        isnothing(ed) && continue
        x = _as_dict(get(ed, "x", nothing))
        y = _as_dict(get(ed, "y", nothing))
        (isnothing(x) || isnothing(y)) && continue
        fx = get(x, "field", nothing)
        fy = get(y, "field", nothing)
        (fx isa AbstractString && fy isa AbstractString) || continue
        return String[fx, fy]
    end
    return String[]
end

# Vega-Lite mis-binds faceted panels when a facet channel carries an explicit
# `sort` array AND the row×column cross-product is sparse (some cells have no
# data): VL fills the sorted header slots positionally, so a missing combination
# shifts real panels under the wrong header. (Third-party VL behaviour, not an
# AoV bug — the `encoding.column` shorthand and the top-level `facet` operator
# forms fail identically, which is why the fix lives at the shared data level.)
# Densify the cross-product: for every missing (row, col) cell, append pad rows
# so the slot owns a cell. Pads are donor CLONES with VALID, in-distribution
# measures — a nulled measure is dropped before faceting in single-layer specs
# (Vega-Lite hoists the `isValid(x) && isValid(y)` filter above the facet,
# ahead of the row/column-domain aggregates — visible in the compiled Vega
# dataflow) and materializes no cell (snag `facet-densify-fi-62fd2dbf`). Pad
# marks are suppressed instead: `opacity`/`size`/`strokeWidth` zero-conditions
# on the filter-less units pads can reach (`__src`-filtered sublayers drop
# `__src`-less pads on their own), plus a `detail` carry-through on composite
# marks whose aggregation would otherwise eat the marker. Only fires when a
# facet `sort` is present and BOTH axes are faceted — unsorted specs and
# single-axis facets already render sparse data correctly.
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
    # Candidate encodings for the x/y measure pair that decides whether a row
    # survives Vega-Lite's hoisted invalid filter (`isValid(x) && isValid(y)`
    # — compiled-dataflow verified, including with color/size/y2 encodings
    # present: only the x/y positionals gate facet survival). A multi-layer
    # facet carries its encodings per sublayer with NO shared encoding, so
    # every level is scanned (snag `facet-column-sor-9904da1f`).
    enc_dicts = Dict[]
    !isnothing(enc) && push!(enc_dicts, enc)
    inner = _as_dict(get(spec, "spec", nothing))
    if !isnothing(inner)
        ie = _as_dict(get(inner, "encoding", nothing))
        !isnothing(ie) && push!(enc_dicts, ie)
        inner_layers = get(inner, "layer", nothing)
        if inner_layers isa AbstractVector
            for sub in inner_layers
                sd = _as_dict(sub)
                isnothing(sd) && continue
                se = _as_dict(get(sd, "encoding", nothing))
                !isnothing(se) && push!(enc_dicts, se)
            end
        end
    end
    top_layers = get(spec, "layer", nothing)
    if top_layers isa AbstractVector
        for sub in top_layers
            sd = _as_dict(sub)
            isnothing(sd) && continue
            se = _as_dict(get(sd, "encoding", nothing))
            !isnothing(se) && push!(enc_dicts, se)
        end
    end
    needfields = _densify_needfields(enc_dicts)
    # Facet values that can own a cell: only rows with valid x/y measures
    # survive to the facet partition — null-measure rows are dropped before
    # it, so their combos still need pads, while a value with ONLY null rows
    # owns no rendered slot and must not invent a header.
    data = _as_dict(get(spec, "data", nothing))
    vals = isnothing(data) ? nothing : _as_vec(get(data, "values", nothing))
    (vals isa AbstractVector && !isempty(vals)) || return  # named datasets / urls: can't densify here
    isvalidrow = rd -> all(f -> (v = get(rd, f, nothing); v !== nothing && !ismissing(v)), needfields)
    rowvals = Any[]
    colvals = Any[]
    for r in vals
        rd = _as_dict(r)
        (isnothing(rd) || !isvalidrow(rd)) && continue
        haskey(rd, row_field) && !any(u -> isequal(u, rd[row_field]), rowvals) && push!(rowvals, rd[row_field])
        haskey(rd, col_field) && !any(u -> isequal(u, rd[col_field]), colvals) && push!(colvals, rd[col_field])
    end
    (isempty(rowvals) || isempty(colvals)) && return
    # Shared pad writer (also serves `_per_column_y_hconcat!`): valid
    # same-column donor clones at the column range corners, `__src` removed,
    # `__aov_pad` marked. Idempotent: pads are valid rows carrying the facet
    # fields, so a re-run counts their combos present and adds nothing.
    npads = _pad_sparse_hconcat_rows!(spec, col_field, row_field, colvals, needfields; rowvals=rowvals)
    npads > 0 || return
    _suppress_pad_marks!(spec)
    _merge_pad_details!(spec)
    return
end

# Generic recursive dict merge: a nested-Dict value merges key-by-key into the
# matching target Dict; every other value (strings, numbers, arrays) replaces.
# Used for the `config(config=…)` passthrough so a user overlay preserves the
# base config's other keys (no-truncate labelLimit defaults, font_scale sizes),
# and for raw `config(encoding=…)` channel overrides so a sub-Dict like
# `y.scale` adds to the auto-generated scale (e.g. `zero=false` on top of the
# `type=log` that `scales()` set) instead of replacing it wholesale. Same-key
# conflicts still resolve to the config value ("later config wins"); to drop an
# auto-generated key, set it to `nothing` (JSON null).
function _deep_merge_dict!(target::Dict, src::Dict)
    for (k, v) in src
        sk = string(k)
        tv = get(target, sk, nothing)
        vd = _as_dict(v)
        if !isnothing(vd) && tv isa Dict
            _deep_merge_dict!(tv, vd)
        else
            target[sk] = v
        end
    end
    return target
end

# Recurse the merge into a child spec only when it's actually a Dict.
_merge_into_child!(args...) = nothing
_merge_into_child!(child::Dict, config_enc::Dict) = _merge_encoding_config!(child, config_enc)

"""Merge raw `config(encoding=...)` overrides.

A top-level Vega-Lite facet operator *is* the row/column encoding. Route its
channel overrides to `facet.row` / `facet.column` before the normal layer
recursion; otherwise a faceted spec has no top-level `encoding`, and the
override recurses into sublayers where a field-less row/channel dict is inert.
"""
function _merge_encoding_config!(spec::Dict, config_enc::Dict)
    if haskey(spec, "facet")
        facet = spec["facet"]
        for config_key in ("row", "column")
            haskey(config_enc, config_key) && haskey(facet, config_key) || continue
            target = _as_dict(facet[config_key])
            override = _as_dict(config_enc[config_key])
            !isnothing(target) && !isnothing(override) &&
                _deep_merge_dict!(target, override)
        end
    end
    if haskey(spec, "encoding")
        _deep_merge_dict!(spec["encoding"], config_enc)
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
        # An unknown key on a positional axis is almost always a misplaced
        # parenthesis (e.g. `scales(Y=(; scale=..., Col=(; categories=...)))`
        # puts the column scale INSIDE the Y NamedTuple and the column order
        # silently stays default). Warn once — never silently swallow.
        for k in keys(props)
            k in keys(_SCALES_NT_FORWARD) && continue
            k === :scale && continue
            @warn "AlgebraOfVega: unknown `$axis_key` scale option `$k` — not a known scale/nice/zero/domain/clamp/constant key. If you meant a facet order or per-column scale, check the parentheses (it must be a sibling of the `$axis_key=` argument, not inside its NamedTuple)." maxlog=1
        end
        vl_scale = Dict{String,Any}()
        scale_fn = get(props, :scale, nothing)
        # A Dict-valued `scale` is the per-facet-column form — it can never go
        # into one shared facet encoding (every column would take the LAST
        # written type). It is consumed by `_per_column_y_hconcat!` instead,
        # which re-lowers the single-facet spec into an `hconcat` of per-column
        # facet views (snag `mixed-log-and-li-a69d2f23`).
        scale_fn isa AbstractDict && continue
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

"""Extract a per-facet-column Y scale mapping from a `Scales` object, or `nothing`.

`scales(Y=(; scale=Dict("Tumor size (mm)" => log10)))` requests one Y scale TYPE
per column-facet VALUE: listed columns get the mapped transform, unlisted columns
stay linear. Values are translated through `_aog_scale_fn_to_vl` (an unsupported
function warns there and drops that column's entry)."""
function _scales_column_y_scales(sc::AlgebraOfGraphics.Scales)
    props = get(sc.dict, :Y, nothing)
    isnothing(props) && return nothing
    s = get(props, :scale, nothing)
    s isa AbstractDict || return nothing
    out = Dict{Any,Any}()
    for (k, v) in s
        translated = _aog_scale_fn_to_vl(v)
        isnothing(translated) || (out[k] = translated)
    end
    isempty(out) ? nothing : out
end

# Vega-Lite filter literals: quote strings (escaping embedded quotes), emit
# numbers/booleans bare, `null` for `nothing`.
function _vl_filter_literal(v)
    v isa AbstractString && return "'" * replace(string(v), "'" => "\\'") * "'"
    isnothing(v) && return "null"
    v isa Bool && return v ? "true" : "false"
    v isa Real && return string(v)
    return "'" * replace(string(v), "'" => "\\'") * "'"
end

# Column-facet values in draw order: the explicit `sort` array wins, otherwise
# first-appearance order over the hoisted top-level data.
function _facet_column_values(spec::Dict, coldef::Dict)
    srt = get(coldef, "sort", nothing)
    srt isa AbstractVector && !isempty(srt) && return collect(srt)
    field = get(coldef, "field", nothing)
    isnothing(field) && return String[]
    data = _as_dict(get(spec, "data", nothing))
    vals = isnothing(data) ? nothing : get(data, "values", nothing)
    vals isa AbstractVector || return String[]
    seen = Any[]
    for r in vals
        rd = _as_dict(r)
        isnothing(rd) && continue
        haskey(rd, field) || continue
        v = rd[field]
        v in seen || push!(seen, v)
    end
    seen
end

# Merge a per-column VL `scale` dict into every field-bearing Y encoding of a
# spec tree (sublayer arrays + nested facet specs), mirroring the scoping rule
# of `_merge_color_scale!`: field-less Y encodings are left alone.
function _merge_column_y_scale!(spec, yscale::Dict)
    d = _as_dict(spec)
    isnothing(d) && return
    enc = _as_dict(get(d, "encoding", nothing))
    if !isnothing(enc)
        y = _as_dict(get(enc, "y", nothing))
        if !isnothing(y) && haskey(y, "field")
            existing = get!(y, "scale", Dict{String,Any}())
            existing isa Dict ? merge!(existing, yscale) : (y["scale"] = copy(yscale))
        end
    end
    layers = get(d, "layer", nothing)
    layers isa AbstractVector && for sub in layers
        _merge_column_y_scale!(sub, yscale)
    end
    _merge_column_y_scale!(get(d, "spec", nothing), yscale)
    return
end

# Header-label text for a column-facet VALUE, matching what the facet operator
# renders for the same value: strings pass through, whole-number floats print
# JS-style (`"20"`, not `"20.0"`), booleans/nulls print JS-style.
function _vl_header_label(v)
    v isa AbstractString && return string(v)
    v isa Bool && return v ? "true" : "false"
    (isnothing(v) || ismissing(v)) && return "null"
    if v isa Real
        f = Float64(v)
        isinteger(v) && abs(f) < 1e15 && return string(Int64(f))
        return string(v)
    end
    return string(v)
end

# Map VL `header` label/title props onto the equivalent `title` props
# (`labelFontSize` → `fontSize`, `titleFontWeight` → `fontWeight`, …) so
# per-column titles honor the column def's header config. `labelExpr`,
# `format`, and `labelPadding` have no title equivalent — titles are static
# text, not data-driven marks — and are skipped, as are the `labels` toggle
# and the bare `title` text key (both handled by the caller).
function _map_header_props!(title::Dict, header, prefix::String)
    header isa Dict || return title
    for (k, v) in header
        ks = string(k)
        ks == "labels" && continue
        startswith(ks, prefix) || continue
        rest = ks[length(prefix)+1:end]
        isempty(rest) && continue
        prop = string(lowercase(first(rest))) * (length(rest) > 1 ? rest[2:end] : "")
        prop in ("expr", "format", "formatType", "padding") && continue
        title[prop] = v
    end
    title
end

# Marker field on pad rows (see `_pad_sparse_hconcat_rows!`). Pads carry no
# `__src`, so every hoisted sublayer filter drops them and real pipelines
# stay pristine; they surface only in the hidden bounds sublayer
# (`_add_pad_bounds_sublayer!`) and in filter-less units, where their marks
# are suppressed (`_merge_pad_condition!`, plus a `detail` carry-through on
# composite marks — `_merge_pad_details!`).
const _AOV_PAD_FIELD = "__aov_pad"

"""Append one pad row per missing (row, column) combo to the shared dataset so
every hconcat child facets the full row domain. Returns the pads added.

Each child filters the shared dataset to ITS column before faceting, so a
column missing a row value packs its remaining rows from the top beside the
wrong (first-view) labels. A pad is a donor clone with the facet fields set,
`__src` REMOVED, and `__aov_pad: true`. Measures stay VALID and SAME-COLUMN:
a nulled measure is dropped before faceting in single-layer specs and
materializes no cell (render-verified against vl-convert 1.9.0), and the pad
enters the hidden bounds sublayer's scale domains, which must stay
in-distribution (pad values ⊆ real values ⇒ shared domains bit-identical).

Two things pads are NOT, both render-verified:
- NOT `transform` guard filters: layer transforms hoist above the facet in
  single-layer specs, removing the pad before the facet domain is computed.
- NOT cross-column donors (see above). Combos in wholly-empty
  (sort-listed, dataless) columns are skipped for the same reason — that
  child keeps its title-only rendering, matching the facet form.

Each missing combo gets TWO pads at the diagonal corners of the column's
x/y range (min,min) and (max,max) over `needfields` (the bounds sublayer's
x/y): a single-datum cell domain renders a one-label axis whose missing
label overhang shrinks that child's row pitch (5px/row), while a spanned
domain renders full top-and-bottom labels and identical pitch
(render-verified on vl-convert 1.9.0). Ranges prefer same-column rows
carrying the fields, else any rows carrying them (a ragged column's empty
cells then show the donor column's range — aligned, documented); when no
range is computable (unorderable or single-point columns) a single pad is
emitted, which still fixes cell existence while pitch may drift.

Pass `rowvals` to pad a caller-derived row set: the facet densifier passes
the values of VALID rows only (null-measure rows are dropped before
faceting, so their values own no slot and must not invent headers); the
default derives the union over all rows (hconcat cross-child alignment needs
every value shared).

Skips (returning 0) when the dataset is not an inline `values` vector: the
combos are unknowable there, so that corner keeps its pre-fix behaviour
rather than gaining a new error."""
function _pad_sparse_hconcat_rows!(spec::Dict, colfield::String, rowfield::String, colvals::AbstractVector,
        needfields::AbstractVector{<:AbstractString}=String[]; rowvals::Union{Nothing,AbstractVector}=nothing)
    data = _as_dict(get(spec, "data", nothing))
    vals = isnothing(data) ? nothing : _as_vec(get(data, "values", nothing))
    (vals isa AbstractVector && !isempty(vals)) || return 0
    rows = Dict[]
    for r in vals
        rd = _as_dict(r)
        isnothing(rd) || push!(rows, rd)
    end
    isempty(rows) && return 0
    # Union over ALL rows (valid or not): alignment requires every row value
    # shared across children, even one whose column data is all null (its
    # cells render empty; the facet form hides globally-null values instead
    # in single-layer specs — inherent to the alignment requirement).
    # `_densify_facet_sort!` overrides via `rowvals=` with the valid-rows
    # union instead (a null-only value owns no facet slot there).
    _rowvals = rowvals
    if isnothing(_rowvals)
        _rowvals = Any[]
        for rd in rows
            haskey(rd, rowfield) || continue
            v = rd[rowfield]
            any(u -> isequal(u, v), _rowvals) || push!(_rowvals, v)
        end
    end
    # Validity-aware presence: a row covers its combo only when its
    # bounds-measure values are valid. Real rows can carry null measures, and
    # in single-layer specs Vega-Lite drops those before faceting, so they
    # materialize no cell and must not suppress pads. (In multi-layer specs
    # they partition but populate nothing; pads still own the cell either
    # way.)
    present = Tuple{Any,Any}[]
    for rd in rows
        (haskey(rd, rowfield) && haskey(rd, colfield)) || continue
        all(f -> (v = get(rd, f, nothing); v !== nothing && !ismissing(v)), needfields) || continue
        push!(present, (rd[rowfield], rd[colfield]))
    end
    hasfields(rd) = all(f -> haskey(rd, f), needfields)
    npads = 0
    for cv in colvals
        colrows = [rd for rd in rows if haskey(rd, colfield) && isequal(rd[colfield], cv)]
        isempty(colrows) && continue
        donor = nothing
        for rd in colrows
            hasfields(rd) && (donor = rd; break)
        end
        isnothing(donor) && (donor = colrows[1])
        rangerows = [rd for rd in colrows if hasfields(rd)]
        if isempty(rangerows)
            rangerows = [rd for rd in rows if hasfields(rd)]
            if !isempty(rangerows) && (isnothing(donor) || !hasfields(donor))
                donor = rangerows[1]
            end
        end
        corners = _pad_range_corners(rangerows, needfields)
        for rv in _rowvals
            any(p -> isequal(p[1], rv) && isequal(p[2], cv), present) && continue
            if isnothing(corners)
                push!(vals, _pad_row(donor, rowfield, rv, colfield, cv, nothing))
                npads += 1
            else
                (lo, hi) = corners
                push!(vals, _pad_row(donor, rowfield, rv, colfield, cv, lo))
                push!(vals, _pad_row(donor, rowfield, rv, colfield, cv, hi))
                npads += 2
            end
        end
    end
    return npads
end

"""One pad row: donor clone with facet fields set, `__src` removed, marker
set, and `corner` (field => value overwrites, or `nothing`) applied."""
function _pad_row(donor::Dict, rowfield::String, rv, colfield::String, cv, corner)
    pad = Dict{String,Any}(donor)
    pad[rowfield] = rv
    pad[colfield] = cv
    delete!(pad, "__src")
    pad[_AOV_PAD_FIELD] = true
    if !isnothing(corner)
        for (f, v) in corner
            pad[f] = v
        end
    end
    return pad
end

"""Column values that received `__aov_pad` rows (see `_pad_sparse_hconcat_rows!`).
Read back from the shared dataset so the child loop can mount pad machinery
only on padded children (snag `per-column-y-pad-0c9e8b2a`)."""
function _padded_hconcat_columns(spec::Dict, colfield::String)
    data = _as_dict(get(spec, "data", nothing))
    vals = isnothing(data) ? nothing : _as_vec(get(data, "values", nothing))
    isnothing(vals) && return Any[]
    out = Any[]
    for r in vals
        rd = _as_dict(r)
        isnothing(rd) && continue
        get(rd, _AOV_PAD_FIELD, false) === true || continue
        haskey(rd, colfield) || continue
        v = rd[colfield]
        any(u -> isequal(u, v), out) || push!(out, v)
    end
    return out
end

"""Diagonal range corners over `needfields` for `rangerows`: `((min...),
(max...))` as field => value pairs, or `nothing` when no range is computable
(fewer than two fields, no valid values, unorderable values, or a single
point — the single-pad fallback then still fixes cell existence)."""
function _pad_range_corners(rangerows::AbstractVector, needfields::AbstractVector{<:AbstractString})
    length(needfields) >= 2 || return nothing
    isempty(rangerows) && return nothing
    lo = Pair{String,Any}[]
    hi = Pair{String,Any}[]
    try
        for f in needfields[1:2]
            vs = Any[]
            for rd in rangerows
                v = get(rd, f, nothing)
                (v === nothing || ismissing(v)) && continue
                push!(vs, v)
            end
            isempty(vs) && return nothing
            push!(lo, f => minimum(vs))
            push!(hi, f => maximum(vs))
        end
    catch e
        e isa InterruptException && rethrow()
        return nothing
    end
    all(i -> isequal(lo[i].second, hi[i].second), eachindex(lo)) && return nothing
    return (lo, hi)
end

"""Add one hidden point sublayer that equalizes facet-cell bounds across
sparse and complete columns. Returns the x/y fields it encodes (for donor
selection), or `nothing` when no sublayer carries both (then pads still fix
cell existence, but pitch may drift — only HLines/VLines-only figures).

Why a sublayer: an invisible FULL-geometry mark contributes full cell bounds
(render-verified: identical row pitch to complete columns), while a
zero-geometry mark measurably shrinks its child's pitch (5px/row). The bounds
sublayer plots the same x/y as the first x/y sublayer (verbatim defs minus
title/axis, so scales — including per-child log/linear types merged later —
match exactly). It draws NOTHING, twice over (snag `per-column-y-pad-0c9e8b2a`):
a pad-filter transform restricts its data to pad rows (pads carry no `__src`,
so a `__src` filter cannot select them — the marker field is the selector;
real rows never reach its marks, so real cells carry zero marks and stay
hover-immune), and `opacity: {condition: pad → 0, value: 0}` hides every mark
unconditionally (a condition-only opacity falls back to the default for
non-matching rows — the phantom-points bug). It carries no tooltip (hovering
it shows nothing) and no color/size encodings (legend/selection immune). Unlike
a guard on a real unit, the pad filter is safe here: it sits on an auxiliary
sublayer inside an operator-facet child, so it filters per-cell AFTER faceting
instead of hoisting above it."""
function _add_pad_bounds_sublayer!(inner::Dict)
    layers = _as_vec(get(inner, "layer", nothing))
    isnothing(layers) && return nothing
    found = _pad_bounds_xy_defs(inner)
    isnothing(found) && return nothing
    x, y = found
    xdef = Dict{String,Any}(x)
    ydef = Dict{String,Any}(y)
    delete!(xdef, "title")
    delete!(xdef, "axis")
    delete!(ydef, "title")
    delete!(ydef, "axis")
    cond = Dict{String,Any}("test" => "datum.$(_AOV_PAD_FIELD)", "value" => 0)
    push!(layers, Dict{String,Any}(
        "mark" => Dict{String,Any}("type" => "point"),
        "encoding" => Dict{String,Any}(
            "x" => xdef, "y" => ydef,
            "opacity" => Dict{String,Any}("condition" => cond, "value" => 0)),
        "transform" => Any[Dict{String,Any}("filter" => "datum.$(_AOV_PAD_FIELD)")]))
    return String[string(x["field"]), string(y["field"])]
end

"""First x/y channel def pair (verbatim dicts) among `inner`'s sublayers, or
`nothing`. Read-only field source for pad donor selection (see call site)."""
function _pad_bounds_xy_defs(inner::Dict)
    layers = _as_vec(get(inner, "layer", nothing))
    isnothing(layers) && return nothing
    for sub in layers
        d = _as_dict(sub)
        isnothing(d) && continue
        enc = _as_dict(get(d, "encoding", nothing))
        isnothing(enc) && continue
        x = _as_dict(get(enc, "x", nothing))
        y = _as_dict(get(enc, "y", nothing))
        (isnothing(x) || isnothing(y)) && continue
        (haskey(x, "field") && haskey(y, "field")) || continue
        return (x, y)
    end
    return nothing
end

"""Merge pad-suppression conditions into filter-less unit sublayers (single-
layer units and any unit without a `__src` filter — pads flow into those,
since nothing drops them). Sublayers WITH a `__src` filter are untouched.

Each of `opacity`, `size`, and `strokeWidth` gets `{condition: {test:
"datum.__aov_pad", value: 0}}`, merged to preserve whatever the unit already
carries (a missing channel gains a bare condition, which falls back to the
mark value or Vega-Lite default for real rows — verified; an existing
condition is demoted behind the pad test, which must match first). Opacity 0
hides the mark in every renderer; size 0 removes point / bar / text / rule
geometry and strokeWidth 0 covers ticks (unhoverable, so no ghost tooltips —
which is why array tooltips need no condition of their own). Cell bounds come
from the bounds sublayer, so zeroing geometry here costs no pitch. Runs only
when pads were added."""
function _suppress_pad_marks!(node)
    d = _as_dict(node)
    isnothing(d) && return
    layers = get(d, "layer", nothing)
    layers isa AbstractVector && for sub in layers
        _suppress_pad_marks!(sub)
    end
    _suppress_pad_marks!(get(d, "spec", nothing))
    if !(layers isa AbstractVector) && isnothing(_as_dict(get(d, "spec", nothing)))
        # Runs before the bounds sublayer is added (see call site), so the
        # bounds sublayer — whose geometry must stay full — is never visited.
        _sublayer_has_src_filter(d) && return
        enc = _as_dict(get(d, "encoding", nothing))
        isnothing(enc) && return
        for ch in ("opacity", "size", "strokeWidth")
            _merge_pad_condition!(enc, ch)
        end
    end
    return
end

function _sublayer_has_src_filter(sublayer::Dict)
    ts = _as_vec(get(sublayer, "transform", nothing))
    isnothing(ts) && return false
    for t in ts
        td = _as_dict(t)
        isnothing(td) && continue
        f = get(td, "filter", nothing)
        f isa AbstractString && occursin("datum.__src", f) && return true
    end
    return false
end

function _merge_pad_condition!(enc::Dict, channel::String)
    cond = Dict{String,Any}("test" => "datum.$(_AOV_PAD_FIELD)", "value" => 0)
    haskey(enc, channel) || (enc[channel] = Dict{String,Any}("condition" => cond); return)
    existing = _as_dict(enc[channel])
    if isnothing(existing)
        # Shorthand value (e.g. `"opacity": 0.5`): keep it as the else-branch.
        enc[channel] = Dict{String,Any}("value" => enc[channel], "condition" => cond)
        return
    end
    # Widen user-supplied dicts: a raw `encoding=Dict("opacity" =>
    # Dict("value" => 0.5))` arrives as `Dict{String,Float64}` (possibly with
    # `Symbol` keys), and merging a `"condition"` Dict into it throws. The
    # widened copy serializes identically (JSON ignores Julia types).
    if !(existing isa Dict{String,Any})
        existing = Dict{String,Any}(string(k) => v for (k, v) in existing)
        enc[channel] = existing
    end
    haskey(existing, "condition") || (existing["condition"] = cond; return)
    cur = existing["condition"]
    if cur isa AbstractVector
        any(c -> _as_dict(c) isa Dict && get(_as_dict(c), "test", nothing) == cond["test"], cur) && return
        if !(cur isa Vector{Any})
            cur = Vector{Any}(cur)
            existing["condition"] = cur
        end
        pushfirst!(cur, cond)
    else
        existing["condition"] = Any[cond, cur]
    end
    return
end

"""Re-lower a single-facet spec into an `hconcat` of per-column facet views so
every column-facet VALUE can carry its own Y scale type.

Vega-Lite's facet operator shares ONE encoding across all columns — the scale
TYPE cannot differ per column. The only VL shape that can is a concat of one
faceted view per column, each with its own inner scale and a row facet. Rows
stay aligned because the shared dataset is padded with two fillers per
missing (row, column) combo (diagonal range corners —
`_pad_sparse_hconcat_rows!`), so every view facets the same full row domain —
a cell without data renders empty, never packed. Only children whose column
received pads carry the hidden bounds sublayer; complete children keep their
exact unpadded shape (snag `per-column-y-pad-0c9e8b2a`).

`ycols` maps column VALUES (as they appear in the data) to VL `scale` dicts
(from `_scales_column_y_scales`). Unlisted columns keep the shared encoding's
existing scale (linear by default).

Requires the operator-facet shape `layers_to_vl` emits: top-level `facet` with a
field-bearing `column` channel and `spec.layer` sublayers over one hoisted
top-level dataset. Anything else is a loud error — a silent fallback would
plot every column with the wrong scale type.

Top-level residue of the facet form (`resolve`, select-filter transforms) moves
into each child; top-level `params`, `config` and `_aov` stay on the concat,
where VL applies them to every view. The facet form's column chrome is
preserved, not dropped: each child gets its column VALUE as a facet-header-
styled title (10px regular, honoring the column def's header label config),
and the column field title sits once on the concat (11px bold; as `subtitle`
when the figure already carries its own title, which is never clobbered).
VL header suppression is honored: `header: null` drops both, `labels: false`
drops the child titles, and a null channel/header title drops the concat
title."""
function _per_column_y_hconcat!(spec::Dict, ycols::Dict)
    facet = _as_dict(get(spec, "facet", nothing))
    if isnothing(facet)
        # Single-view `col=` specs carry the facet at the encoding level —
        # normalize into the operator form (`facet` + `spec.layer`) so the rest
        # of the lowering is shape-uniform.
        enc = _as_dict(get(spec, "encoding", nothing))
        if !isnothing(enc) && haskey(enc, "column")
            unit = Dict{String,Any}()
            for k in ("mark", "encoding", "transform", "params")
                haskey(spec, k) && (unit[k] = spec[k])
            end
            uenc = _as_dict(unit["encoding"])
            facet = Dict{String,Any}()
            facet["column"] = uenc["column"]
            haskey(uenc, "row") && (facet["row"] = uenc["row"])
            delete!(uenc, "column")
            delete!(uenc, "row")
            delete!(enc, "column")
            delete!(enc, "row")
            isempty(enc) && delete!(spec, "encoding")
            spec["facet"] = facet
            spec["spec"] = Dict{String,Any}("layer" => Any[unit])
            delete!(spec, "mark")
            delete!(spec, "transform")
            delete!(spec, "params")
            haskey(spec, "data") || (spec["data"] = Dict{String,Any}("values" => Any[]))
        else
            error("AlgebraOfVega: per-column Y scales (`scales(Y=(; scale=Dict(...)))`) need a faceted spec with a column facet; this spec has no facet.")
        end
    end
    coldef = _as_dict(get(facet, "column", nothing))
    if isnothing(coldef) || !haskey(coldef, "field")
        error("AlgebraOfVega: per-column Y scales need a column facet (mapping col=...); this spec only facets by row/layout.")
    end
    inner = _as_dict(get(spec, "spec", nothing))
    if isnothing(inner) || !haskey(inner, "layer")
        error("AlgebraOfVega: per-column Y scales need the multi-layer faceted form (one `+`-composed spec with facet rows); single-layer `col=` specs keep one shared encoding and cannot vary the scale type per column.")
    end
    colfield = string(coldef["field"])
    rowdef = _as_dict(get(facet, "row", nothing))

    # Column chrome the facet form rendered and the concat must keep. Sizes
    # consult the spec's own `config.header` first (so `font_scale` applies),
    # then the column def's header (channel-near wins, matching VL
    # precedence), defaulting to VL's header sizes (10px labels, 11px bold
    # titles — verified against a headless facet render, not a bare title).
    cheader_raw = get(coldef, "header", :absent)
    header_off = cheader_raw === nothing
    cheader = header_off ? nothing : _as_dict(cheader_raw)
    labels_off = header_off ||
        (!isnothing(cheader) && get(cheader, "labels", true) === false)
    htitle_raw = isnothing(cheader) ? :absent : get(cheader, "title", :absent)
    ctitle_raw = get(coldef, "title", :absent)
    title_off = header_off || htitle_raw === nothing || ctitle_raw === nothing
    field_title = htitle_raw isa AbstractString ? string(htitle_raw) :
        ctitle_raw isa AbstractString ? string(ctitle_raw) : colfield
    cfg = _as_dict(get(spec, "config", nothing))
    cfg_header = isnothing(cfg) ? nothing : _as_dict(get(cfg, "header", nothing))

    colvals = _facet_column_values(spec, coldef)
    isempty(colvals) && error("AlgebraOfVega: per-column Y scales found no values for column facet field `$colfield`.")

    # Pad sparse row sets BEFORE building children: every child facets the
    # shared dataset through its own column filter, so without fillers for
    # each missing (row, column) combo a sparse column packs its rows from
    # the top beside the wrong first-view labels (snag
    # `per-column-y-sca-ad6baf40`). Complete cross-products pad nothing.
    # Pad machinery (suppression + the hidden bounds sublayer) rides ONLY the
    # children whose column actually received pads (snag
    # `per-column-y-pad-0c9e8b2a`): complete children keep their exact
    # unpadded shape, so real data there renders pixel-identical.
    rowfield = isnothing(rowdef) ? nothing : get(rowdef, "field", nothing)
    padded_cols = Any[]
    if rowfield isa AbstractString
        xydefs = _pad_bounds_xy_defs(inner)
        needfields = isnothing(xydefs) ? String[] :
            String[string(xydefs[1]["field"]), string(xydefs[2]["field"])]
        npads = _pad_sparse_hconcat_rows!(spec, colfield, rowfield, colvals, needfields)
        if npads > 0
            padded_cols = _padded_hconcat_columns(spec, colfield)
        end
    end

    # Top-level state that must survive onto every child / the concat.
    resolve = _as_dict(get(spec, "resolve", nothing))
    select_transforms = _as_vec(get(spec, "transform", nothing))
    children = Any[]
    for (i, v) in enumerate(colvals)
        child = Dict{String,Any}()
        # The row facet moves into each view; later views drop the row header
        # (labels would repeat per column — never-truncate never-means-repeat).
        # Suppression is sound: padding above keeps every child's row domain
        # complete, so the first view's labels stay true for every column.
        if !isnothing(rowdef)
            rd = deepcopy(rowdef)
            i > 1 && (rd["header"] = nothing)
            child["facet"] = Dict{String,Any}("row" => rd)
        end
        child_inner = deepcopy(inner)
        if any(p -> isequal(p, v), padded_cols)
            # Suppress first (filter-less units only), then add the bounds
            # sublayer — order matters: suppression must not visit it (its
            # size-0 geometry would defeat the pitch equalization). The
            # `detail` carry-through rides alongside suppression: composite
            # units aggregate per group, so without it the pad conditions
            # never match and the pad mark renders a visible sliver (snag
            # `hconcat-pads-mis-96d5cb25`).
            _suppress_pad_marks!(child_inner)
            _merge_pad_details!(child_inner)
            _add_pad_bounds_sublayer!(child_inner)
        end
        yscale = get(ycols, v, nothing)
        isnothing(yscale) || _merge_column_y_scale!(child_inner, yscale)
        child["spec"] = child_inner
        # The column facet becomes a child-level filter (applies before the
        # row facet and every sublayer transform).
        ctransforms = Any[Dict{String,Any}(
            "filter" => "datum.$colfield === $(_vl_filter_literal(v))")]
        if !isnothing(select_transforms)
            append!(ctransforms, deepcopy(select_transforms))
        end
        child["transform"] = ctransforms
        if !isnothing(resolve)
            child["resolve"] = deepcopy(resolve)
        end
        if !labels_off
            ct = Dict{String,Any}("text" => _vl_header_label(v),
                                  "fontSize" => 10, "fontWeight" => "normal")
            _map_header_props!(ct, cfg_header, "label")
            _map_header_props!(ct, cheader, "label")
            child["title"] = ct
        end
        push!(children, child)
    end

    newspec = Dict{String,Any}(
        "\$schema" => VL_SCHEMA,
        "hconcat" => children,
    )
    for keep in ("data", "params", "config", "spacing", "usermeta")
        haskey(spec, keep) && (newspec[keep] = spec[keep])
    end
    if title_off
        # Only a figure title the user explicitly set survives; the derived
        # field title stays dropped.
        haskey(spec, "title") && (newspec["title"] = spec["title"])
    else
        ft = Dict{String,Any}("text" => field_title,
                              "fontSize" => 11, "fontWeight" => "bold")
        _map_header_props!(ft, cfg_header, "title")
        _map_header_props!(ft, cheader, "title")
        if !haskey(spec, "title") || spec["title"] === nothing
            # An explicit null figure title suppresses only the FIGURE title —
            # the facet form still showed the field title, so the concat does.
            newspec["title"] = ft
        else
            ut = spec["title"]
            ud = _as_dict(ut)
            if isnothing(ud)
                newspec["title"] = Dict{String,Any}(
                    "text" => ut isa AbstractString ? ut : string(ut),
                    "subtitle" => ft["text"])
            elseif !haskey(ud, "subtitle")
                merged = deepcopy(ud)
                merged["subtitle"] = ft["text"]
                newspec["title"] = merged
            else
                # An explicit subtitle (even null) wins; the field title drops
                # rather than clobbering user content.
                newspec["title"] = ut
            end
        end
    end
    aov = _as_dict(get(spec, "_aov", nothing))
    if !isnothing(aov)
        newspec["_aov"] = merge!(deepcopy(aov), Dict{String,Any}("nFacetCols" => length(children)))
    else
        newspec["_aov"] = Dict{String,Any}("nFacetCols" => length(children))
    end
    empty!(spec)
    merge!(spec, newspec)
    spec
end

"""Translate the props of a categorical/continuous `scales(Color=(; palette, categories, colormap))`
into a VL colour `scale` dict — or an empty dict if the `Scales` object names no `Color` scale.

- `categories` → `scale.domain` (the group ORDER). AoG allows a plain value vector
  (`["reference","Female","Male"]`) or `value => label` relabel pairs; either way the
  domain is the VALUES (relabel targets are dropped — VL relabels via `legend.labelExpr`,
  out of scope here).
- `palette` → `scale.range` when it is an explicit colour vector, or `scale.scheme` when it
  is a named Vega scheme (`Symbol`/`String`, e.g. `:tableau10`).
- `colormap` → `scale.scheme` (the continuous-colour spelling of a named scheme).
- `colorrange` → `scale.domain` (the continuous-colour value range, e.g. `(0.0, 1.0)`)."""
function _color_scale_props_to_vl(props)
    vl_scale = Dict{String,Any}()
    if haskey(props, :categories)
        cats = props[:categories]
        vl_scale["domain"] = [c isa Pair ? first(c) : c for c in cats]
    end
    if haskey(props, :palette)
        pal = props[:palette]
        if pal isa Symbol || pal isa AbstractString
            vl_scale["scheme"] = string(pal)
        else
            vl_scale["range"] = collect(pal)
        end
    end
    haskey(props, :colormap) && (vl_scale["scheme"] = string(props[:colormap]))
    haskey(props, :colorrange) && (vl_scale["domain"] = collect(props[:colorrange]))
    vl_scale
end

"""Extract the VL colour `scale` dict from a `scales(Color=...)` object (empty if none)."""
function _scales_to_color_scale(sc::AlgebraOfGraphics.Scales)
    props = get(sc.dict, :Color, nothing)
    isnothing(props) && return Dict{String,Any}()
    _color_scale_props_to_vl(props)
end

"""Merge a colour `scale` dict into every colour encoding that carries a `field`,
recursing through layered / faceted sublayers.

Field-LESS colour encodings are deliberately SKIPPED. A layered analysis such as
`pointinterval()` draws its median dot with a fixed white fill and NO colour field
(`src/analysis_to_vl.jl` `_interval_point_layer`); broadcasting a colour override into
that layer (what a raw `config(encoding=Dict("color"=>…))` does) injects a bare
field-less colour encoding that Vega-Lite drops with a warning. Scoping to
field-bearing colour encodings pins the palette/domain on the data-bearing layers only,
leaving the deliberate field-less layer untouched."""
function _merge_color_scale!(spec::Dict, color_scale::Dict; channel::String="color")
    isempty(color_scale) && return
    enc = _as_dict(get(spec, "encoding", nothing))
    if !isnothing(enc)
        col = _as_dict(get(enc, channel, nothing))
        if !isnothing(col) && haskey(col, "field")
            existing = get!(col, "scale", Dict{String,Any}())
            existing isa Dict ? merge!(existing, color_scale) : (col["scale"] = copy(color_scale))
        end
    end
    if haskey(spec, "layer")
        for sub in spec["layer"]; sub isa Dict && _merge_color_scale!(sub, color_scale; channel); end
    end
    if haskey(spec, "spec") && spec["spec"] isa Dict
        _merge_color_scale!(spec["spec"], color_scale; channel)
    end
    return
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
function _apply_scales_sugar!(spec, s::AlgebraOfGraphics.Scales)
    # X/Y/Z axis scales broadcast into every matching positional encoding.
    override = _scales_to_encoding_override(s)
    isempty(override) || _merge_encoding_config!(spec, override)
    # A `Color` scale (palette/categories/colormap) is applied ONLY to colour
    # encodings that carry a `field` — never broadcast onto a field-less layer.
    _merge_color_scale!(spec, _scales_to_color_scale(s))
    marker = get(s.dict, :Marker, nothing)
    if !isnothing(marker)
        shape_scale = Dict{String,Any}()
        if haskey(marker, :categories)
            shape_scale["domain"] = [c isa Pair ? first(c) : c for c in marker[:categories]]
        end
        if haskey(marker, :palette)
            shape_scale["range"] = [string(m) for m in marker[:palette]]
        end
        _merge_color_scale!(spec, shape_scale; channel="shape")
    end
    _merge_facet_sorts!(spec, _scales_to_facet_sorts(s))
    spec
end

# `categories` is AoG's categorical-scale order; `value => label` pairs contribute
# their raw value, matching the Colour-scale translation.
_scales_categories(props) = map(c -> c isa Pair ? first(c) : c, props[:categories])

"""Extract facet-order arrays from AoG facet scale overrides.

`scales(Row=(; categories=[...]))` and `scales(Col=(; categories=[...]))` map directly to
the VL row/column facet channels. AoG's `Layout` scale is one wrap dimension; on a wrap
facet it maps to `facet.field`, and on a single row/column facet it maps to that channel.
When both grid channels exist, `Layout` is ambiguous and is ignored with a warning.
"""
function _scales_to_facet_sorts(s::AlgebraOfGraphics.Scales)
    sorts = Dict{String,Any}()
    for (key, channel) in ((:Row, "row"), (:Col, "column"), (:Column, "column"))
        props = get(s.dict, key, nothing)
        !isnothing(props) && haskey(props, :categories) && (sorts[channel] = _scales_categories(props))
    end
    props = get(s.dict, :Layout, nothing)
    if !isnothing(props) && haskey(props, :categories)
        sorts["layout"] = _scales_categories(props)
    end
    sorts
end

"""Merge explicit facet-order arrays into field-bearing facet channels."""
function _merge_facet_sorts!(spec::Dict, sorts::Dict)
    isempty(sorts) && return
    for (channel, order) in sorts
        _merge_facet_sort!(spec, channel, order)
    end
end

function _merge_facet_sort!(spec::Dict, channel::String, order)
    facet = _as_dict(get(spec, "facet", nothing))
    encoding = _as_dict(get(spec, "encoding", nothing))
    target = nothing
    if !isnothing(facet)
        if channel == "layout"
            if haskey(facet, "field")
                target = _as_dict(facet)
            else
                available = String[ch for ch in ("row", "column") if
                    haskey(facet, ch) && haskey(_as_dict(facet[ch]), "field")]
                if length(available) == 1
                    target = _as_dict(facet[only(available)])
                elseif length(available) > 1
                    @warn "AlgebraOfVega: `scales(Layout=(; categories=...))` is ambiguous with both row= and col= facets; use scales(Row=...)/scales(Col=...)." maxlog=1
                end
            end
        elseif haskey(facet, channel)
            target = _as_dict(facet[channel])
        end
    elseif !isnothing(encoding) && haskey(encoding, channel)
        target = _as_dict(encoding[channel])
    end
    isnothing(target) && return
    haskey(target, "field") || return
    target["sort"] = copy(order)
    spec
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

function to_vegalite(v::VegaSpec; interactive::Bool=true)
    spec = _base_vegalite(v.drawable)
    select_fields = nothing
    col_yscales = nothing
    if !isnothing(v.config)
        props = v.config.properties
        # First pass: apply AoG-style sugar (scales, facet) so user-supplied
        # `encoding=Dict(...)` in the second pass can still override on conflict.
        haskey(props, :scales) && _apply_scales_sugar!(spec, props[:scales])
        if haskey(props, :scales)
            sc = _as_scales(props[:scales])
            isnothing(sc) || (col_yscales = _scales_column_y_scales(sc))
        end
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
            elseif sk == "config" && !isnothing(_as_dict(val))
                # Deep-merge a user `config(config=…)` Dict into the base config
                # rather than replacing it. The base config now carries the
                # no-truncate `labelLimit` defaults (and any `font_scale` sizes),
                # so a wholesale replace would silently drop them — re-enabling
                # truncation just because the user set some unrelated config key.
                _deep_merge_dict!(get!(spec, "config", Dict{String,Any}()), _as_dict(val))
            else
                spec[sk] = val
            end
        end
    end
    if !isnothing(select_fields)
        add_select_filters!(spec, v.drawable, select_fields)
    end
    auto_legend = interactive && !_has_vl_params(spec)
    interactive && add_auto_interactivity!(spec)
    # Per-column Y scales re-lower the finished faceted spec into an hconcat of
    # per-column facet views. Runs last among the lowerings so child copies
    # inherit select filters (moved per child) and auto-interactivity params
    # (inner layers) as built.
    isnothing(col_yscales) || _per_column_y_hconcat!(spec, col_yscales)
    # Facet sorts can arrive via config — `scales(Row/Col/Layout=categories)`
    # sugar or a raw `encoding.sort` override — AFTER the inner lowering already
    # ran the densifier on the unsorted spec. Re-run it so a sparse row×column
    # grid never meets a sort (snag `facet-column-sor-9904da1f`); a no-op on
    # hconcat tops, unsorted specs, and already-dense grids.
    _densify_facet_sort!(spec)
    auto_legend && _add_auto_legend_interactivity!(spec)
    spec
end

"""
    to_vegalite(spec, scales; interactive=true) -> Dict{String,Any}

Mirror of `AlgebraOfGraphics.draw(spec, scales(...))`: lower `spec` (a `Layer`,
`Layers`, or `VegaSpec`) to a Vega-Lite dict, then apply the AoG `Scales` override
to it. This is the second-positional-argument form; `config(scales=scales(...))`
applies the identical override inline.

Handles X/Y/Z axis scales (log/log2/log10/sqrt/symlog + `nice`/`zero`/`domain`/
`clamp`/`constant`) and a categorical/continuous `Color` scale — `palette`
(explicit colours or a named scheme), `categories` (domain/group ORDER), `colormap`
(named scheme), `colorrange` (continuous value range). The `Color` override is merged
only into colour encodings that carry a `field`, so a layer with a deliberate
field-less colour (e.g. a `pointinterval()` median dot) is never given a bare,
VL-dropped colour encoding.
"""
function to_vegalite(v, sc::AlgebraOfGraphics.Scales; interactive::Bool=true)
    spec = to_vegalite(v; interactive)
    _apply_scales_sugar!(spec, sc)
    col = _scales_column_y_scales(sc)
    isnothing(col) || _per_column_y_hconcat!(spec, col)
    # The sugar above can add a facet sort after the inner lowering densified
    # (or skipped an unsorted spec) — re-run so a sparse grid never meets a
    # sort (snag `facet-column-sor-9904da1f`).
    _densify_facet_sort!(spec)
    haskey(get(spec, "_aov", Dict()), "legendInteraction") &&
        _add_auto_legend_interactivity!(spec)
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

const _AUTO_LEGEND_MODE = :highlight

# Walk composition nodes, carrying inherited data/encoding into each unit.
# The units belong to the fresh lowering output; caller tables remain read-only.
function _legend_units!(out, node::Dict; data=nothing, encoding=Dict{String,Any}())
    data = get(node, "data", data)
    enc = merge(encoding, get(node, "encoding", Dict{String,Any}()))
    children = Any[]
    haskey(node, "spec") && push!(children, node["spec"])
    for key in ("layer", "hconcat", "vconcat", "concat")
        append!(children, get(node, key, Any[]))
    end
    if isempty(children)
        haskey(node, "mark") && push!(out, (; unit=node, data, encoding=enc))
    else
        for child in children
            _legend_units!(out, child; data, encoding=enc)
        end
    end
    out
end

function _has_vl_params(node::Dict)
    haskey(node, "params") && return true
    haskey(node, "spec") && _has_vl_params(node["spec"]) && return true
    any(key -> any(_has_vl_params, get(node, key, Any[])),
        ("layer", "hconcat", "vconcat", "concat"))
end

# Clear only our own generated definitions. Required when a later lowering or
# the channel picker copies/remaps units; explicit user parameters are untouched.
function _clear_auto_legend!(unit::Dict)
    meta = pop!(unit, "_aovLegend", nothing)
    isnothing(meta) && return
    if haskey(unit, "params")
        unit["params"] = [p for p in unit["params"] if get(p, "name", nothing) ∉ meta["params"]]
        isempty(unit["params"]) && delete!(unit, "params")
    end
    if meta["dimmed"]
        if isnothing(meta["opacity"])
            delete!(unit["encoding"], "opacity")
        else
            unit["encoding"]["opacity"] = meta["opacity"]
        end
    end
    if haskey(meta, "domain")
        color = get(unit["encoding"], "color", nothing)
        scale = color isa AbstractDict ? get(color, "scale", nothing) : nothing
        if scale isa AbstractDict && get(scale, "domain", nothing) == meta["domain"]
            delete!(color["scale"], "domain")
            isempty(color["scale"]) && delete!(color, "scale")
        end
    end
    if meta["filtered"]
        unit["transform"] = meta["transform"]
        isempty(unit["transform"]) && delete!(unit, "transform")
    end
end

_legend_has_field(value, field) = false
_legend_has_field(value::AbstractDict, field) =
    get(value, "field", nothing) == field || any(v -> _legend_has_field(v, field), values(value))
_legend_has_field(value::AbstractVector, field) = any(v -> _legend_has_field(v, field), value)

function _legend_predicate(names, fields)
    Dict{String,Any}("and" => Any[Dict{String,Any}("or" => Any[
        "!isValid(datum[" * JSON.json(field) * "])" ,
        Dict{String,Any}("param" => name, "empty" => true)])
        for (name, field) in zip(names, fields)])
end

function _apply_legend_response!(::Val{:highlight}, unit, enc, predicate, meta)
    opacity = get(enc, "opacity", nothing)
    opacity isa AbstractDict && haskey(opacity, "condition") && return
    # Preserve data-driven opacity, existing conditions, and pad suppression.
    base = isnothing(opacity) ? get(something(_as_dict(get(unit, "mark", nothing)), Dict()), "opacity", 1) :
        get(something(_as_dict(opacity), Dict()), "value", nothing)
    base isa Real || return
    meta["dimmed"] = true
    enc["opacity"] = Dict{String,Any}("condition" => Dict{String,Any}(
        "test" => predicate, "value" => base), "value" => 0.15 * base)
end

function _apply_legend_response!(::Val{:filter}, unit, enc, predicate, meta)
    meta["filtered"] = true
    unit["transform"] = vcat(meta["transform"], Any[Dict{String,Any}("filter" => predicate)])
end

function _add_auto_legend_interactivity!(spec::Dict; mode=_AUTO_LEGEND_MODE)
    # One owner per categorical color field, including layer-local encodings.
    # A unit-owned selection binds the shared legend without VL cloning tuple
    # signals into every sibling layer. Its global predicate spans all facets.
    units = _legend_units!(Any[], spec)
    foreach(info -> _clear_auto_legend!(info.unit), units)
    units = _legend_units!(Any[], spec)
    owners = Dict{String,Any}()
    fields = String[]
    for info in units
        _is_composite_mark(info.unit) && continue
        color = _as_dict(get(info.encoding, "color", nothing))
        isnothing(color) && continue
        get(color, "type", "") in ("nominal", "ordinal") || continue
        haskey(color, "field") || continue
        any(k -> haskey(color, k), ("aggregate", "bin", "timeUnit")) && continue
        get(color, "legend", true) === nothing && continue
        get(color, "scale", true) === nothing && continue
        field = string(color["field"])
        haskey(owners, field) && continue
        owners[field] = info.unit
        push!(fields, field)
    end
    isempty(fields) && return spec
    names = [i == 1 ? "legend_selection" : "legend_selection_$i" for i in eachindex(fields)]
    get!(spec, "_aov", Dict{String,Any}())["legendInteraction"] = string(mode)
    for info in units
        unit = info.unit
        _is_composite_mark(unit) && continue
        rows = isnothing(info.data) ? Any[] : get(info.data, "values", Any[])
        member = [i for i in eachindex(fields) if _legend_has_field(info.encoding, fields[i]) ||
            any(row -> row isa AbstractDict && haskey(row, fields[i]), rows)]
        isempty(member) && continue
        enc = Dict{String,Any}(info.encoding)
        unit["encoding"] = enc
        meta = Dict{String,Any}("params" => String[], "dimmed" => false, "filtered" => false,
            "opacity" => deepcopy(get(enc, "opacity", nothing)),
            "transform" => deepcopy(get(unit, "transform", Any[])))
        unit["_aovLegend"] = meta
        color = _as_dict(get(enc, "color", nothing))
        if mode == :filter && !isnothing(color) && haskey(color, "field") &&
                get(color, "scale", true) !== nothing &&
                !haskey(get(color, "scale", Dict()), "domain")
            field = string(color["field"])
            domain = unique(Any[row[field] for peer in units for row in
                (isnothing(peer.data) ? Any[] : get(peer.data, "values", Any[]))
                if row isa AbstractDict && haskey(row, field) && !isnothing(row[field])])
            if !isempty(domain)
                color = Dict{String,Any}(color)
                generated_domain = Dict("unionWith" => domain)
                scale = Dict{String,Any}(get(color, "scale", Dict()))
                scale["domain"] = generated_domain
                color["scale"] = scale
                enc["color"] = color
                meta["domain"] = deepcopy(generated_domain)
            end
        end
        for i in member
            owners[fields[i]] === unit || continue
            push!(get!(unit, "params", Any[]), Dict{String,Any}("name" => names[i],
                "select" => Dict{String,Any}("type" => "point", "fields" => [fields[i]]),
                "bind" => "legend"))
            push!(meta["params"], names[i])
        end
        _apply_legend_response!(Val(mode), unit, enc,
            _legend_predicate(names[member], fields[member]), meta)
    end
    spec
end

"""
    add_auto_interactivity!(spec)

Add zoom/pan and point hover parameters without overriding user parameters.
Legend selection is added separately after facet/concat lowering, so a selection
has exactly one unit owner even when per-column scale lowering copies layers.
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
to_vegalite(d::Dict; interactive::Bool=true) = d
