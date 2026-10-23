# --- A coloured ribbon's point-interval view (`lineribbon(...; intervals=…)`) ---
#
# A ribbon coloured by group over a handful of numeric x values (a dose ladder)
# is lowered a second time as the vertical `pointinterval` of the same rows: at
# each x one interval per colour group, dodged by colour. The x axis stays the
# ribbon's (a log scale included), each group's intervals sitting a small
# step from the true x (`_true_x_axis!`); where the x values are too unevenly
# spaced on that axis for the step to stay readable, or the scale is neither
# linear nor log, they sit on evenly spaced x slots instead (`_slot_x_axis!`).
# Both drawings go to the browser, where a "Ribbons | Intervals" control swaps
# them (`AoV.setRibbonView`, vendor/aov-runtime.js); the figure starts in the
# one `intervals=` picks from the overlap of the groups' outer bands.
#
# Both drawings are whole Vega-Lite specs from the same lowering, so every pass
# after it (positional scales, the picker's layer tags, `_embed_spec`'s sizing)
# must reach both. Until `_finish_ribbon_views!` decides, the interval lowering
# rides along as `_aov.ribbonView.pending` and `_each_ribbon_view!` applies a
# pass to both; finished, the spec is the starting view and carries the other
# as `_aov.ribbonView.alt`.

# The coloured ribbon a figure's interval view is drawn from: the figure has
# exactly one ribbon layer, it maps `color=` (and no `detail`), its x is numeric
# and has at most `_RIBBON_INTERVAL_MAX_X` distinct values. `cells` are the
# outer band of each (facet panel, colour group, x), which the overlap score
# reads; `slots` the x values in ascending order. A figure that misses one of
# these gets the condition it misses, as the Symbol `ribbon_view` reports.
function _ribbon_view_source(v)
    layers = _spec_layers_or_nothing(_spec_drawable(v))
    isnothing(layers) && return :no_ribbon
    found = [(i, l, a) for (i, l) in enumerate(layers)
             for a in (extract_transformation(l, LineRibbonAnalysis),
                       extract_transformation(l, PrecomputedRibbonAnalysis))
             if !isnothing(a)]
    isempty(found) && return :no_ribbon
    length(found) == 1 || return :several_ribbons
    index, layer, a = only(found)
    haskey(layer.named, :color) || return :no_color
    isempty(a.detail_fields) || return :detail
    # A ribbon without data or a y does not lower at all.
    table = length(layer.positional) >= 2 ? extract_data(layer) : nothing
    isnothing(table) && return :no_ribbon
    x_field = _field_name(layer.positional[1])
    x_col = Tables.getcolumn(table, Symbol(x_field))
    _ribbon_x_type(x_col) == "quantitative" || return :not_numeric_x
    color_field = _field_name(layer.named[:color])
    _, facet_fields = _extract_facet_info(layer)
    rows, lo, hi = _ribbon_outer_rows(a, layer, table, x_field, color_field, facet_fields)
    cells = NamedTuple{(:panel, :color, :x, :lo, :hi),Tuple{Tuple,Any,Float64,Float64,Float64}}[]
    slots = Dict{Float64,Any}()
    for row in rows
        x = get(row, x_field, nothing)
        _finite_number(x) || continue
        get!(slots, Float64(x), x)
        l, h = get(row, lo, nothing), get(row, hi, nothing)
        (_finite_number(l) && _finite_number(h)) || continue
        push!(cells, (; panel=Tuple(get(row, f, nothing) for f in facet_fields),
                        color=get(row, color_field, nothing), x=Float64(x),
                        lo=Float64(min(l, h)), hi=Float64(max(l, h))))
    end
    # No x value to draw: either none is a number (text), or there are no rows
    # yet, or only missing ones.
    isempty(slots) && return any(x -> !(isnothing(x) || ismissing(x) || (x isa Real && !(x isa Bool))), x_col) ?
        :not_numeric_x : :no_x_values
    length(slots) > _RIBBON_INTERVAL_MAX_X && return :too_many_x
    (; index, analysis=a, x_field, x_title=_field_label(layer.positional[1]), lo, hi, cells,
       slots=Any[slots[k] for k in sort!(collect(keys(slots)))])
end

_finite_number(x) = x isa Real && !(x isa Bool) && isfinite(x)

# The summary rows the ribbon draws, and the names of its outer band's columns.
function _ribbon_outer_rows(a::PrecomputedRibbonAnalysis, layer, table, x_field, color_field, facet_fields)
    table_to_rows(table), string(first(a.bands[1])), string(last(a.bands[1]))
end
function _ribbon_outer_rows(a::LineRibbonAnalysis, layer, table, x_field, color_field, facet_fields)
    p = maximum(a.probs)
    group_field = haskey(layer.named, :group) ? _field_name(layer.named[:group]) : "draw"
    rows = compute_ribbon_summary(table, x_field, _field_name(layer.positional[2]), group_field, [p];
        color_field, facet_fields)
    rows, _vl_prob_field("lo", p), _vl_prob_field("hi", p)
end

# The ribbon's interval view as a figure: the ribbon layer replaced by the
# vertical point-interval of the same rows (computed ones from the same draws,
# `bands=` ones from the same columns), its `group=` dropped. A `visual` on the
# ribbon is dropped too: its fixed colour yields to the colour mapping anyway.
function _ribbon_intervals_spec(v, src)
    layers = collect(_spec_layers_or_nothing(_spec_drawable(v)))
    l = layers[src.index]
    m = AlgebraOfGraphics.mapping(l.positional...; (k => s for (k, s) in pairs(l.named) if k !== :group)...)
    layers[src.index] = AlgebraOfGraphics.Layer(_interval_view_analysis(src.analysis), l.data, m.positional, m.named)
    _wrap_with_config(v, length(layers) == 1 ? only(layers) : reduce(+, layers))
end

_interval_view_analysis(a::LineRibbonAnalysis) = PointIntervalAnalysis(a.probs, :median, a.detail_fields, :vertical)
_interval_view_analysis(a::PrecomputedRibbonAnalysis) = PrecomputedIntervalAnalysis(a.bands, a.detail_fields, :vertical)

# `_lower_vegaspec(v)` with, for a figure that has a ribbon interval view, the
# interval lowering pending in `_aov.ribbonView` (see the top of this file).
function _vegaspec_views(v::VegaSpec; interactive::Bool=true)
    vl = _lower_vegaspec(v; interactive)
    src = _ribbon_view_source(v)
    src isa Symbol && return vl
    alt = _lower_vegaspec(_ribbon_intervals_spec(v, src); interactive)
    get!(Dict{String,Any}, vl, "_aov")["ribbonView"] = Dict{String,Any}("pending" => alt, "source" => src)
    vl
end
_vegaspec_views(v::Union{AlgebraOfGraphics.Layer,AlgebraOfGraphics.Layers}; interactive::Bool=true) =
    _vegaspec_views(vlspec(v); interactive)

_ribbon_view_meta(vl::Dict) = let aov = _as_dict(get(vl, "_aov", nothing))
    isnothing(aov) ? nothing : _as_dict(get(aov, "ribbonView", nothing))
end
_ribbon_view_meta(_) = nothing

# `vl` without its other drawing and the control's metadata, for output that
# shows one drawing (`vsave` writes the starting view). Shares the rest with `vl`.
function _without_ribbon_view(vl::Dict)
    isnothing(_ribbon_view_meta(vl)) && return vl
    aov = copy(vl["_aov"])
    delete!(aov, "ribbonView")
    out = copy(vl)
    isempty(aov) ? delete!(out, "_aov") : (out["_aov"] = aov)
    out
end
_without_ribbon_view(x) = x

# Apply the pass `f(spec)` to `vl` and to the other drawing it carries.
function _each_ribbon_view!(f, vl::Dict)
    f(vl)
    rv = _ribbon_view_meta(vl)
    isnothing(rv) && return vl
    for key in ("pending", "alt")
        other = _as_dict(get(rv, key, nothing))
        isnothing(other) || f(other)
    end
    vl
end

# Decide a pending interval view and return the spec to use: the starting view,
# carrying the other as `_aov.ribbonView.alt`, with the start, the overlap score
# and the `:auto` threshold for the runtime's control. On slots, the view is
# dropped when another layer's x values miss them (an interval view cannot place
# it); the ribbon spec is then returned without any `ribbonView`.
function _finish_ribbon_views!(vl::Dict)
    rv = _ribbon_view_meta(vl)
    (isnothing(rv) || !haskey(rv, "pending")) && return vl
    alt, src = rv["pending"], rv["source"]
    aov = vl["_aov"]
    delete!(aov, "ribbonView")
    isempty(aov) && delete!(vl, "_aov")
    _true_x_axis!(alt, vl, src) || _slot_x_axis!(alt, src) || return vl
    score = _ribbon_overlap_score(vl, src)
    iv = src.analysis.intervals
    start = iv.start === :auto ? (score > iv.threshold ? "intervals" : "ribbons") : string(iv.start)
    meta(view) = Dict{String,Any}("view" => view, "start" => start, "score" => round(score; digits=3),
        "threshold" => iv.start === :auto ? iv.threshold : nothing)
    shown, other = start == "ribbons" ? (vl, alt) : (alt, vl)
    get!(Dict{String,Any}, other, "_aov")["ribbonView"] = meta(start == "ribbons" ? "intervals" : "ribbons")
    shown_meta = meta(start)
    shown_meta["alt"] = other
    get!(Dict{String,Any}, shown, "_aov")["ribbonView"] = shown_meta
    shown
end

# Visit every spec of a Vega-Lite tree that has an encoding, with the chain of
# specs from the root down to it (data and transforms are inherited along it).
function _each_encoded(f, d::Dict, chain=Any[])
    chain = Any[chain..., d]
    haskey(d, "encoding") && f(d, chain)
    for key in ("layer", "concat", "hconcat", "vconcat")
        sub = get(d, key, nothing)
        sub isa AbstractVector || continue
        for s in sub
            sd = _as_dict(s)
            isnothing(sd) || _each_encoded(f, sd, chain)
        end
    end
    inner = _as_dict(get(d, "spec", nothing))
    isnothing(inner) || _each_encoded(f, inner, chain)
    nothing
end

# The rows a spec in `chain` draws: the nearest inline data, narrowed to its
# layer's own rows by the `__src` filters `layers_to_vl` gives each layer of a
# merged dataset, without facet pad rows (`__aov_pad`). `nothing` when the rows
# are not inline.
function _chain_rows(chain)
    rows = nothing
    for d in Iterators.reverse(chain)
        dat = _as_dict(get(d, "data", nothing))
        isnothing(dat) && continue
        vals = get(dat, "values", nothing)
        vals isa AbstractVector || return nothing
        rows = vals
        break
    end
    isnothing(rows) && return nothing
    tags = String[]
    for d in chain
        ts = get(d, "transform", nothing)
        ts isa AbstractVector || continue
        for t in ts
            td = _as_dict(t)
            ft = isnothing(td) ? nothing : _as_str(get(td, "filter", nothing))
            m = isnothing(ft) ? nothing : match(r"^datum\.__src === '([^']*)'$", ft)
            isnothing(m) || push!(tags, m[1])
        end
    end
    [r for r in rows if r isa AbstractDict && get(r, _AOV_PAD_FIELD, false) !== true &&
                        all(t -> get(r, "__src", nothing) == t, tags)]
end

# Whether every x (and x2) of the spec `d` lands on a slot: a field whose rows'
# values are all slots (or missing), or no field at all (a pixel value).
function _x_on_slots(d, chain, slotset)
    enc = d["encoding"]
    for ch in ("x", "x2")
        haskey(enc, ch) || continue
        e = _as_dict(enc[ch])
        (isnothing(e) || haskey(e, "datum")) && return false
        f = _as_str(get(e, "field", nothing))
        isnothing(f) && continue
        any(k -> haskey(e, k), ("aggregate", "bin", "timeUnit")) && return false
        rows = _chain_rows(chain)
        isnothing(rows) && return false
        for r in rows
            x = get(r, f, nothing)
            (isnothing(x) || ismissing(x)) && continue
            (_finite_number(x) && Float64(x) in slotset) || return false
        end
    end
    true
end

# The dodge of the interval view on the ribbon's own x axis. Vega-Lite drops an
# `xOffset` on a continuous x, so each interval layer draws `__aov_x`, a
# `calculate` of the true x moved by its colour group's step: added on a linear
# axis, multiplied in (as `exp` of a log step) on a log one. The groups together
# span `_RIBBON_DODGE_SPAN` of the smallest gap between adjacent x values on the
# axis, so neighbouring x values' groups never meet. The recipe rides along as
# `_aov.dodgeX`, from which the runtime rebuilds the expression when the
# picker moves the colour (`_dodgeXExpr`, vendor/aov-runtime.js — the same
# formula as `_ribbon_dodge_expr`).
const _RIBBON_DODGE_FIELD = "__aov_x"
const _RIBBON_DODGE_SPAN = 0.7

# The interval view on the ribbon's x axis: the interval layers' x (the ones the
# lowering dodges with `xOffset`) becomes the dodged `__aov_x`, and every other
# x on the ribbon's x field (observations, dose `VLines`, which the lowering made
# nominal to share the category axis) keeps its field; all of them quantitative
# on the ribbon's x scale, with its x title. Returns false, changing nothing, when the
# ribbon's x scale is neither linear nor log, or the x values are so unevenly
# spaced on it that the closest pair gets less than a quarter of an even share
# of the axis (a dose ladder on a linear axis): evenly spaced slots read better.
function _true_x_axis!(alt::Dict, vl::Dict, src)
    scale = _ribbon_x_scale(vl, src)
    kind = _ribbon_dodge_kind(scale)
    isnothing(kind) && return false
    gap = _ribbon_dodge_gap(src.slots, kind)
    isnothing(gap) && return false
    color = Ref{Any}(nothing)
    _each_encoded(alt) do d, _
        isnothing(color[]) || return
        (_is_interval_x(get(d["encoding"], "x", nothing), src) && haskey(d["encoding"], "xOffset")) || return
        c = _as_dict(get(d["encoding"], "color", nothing))
        isnothing(c) || (color[] = c)
    end
    isnothing(color[]) && return false
    by = string(color[]["field"])
    domain = _ribbon_dodge_domain(Any[c.color for c in src.cells], get(color[], "sort", nothing))
    span = _RIBBON_DODGE_SPAN * gap
    expr = _ribbon_dodge_expr(src.x_field, by, domain, span, kind)
    _each_encoded(alt) do d, _
        enc = d["encoding"]
        e = _as_dict(get(enc, "x", nothing))
        _is_interval_x(e, src) || return
        dodged = haskey(enc, "xOffset")
        delete!(enc, "xOffset")
        x = Dict{String,Any}("field" => dodged ? _RIBBON_DODGE_FIELD : src.x_field,
            "type" => "quantitative", "title" => src.x_title)
        ax = _as_dict(get(e, "axis", nothing))
        if !isnothing(ax)
            ax = copy(ax)
            haskey(ax, "title") && isnothing(ax["title"]) && delete!(ax, "title")
            isempty(ax) || (x["axis"] = ax)
        end
        isnothing(scale) || (x["scale"] = deepcopy(scale))
        enc["x"] = x
        dodged || return
        ts = get(d, "transform", nothing)
        d["transform"] = Any[(ts isa AbstractVector ? ts : Any[])...,
            Dict{String,Any}("calculate" => expr, "as" => _RIBBON_DODGE_FIELD)]
    end
    # The lowering zooms only along a quantitative x; the x is one now.
    _add_x_scale_binding!(alt)
    get!(Dict{String,Any}, alt, "_aov")["dodgeX"] = Dict{String,Any}(
        "field" => src.x_field, "by" => by, "domain" => domain, "span" => span,
        "scale" => string(kind), "as" => _RIBBON_DODGE_FIELD)
    true
end

# An x encoding on the interval lowering's nominal category axis: the ribbon's
# x field, nominal (the lowering makes every layer on that field share it).
_is_interval_x(e, src) = (e = _as_dict(e); !isnothing(e) &&
    get(e, "field", nothing) == src.x_field && get(e, "type", nothing) == "nominal")

# The ribbon drawing's x scale (`scales(X=…)`, a raw `config(encoding=…)`, the
# no-zero default): the first `scale` on an x encoding of the ribbon's x field.
function _ribbon_x_scale(vl::Dict, src)
    found = Ref{Any}(nothing)
    _each_encoded(vl) do d, _
        isnothing(found[]) || return
        e = _as_dict(get(d["encoding"], "x", nothing))
        (isnothing(e) || get(e, "field", nothing) != src.x_field) && return
        s = _as_dict(get(e, "scale", nothing))
        isnothing(s) || (found[] = s)
    end
    found[]
end

# `:linear` or `:log`, the scales the dodge can move along; `nothing` otherwise.
function _ribbon_dodge_kind(scale)
    t = isnothing(scale) ? nothing : get(scale, "type", nothing)
    (isnothing(t) || t == "linear") && return :linear
    t == "log" && return :log
    nothing
end

# The smallest gap between adjacent x values on the axis (natural-log units on
# a log axis), or `nothing` when there is no gap or it is too small to read.
function _ribbon_dodge_gap(slots, kind)
    xs = Float64[Float64(s) for s in slots]
    length(xs) >= 2 || return nothing
    if kind === :log
        all(>(0), xs) || return nothing
        xs = log.(xs)
    end
    gap = minimum(diff(xs))
    gap >= (last(xs) - first(xs)) / (4 * (length(xs) - 1)) ? gap : nothing
end

# The colour groups in the colour scale's order: a sort array's values first,
# in its order, then the rest ascending (Vega-Lite's order for a nominal field).
function _ribbon_dodge_domain(colors, sort)
    present = unique(c for c in colors if !(isnothing(c) || ismissing(c)))
    lead = sort isa AbstractVector ? [s for s in sort if s in present] : Any[]
    rest = [c for c in present if !(c in lead)]
    Any[lead..., (all(c -> c isa Real, rest) ? Base.sort(rest) : Base.sort(rest; by=string))...]
end

# The Vega expression for `__aov_x`; kept in step with `_dodgeXExpr` in
# vendor/aov-runtime.js. A row whose colour is not in `domain` stays at its x.
function _ribbon_dodge_expr(field, by, domain, span, kind)
    f = "datum[" * _vl_json(string(field)) * "]"
    n = length(domain)
    n < 2 && return "isValid($f) ? $f : null"
    k = "indexof(" * _vl_json(domain) * ", datum[" * _vl_json(by) * "])"
    d = "($k < 0 ? 0 : ($k - $((n - 1) / 2)) * $(span / n))"
    "isValid($f) ? " * (kind === :log ? "$f * exp($d)" : "$f + $d") * " : null"
end

# Put every x of the interval view on the ribbon's slots: nominal, the slots as
# its domain in ascending order (a log or other continuous scale, from
# `scales(X=…)` or a raw `config(encoding=…)`, does not apply to slots), and the
# ribbon's x title, which the interval lowering hides on its category axis, and
# level labels. A
# zoom bound to the x scale is dropped: a nominal axis does not zoom. Returns
# false, changing nothing, when some x value is not a slot.
function _slot_x_axis!(alt::Dict, src)
    slotset = Set{Float64}(Float64(s) for s in src.slots)
    ok = Ref(true)
    _each_encoded(alt) do d, chain
        ok[] &= _x_on_slots(d, chain, slotset)
    end
    ok[] || return false
    _each_encoded(alt) do d, _
        e = _as_dict(get(d["encoding"], "x", nothing))
        (isnothing(e) || isnothing(get(e, "field", nothing))) && return
        e["type"] = "nominal"
        e["scale"] = Dict{String,Any}("domain" => copy(src.slots))
        delete!(e, "sort")
        if e["field"] == src.x_field
            # Vega-Lite turns a nominal x axis's labels upright; the slots are
            # short numbers, read like the ribbon's x labels.
            ax = get!(Dict{String,Any}, e, "axis")
            haskey(ax, "title") && isnothing(ax["title"]) && delete!(ax, "title")
            haskey(ax, "labelAngle") || (ax["labelAngle"] = 0)
            src.x_title == src.x_field ? delete!(e, "title") : (e["title"] = src.x_title)
        end
    end
    _drop_x_scale_binding!(alt)
    true
end

function _add_x_scale_binding!(d::Dict)
    ps = get(d, "params", nothing)
    if ps isa AbstractVector
        for p in ps
            pd = _as_dict(p)
            (isnothing(pd) || get(pd, "bind", nothing) != "scales") && continue
            sel = _as_dict(get(pd, "select", nothing))
            encs = isnothing(sel) ? nothing : get(sel, "encodings", nothing)
            encs isa AbstractVector && !("x" in encs) && (sel["encodings"] = Any["x", encs...])
        end
    end
    for key in ("layer", "concat", "hconcat", "vconcat")
        sub = get(d, key, nothing)
        sub isa AbstractVector || continue
        foreach(s -> (sd = _as_dict(s); isnothing(sd) || _add_x_scale_binding!(sd)), sub)
    end
    inner = _as_dict(get(d, "spec", nothing))
    isnothing(inner) || _add_x_scale_binding!(inner)
    d
end

function _drop_x_scale_binding!(d::Dict)
    ps = get(d, "params", nothing)
    if ps isa AbstractVector
        for p in ps
            pd = _as_dict(p)
            (isnothing(pd) || get(pd, "bind", nothing) != "scales") && continue
            sel = _as_dict(get(pd, "select", nothing))
            encs = isnothing(sel) ? nothing : get(sel, "encodings", nothing)
            encs isa AbstractVector && (sel["encodings"] = filter(!=("x"), encs))
        end
        filter!(ps) do p
            pd = _as_dict(p)
            sel = isnothing(pd) ? nothing : _as_dict(get(pd, "select", nothing))
            encs = isnothing(sel) ? nothing : get(sel, "encodings", nothing)
            !(get(something(pd, Dict()), "bind", nothing) == "scales" && encs isa AbstractVector && isempty(encs))
        end
        isempty(ps) && delete!(d, "params")
    end
    for key in ("layer", "concat", "hconcat", "vconcat")
        sub = get(d, key, nothing)
        sub isa AbstractVector || continue
        foreach(s -> (sd = _as_dict(s); isnothing(sd) || _drop_x_scale_binding!(sd)), sub)
    end
    inner = _as_dict(get(d, "spec", nothing))
    isnothing(inner) || _drop_x_scale_binding!(inner)
    d
end

# How far the colour groups' outer bands overlap, as a share of the y range: in
# each facet panel, for each pair of groups, the mean over their shared x of the
# overlap of their outer bands; the largest over panels and pairs. The y range
# is the axis domain when the spec fixes one, else the bands' extent (each
# panel's own under independent y scales); a log y axis is measured in log10.
function _ribbon_overlap_score(vl::Dict, src)
    y = _ribbon_y_scale(vl, src)
    tr(v) = y.log ? (v > 0 ? log10(v) : NaN) : v
    cells = [(; c.panel, c.color, c.x, lo=tr(c.lo), hi=tr(c.hi)) for c in src.cells]
    filter!(c -> isfinite(c.lo) && isfinite(c.hi), cells)
    isempty(cells) && return 0.0
    extent(cs) = maximum(c -> c.hi, cs) - minimum(c -> c.lo, cs)
    fixed = isnothing(y.domain) ? nothing : tr(y.domain[2]) - tr(y.domain[1])
    shared = extent(cells)
    score = 0.0
    for panel in unique(c.panel for c in cells)
        pcells = filter(c -> isequal(c.panel, panel), cells)
        range = something(fixed, y.per_panel ? extent(pcells) : shared)
        (isfinite(range) && range > 0) || continue
        bands = Dict{Any,Dict{Float64,Tuple{Float64,Float64}}}()
        for c in pcells
            get!(Dict{Float64,Tuple{Float64,Float64}}, bands, c.color)[c.x] = (c.lo, c.hi)
        end
        groups = collect(values(bands))
        for i in eachindex(groups), j in (i+1):lastindex(groups)
            xs = intersect(keys(groups[i]), keys(groups[j]))
            isempty(xs) && continue
            overlap = sum(xs) do x
                (lo1, hi1), (lo2, hi2) = groups[i][x], groups[j][x]
                max(0.0, min(hi1, hi2) - max(lo1, lo2)) / range
            end
            score = max(score, overlap / length(xs))
        end
    end
    score
end

# The y scale the ribbon's outer band is drawn on: a fixed two-value domain or
# `nothing`, whether it is a log scale, and whether each facet panel has its own.
function _ribbon_y_scale(vl::Dict, src)
    found = Ref{Any}(nothing)
    _each_encoded(vl) do d, chain
        isnothing(found[]) || return
        enc = d["encoding"]
        y, y2 = _as_dict(get(enc, "y", nothing)), _as_dict(get(enc, "y2", nothing))
        (isnothing(y) || isnothing(y2)) && return
        (get(y, "field", nothing) == src.lo && get(y2, "field", nothing) == src.hi) || return
        found[] = (y, chain)
    end
    isnothing(found[]) && return (; domain=nothing, log=false, per_panel=false)
    y, chain = found[]
    scale = something(_as_dict(get(y, "scale", nothing)), Dict{String,Any}())
    dom = get(scale, "domain", nothing)
    domain = dom isa Union{AbstractVector,Tuple} && length(dom) == 2 && all(_finite_number, dom) ?
        Float64[dom...] : nothing
    independent = haskey(vl, "hconcat") || any(chain) do d
        res = _as_dict(get(d, "resolve", nothing))
        sc = isnothing(res) ? nothing : _as_dict(get(res, "scale", nothing))
        !isnothing(sc) && get(sc, "y", nothing) == "independent"
    end
    (; domain, log=get(scale, "type", nothing) == "log", per_panel=independent)
end

# --- Public API: ribbon_view ---

"""
    ribbon_view(spec; auto_remap=nothing) -> NamedTuple
    ribbon_view(spec, scales(...); auto_remap=nothing) -> NamedTuple

Whether a coloured `lineribbon`/`ribbon` figure gets the "Ribbons | Intervals"
switch, and which drawing it starts in: the facts the switch's tooltip shows,
read from the figure `to_vegalite` lowers from the same arguments (pass the
picker's keywords as `auto_remap` for a figure drawn through the channel
picker). Returns `(; offered, why_not, start, score, threshold)`:

- `offered`: whether the figure carries the switch.
- `why_not`: `nothing` when it does; otherwise the condition the figure misses.
  `:no_ribbon` (no `lineribbon`/`ribbon` layer), `:several_ribbons` (more than
  one), `:no_color` (the ribbon maps no `color=`), `:detail` (a `detail=`
  split), `:not_numeric_x` (a date or text x), `:no_x_values` (no rows with an x
  value yet), `:too_many_x` (more than $(_RIBBON_INTERVAL_MAX_X) distinct x
  values across the figure) or `:x_off_slots` (the point-interval drawing puts
  the x values on evenly spaced slots, and another layer's x cannot sit on one:
  a value that is not one of the ribbon's x values, or a binned, aggregated or
  `datum` x).
- `start`: `:ribbons` or `:intervals`, the drawing the figure starts in.
- `score`: the overlap score the tooltip shows (to three decimals): how far the
  colour groups' outer bands overlap, as a share of the y range. It is measured
  whatever `intervals=` says, so a fixed start can be calibrated too.
- `threshold`: the share `intervals=:auto` compared `score` against;
  `nothing` when `intervals=true`/`false` fixes the start.

`start`, `score` and `threshold` are `nothing` when the switch is not offered.

    fig = data(summary) * mapping(:dose, :median; color=:group) *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75])
    v = ribbon_view(fig)
    v.start === :intervals   # true when v.score > v.threshold
"""
ribbon_view(spec::Union{AlgebraOfGraphics.Layer,AlgebraOfGraphics.Layers,VegaSpec};
            auto_remap::Union{Nothing,NamedTuple}=nothing) =
    _ribbon_view_facts(to_vegalite(spec; auto_remap), spec, auto_remap)
ribbon_view(spec::Union{AlgebraOfGraphics.Layer,AlgebraOfGraphics.Layers,VegaSpec}, sc::AlgebraOfGraphics.Scales;
            auto_remap::Union{Nothing,NamedTuple}=nothing) =
    _ribbon_view_facts(to_vegalite(spec, sc; auto_remap), spec, auto_remap)

# The facts of the finished spec `vl`. Without a switch, the reason comes from
# the figure the lowering drew (the picker's resolved figure under `auto_remap`):
# the condition it misses, or, when it has none, the one `_finish_ribbon_views!`
# checks last — another layer's x values miss the slots.
function _ribbon_view_facts(vl, spec, auto_remap)
    rv = _ribbon_view_meta(vl)
    if !isnothing(rv)
        threshold = rv["threshold"]
        return (; offered=true, why_not=nothing, start=Symbol(rv["start"]), score=Float64(rv["score"]),
                  threshold=isnothing(threshold) ? nothing : Float64(threshold))
    end
    drawn = isnothing(auto_remap) ? spec : _auto_remap_lowering(spec; finish=false, auto_remap...).new_spec
    src = _ribbon_view_source(drawn)
    (; offered=false, why_not=src isa Symbol ? src : :x_off_slots, start=nothing, score=nothing, threshold=nothing)
end
