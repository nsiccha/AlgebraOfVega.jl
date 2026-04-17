module AlgebraOfVegaHTMXObjectsExt

using AlgebraOfVega
using HTMXObjects
using HTMXObjects: CaptionSpec, with_caption, render_caption, render_table
using HTMX: h
import JSON
import Tables
import Statistics
import AlgebraOfVega: with_plot_caption, draws_summary_table, _sanitize_id

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
    isnothing(summary_table) || push!(body, summary_table)

    if data_preview
        preview_id = plot_id * "-data-preview"
        summary_label = isnothing(summary_table) ? "Show data" : "Show raw data"
        preview = h.details(; class="aov-data-preview",
                            ontoggle="if(this.open) AoV.showPlotData('$(plot_id)', this.querySelector('.aov-data-preview-body'), $(labels_js))")(
            h.summary(summary_label),
            h.div(; class="aov-data-preview-body", id=preview_id)(),
        )
        push!(body, preview)
    end

    if data_preview || !isnothing(summary_table)
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
                              outcome::Symbol,
                              group_cols::Vector{Symbol}=Symbol[],
                              ci_level::Float64=0.95,
                              digits::Int=2,
                              caption=nothing,
                              kwargs...)
    cols = Tables.columns(table)
    vals = Tables.getcolumn(cols, value)
    outs = Tables.getcolumn(cols, outcome)
    group_vecs = [Tables.getcolumn(cols, c) for c in group_cols]

    α = (1 - ci_level) / 2
    fmt(x) = string(round(x; digits=digits))

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
