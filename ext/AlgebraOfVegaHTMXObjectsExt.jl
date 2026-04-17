module AlgebraOfVegaHTMXObjectsExt

using AlgebraOfVega
using HTMXObjects
using HTMXObjects: CaptionSpec, with_caption, render_caption
using HTMX: h
import JSON
import AlgebraOfVega: with_plot_caption

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
                            extra_actions=())
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

    if data_preview
        preview_id = plot_id * "-data-preview"
        preview = h.details(; class="aov-data-preview",
                            ontoggle="if(this.open) AoV.showPlotData('$(plot_id)', this.querySelector('.aov-data-preview-body'), $(labels_js))")(
            h.summary("Show data"),
            h.div(; class="aov-data-preview-body", id=preview_id)(),
        )
        h.figure(; class="captioned")(
            render_caption(caption; actions=tuple(actions...)),
            plot_node,
            preview,
        )
    else
        with_caption(caption, plot_node; actions=tuple(actions...))
    end
end

# Convenience: also accept a NamedTuple/kwargs form so callers don't need to
# import CaptionSpec just to label one plot.
with_plot_caption(plot_node; title, short="", long=nothing, kwargs...) =
    with_plot_caption(plot_node, CaptionSpec(; title, short, long); kwargs...)

end # module
