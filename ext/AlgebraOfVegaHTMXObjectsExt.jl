module AlgebraOfVegaHTMXObjectsExt

using AlgebraOfVega
using HTMXObjects
using HTMXObjects: CaptionSpec, with_caption, render_caption, render_table
using HTMX: h
import JSON
import Tables
import Statistics
import AlgebraOfVega: with_plot_caption, draws_summary_table, _sanitize_id,
                      _auto_summary_args, _auto_remap_parts, to_node, VegaSpec

"""
    with_plot_caption(plot_node, caption::CaptionSpec; plot_id,
                      data_download=true,
                      data_preview=true,
                      filename_base=nothing,
                      layer_labels=nothing,
                      extra_actions=())

Wrap `plot_node` (the result of `to_node(spec; id=plot_id)` or
`auto_remap_node(plot_id, spec; ...)`) in a `<figure>` with a caption header.

Buttons added to the caption actions (in order):
- "⬇ CSV" download per layer (when `data_download=true`). For multi-source
  specs (i.e. data with a `__src` discriminator column), triggers one CSV per source.
- "⬇ PNG" / "⬇ SVG" image download per format in `images` (default `(:png, :svg)`).
  Pass `images=()` or `images=nothing` to disable, or e.g. `images=(:png,)` for one.
- A lazy "Show data" `<details>` rendered below the plot (when `data_preview=true`),
  populated on first expand via the Vega view.

The plot's own Vega-Lite title (if set) is preserved so PNG/SVG exports retain
it; the figcaption sits above the plot, which may visually duplicate. Callers
who don't want that should not set the VL title.

# Keyword arguments
- `plot_id::AbstractString` (required): the same id passed to `to_node` / `auto_remap_node`
- `data_download::Bool=true`: add the "⬇ CSV" button
- `data_preview::Bool=true`: add the lazy preview details below the plot
- `images=(:png, :svg)`: image format buttons; pass `()` / `nothing` to disable
- `filename_base`: base for downloaded filenames (defaults to `plot_id`)
- `layer_labels::Union{Nothing,Dict}=nothing`: map from raw `__src` value → human label,
  used both in download filenames and preview headings
- `extra_actions`: iterable of additional action nodes for the caption header
"""
function with_plot_caption(plot_node, caption::CaptionSpec;
                            plot_id::AbstractString,
                            data_download::Bool=true,
                            data_preview::Bool=true,
                            images=(:png, :svg),
                            filename_base::Union{Nothing,AbstractString}=nothing,
                            layer_labels::Union{Nothing,AbstractDict}=nothing,
                            extra_actions=(),
                            summary_table=nothing)
    plot_id = _sanitize_id(plot_id)
    fname = something(filename_base, plot_id)
    labels_js = isnothing(layer_labels) ? "{}" : JSON.json(Dict(string(k) => string(v) for (k, v) in layer_labels))

    actions = Any[]
    if data_download
        push!(actions,
            h.button("⬇ CSV";
                type="button", class="outline caption-action",
                onclick="AoV.downloadPlotData('$(plot_id)', '$(fname)', $(labels_js))"))
    end
    if !isnothing(images)
        for fmt in images
            fmt_str = lowercase(String(fmt))
            push!(actions,
                h.button("⬇ " * uppercase(fmt_str);
                    type="button", class="outline caption-action",
                    onclick="AoV.downloadPlotImage('$(plot_id)', '$(fmt_str)', '$(fname)')"))
        end
    end
    for ea in extra_actions
        push!(actions, ea)
    end

    body = Any[render_caption(caption; actions=tuple(actions...)), plot_node]

    has_pretty = !isnothing(summary_table)
    if data_preview || has_pretty
        preview_id = plot_id * "-data-preview"
        if has_pretty && data_preview
            details = h.details(; class="aov-data-preview")(
                h.summary("Show data"),
                h.div(; class="aov-data-toggle", role="group")(
                    h.button("Pretty"; type="button",
                        class="outline aov-toggle-btn aov-toggle-active",
                        data_view="pretty", aria_pressed="true",
                        onclick="AoV.toggleDataView(this, 'pretty')"),
                    h.button("Raw"; type="button",
                        class="outline aov-toggle-btn",
                        data_view="raw",
                        onclick="AoV.toggleDataView(this, 'raw')"),
                ),
                h.div(; class="aov-data-pretty")(summary_table),
                h.div(; class="aov-data-raw", hidden=true)(
                    h.div(; class="aov-data-raw-body", id=preview_id,
                          data_aov_plot_id=plot_id,
                          data_aov_labels=labels_js)(),
                ),
            )
            push!(body, details)
        elseif has_pretty
            details = h.details(; class="aov-data-preview")(
                h.summary("Show summary"),
                summary_table,
            )
            push!(body, details)
        else
            details = h.details(; class="aov-data-preview",
                                ontoggle="if(this.open) AoV.showPlotData('$(plot_id)', this.querySelector('.aov-data-preview-body'), $(labels_js))")(
                h.summary("Show data"),
                h.div(; class="aov-data-preview-body", id=preview_id)(),
            )
            push!(body, details)
        end
        h.figure(; class="captioned")(body...)
    else
        with_caption(caption, plot_node; actions=tuple(actions...))
    end
end

# Convenience: also accept a NamedTuple/kwargs form so callers don't need to
# import CaptionSpec just to label one plot.
with_plot_caption(plot_node; title, short="", long=nothing, kwargs...) =
    with_plot_caption(plot_node, CaptionSpec(; title, short, long); kwargs...)

"""
    with_plot_caption(spec::VegaSpec, caption; plot_id,
                      auto_remap=nothing, summary_table=:auto, kwargs...)

Spec-aware dispatch: takes the original `VegaSpec` (not a pre-rendered node),
builds the plot internally, and can:

- auto-wire `auto_remap_node` via `auto_remap=(; dims=..., fixed=..., pinned=...)`
  — controls are hoisted **above** the `<figure>` so they appear before the
  caption rather than between caption and plot.
- auto-build a `draws_summary_table` when the spec has a PointInterval /
  GradientInterval / DotIntervalAnalysis transformation (`summary_table=:auto`,
  the default). Pass `summary_table=nothing` to disable, or pass an explicit
  node to override.

Remaining `kwargs` are forwarded to the `plot_node` method.
"""
function with_plot_caption(spec::VegaSpec, caption::CaptionSpec;
                            plot_id::AbstractString,
                            auto_remap=nothing,
                            summary_table=:auto,
                            kwargs...)
    plot_id_s = _sanitize_id(plot_id)

    controls, plot_node = if isnothing(auto_remap)
        nothing, to_node(spec; id=plot_id_s)
    else
        remap_kw = auto_remap isa NamedTuple ? auto_remap : (;)
        _auto_remap_parts(plot_id_s, spec; remap_kw...)
    end

    resolved_summary = if summary_table === :auto
        args = _auto_summary_args(spec)
        if isnothing(args)
            nothing
        elseif args.kind === :pointinterval
            draws_summary_table(args.table;
                value=args.value, outcome=args.outcome, group_cols=args.group_cols)
        elseif args.kind === :lineribbon
            draws_summary_table(args.table;
                value=args.value, group_cols=args.group_cols)
        else
            nothing
        end
    else
        summary_table
    end

    figure = with_plot_caption(plot_node, caption;
        plot_id=plot_id_s, summary_table=resolved_summary, kwargs...)

    isnothing(controls) ? figure : h.div()(controls, figure)
end

with_plot_caption(spec::VegaSpec; title, short="", long=nothing, kwargs...) =
    with_plot_caption(spec, CaptionSpec(; title, short, long); kwargs...)

"""
    draws_summary_table(table; value, outcome, group_cols=Symbol[], ci_level=0.95,
                        digits=2, caption=nothing, kwargs...)

Build a "median [lo, hi]" summary table from long-format draws data.

Groups `table` by `[group_cols..., outcome]`, computes `median`, `lo` and `hi`
quantiles of the `value` column at the requested `ci_level`, and pivots wide
so each unique value of `outcome` becomes a column. Each cell renders as
`"median [lo, hi]"` rounded to `digits` decimals.

Column order: `group_cols` in provided order, then outcome columns sorted
alphabetically. Extra `kwargs` are forwarded to `render_table`.
"""
function draws_summary_table(table;
                              value::Symbol,
                              outcome::Union{Nothing,Symbol}=nothing,
                              group_cols::Vector{Symbol}=Symbol[],
                              ci_level::Float64=0.95,
                              digits::Int=2,
                              caption=nothing,
                              kwargs...)
    cols = Tables.columns(table)
    vals = Tables.getcolumn(cols, value)
    group_vecs = [Tables.getcolumn(cols, c) for c in group_cols]

    α = (1 - ci_level) / 2
    fmt(x) = string(round(x; digits=digits))

    if isnothing(outcome)
        groups = Dict{Tuple,Vector{Int}}()
        order = Tuple[]
        n = length(vals)
        for i in 1:n
            key = ntuple(j -> group_vecs[j][i], length(group_cols))
            idxs = get!(groups, key) do
                push!(order, key)
                Int[]
            end
            push!(idxs, i)
        end
        cells = String[]
        for key in order
            draws = [vals[i] for i in groups[key]]
            med = Statistics.median(draws)
            lo = Statistics.quantile(draws, α)
            hi = Statistics.quantile(draws, 1 - α)
            push!(cells, "$(fmt(med)) [$(fmt(lo)), $(fmt(hi))]")
        end
        col_pairs = Pair{Symbol,Any}[]
        for (j, c) in enumerate(group_cols)
            push!(col_pairs, c => [gkey[j] for gkey in order])
        end
        push!(col_pairs, value => cells)
        return render_table((; col_pairs...); caption, kwargs...)
    end

    outs = Tables.getcolumn(cols, outcome)

    groups = Dict{Tuple,Vector{Int}}()
    order = Tuple[]
    n = length(vals)
    for i in 1:n
        key = (ntuple(j -> group_vecs[j][i], length(group_cols))..., outs[i])
        idxs = get!(groups, key) do
            push!(order, key)
            Int[]
        end
        push!(idxs, i)
    end

    cell_by_key = Dict{Tuple,String}()
    outcome_set = Set{Any}()
    group_keys = Tuple[]
    seen_groups = Set{Tuple}()
    for key in order
        gkey = key[1:length(group_cols)]
        ocol = key[end]
        push!(outcome_set, ocol)
        if !(gkey in seen_groups)
            push!(seen_groups, gkey)
            push!(group_keys, gkey)
        end
        idxs = groups[key]
        draws = [vals[i] for i in idxs]
        med = Statistics.median(draws)
        lo = Statistics.quantile(draws, α)
        hi = Statistics.quantile(draws, 1 - α)
        cell_by_key[key] = "$(fmt(med)) [$(fmt(lo)), $(fmt(hi))]"
    end

    outcome_cols = sort!(collect(outcome_set); by=string)

    col_pairs = Pair{Symbol,Any}[]
    for (j, c) in enumerate(group_cols)
        push!(col_pairs, c => [gkey[j] for gkey in group_keys])
    end
    for oc in outcome_cols
        push!(col_pairs, Symbol(string(oc)) => [get(cell_by_key, (gkey..., oc), "") for gkey in group_keys])
    end
    pivoted = (; col_pairs...)

    render_table(pivoted; caption, kwargs...)
end

end # module
