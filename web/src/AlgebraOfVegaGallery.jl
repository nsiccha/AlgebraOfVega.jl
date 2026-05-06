module AlgebraOfVegaGallery

using HTMXObjects
using AlgebraOfVega
import CairoMakie
using JSON
using TestModules, Random, Tables, Statistics
# Load Treebars before importing RecordingRoutes — Treebars activates
# HTMXObjects's HTMXObjectsTreebarsExt, which injects `RecordingRoutes`
# into the HTMXObjects namespace.
using Treebars
using HTMXObjects: RecordingRoutes

include("test/runtests.jl")

# Two-callable dispatch on `spec` type: replaces the old `_is_html_node` Bool
# predicate + `is_node ? ... : ...` ternaries scattered through the gallery
# views. `node_fn(spec)` runs when `spec` is an HTMX.Node; `other_fn(spec)`
# otherwise. Each call site picks its branch closures (typically `identity`
# for the node side when the branch is just `spec`).
_dispatch_node(spec::HTMX.Node, node_fn, _other_fn) = node_fn(spec)
_dispatch_node(spec, _node_fn, other_fn) = other_fn(spec)

_push_compose_parts!(args...) = nothing
function _push_compose_parts!(lines, t::ComposedFunction)
    push!(lines, "  outer: $(t.outer) ($(typeof(t.outer)))")
    push!(lines, "  inner: $(t.inner) ($(typeof(t.inner)))")
end

# --- Sample datasets (from AlgebraOfVega.datasets) ---
# Local aliases to keep existing plot code unchanged
cars() = sample_cars()
tips() = sample_tips()
stocks() = sample_stocks()
temperatures() = sample_temperatures()
population() = sample_population()
monthly_sales() = sample_monthly_sales()
posterior_draws(; kw...) = sample_posterior_draws(; kw...)
regression_predictions(; kw...) = sample_regression_predictions(; kw...)
grouped_regression_predictions(; kw...) = sample_grouped_regression_predictions(; kw...)
faceted_regression_predictions(; kw...) = sample_faceted_regression_predictions(; kw...)
faceted_observations(; kw...) = sample_faceted_observations(; kw...)

function _preaggregate(raw, group_keys::Symbol...)
    ct = Tables.columntable(raw)
    ys = ct.y
    key_cols = [ct[k] for k in group_keys]
    nk = length(group_keys)
    groups = Dict{Any,Vector{Int}}()
    for i in eachindex(ys)
        key = nk == 1 ? key_cols[1][i] : Tuple(kc[i] for kc in key_cols)
        push!(get!(Vector{Int}, groups, key), i)
    end
    out_keys = [Any[] for _ in 1:nk]
    out_q025 = Float64[]; out_q10 = Float64[]; out_q25 = Float64[]; out_med = Float64[]
    out_q75 = Float64[]; out_q90 = Float64[]; out_q975 = Float64[]
    for key in sort(collect(keys(groups)))
        idxs = groups[key]
        v = sort(ys[idxs])
        if nk == 1
            push!(out_keys[1], key)
        else
            for (j, k) in enumerate(key)
                push!(out_keys[j], k)
            end
        end
        push!(out_q025, quantile(v, 0.025))
        push!(out_q10, quantile(v, 0.10))
        push!(out_q25, quantile(v, 0.25))
        push!(out_med, quantile(v, 0.5))
        push!(out_q75, quantile(v, 0.75))
        push!(out_q90, quantile(v, 0.90))
        push!(out_q975, quantile(v, 0.975))
    end
    (; (k => out_keys[i] for (i, k) in enumerate(group_keys))...,
       q025=out_q025, q10=out_q10, q25=out_q25, median=out_med, q75=out_q75, q90=out_q90, q975=out_q975)
end

# --- Plot specifications (file-based gallery) ---
#
# The hardcoded ~2000-line PLOTS literal previously lived here. It has
# been split into one file per entry under
# `examples/aov-gallery/<section>/<id>.jl`, with a `# title:` /
# `# description:` metadata header and the spec body verbatim. The
# directory layout determines section grouping (one `_section.md`
# per dir).
#
# `PLOTS` and `PLOT_SECTIONS` are reconstructed from the file tree
# below as compatibility shims so the rest of this file can stay
# unchanged. The 5-tuple shape `(id, title, description, code_string,
# spec_thunk)` is preserved; new code can use `_gallery::Gallery`,
# `find_item(_gallery, id)`, and `gallery_grid(...)` directly.
const _GALLERY_DIR = joinpath(dirname(dirname(@__DIR__)), "examples", "aov-gallery")
const _gallery = Gallery(_GALLERY_DIR)

# Load each item's body once at module init via `Base.include`, in
# this module's namespace, so cars(), data(), mapping(), … resolve.
# The `include` returns the file's last top-level expression, which is
# the AoV spec the gallery card renders. Wrap in a thunk so existing
# `entry[5]()` callsites keep working. Items whose body fails to eval
# are stored with an error spec so the gallery still renders the rest.
const _gallery_specs = Dict{String,Any}()
for _it in _gallery.items
    _gallery_specs[_it.id] = Base.include(@__MODULE__, _it.path)
end

PLOTS = [
    (it.id, it.title, it.description, it.code_string, () -> _gallery_specs[it.id])
    for it in _gallery.items
]

# `RecordingRoutes` (from HTMXObjects's TreebarsExt) provides the canonical
# recording flow — IP-backed `polling_fetchindex` with per-path progress
# phases, summary article on completion, `?force=true` to re-record. Mounted
# below at `/record_gallery` via @include with the gallery path list.
const _RECORDING_PATHS = let ids = [it.id for it in _gallery.items]
    vcat(
        ["/"],
        ["/plot/$id"       for id in ids],
        ["/standalone/$id" for id in ids],
        ["/spec/$id"       for id in ids],
        ["/aov_runtime_js", "/explorer", "/flagged"],
    )
end
const _RECORDING_DIR = joinpath(dirname(dirname(@__DIR__)), "docs", "src", "public", "live-aov")
_recording_base() = get(ENV, "RECORD_BASE_PREFIX", "/AlgebraOfVega.jl/dev/live-aov")

# --- Utilities ---


function json_response(text)
    HTTP.Response(200, ["Content-Type" => "application/json; charset=utf-8"], body=text)
end

function find_plot(id)
    idx = findfirst(p -> p[1] == id, PLOTS)
    isnothing(idx) ? nothing : PLOTS[idx]
end

function escape_html(s::AbstractString)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s
end

# --- Flagged plots persistence ---
flags_file() = joinpath(@__DIR__, "..", "flagged.txt")

function load_flags()
    s = Set{String}()
    f = flags_file()
    isfile(f) || return s
    for line in readlines(f)
        l = strip(line)
        !isempty(l) && push!(s, l)
    end
    s
end

function save_flags(flagged)
    open(flags_file(), "w") do io
        for id in sort(collect(flagged))
            println(io, id)
        end
    end
end

function toggle_flag!(id)
    flagged = load_flags()
    if id in flagged
        delete!(flagged, id)
    else
        push!(flagged, id)
    end
    save_flags(flagged)
    id in flagged
end

# --- HTMXObjects App ---

@htmx struct AppContext
    flag_button(id) = let flagged = id in load_flags()
        h.button(flagged ? "flagged" : "flag";
            hx_post=__self__/"flag/$id",
            hx_target="#flag-$id",
            hx_swap="outerHTML",
            id="flag-$id",
            class=flagged ? "aov-flag-button is-flagged" : "aov-flag-button",
        )
    end

    plot_card(id, title, description, ref_url=nothing) = begin
        entry = find_plot(id)
        let spec = isnothing(entry) ? nothing : entry[5]()
            code_str = isnothing(entry) ? "" : entry[4]
            h.article(; class="htmxo-gallery-card")(
                h.h4(; class="htmxo-gallery-card-title")(
                    h.a(title; href=__self__/"standalone/$id", target="_blank"),
                    _dispatch_node(spec,
                        _ -> h.span(),
                        _ -> h.a(" · static";
                            class="htmxo-gallery-card-meta",
                            href=__self__/"static_plot/$id", target="_blank")),
                    flag_button(id),
                    isnothing(ref_url) ? h.span() :
                        h.a(" · ref"; class="htmxo-gallery-card-meta", href=ref_url, target="_blank"),
                ),
                isempty(description) ? h.span() :
                    h.p(description; class="htmxo-gallery-card-description"),
                isnothing(spec) ? h.p("Unknown plot") :
                    _dispatch_node(spec, identity, s -> vdraw(s; id=id)),
                h.pre(h.code(code_str; class="language-julia"); class="htmxo-gallery-card-code"),
            )
        end
    end

    # Group plots by category for the index. Order is simple → complex
    # → tests/edge-cases. The final "Uncategorized" bucket collects
    # every gallery item not assigned to one of the curated sections
    # above; those are bug-repro / test items rather than curated
    # examples, so they render last.
    _CURATED_SECTIONS = [
        ("Basic" => ["scatter", "bar", "line", "lines_only", "area", "histogram", "heatmap", "boxplot"]),
        ("Composition" => ["layered", "multi_layer", "stacked_bar", "grouped_bar", "bubble", "scatter_jitter", "custom_config"]),
        ("AoG: Basic Visualizations" => ["aog_scatter_basic", "aog_sine_lines", "aog_lines_scatter", "aog_two_sources", "aog_boxplot"]),
        ("AoG: Additional Marks" => ["aog_step", "aog_rules", "aog_vlines_faceted_color", "aog_vlines_faceted_color_remap", "aog_errorbars"]),
        ("AoG: Statistical Analyses" => ["aog_density", "aog_ecdf", "aog_ecdf_grouped", "aog_histogram_basic", "aog_histogram", "aog_frequency", "aog_expectation", "aog_frequency_color", "aog_linear", "aog_smooth", "aog_linear_band", "aog_smooth_band"]),
        ("AoG: Layout" => ["aog_facet", "aog_facet_wrap", "aog_facet_multi_layer", "aog_facet_regression"]),
        ("AoG: Composition Patterns" => ["aog_scatter_regression", "aog_scatter_smooth", "aog_bar_line_combo", "aog_stacked_area", "aog_color_regression"]),
        ("AoG: Applications" => ["aog_timeseries", "aog_timeseries_box", "aog_2d_histogram"]),
        ("Uncertainty (tidybayes)" => ["pointinterval", "pointinterval_vertical", "halfeye", "gradient_interval", "lineribbon", "lineribbon_grouped", "lineribbon_faceted", "lineribbon_overlay", "lineribbon_logscale", "ppc_overlay", "ribbon_only", "precomputed_lineribbon", "precomputed_lineribbon_grouped", "precomputed_pointinterval", "remap_precomputed_pointinterval_positional", "dotinterval", "raincloud"]),
        ("Interactive" => ["interactive_brush", "interactive_highlight", "interactive_zoom", "interactive_slider", "interactive_dropdown", "remap_encoding", "remap_axes", "remap_lineribbon", "remap_detail", "remap_precomputed_lineribbon"]),
        ("Interactive Filtering" => ["filter_origin", "filter_multi", "filter_tips", "filter_histogram", "filter_regression", "filter_bar"]),
        ("AoG: Data Manipulations" => ["aog_wide_lines", "aog_wide_scatter", "aog_presorted_bar"]),
        ("AoG: Pregrouped" => ["pregrouped_boxplot", "pregrouped_boxplot_plain", "pregrouped_dose_response"]),
        ("AoG: Scales" => ["aog_log_transform", "aog_discrete_boxplot", "aog_combined_boxplot", "aog_barplot_names", "aog_dodge", "aog_legend_merge", "aog_multi_color"]),
    ]
    PLOT_SECTIONS = let curated_ids = Set(id for (_, ids) in _CURATED_SECTIONS for id in ids),
                        leftover = [it.id for it in _gallery.items if !(it.id in curated_ids)]
        isempty(leftover) ? _CURATED_SECTIONS :
            [_CURATED_SECTIONS..., "Tests / Edge cases" => leftover]
    end

    gallery_section(section_title, ids) = begin
        entries = filter(!isnothing, [find_plot(id) for id in ids])
        h.section(; class="htmxo-gallery-section")(
            h.h3(section_title; class="htmxo-gallery-section-heading"),
            [plot_card(e[1], e[2], e[3], length(e) >= 6 ? e[6] : nothing) for e in entries]...,
        )
    end

    demo_card(href, title, description) = h.article(; class="htmxo-gallery-card")(
        h.h4(; class="htmxo-gallery-card-title")(
            h.a(title;
                href=href,
                hx_get=href,
                hx_target="#main-content",
                hx_swap="innerHTML",
                hx_push_url="true"),
        ),
        h.p(description; class="htmxo-gallery-card-description"),
    )

    gallery_index = h.div(; class="htmxo-gallery")(
        h.p("$(length(PLOTS)) examples of AlgebraOfGraphics.jl specs translated to Vega-Lite. ",
            h.a("Data Explorer →"; href=__self__/"explorer"),
            " · ",
            h.a("View flagged plots →"; href=__self__/"flagged"),
        ),
        [gallery_section(title, ids) for (title, ids) in PLOT_SECTIONS]...,
        h.section(; class="htmxo-gallery-section")(
            h.h3("HTMX + Vega Demos"; class="htmxo-gallery-section-heading"),
            demo_card("/demo_brush",     "Brush → Server Stats",      "Brush a scatter plot, server computes stats on selection"),
            demo_card("/demo_update",    "Server-Side Data Update",   "Buttons fetch filtered data from server, plot animates update"),
            demo_card("/demo_responsive","Responsive Width",          "Plots adapt to container width — 50%, side-by-side, faceted"),
        ),
    )

    plot_nav(active_id) = h.nav(; class="aov-plot-nav")(
        h.a("← Gallery"; href=__self__, hx_get=__self__, hx_target="#main-content", hx_swap="innerHTML", hx_push_url="true", role="button", class="outline secondary aov-mr-auto"),
        [h.a(title;
            href=__self__/"plot/$id",
            hx_get=__self__/"plot/$id",
            hx_target="#main-content",
            hx_swap="innerHTML",
            hx_push_url="true",
            role="button",
            class=(id == active_id ? "contrast" : "secondary outline") * " aov-plot-nav-btn",
        ) for p in PLOTS for (id, title) in ((p[1], p[2]),)]...
    )

    plot_detail(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, description, code_str, spec_fn = entry[2], entry[3], entry[4], entry[5]
            let spec = spec_fn()
                plot_body = _dispatch_node(spec, identity, s -> vdraw(s))
                json_details = _dispatch_node(spec,
                    _ -> h.span(),
                    s -> h.details(; class="u-mt-4")(
                        h.summary("Vega-Lite JSON Spec"),
                        h.pre(h.code(escape_html(JSON.json(to_vegalite(s), 2))); class="u-code-block u-scroll-y-lg"),
                    ))
                h.div(
                    plot_nav(id),
                    h.h2(title),
                    h.p(description),
                    plot_body,
                    h.h4("Julia Code"; class="u-mt-5"),
                    h.pre(h.code(code_str); class="u-code-block"),
                    json_details,
                )
            end
        end
    end

    __page__(content) = htmx(
        h.main(class="container-fluid")(
            h.div(content; id="main-content"),
        );
        pico_version="2",
        extra_head=(vega_head()..., htmxo_gallery_styles(), htmxo_syntax_head()...),
    )

    @get index = gallery_index

    # Serve the AoV vega-embed runtime JS as a plain script so external
    # docs (VitePress, README inserts, etc.) can pull it in alongside
    # vega-embed without scraping it out of `htmx(…)`'s page wrapper.
    # Strips the wrapping `<script>...</script>` and serves the body
    # with `Content-Type: application/javascript`.
    @get aov_runtime_js = let
        # `vega_runtime()` returns an HTMX `Node` wrapping a `<script>`
        # element. `string(node)` gives the `HTMX.Node(...)` debug repr;
        # we want the rendered HTML, then strip the `<script>` wrap.
        wrapped = sprint(show, MIME"text/html"(), vega_runtime())
        body = replace(wrapped, r"^\s*<script[^>]*>"i => "")
        body = replace(body, r"</script>\s*$"i => "")
        MIMEResponse("application/javascript; charset=utf-8", body)
    end

    compact_card(id) = begin
        entry = find_plot(id)
        isnothing(entry) && return h.span()
        let spec = entry[5]()
            isnothing(spec) && return h.span()
            h.div(; class="aov-grid-cell")(
                h.div(entry[2]; class="aov-grid-cell-title"),
                _dispatch_node(spec, identity, s -> vdraw(s; width="container")),
            )
        end
    end

    @get compact = begin
        all_cards = [compact_card(e[1]) for section in PLOT_SECTIONS for e in filter(!isnothing, [find_plot(id) for id in section[2]])]
        h.div(; class="aov-grid-page")(
            h.h2("AlgebraOfVega Gallery"; class="u-mb-2"),
            h.div(; class="aov-grid-16")(
                all_cards...,
            ),
        )
    end

    static_compact_card(id) = begin
        entry = find_plot(id)
        isnothing(entry) && return h.span()
        let spec = entry[5]()
            isnothing(spec) && return h.span()
            path = joinpath(plots_dir, "$id.png")
            sdraw_file(spec, path; px_per_unit=2)
            h.div(; class="aov-grid-cell")(
                h.div(entry[2]; class="aov-grid-cell-title"),
                h.img(; src=__self__/"plot_img/$id.png", class="u-w-full"),
            )
        end
    end

    @get static_compact = begin
        all_cards = [static_compact_card(e[1]) for section in PLOT_SECTIONS for e in filter(!isnothing, [find_plot(id) for id in section[2]])]
        h.div(; class="aov-grid-page")(
            h.h2("AlgebraOfVega Static Gallery"; class="u-mb-2"),
            h.div(; class="aov-grid-16")(
                all_cards...,
            ),
        )
    end

    @get plot(id) = plot_detail[id]

    @get captioned_demo = let
        id = "captioned-demo"
        summary = _preaggregate(faceted_regression_predictions(), :x, :panel, :site)
        the_spec = data(summary) * mapping(:x, :median, color=:panel, row=:site) *
                   lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
                   config(title="Captioned Pre-aggregated Lineribbon")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned pre-aggregated lineribbon",
            short = "Posterior medians + 50/80/95% CrIs across 2 conditions × 2 sites. " *
                    "Use the picker to remap color/row; the data button always reflects " *
                    "the underlying summary table.",
            long = "The plot is built via the spec-dispatch `with_plot_caption` with " *
                   "`auto_remap=(; dims=...)`, over a pre-aggregated summary (median, " *
                   "q025, q10, q25, q75, q90, q975 columns). Controls appear above the " *
                   "`<figure>` (controls → caption → plot). The CSV button reads from " *
                   "the live Vega view via `view.data('source_0')`, so after a remap it " *
                   "still returns the original input rows. The lazy 'Show data' details " *
                   "below the plot renders the same table client-side, sortable.",
        )
        h.main(class="container")(
            h.h1("Captioned plot demo"),
            h.p("Verifies the HTMXObjects caption integration on the most common " *
                "bruno path: pre-aggregated lineribbon + auto_remap_node via spec dispatch."),
            with_plot_caption(the_spec, caption;
                plot_id=id,
                filename_base="lineribbon_summary",
                auto_remap=(; dims=[:panel => "Condition", :site => "Site"]),
            ),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get captioned_spec_demo = let
        id = "captioned-spec-demo"
        draws = sample_posterior_draws()
        the_spec = data(draws) * mapping(:value, y=:parameter, color=:chain) * pointinterval() *
                   config(title="Captioned pointinterval (spec dispatch)")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned pointinterval via spec dispatch",
            short = "Exercises `with_plot_caption(spec::VegaSpec, caption; auto_remap, summary_table=:auto)` — " *
                    "controls hoist above the figure, auto-summary table below the plot.",
            long = "The `::VegaSpec` dispatch builds the plot internally, detects the " *
                   "PointIntervalAnalysis transformation, and auto-generates a `draws_summary_table` " *
                   "with one column per parameter (grouped by :chain via the color mapping).",
        )
        h.main(class="container")(
            h.h1("Captioned spec-dispatch demo"),
            h.p("Verifies auto-summary + auto_remap placement (controls above, caption+plot+summary below)."),
            with_plot_caption(the_spec, caption;
                plot_id=id,
                filename_base="pointinterval",
                auto_remap=(; dims=[:chain => "Chain"]),
            ),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get captioned_lineribbon_demo = let
        id = "captioned-lineribbon-demo"
        the_spec = data(grouped_regression_predictions()) *
                   mapping(:x, :y, group=:draw, color=:group) *
                   lineribbon() *
                   config(width=500, height=350, title="Captioned raw-draws lineribbon")
        caption = HTMXObjects.CaptionSpec(;
            title = "Captioned lineribbon (raw draws, auto-summary)",
            short = "Verifies the lineribbon path of `_auto_summary_args`: long-format draws " *
                    "table → per-x median [lo, hi] grouped by color, inside the Pretty/Raw toggle.",
            long = "Uses `lineribbon()` over raw draws (one row per (x, draw, group)). The " *
                   "summary table groups by [x, color, ...] and reports the value field's " *
                   "median + 95% CI per group.",
        )
        h.main(class="container")(
            h.h1("Captioned lineribbon (raw draws) demo"),
            h.p("Verifies auto-summary on raw-draws lineribbon (LineRibbonAnalysis)."),
            with_plot_caption(the_spec, caption; plot_id=id, filename_base="lineribbon"),
            HTMXObjects.caption_style(),
            HTMXObjects.sortable_table_js(),
            HTMXObjects.download_table_js(),
        )
    end

    @get card_plot(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, code_str, spec_fn = entry[2], entry[4], entry[5]
            let spec = spec_fn()
                json_str = JSON.json(to_vegalite(spec), 2)
                h.div(
                    vdraw(spec),
                    h.details(; class="u-mt-2")(
                        h.summary("Julia Code"),
                        h.pre(h.code(code_str); class="u-code-block u-text-sm"),
                    ),
                    h.details(; class="u-mt-1")(
                        h.summary("Vega-Lite JSON"),
                        h.pre(h.code(escape_html(json_str)); class="u-code-block u-text-sm u-scroll-y"),
                    ),
                )
            end
        end
    end

    @post flag(id) = begin
        toggle_flag!(id)
        flag_button(id)
    end

    # `/record_gallery` is provided by the @include below. It mounts
    # HTMXObjects's `RecordingRoutes` (from HTMXObjectsTreebarsExt) at the
    # `/record_gallery` prefix and supplies the gallery path enumerator
    # plus the docs-deploy `record_base` URL prefix. `?force=true`
    # invalidates the cached run and re-records.

    @get flagged = begin
        flags = load_flags()
        content = if isempty(flags)
            h.div(
                h.h1("Flagged Plots"),
                h.p("No flagged plots."),
                h.a("← Back to gallery"; href=__self__, class="aov-back-link"),
            )
        else
            flagged_ids = sort(collect(flags))
            flagged_entries = filter(!isnothing, [find_plot(id) for id in flagged_ids])
            h.div(
                h.h1("Flagged Plots ($(length(flagged_entries)))"),
                h.a("← Back to gallery"; href=__self__, class="aov-back-link u-mb-4 u-inline-block"),
                h.div(; class="aov-grid-4")(
                    [plot_card(e[1], e[2], e[3], length(e) >= 6 ? e[6] : nothing) for e in flagged_entries]...,
                ),
            )
        end
        content
    end

    @get spec(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            "Unknown plot: $id"
        else
            spec = entry[5]()
            json_response(JSON.json(to_vegalite(spec), 2))
        end
    end

    @get inspect_layer(expr) = begin
        layer = if expr == "linear"
            linear()
        elseif expr == "smooth"
            smooth()
        elseif expr == "density"
            density()
        elseif expr == "histogram"
            histogram()
        elseif expr == "frequency"
            frequency()
        elseif expr == "expectation"
            expectation()
        else
            nothing
        end
        if isnothing(layer)
            "Unknown: $expr"
        else
            lines = String[]
            push!(lines, "typeof: $(typeof(layer))")
            push!(lines, "fields: $(fieldnames(typeof(layer)))")
            t = layer.transformation
            push!(lines, "transformation: $t")
            push!(lines, "transformation type: $(typeof(t))")
            _push_compose_parts!(lines, t)
            if hasproperty(layer, :positional)
                push!(lines, "positional: $(layer.positional)")
            end
            if hasproperty(layer, :named)
                push!(lines, "named: $(layer.named)")
            end
            join(lines, "\n")
        end
    end

    # --- Pregrouped debug page ---
    @get debug_pregrouped = begin
        # Test case 1: basic with renamer
        spec1 = pregrouped(
            fill.(1:3, 100) => renamer(["A", "B", "C"]),
            [randn(100) for _ in 1:3]
        ) * visual(BoxPlot) * config(title="1. Basic with renamer")

        # Test case 2: without renamer
        spec2 = pregrouped(
            fill.(1:2, 50),
            [randn(50) for _ in 1:2]
        ) * visual(BoxPlot) * config(title="2. Without renamer")

        # Test case 3: Bruno QT pattern (axes/eachcol)
        cdslope = randn(5000)
        cdslope_mat = reshape(cdslope, 1000, 5)
        spec3 = pregrouped(
            fill.(axes(cdslope_mat, 2), size(cdslope_mat, 1)) => renamer(string.([0, 10, 20, 40, 80])),
            collect(eachcol(cdslope_mat))
        ) * visual(BoxPlot) * config(title="3. Bruno QT pattern (axes/eachcol)")

        specs = [spec1, spec2, spec3]
        h.div(
            vega_head(),
            h.h2("Pregrouped Debug"),
            [h.div(; class="u-mb-6")(
                vdraw(s),
                h.details(
                    h.summary("Spec JSON"),
                    h.pre(h.code(JSON.json(to_vegalite(s), 2)); class="u-text-xs u-scroll-y-lg"),
                ),
            ) for s in specs]...,
        )
    end

    # --- Standalone HTML page for any plot ---
    @get standalone(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            HTTP.Response(404, ["Content-Type" => "text/plain"], body="Unknown plot: $id")
        else
            let spec = entry[5]()
                _dispatch_node(spec,
                    s -> h.html(h.head(vega_head()...), h.body(s)),
                    s -> HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body=to_html(s)))
            end
        end
    end

    # --- Data Explorer (fully client-side) ---

    EXPLORER_DATASETS = default_explorer_datasets()

    @get explorer = h.div(
        explorer_widget(EXPLORER_DATASETS),
        h.a("← Back to gallery"; href=__self__, class="u-inline-block u-mt-4"),
    )

    # --- Interactive demo: Brush → Server Stats ---

    brush_plot_spec = data(cars()) *
        mapping(:horsepower, :mpg, color=:origin) *
        visual(Scatter) *
        config(
            width=550, height=350,
            title="Brush to Compute Server-Side Stats",
            params=[Dict("name" => "brush", "select" => "interval")],
            encoding=Dict(
                "opacity" => Dict(
                    "condition" => Dict("param" => "brush", "value" => 1),
                    "value" => 0.15,
                ),
            ),
        )

    @get brush_stats(; horsepower="", mpg="") = begin
        c = cars()
        hp_range = isempty(horsepower) ? nothing : JSON.parse(horsepower)
        mpg_range = isempty(mpg) ? nothing : JSON.parse(mpg)

        if isnothing(hp_range) || isnothing(mpg_range)
            h.div(; id="brush-stats")(
                h.p("Drag a rectangle on the plot to select points."; class="u-text-muted"),
            )
        else
            hp_min, hp_max = extrema(hp_range)
            mpg_min, mpg_max = extrema(mpg_range)
            mask = [
                hp_min <= hp <= hp_max && mpg_min <= m <= mpg_max
                for (hp, m) in zip(c.horsepower, c.mpg)
            ]
            n = sum(mask)
            if n == 0
                h.div(; id="brush-stats")(h.p("No points in selection."))
            else
                sel_hp = c.horsepower[mask]
                sel_mpg = c.mpg[mask]
                sel_origins = c.origin[mask]
                origin_counts = Dict{String,Int}()
                for o in sel_origins
                    origin_counts[o] = get(origin_counts, o, 0) + 1
                end
                h.div(; id="brush-stats")(
                    h.h4("Selection: $n points"),
                    h.table(; role="grid")(
                        h.thead(h.tr(h.th("Stat"), h.th("Horsepower"), h.th("MPG"))),
                        h.tbody(
                            h.tr(h.td("Min"), h.td(string(minimum(sel_hp))), h.td(string(minimum(sel_mpg)))),
                            h.tr(h.td("Max"), h.td(string(maximum(sel_hp))), h.td(string(maximum(sel_mpg)))),
                            h.tr(h.td("Mean"), h.td(string(round(sum(sel_hp)/n, digits=1))), h.td(string(round(sum(sel_mpg)/n, digits=1)))),
                        ),
                    ),
                    h.p("Origins: ", join(["$o ($c)" for (o, c) in sort(collect(origin_counts))], ", ")),
                )
            end
        end
    end

    @get demo_brush = h.div(
            plot_nav("demo_brush"),
            h.h2("Brush → Server Stats"),
            h.p("Drag a selection on the scatter plot. The brush bounds are sent to the server via HTMX, ",
                "which computes summary statistics in Julia and returns them as HTML."),
            vdraw(brush_plot_spec;
                id="brush-demo",
                signals=[(signal="brush", url="/brush_stats", target="#brush-stats", debounce=200)],
            ),
            h.div(; id="brush-stats", class="u-mt-4")(
                h.p("Drag a rectangle on the plot to select points."; class="u-text-muted"),
            ),
            h.h4("How it works"; class="u-mt-5"),
            h.pre(h.code("""# In the @htmx struct:
vdraw(spec;
    id="brush-demo",
    signals=[(signal="brush", url="/brush_stats", target="#brush-stats")],
)

# The signal listener sends brush bounds as query params:
#   GET /brush_stats?horsepower=[50,200]&mpg=[15,30]
# Server computes stats and returns HTML fragment.""");
                class="u-code-block"),
    )

    # --- Interactive demo: Server-side data update ---

    @get demo_update = begin
        origins = ["All", "USA", "Europe", "Japan"]
        h.div(
            plot_nav("demo_update"),
            h.h2("Server-Side Data Filtering"),
            h.p("Click a button to fetch filtered data from the server. ",
                "The Vega view's dataset is swapped without re-creating the plot — axes animate smoothly."),
            vdraw(
                data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
                config(width=550, height=350, title="Click a button to filter");
                id="update-demo",
            ),
            h.div(; class="aov-plot-row-tight")(
                [h.button(o;
                    hx_get=__self__/"filter_data/$o",
                    hx_target="#update-script",
                    hx_swap="innerHTML",
                    class="outline",
                ) for o in origins]...
            ),
            h.div(; id="update-script"),
            h.h4("How it works"; class="u-mt-5"),
            h.pre(h.code("""# Button triggers HTMX GET:
#   <button hx-get="/update_data/USA" hx-target="#update-script">

# Server filters data and returns a script that updates the view:
@get update_data(origin) = begin
    filtered = origin == "All" ? cars() : filter_by_origin(cars(), origin)
    update_data("update-demo", filtered)
end""");
                class="u-code-block"),
        )
    end

    @get demo_responsive = begin
        let spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter)
            faceted_spec = data(cars()) * mapping(:horsepower, :mpg, col=:origin) * visual(Scatter)
            h.div(
                h.h2("Responsive Width Demo"),
                h.p("Plots adapt to their container width. Resize the browser to see them reflow."),

                h.h4("Full width (layered)"),
                vdraw(spec + (data(cars()) * mapping(:horsepower, :mpg) * linear())),

                h.h4("50% width"; class="u-mt-5"),
                h.div(; class="aov-w-50")(vdraw(spec)),

                h.h4("Side by side (50% each)"; class="u-mt-5"),
                h.div(; class="aov-plot-row")(
                    h.div(; class="aov-flex-1")(vdraw(spec)),
                    h.div(; class="aov-flex-1")(vdraw(spec + (data(cars()) * mapping(:horsepower, :mpg) * linear()))),
                ),

                h.h4("Faceted — full width"; class="u-mt-5"),
                vdraw(faceted_spec),

                h.h4("Faceted — 60% width"; class="u-mt-5"),
                h.div(; class="aov-w-60")(vdraw(faceted_spec)),

                h.h4("Saveable (actions=true)"; class="u-mt-5"),
                h.p("Click the ⋯ menu to Save as PNG/SVG."),
                vdraw(spec; actions=true),
            )
        end
    end

    @get filter_data(origin) = begin
        c = cars()
        if origin == "All"
            update_data("update-demo", c)
        else
            mask = [o == origin for o in c.origin]
            filtered = (;
                horsepower = c.horsepower[mask],
                mpg = c.mpg[mask],
                origin = c.origin[mask],
                cylinders = c.cylinders[mask],
                weight = c.weight[mask],
                acceleration = c.acceleration[mask],
            )
            update_data("update-demo", filtered)
        end
    end

    plots_dir = let d = joinpath(@__DIR__, "..", "plots"); mkpath(d); d end

    @get static_plot(id) = begin
        entry = find_plot(id)
        if isnothing(entry)
            h.p("Unknown plot: $id")
        else
            title, spec_fn = entry[2], entry[5]
            let spec = spec_fn()
                path = joinpath(plots_dir, "$id.png")
                sdraw_file(spec, path; px_per_unit=2)
                h.div(
                    h.h3(title),
                    h.img(; src=__self__/"plot_img/$id.png", class="aov-img-fluid"),
                )
            end
        end
    end

    @get plot_img(filename) = begin
        path = joinpath(plots_dir, filename)
        if isfile(path)
            HTTP.Response(200, ["Content-Type" => "image/png"], read(path))
        else
            HTTP.Response(404, "Not found")
        end
    end

    static_plot_card(id) = begin
        let entry = find_plot(id)
            isnothing(entry) && return h.article(h.p("Unknown: $id"))
            title = entry[2]
            let spec = entry[5]()
                path = joinpath(plots_dir, "$id.png")
                sdraw_file(spec, path; px_per_unit=2)
                h.article(; class="aov-card")(
                    h.header(; class="aov-card-header")(
                        h.a(title;
                            href=__self__/"static_plot/$id", target="_blank",
                            class="aov-card-title-link",
                        ),
                        flag_button(id),
                    ),
                    h.img(; src=__self__/"plot_img/$id.png", class="u-w-full"),
                )
            end
        end
    end

    static_gallery_section(section_title, ids) = begin
        entries = filter(!isnothing, [find_plot(id) for id in ids])
        h.div(; class="u-mb-6")(
            h.h3(section_title; class="u-mb-2"),
            h.div(; class="aov-grid-4")(
                [static_plot_card(e[1]) for e in entries]...,
            ),
        )
    end

    @get static_gallery = h.div(
        h.h2("Static Gallery (Makie/CairoMakie)"),
        [static_gallery_section(title, ids) for (title, ids) in PLOT_SECTIONS]...,
    )

    @include tests = TestRoutes(; __req__, test_module=@__MODULE__)

    @include record_gallery = RecordingRoutes(;
        app_type=AppContext,
        paths=_RECORDING_PATHS,
        record_dir=_RECORDING_DIR,
        record_base=_recording_base(),
        label="Recording AoV gallery",
    )
end

function __init__()
    route!(AppContext())
end

end # module AlgebraOfVegaGallery
