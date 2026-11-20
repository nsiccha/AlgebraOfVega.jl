# Per-panel axis titles: `config(facet = (; ylabels = :quantity, xlabels = :col))`.
#
# A faceted figure whose panels show different quantities on unlinked axes titles
# each panel's own axis with that panel's value of a column: the facet column
# itself (its header text, and the header is then left out because it would
# repeat the title) or any other column holding one value per panel, such as a
# quantity with its unit beside an output's name in the header.
#
# Vega-Lite (5.23) accepts an expression as an axis title and hands it to each
# facet cell's own axis as a Vega signal. Inside a cell, `parent[field]` is the
# panel's facet value, and `data('facet')` the panel's rows (`concat_<k>_facet`
# in the k-th child of a per-column-Y `hconcat`), so the title is read when Vega
# draws the panel and follows `update_spec`, `replace_data` and rows the browser
# computes. Rows a summary computed in Julia lack the column, so they get it from
# the panel's own rows here. The browser runtime names the tooltip's estimate row,
# a plain mark's value row and the readout's series by the same title
# (`_panelTooltipValue`, `_panelTitle` in vendor/aov-runtime.js), from the
# `_aov.panelLabels` record this pass writes. Design: decision
# `AlgebraOfVega:snag.facet-panels-can-13c4e53c/decisions/2026-11-19T13-20-11-057-08wsvrj`.

const _PANEL_LABEL_KEYS = (:xlabels => "x", :ylabels => "y")

# The columns a figure asks to title its panels' axes with, by channel.
_panel_label_opts(_) = Dict{String,String}()
_panel_label_opts(v::VegaSpec) = isnothing(v.config) ? Dict{String,String}() :
    _panel_label_opts(get(v.config.properties, :facet, nothing))
function _panel_label_opts(nt::NamedTuple)
    out = Dict{String,String}()
    for (key, ch) in _PANEL_LABEL_KEYS
        col = get(nt, key, nothing)
        isnothing(col) && continue
        col isa Union{Symbol,AbstractString} && !isempty(string(col)) || throw(ArgumentError(
            "AlgebraOfVega: `config(facet=(; $key=…))` names the column whose value titles each " *
            "facet panel's $ch axis, as a Symbol or String (for example `$key=:quantity`); got $(repr(col))."))
        out[ch] = string(col)
    end
    out
end

# The facet keys AlgebraOfGraphics does not know, which `sdraw` takes out of
# `config(facet=…)` before it calls AoG's `draw`.
_without_panel_label_keys(nt::NamedTuple) =
    NamedTuple(k => v for (k, v) in pairs(nt) if !(k in first.(_PANEL_LABEL_KEYS)))

# The facet fields one facet view partitions its rows by: the facet operator's
# wrap field or row/column fields, or a single view's facet encodings.
function _view_facet_defs(view::Dict)
    defs = Pair{Symbol,Dict}[]
    facet = _as_dict(get(view, "facet", nothing))
    if !isnothing(facet)
        haskey(facet, "field") && push!(defs, :wrap => facet)
        for ch in ("row", "column")
            d = _as_dict(get(facet, ch, nothing))
            !isnothing(d) && haskey(d, "field") && push!(defs, :grid => d)
        end
        return defs
    end
    enc = _as_dict(get(view, "encoding", nothing))
    isnothing(enc) && return defs
    for ch in _FACET_ENCODING_CHANNELS
        d = _as_dict(get(enc, ch, nothing))
        !isnothing(d) && haskey(d, "field") && push!(defs, (ch == "facet" ? :wrap : :grid) => d)
    end
    defs
end
_view_facet_fields(view::Dict) = unique!([string(d["field"]) for (_, d) in _view_facet_defs(view)])

# Every inline row set of a lowered spec: `data.values` here and in its layers,
# inner spec and concat children.
function _inline_row_sets!(out, node::AbstractDict)
    data = _as_dict(get(node, "data", nothing))
    vals = isnothing(data) ? nothing : get(data, "values", nothing)
    vals isa AbstractVector && push!(out, vals)
    for key in ("layer", "hconcat", "vconcat", "concat")
        kids = get(node, key, nothing)
        kids isa AbstractVector && foreach(k -> k isa AbstractDict && _inline_row_sets!(out, k), kids)
    end
    inner = _as_dict(get(node, "spec", nothing))
    isnothing(inner) || _inline_row_sets!(out, inner)
    out
end
_inline_row_sets!(out, _) = out

# How a value reads as a panel key: a facet field holds the same value in the
# Julia table and, written by `_vl_safe`, in the lowered rows.
_panel_key_part(v) = string(v)
_panel_key_part(v::AbstractString) = String(v)
_panel_value(v) = v === nothing || v === missing || (v isa AbstractFloat && isnan(v)) ? nothing : v

# Each panel's label, keyed by its facet values: from the figure's tables (which
# hold the column also where a summary dropped it) and from the lowered rows
# (which hold the picker's combined facet columns). A panel whose rows give two
# labels is an error: its axis takes one title.
function _panel_label_map(tables, row_sets, fields, col, key_name)
    seen = Dict{Vector{String},Any}()
    function note!(key, label)
        label = _panel_value(label)
        isnothing(label) && return
        prev = get(seen, key, nothing)
        if isnothing(prev)
            seen[key] = label
        elseif string(prev) != string(label)
            panel = join(("$f = $(repr(k))" for (f, k) in zip(fields, key)), ", ")
            throw(ArgumentError("AlgebraOfVega: `config(facet=(; $key_name=:$col))` titles each facet panel's axis " *
                "with the panel's value of `$col`, but the panel $panel has rows with $(repr(string(prev))) and " *
                "$(repr(string(label))). Give `$col` one value per panel, or name another column."))
        end
    end
    for t in tables
        names = Set(string.(Tables.columnnames(t)))
        (col in names && all(in(names), fields)) || continue
        cols = [Tables.getcolumn(t, Symbol(f)) for f in fields]
        labels = Tables.getcolumn(t, Symbol(col))
        for i in eachindex(labels)
            note!([_panel_key_part(c[i]) for c in cols], labels[i])
        end
    end
    for rows in row_sets, r in rows
        r isa AbstractDict && all(f -> haskey(r, f), fields) || continue
        note!([_panel_key_part(r[f]) for f in fields], get(r, col, nothing))
    end
    seen
end

# Whether any of the figure's tables or rows has the column at all.
function _has_column(tables, row_sets, col)
    any(t -> col in string.(Tables.columnnames(t)), tables) && return true
    any(rows -> any(r -> r isa AbstractDict && haskey(r, col), rows), row_sets)
end

# The tables of the figure's layers (pregrouped data is not a table).
function _panel_label_tables(v)
    out = Any[]
    for l in something(_spec_layers_or_nothing(_spec_drawable(v)), [])
        l isa AlgebraOfGraphics.Layer || continue
        is_pregrouped(l) && continue
        t = extract_data(l)
        isnothing(t) || !Tables.istable(t) || push!(out, Tables.columns(t))
    end
    out
end

# A Vega expression text for a JavaScript string.
_js_string(s) = _vl_json(string(s))

# The panel's title, or the encoding's own title where the panel has none.
function _panel_title_expr(col, fields, dataset, fallback)
    pick = col in fields ? "parent[$(_js_string(col))]" :
        "extent(pluck(data($(_js_string(dataset))), $(_js_string(col))))[0]"
    "isValid($pick) && $pick !== '' ? '' + $pick : $(_js_string(fallback))"
end

# The title an encoding shows without per-panel labels.
_static_title(enc::Dict) = let t = get(enc, "title", :absent)
    t === :absent ? string(get(enc, "field", "")) : t === nothing ? "" : string(t)
end

# Hide the header of the facet channel that holds the label column: each axis
# already says it. A wrap facet's labels are its cells' titles, which Vega-Lite
# 5.23 keeps under `labels: false`, so they are emptied and take no room.
function _hide_panel_header!(kind::Symbol, def::Dict)
    haskey(def, "header") && isnothing(def["header"]) && return
    header = something(_as_dict(get(def, "header", nothing)), Dict{String,Any}())
    if kind === :wrap
        merge!(header, Dict{String,Any}("labelExpr" => "''", "labelFontSize" => 0, "labelPadding" => 0, "title" => nothing))
    else
        merge!(header, Dict{String,Any}("labels" => false, "title" => nothing))
    end
    def["header"] = header
end

# Title one facet view's `ch` axes with the panels' labels; returns the static
# titles it replaced and the fields it titled, or `nothing` when the view has no
# facet (an unfaceted figure has one panel and keeps its title, as AoG keeps
# `linkyaxes` without effect there).
function _panel_labels_view!(view::Dict, ch, col, dataset, labels, row_sets)
    fields = _view_facet_fields(view)
    isempty(fields) && return nothing
    if !(col in fields)
        # A summary computed in Julia (a ribbon or interval from raw draws, a
        # faceted density) keeps only its key columns: its rows take the
        # panel's label from the others, so `data('facet')` finds it in every
        # panel and the tooltip names the hovered row's panel.
        for rows in row_sets, r in rows
            r isa AbstractDict && all(f -> haskey(r, f), fields) || continue
            isnothing(_panel_value(get(r, col, nothing))) || continue
            label = get(labels, [_panel_key_part(r[f]) for f in fields], nothing)
            isnothing(label) || (r[col] = _vl_safe(label))
        end
    end
    # The encodings whose axis takes the panel's title: not one with `axis: null`
    # (no axis) or an authored (or deliberately empty) axis title.
    encs = Dict[]
    _foreach_encoding(view, ch, enc -> haskey(enc, "field")) do enc
        axis = get(enc, "axis", Dict{String,Any}())
        axis isa Dict && !haskey(axis, "title") && push!(encs, enc)
    end
    isempty(encs) && return nothing
    # One expression on every layer, so Vega-Lite merges one axis title. Where a
    # panel has no label, it reads as the layers' titles read without labels
    # (Vega-Lite joins different layer titles with ", ").
    titles = unique!([_static_title(enc) for enc in encs])
    expr = _panel_title_expr(col, fields, dataset, join(filter(!isempty, titles), ", "))
    for enc in encs
        axis = get(enc, "axis", Dict{String,Any}())
        axis["title"] = Dict{String,Any}("expr" => expr)
        enc["axis"] = axis
    end
    titled = unique!([string(enc["field"]) for enc in encs])
    # Each panel draws its own axis, whether or not its scale is linked.
    resolve = Dict{String,Any}(string(k) => v for (k, v) in pairs(get(view, "resolve", (;))))
    axes = Dict{String,Any}(string(k) => v for (k, v) in pairs(get(resolve, "axis", (;))))
    get!(axes, ch, "independent")
    resolve["axis"] = axes
    view["resolve"] = resolve
    if col in fields
        for (kind, def) in _view_facet_defs(view)
            string(def["field"]) == col && _hide_panel_header!(kind, def)
        end
    end
    (; titles, titled, fields)
end

"""Title each facet panel's own x/y axis with the panel's value of the column
`config(facet=(; xlabels, ylabels))` names (see the top of src/panel_labels.jl).
Runs on both drawings of a ribbon with an interval view, after every lowering
path (`_finish_vegalite!`), so a per-column-Y `hconcat` built by the positional
`to_vegalite(spec, scales(…))` form is titled per child too."""
_apply_panel_labels!(vl, _) = vl
function _apply_panel_labels!(vl::Dict, v::VegaSpec)
    opts = _panel_label_opts(v)
    isempty(opts) && return vl
    tables = _panel_label_tables(v)
    row_sets = _inline_row_sets!(Any[], vl)
    _is_panel_concat(vl) && return _panel_labels_stack!(vl, opts, tables, row_sets)
    children = get(vl, "hconcat", nothing)
    views = children isa AbstractVector ?
        [(c, "concat_$(k - 1)_facet") for (k, c) in enumerate(children) if c isa Dict] : [(vl, "facet")]
    meta = Dict{String,Any}()
    for ch in sort!(collect(keys(opts)))
        col = opts[ch]
        key_name = ch == "y" ? "ylabels" : "xlabels"
        _has_column(tables, row_sets, col) || throw(ArgumentError(
            "AlgebraOfVega: `config(facet=(; $key_name=:$col))` names no column of the figure's tables. " *
            "Name a column that holds each panel's $ch-axis title, such as the facet column itself."))
        titles, titled, facets = String[], String[], String[]
        for (view, dataset) in views
            fields = _view_facet_fields(view)
            isempty(fields) && continue
            labels = col in fields ? Dict{Vector{String},Any}() :
                _panel_label_map(tables, row_sets, fields, col, key_name)
            done = _panel_labels_view!(view, ch, col, dataset, labels, row_sets)
            isnothing(done) && continue
            append!(titles, done.titles); append!(titled, done.titled); append!(facets, done.fields)
            # A per-column child's title is its column value; the axis says it now.
            children isa AbstractVector && col in fields && delete!(view, "title")
        end
        isempty(titled) && continue
        meta[ch] = Dict{String,Any}("field" => col, "facet" => unique!(facets),
            "titles" => unique!(titles), "fields" => unique!(titled))
    end
    isempty(meta) || (get!(Dict{String,Any}, vl, "_aov")["panelLabels"] = meta)
    vl
end

# The panels of a per-row-Y stack or per-wrap-Y concat are not facet cells, so
# each one's axis takes its title as text: the panel's facet value, or its value
# of another column, written as the encodings' title (an authored axis title is
# kept). The panel title (its facet header) leaves when the axis already says it.
function _panel_labels_stack!(vl::Dict, opts, tables, row_sets)
    meta = Dict{String,Any}()
    for ch in sort!(collect(keys(opts)))
        col = opts[ch]
        key_name = ch == "y" ? "ylabels" : "xlabels"
        _has_column(tables, row_sets, col) || throw(ArgumentError(
            "AlgebraOfVega: `config(facet=(; $key_name=:$col))` names no column of the figure's tables. " *
            "Name a column that holds each panel's $ch-axis title, such as the facet column itself."))
        titles, titled, facets = String[], String[], String[]
        labels = nothing    # read once, for the first panel that needs it
        for view in _panel_kids(vl)
            panel = view["_aovPanel"]
            fields = collect(String, keys(panel))
            label = if col in fields
                panel[col]
            else
                isnothing(labels) && (labels = _panel_label_map(tables, row_sets, fields, col, key_name))
                get(labels, [_panel_key_part(panel[f]) for f in fields], nothing)
            end
            encs = Dict[]
            _foreach_encoding(view, ch, enc -> haskey(enc, "field")) do enc
                axis = get(enc, "axis", Dict{String,Any}())
                axis isa Dict && !haskey(axis, "title") && push!(encs, enc)
            end
            isempty(encs) && continue
            append!(titles, _static_title.(encs)); append!(titled, [string(e["field"]) for e in encs])
            append!(facets, fields)
            label = _panel_value(label)
            isnothing(label) && continue
            # The encoding's own title, which its axis shows and the stack's
            # readout heads the panel's series with.
            foreach(enc -> enc["title"] = _vl_header_label(label), encs)
            col in fields && delete!(view, "title")
        end
        isempty(titled) && continue
        meta[ch] = Dict{String,Any}("field" => col, "facet" => unique!(facets),
            "titles" => unique!(titles), "fields" => unique!(titled))
    end
    isempty(meta) || (get!(Dict{String,Any}, vl, "_aov")["panelLabels"] = meta)
    vl
end
