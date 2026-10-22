module AlgebraOfVegaHTMXObjectsExt

using AlgebraOfVega
using HTMXObjects
using HTMXObjects: CaptionSpec, render_caption, render_table,
    caption_style, sortable_table_js, html_only
using HTMX: h
import Tables
import Statistics
import AlgebraOfVega: with_plot_caption, draws_summary_table, _sanitize_id,
                      _auto_summary_args, _auto_remap_parts, to_node, to_html,
                      VegaSpec, caption_share_button, _vl_json,
                      PlotTexts, _EN_PLOT_TEXTS, _plot_text, _runtime_texts_attrs,
                      _static_img, _MarkdownView

# HTMX 1.0 escapes attribute values itself (`&`, `"`, `'`, `<`, `>`), and the
# HTML parser decodes them back before JS/`dataset` ever sees them — so JSON
# payloads are passed through VERBATIM here. Escaping them again would emit
# `&amp;quot;` and break `JSON.parse` on the other side.

_as_nt_or_nothing(nt::NamedTuple) = nt
_as_nt_or_nothing(_) = nothing

_ci_str(s::Symbol) = string(s)
_ci_str(s) = s

"""
    with_plot_caption(plot_node, caption::CaptionSpec; plot_id,
                      data_download=true,
                      data_preview=true,
                      filename_base=nothing,
                      layer_labels=nothing,
                      extra_actions=(),
                      texts=plot_texts(),
                      static_image=nothing, alt=nothing)

Wrap `plot_node` (the result of `to_node(spec; id=plot_id)` or
`auto_remap_node(plot_id, spec; ...)`) in a `<figure>` with a caption header.

Buttons added to the caption actions (in order):
- "⬇ CSV" download per layer (when `data_download=true`). For multi-source
  specs (i.e. data with a `__src` discriminator column), triggers one CSV per source.
- "⬇ PNG" / "⬇ SVG" image download per format in `images` (default `(:png, :svg)`).
  Pass `images=()` or `images=nothing` to disable, or e.g. `images=(:png,)` for one.
- "⬇ HTML" standalone-page download (when `html_download=true`): the whole
  card as one `.html` file via `AoV.downloadPlotHtml`, client-side, no server
  round-trip.
- A lazy "Show data" `<details>` rendered below the plot (when `data_preview=true`),
  populated on first expand via the Vega view.
- "Share" clipboard button (when `share_url` is given): copies the absolute
  card URL; appended after `extra_actions`.

The plot's own Vega-Lite title (if set) is preserved so PNG/SVG exports retain
it; the figcaption sits above the plot, which may visually duplicate. Callers
who don't want that should not set the VL title.

# Keyword arguments
- `plot_id::AbstractString` (required): the same id passed to `to_node` / `auto_remap_node`
- `data_download::Bool=true`: add the "⬇ CSV" button
- `data_preview::Bool=true`: add the lazy preview details below the plot
- `images=(:png, :svg)`: image format buttons; pass `()` / `nothing` to disable
- `html_download::Bool=true`: add the "⬇ HTML" standalone-page button
- `share_url=nothing`: when given, append a "Share" clipboard button for this URL
- `filename_base`: base for downloaded filenames (defaults to `plot_id`)
- `layer_labels::Union{Nothing,Dict}=nothing`: map from raw `__src` value → human label,
  used both in download filenames and preview headings
- `extra_actions`: iterable of additional action nodes for the caption header
- `texts::PlotTexts=plot_texts()`: the words of the caption's "More" toggle,
  the buttons, the data preview and its summary, and of a standalone HTML
  download — `plot_texts(:de)` for a German page, with per-text overrides (see
  [`plot_texts`](@ref)). The caption's own title, summary and long text are
  `caption`'s. A non-English "More" needs HTMXObjects' `caption_texts`
  (HTMXObjects `d344dfd` or later).
- `static_image=nothing`: the figure's image for a report built from the
  page's markdown view, such as an accessible (PDF/UA) PDF. With it, the
  markdown view shows the caption and `<img src=static_image alt=…>` in place
  of the plot, so the report gets the figure with its alt text. The browser
  (HTML) view is unchanged. AoV does not write the image: render it first
  (`sdraw_file`, or any other renderer). It is the `src` as given, so it must
  resolve where the markdown is rendered: a path relative to the report, an
  absolute path, a URL or a `data:` URI.
- `alt=nothing`: the image's alt text, a description of what the figure shows.
  Defaults to the caption's title and short summary, joined by `" — "`. Needs
  `static_image`.
"""
function with_plot_caption(plot_node, caption::CaptionSpec;
                            plot_id::AbstractString,
                            data_download::Bool=true,
                            data_preview::Bool=true,
                            images=(:png, :svg),
                            html_download::Bool=true,
                            share_url::Union{Nothing,AbstractString}=nothing,
                            filename_base::Union{Nothing,AbstractString}=nothing,
                            layer_labels::Union{Nothing,AbstractDict}=nothing,
                            extra_actions=(),
                            summary_table=nothing,
                            texts::PlotTexts=_EN_PLOT_TEXTS,
                            static_image::Union{Nothing,AbstractString}=nothing,
                            alt::Union{Nothing,AbstractString}=nothing)
    plot_id = _sanitize_id(plot_id)
    fname = something(filename_base, plot_id)
    labels_js = isnothing(layer_labels) ? "{}" : _vl_json(Dict(string(k) => string(v) for (k, v) in layer_labels))

    actions = Any[]
    if data_download
        push!(actions,
            h.button(texts.csv;
                type="button", class="outline caption-action",
                onclick="AoV.downloadPlotData('$(plot_id)', '$(fname)', $(labels_js))"))
    end
    if !isnothing(images)
        for fmt in images
            fmt_str = lowercase(String(fmt))
            push!(actions,
                h.button(_plot_text(texts, :image; format=uppercase(fmt_str));
                    type="button", class="outline caption-action",
                    onclick="AoV.downloadPlotImage('$(plot_id)', '$(fmt_str)', '$(fname)')"))
        end
    end
    if html_download
        push!(actions,
            h.button(texts.html;
                type="button", class="outline caption-action",
                onclick="AoV.downloadPlotHtml('$(plot_id)', '$(fname)')"))
    end
    for ea in extra_actions
        push!(actions, ea)
    end
    if !isnothing(share_url)
        push!(actions, caption_share_button(share_url; texts))
    end

    body = Any[render_caption(caption; actions=tuple(actions...), _caption_texts_kw(texts)...),
               _report_children(plot_node, caption, static_image, alt)...]

    has_pretty = !isnothing(summary_table)
    if data_preview || has_pretty
        preview_id = plot_id * "-data-preview"
        if has_pretty && data_preview
            details = h.details(; class="aov-data-preview", data_mode="pretty",
                                ontoggle="if(this.open) AoV._lazyRenderDataView(this, 'pretty')")(
                h.summary(texts.show_data),
                h.div(; role="group")(
                    h.button(texts.pretty; type="button", class="outline",
                        data_view="pretty", aria_pressed="true",
                        onclick="AoV.toggleDataView(this, 'pretty')"),
                    h.button(texts.raw; type="button", class="outline",
                        data_view="raw",
                        onclick="AoV.toggleDataView(this, 'raw')"),
                ),
                h.div(; data_view="pretty")(summary_table),
                h.div(; data_view="raw")(
                    h.div(; class="aov-data-raw-body", id=preview_id,
                          data_aov_plot_id=plot_id,
                          data_aov_labels=labels_js)(),
                ),
            )
            push!(body, details)
        elseif has_pretty
            details = h.details(; class="aov-data-preview",
                                ontoggle="if(this.open) AoV._lazyRenderDataView(this, 'pretty')")(
                h.summary(texts.show_summary),
                summary_table,
            )
            push!(body, details)
        else
            details = h.details(; class="aov-data-preview",
                                ontoggle="if(this.open) AoV._lazyRenderDataView(this, 'raw')")(
                h.summary(texts.show_data),
                h.div(; class="aov-data-raw-body", id=preview_id,
                      data_aov_plot_id=plot_id,
                      data_aov_labels=labels_js)(),
            )
            push!(body, details)
        end
    end
    # The figure carries non-English `texts` for the runtime, which writes the
    # preview contents and the HTML download's `lang` and title.
    h.figure(; class="captioned", _runtime_texts_attrs(texts)...)(body...)
end

# The caption's own word ("More") is HTMXObjects' `caption_texts`, which
# HTMXObjects has carried since `d344dfd`. English passes none, so a consumer
# on an older HTMXObjects keeps rendering English captions.
_caption_texts_kw(texts::PlotTexts) = texts.more == _EN_PLOT_TEXTS.more ? (;) :
    (; texts=HTMXObjects.caption_texts(; more=texts.more))

# A pre-rendered plot passed as a tuple of nodes is spliced in, as
# `HTMXObjects.with_caption` does.
_figure_children(plot_node) = (plot_node,)
_figure_children(plot_node::Tuple) = plot_node

# With a static image, the plot is HTML-only and the markdown view shows the
# image with its alt text instead (an accessible PDF report is built from it).
_report_children(plot_node, caption, ::Nothing, ::Nothing) = _figure_children(plot_node)
_report_children(plot_node, caption, ::Nothing, alt) = throw(ArgumentError(
    "with_plot_caption: `alt` is the alt text of `static_image`; pass the figure's static image too"))
_report_children(plot_node, caption, static_image, alt) =
    (map(html_only, _figure_children(plot_node))...,
     _MarkdownView(_static_img(static_image, _figure_alt(caption, alt))))

# A report figure is never decorative, so its alt text must say something.
_figure_alt(caption, ::Nothing) = _figure_alt(caption,
    isempty(caption.short) ? caption.title : caption.title * " — " * caption.short)
_figure_alt(caption, alt::AbstractString) = isempty(strip(alt)) ? throw(ArgumentError(
    "with_plot_caption: the static image's alt text is empty; pass `alt` describing what the figure shows")) : alt

# Convenience: also accept a NamedTuple/kwargs form so callers don't need to
# import CaptionSpec just to label one plot.
with_plot_caption(plot_node; title, short="", long=nothing, kwargs...) =
    with_plot_caption(plot_node, CaptionSpec(; title, short, long); kwargs...)

with_plot_caption(plot_node, caption::AbstractString; kwargs...) =
    with_plot_caption(plot_node, CaptionSpec(; title=caption); kwargs...)

"""
    with_plot_caption(spec::VegaSpec, caption; plot_id,
                      auto_remap=nothing, summary_table=:auto,
                      summary_ci=:outer, summary_sigfigs=2, kwargs...)

Spec-aware dispatch: takes the original `VegaSpec` (not a pre-rendered node),
builds the plot internally, and can:

- auto-wire `auto_remap_node` via `auto_remap=(; dims=..., fixed=..., pinned=...)`
  — controls are hoisted **above** the `<figure>` so they appear before the
  caption rather than between caption and plot.
- emit a lazy pretty-summary shell that the AoV runtime fills client-side
  from the live Vega view's already-aggregated columns (`__median__` +
  `lo_<prob>_` / `hi_<prob>_`), when the spec has a PointInterval /
  GradientInterval / DotInterval / LineRibbon analysis (`summary_table=:auto`,
  the default). Pass `summary_table=nothing` to disable, or an explicit node
  to bypass the lazy mechanism.

`texts` (a [`PlotTexts`](@ref)) also sets the channel picker's labels.

`summary_ci` controls which interval is shown: `:outer` (default — widest
band, typically 95%), `:inner` (narrowest), or a `Float64` like `0.8` (closest
prob match — auto path only). `summary_sigfigs` rounds cells to N significant
figures (default 2).

`static_image` (with optional `alt`) puts the figure's image into the
markdown view in place of the plot, as in the `plot_node` method; the channel
picker is then left out of the markdown view too.

Remaining `kwargs` are forwarded to the `plot_node` method.
"""
function with_plot_caption(spec::VegaSpec, caption::CaptionSpec;
                            plot_id::AbstractString,
                            auto_remap=nothing,
                            summary_table=:auto,
                            summary_ci=:outer,
                            summary_sigfigs::Int=2,
                            texts::PlotTexts=_EN_PLOT_TEXTS,
                            static_image::Union{Nothing,AbstractString}=nothing,
                            kwargs...)
    plot_id_s = _sanitize_id(plot_id)

    controls, plot_node = if isnothing(auto_remap)
        nothing, to_node(spec; id=plot_id_s)
    else
        remap_kw = something(_as_nt_or_nothing(auto_remap), (;))
        _auto_remap_parts(plot_id_s, spec; texts, remap_kw...)
    end

    resolved_summary = if summary_table === :auto
        args = _auto_summary_args(spec)
        if isnothing(args)
            nothing
        else
            ci_val = _ci_str(summary_ci)
            opts = Dict{String,Any}(
                "ci" => ci_val,
                "sigfigs" => summary_sigfigs,
                "value_label" => string(args.value),
            )
            ll = get(kwargs, :layer_labels, nothing)
            if !isnothing(ll)
                opts["labels"] = Dict(string(k) => string(v) for (k, v) in ll)
            end
            if args.kind === :precomputed_ribbon
                opts["point_col"] = args.point_col
                opts["point_label"] = texts.median
                opts["bands"] = [Any[lo, hi, label] for (lo, hi, label) in args.bands]
            end
            h.div(; class="aov-data-pretty-body",
                  id="$(plot_id_s)-pretty",
                  data_aov_plot_id=plot_id_s,
                  data_aov_summary_opts=_vl_json(opts))()
        end
    else
        summary_table
    end

    figure = with_plot_caption(plot_node, caption;
        plot_id=plot_id_s, summary_table=resolved_summary, texts, static_image, kwargs...)

    # `data-aov-fragment` marks the whole card (controls + figure) so the
    # client-side "⬇ HTML" download can clone exactly this subtree.
    isnothing(controls) ? figure :
        h.div(; data_aov_fragment=plot_id_s)(_report_controls(controls, static_image), figure)
end

# The picker's labels and options are noise in a report built from the
# markdown view of a figure that has a static image.
_report_controls(controls, ::Nothing) = controls
_report_controls(controls, _) = html_only(controls)

with_plot_caption(spec::VegaSpec; title, short="", long=nothing, kwargs...) =
    with_plot_caption(spec, CaptionSpec(; title, short, long); kwargs...)

with_plot_caption(spec::VegaSpec, caption::AbstractString; kwargs...) =
    with_plot_caption(spec, CaptionSpec(; title=caption); kwargs...)

# Head extras a captioned fragment needs beyond `vega_head()`: caption-row
# CSS plus the global `sortTable` the lazy "Show data" tables call into.
function _caption_head_extra(head_extra::AbstractString)
    io = IOBuffer()
    show(io, MIME"text/html"(), caption_style())
    show(io, MIME"text/html"(), sortable_table_js())
    String(take!(io)) * head_extra
end

"""
    to_html(spec::VegaSpec, caption; plot_id, auto_remap=nothing, summary_table=:auto,
            title=caption title, head_extra="", kwargs...) -> String

Serialize a full captioned + auto-remap fragment — the `with_plot_caption`
spec form (channel picker + plot + `CaptionSpec` + CSV/PNG/SVG/HTML download
buttons + summary table + raw-data preview) — as ONE standalone `.html`
document string. Opening the saved file with no server keeps working: picker
re-facets, CSV/PNG/SVG download, caption/summary render. `kwargs` forward to
`with_plot_caption` (e.g. `filename_base`, `share_url`, `html_download`).

The node form `to_html(plot_node, caption; plot_id, ...)` wraps a
pre-rendered node instead; use it for `signals=`-wired nodes, which degrade
silently offline (their `htmx.ajax` callback has no server).
`source`, `base` and `runtime` select the `<head>` as in `vega_head`;
`source=:inline` inlines AoV's vendored Vega builds, so the saved file renders
with no network at all. `texts` (a [`PlotTexts`](@ref)) sets the card's
words, as in `with_plot_caption`, and the page's `<html lang>`.
"""
function to_html(spec::VegaSpec, caption::CaptionSpec;
                 plot_id::AbstractString,
                 auto_remap=nothing,
                 summary_table=:auto,
                 title::Union{Nothing,AbstractString}=nothing,
                 head_extra::AbstractString="",
                 source::Symbol=:cdn,
                 base::AbstractString="/vendor",
                 runtime::Symbol=:inline,
                 texts::PlotTexts=_EN_PLOT_TEXTS,
                 kwargs...)
    frag = with_plot_caption(spec, caption;
        plot_id=plot_id, auto_remap=auto_remap, summary_table=summary_table, texts, kwargs...)
    to_html(frag; title=something(title, caption.title), texts,
            head_extra=_caption_head_extra(head_extra), source=source, base=base, runtime=runtime)
end

to_html(spec::VegaSpec, caption::AbstractString; kwargs...) =
    to_html(spec, CaptionSpec(; title=caption); kwargs...)

function to_html(plot_node, caption::CaptionSpec;
                 plot_id::AbstractString,
                 title::Union{Nothing,AbstractString}=nothing,
                 head_extra::AbstractString="",
                 source::Symbol=:cdn,
                 base::AbstractString="/vendor",
                 runtime::Symbol=:inline,
                 texts::PlotTexts=_EN_PLOT_TEXTS,
                 kwargs...)
    figure = with_plot_caption(plot_node, caption; plot_id=plot_id, texts, kwargs...)
    to_html(figure; title=something(title, caption.title), texts,
            head_extra=_caption_head_extra(head_extra), source=source, base=base, runtime=runtime)
end

to_html(plot_node, caption::AbstractString; kwargs...) =
    to_html(plot_node, CaptionSpec(; title=caption); kwargs...)

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
