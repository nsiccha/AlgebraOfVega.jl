# --- Panels on one shared x: `vconcat(a, b, …)` ---
#
# A main panel with a bar panel under it (a forecast and its precipitation) is
# one figure: Vega-Lite's `vconcat` with the x scale shared, so the panels'
# plot areas line up to the pixel (`bounds: "flush"` lays them out by their plot
# areas, not by their axes) and one x zoom and one readout run across them.
# AlgebraOfGraphics composes figures through Makie's layout, which the browser
# figure has no counterpart for, so this is AoV's own spelling. Each panel lowers
# as it would alone (`to_vegalite`); the stack keeps its marks, data, height,
# title and legends, takes the panels' config and runtime metadata (`_aov`) to
# the top, and leaves the x axis labels and title to the bottom panel. The
# runtime sizes every panel to the container (`_applyResponsiveWidth`, kind
# `vconcat`) and reads the panels as one readout (`_readoutPlan`).

"""
    VConcat

Figures stacked top to bottom on one shared x scale; see [`vconcat`](@ref).
"""
struct VConcat
    panels::Vector{Any}
    spacing::Int
end

"""
    vconcat(panels...; spacing=8) -> VConcat

Stack figures top to bottom on one shared x scale, as one plot: a main panel with
a bar panel under it, such as a forecast over the hourly precipitation. Each
panel is an ordinary figure (`data(...) * mapping(...) * visual(...)`, with its
own `config(height=…)`, scales and legends); they share the x scale, so their
plot areas line up exactly, the x axis is labelled once under the bottom panel,
and the readout (§11g) and an x zoom run across all panels. `spacing` is the gap
between the panels' plot areas in pixels.

Use it wherever a figure goes: `vdraw`, `to_node`, `with_plot_caption`, `vsave`,
`to_vegalite`. A panel cannot be faceted, a frame animation or a cell column, and
the channel picker works on one figure only (`ArgumentError`). The panels share
one link group (`config(link=…)`) if any has one. A ribbon panel draws the
drawing it starts in, without the Ribbons | Intervals switch. `sdraw` composes
Makie panels with `sdraw!` and `Makie.linkxaxes!` instead.
"""
function vconcat(panels...; spacing::Integer=8)
    length(panels) >= 2 || throw(ArgumentError(
        "vconcat: stack two or more figures, e.g. `vconcat(level, rain)`; got $(length(panels))."))
    for (k, p) in enumerate(panels)
        p isa Union{AlgebraOfGraphics.Layer,AlgebraOfGraphics.Layers,VegaSpec} || throw(ArgumentError(
            "vconcat: panel $k is a $(typeof(p)), not a figure (`data(...) * mapping(...) * visual(...)`)."))
    end
    spacing >= 0 || throw(ArgumentError("vconcat: `spacing` is a gap in pixels, ≥ 0; got $spacing."))
    VConcat(collect(Any, panels), Int(spacing))
end

function to_vegalite(s::VConcat; interactive::Bool=true, auto_remap::Union{Nothing,NamedTuple}=nothing)
    isnothing(auto_remap) || throw(ArgumentError(
        "vconcat: the channel picker (`auto_remap`) rearranges one figure; stack the figures it would show instead."))
    kids = [to_vegalite(p; interactive) for p in s.panels]
    top = Dict{String,Any}("\$schema" => VL_SCHEMA, "vconcat" => Any[], "spacing" => s.spacing,
        "bounds" => "flush", "resolve" => Dict{String,Any}("scale" => Dict{String,Any}("x" => "shared")))
    config = Dict{String,Any}()
    aov = Dict{String,Any}()
    readouts = Any[]
    links = Any[]
    widths = Real[]
    for (k, kid) in enumerate(kids)
        _vconcat_refuse(kid, k)
        # The panels' config: the first panel's keys win (a later panel adds
        # what it alone sets), as one figure has one config.
        c = get(kid, "config", nothing)
        c isa Dict && (config = _deep_merge_dict!(deepcopy(c), config))
        meta = get(kid, "_aov", nothing)
        meta = meta isa Dict ? meta : Dict{String,Any}()
        push!(readouts, get(meta, "readout", nothing))
        haskey(meta, "link") && push!(links, meta["link"])
        for key in ("legendInteraction", "theme", "inkPalette", "maxWidth")
            haskey(meta, key) && !haskey(aov, key) && (aov[key] = meta[key])
        end
        summary = get(kid, "_aovSummary", nothing)
        isnothing(summary) || haskey(top, "_aovSummary") || (top["_aovSummary"] = summary)
        ds = get(kid, "datasets", nothing)
        ds isa Dict && merge!(get!(top, "datasets", Dict{String,Any}()), ds)
        w = get(kid, "width", nothing)
        w isa Real && push!(widths, w)
        panel = Dict{String,Any}(key => v for (key, v) in kid
            if !(key in ("\$schema", "config", "_aov", "_aovSummary", "datasets", "autosize", "padding", "width", "background")))
        # A value parameter (no `select`, such as the reference labels' rows)
        # exists only at the top of a Vega-Lite spec: the stack holds it once.
        ps = get(panel, "params", nothing)
        if ps isa AbstractVector
            values = [p for p in ps if p isa AbstractDict && !haskey(p, "select")]
            if !isempty(values)
                top_params = get!(top, "params", Any[])
                for p in values
                    any(q -> get(q, "name", nothing) == get(p, "name", nothing), top_params) || push!(top_params, p)
                end
                rest = [p for p in ps if !(p isa AbstractDict && !haskey(p, "select"))]
                isempty(rest) ? delete!(panel, "params") : (panel["params"] = rest)
            end
        end
        k < length(kids) && _vconcat_hide_x_labels!(panel)
        push!(top["vconcat"], panel)
    end
    isempty(config) || (top["config"] = config)
    # One link group for the stack: a hovered mark of any panel announces its key.
    if !isempty(links)
        all(==(first(links)), links) || throw(ArgumentError(
            "vconcat: the panels set different link groups ($(join(unique(string.(get.(links, "group", ""))), ", "))); " *
            "a stack is one plot in one group, so give its panels the same `config(link=…)`."))
        aov["link"] = first(links)
    end
    # The readout: on when any panel would show one; a panel with
    # `config(readout=false)` is left out of it (`_aov.panels`).
    any(==(true), readouts) && (aov["readout"] = true)
    all(==(false), readouts) && (aov["readout"] = false)
    aov["panels"] = Any[Dict{String,Any}("readout" => r) for r in readouts]
    top["_aov"] = aov
    # An authored width (`config(width=…)` on a panel) sizes every panel, the widest.
    isempty(widths) || foreach(p -> p["width"] = maximum(widths), top["vconcat"])
    top
end

# A panel the stack cannot hold, said in terms of the figure.
function _vconcat_refuse(kid::Dict, k)
    what = haskey(kid, "facet") || haskey(kid, "spec") ? "faceted (`col=`, `row=` or `layout=`)" :
        any(key -> haskey(kid, key), ("hconcat", "vconcat", "concat")) ? "itself a composition" :
        haskey(get(kid, "_aov", Dict()), "frame") ? "a frame animation (`config(frame=…)`)" :
        haskey(get(kid, "_aov", Dict()), "cells") ? "a cell column" : nothing
    isnothing(what) || throw(ArgumentError("vconcat: panel $k is $what; a stack holds unfaceted figures on one x."))
    _has_any_encoding(kid, ("column", "row", "facet")) && throw(ArgumentError(
        "vconcat: panel $k is faceted (`col=`, `row=` or `layout=`); a stack holds unfaceted figures on one x."))
end
_has_any_encoding(node, chs) = false
function _has_any_encoding(node::Dict, chs)
    enc = get(node, "encoding", nothing)
    enc isa Dict && any(ch -> haskey(enc, ch), chs) && return true
    sub = get(node, "layer", nothing)
    sub isa AbstractVector && any(l -> _has_any_encoding(l, chs), sub)
end

# A panel above the bottom one keeps its x ticks' grid but no labels, ticks,
# axis line or title: the bottom panel labels the shared x.
function _vconcat_hide_x_labels!(node)
    node isa Dict || return
    enc = get(node, "encoding", nothing)
    if enc isa Dict && get(enc, "x", nothing) isa Dict
        x = enc["x"]
        # `axis: null` hides it already.
        if !(haskey(x, "axis") && x["axis"] === nothing)
            ax = get(x, "axis", nothing)
            ax = ax isa Dict ? ax : Dict{String,Any}()
            x["axis"] = merge(ax, Dict{String,Any}("labels" => false, "title" => nothing, "ticks" => false, "domain" => false))
        end
    end
    sub = get(node, "layer", nothing)
    sub isa AbstractVector && foreach(_vconcat_hide_x_labels!, sub)
    nothing
end

plot_size(s::VConcat) = plot_size(to_vegalite(s))

# Makie composes panels in its own layout; a stack has no single AoG figure
# (`sdraw_file` and `sdraw!` call this first).
_sdraw_check(_) = nothing
_sdraw_check(::VConcat) = throw(ArgumentError(
    "sdraw: a `vconcat` stack is a browser figure; write it to a file with `vsave`, or compose Makie panels " *
    "with `sdraw!(fig[1, 1], a)`, `sdraw!(fig[2, 1], b)` and `Makie.linkxaxes!` (aov-use §1a)."))

# The automatic data summary of a captioned stack: its first panel's that has one
# (`with_plot_caption`, src/plot_summary_table.jl).
function _summary_meta(s::VConcat)
    for p in s.panels
        meta = _summary_meta(p)
        isnothing(meta) || return meta
    end
    nothing
end
