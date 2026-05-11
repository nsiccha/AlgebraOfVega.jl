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

# --- AppData: every data/cached value the app holds ---
#
# A single DO global. Per-id state (loaded spec, derived properties)
# lives in the inline indexed `entry(id)` DO so it's cached by id and
# disappears in lockstep with the `Gallery` it's keyed against. There
# is no `_gallery_specs` Dict, no `PLOTS` 5-tuple shim, and no
# `find_plot` linear scan — the upstream `Gallery` / `GalleryItem` /
# `find_item` API is the source of truth.

@dynamicstruct struct AoVAppData
    gallery_dir = joinpath(dirname(dirname(@__DIR__)), "examples", "aov-gallery")
    gallery     = Gallery(gallery_dir)

    flagged_path = joinpath(@__DIR__, "..", "flagged.txt")
    plots_dir    = (let d = joinpath(@__DIR__, "..", "plots"); mkpath(d); d end)

    # File-of-truth flag set. Owns the path and the ops that read/write
    # it — callers never pass the path around. `load()` is an IP (re-
    # reads the file each call); `save(set)` and `toggle!(id)` write.
    @struct flags = begin
        path = flagged_path
        load() = begin
            s = Set{String}()
            isfile(path) || return s
            for line in readlines(path)
                l = strip(line)
                !isempty(l) && push!(s, l)
            end
            s
        end
        save(set) = open(path, "w") do io
            for fid in sort(collect(set))
                println(io, fid)
            end
        end
        toggle!(fid) = begin
            s = load()
            fid in s ? delete!(s, fid) : push!(s, fid)
            save(s)
            fid in s
        end
    end

    # Recording flow (HTMXObjectsTreebarsExt's `RecordingRoutes`).
    recording_dir  = joinpath(dirname(dirname(@__DIR__)), "docs", "src", "public", "live-aov")
    recording_base = get(ENV, "RECORD_BASE_PREFIX", "/AlgebraOfVega.jl/dev/live-aov")
    recording_paths = let ids = [it.id for it in gallery.items]
        vcat(
            ["/"],
            ["/entries/$id/plot"       for id in ids],
            ["/entries/$id/standalone" for id in ids],
            ["/entries/$id/spec"       for id in ids],
            ["/aov_runtime_js", "/explorer", "/flagged"],
        )
    end

    explorer_datasets = default_explorer_datasets()

    # Curated section grouping for the index. Order is simple → complex
    # → tests/edge-cases. The final "Uncategorized" bucket collects
    # every gallery item not assigned to one of the curated sections
    # above; those are bug-repro / test items rather than curated
    # examples, so they render last.
    curated_sections = [
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

    plot_sections = let curated_ids = Set(id for (_, ids) in curated_sections for id in ids),
                        leftover = [it.id for it in gallery.items if !(it.id in curated_ids)]
        isempty(leftover) ? curated_sections :
            [curated_sections..., "Tests / Edge cases" => leftover]
    end

    # Flat ordered list of all GalleryItems across every section —
    # eliminates repeated `for (_, ids) … for it in [find_item(…)]` in routes.
    gallery_items = [find_item(gallery, id) for (_, ids) in plot_sections for id in ids]

    # Per-id loaded spec + derived display values. `Base.include` runs
    # the example file in this module's namespace so cars(), data(),
    # mapping(), … resolve, and returns the file's last top-level
    # expression (the AoV spec). DO caches by id, so each id's file is
    # evaluated at most once per instance.
    @struct entry(id) = begin
        item         = find_item(gallery, id)
        title        = item.title
        description  = item.description
        code_string  = item.code_string
        spec         = Base.include(@__MODULE__, item.path)
        is_html_node = spec isa HTMX.Node

        # Body renderings — pass through if the spec already produced
        # HTML directly, otherwise vega-draw at the requested width.
        body_card    = is_html_node ? spec : vdraw(spec; id=id)
        body_compact = is_html_node ? spec : vdraw(spec; width="container")
        body_plain   = is_html_node ? spec : vdraw(spec)

        # Pure-data JSON derivations. `to_vegalite` errors for HTMX.Node
        # specs, so these properties are only safe to reach for after
        # `is_html_node` has been checked false (or via `json_details`,
        # which gates internally).
        vegalite_dict   = to_vegalite(spec)
        vegalite_json   = JSON.json(vegalite_dict, 2)
        escaped_json    = escape_html(vegalite_json)

        json_details = is_html_node ? h.span() :
            h.details(; class="aov-json-details")(
                h.summary("Vega-Lite JSON Spec"),
                h.pre(h.code(escaped_json); class="aov-code-scroll"),
            )

        standalone_html = is_html_node ?
            h.html(h.head(vega_head()...), h.body(spec)) :
            HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], body=to_html(spec))

        static_png_path = joinpath(plots_dir, "$(id).png")
        ensure_static_png() = (sdraw_file(spec, static_png_path; px_per_unit=2); static_png_path)
    end
end

const APPDATA = AoVAppData()

# --- HTMXObjects App ---

@htmx struct AppContext
    __appdata__ = APPDATA

    # === Per-id rendering + routes ===
    # Folded into one `@include` so all (id)-keyed routes share a single
    # mount prefix (`/entries/<id>/…`), and the renderer properties live
    # in the same scope as the routes that serve them. Plural mirrors
    # WHMC's `@include posteriors(name)` (singular `posterior(name)`
    # being the AppData entity). URL shape:
    #   /entries/<id>/plot          (was /plot/<id>)
    #   /entries/<id>/standalone    (was /standalone/<id>)
    #   /entries/<id>/spec          (was /spec/<id>)
    #   /entries/<id>/static_plot   (was /static_plot/<id>)
    #   /entries/<id>/card_plot     (was /card_plot/<id>)
    #   POST /entries/<id>/flag     (was POST /flag/<id>)
    @include entries(id::String) = begin
        e    = __appdata__.entry(id)
        item = e.item

        flag_button() = let flagged = id in __appdata__.flags.load()
            h.button(flagged ? "flagged" : "flag";
                hx_post=__self__/"flag",
                hx_target="#flag-$id",
                hx_swap="outerHTML",
                id="flag-$id",
                class="htmxo-toggle-button htmxo-flag-button",
                aria_pressed=flagged,
            )
        end

        card = h.article(
            h.h4(
                h.a(e.title; href=__self__/"standalone", target="_blank"),
                e.is_html_node ? h.span() :
                    h.a(" · static"; rel="external",
                        href=__self__/"static_plot", target="_blank"),
                flag_button(),
            ),
            isempty(e.description) ? h.span() :
                h.p(e.description),
            e.body_card,
            h.pre(h.code(e.code_string; class="language-julia")),
        )

        compact = h.figure(
            h.figcaption(e.title),
            e.body_compact,
        )

        static_compact = begin
            e.ensure_static_png()
            h.figure(
                h.figcaption(e.title),
                h.img(; src=__parent__/"plot_img/$(id).png"),
            )
        end

        static_card = begin
            e.ensure_static_png()
            h.article(
                h.header(
                    h.a(e.title; href=__self__/"static_plot", target="_blank"),
                    flag_button(),
                ),
                h.img(; src=__parent__/"plot_img/$(id).png"),
            )
        end

        @get plot() = h.div(; class="aov-detail")(
            __parent__.plot_nav(id),
            h.h2(e.title),
            h.p(e.description),
            e.body_plain,
            h.h4("Julia Code"),
            h.pre(h.code(e.code_string)),
            e.json_details,
        )

        @get card_plot() = h.div(; class="aov-card-with-specs")(
            vdraw(e.spec),
            h.details(
                h.summary("Julia Code"),
                h.pre(h.code(e.code_string)),
            ),
            h.details(
                h.summary("Vega-Lite JSON"),
                h.pre(h.code(e.escaped_json); class="aov-code-scroll"),
            ),
        )

        @get spec() = MIMEResponse("application/json", e.vegalite_json)
        @get standalone() = e.standalone_html

        @get static_plot() = begin
            e.ensure_static_png()
            h.div(
                h.h3(e.title),
                h.img(; src=__parent__/"plot_img/$(id).png"),
            )
        end
        @post flag() = begin
            __appdata__.flags.toggle!(id)
            flag_button()
        end
    end

    # === Per-section rendering ===
    # Folds the previous `gallery_section` and `static_gallery_section`
    # (both keyed by `(section_title, ids)`) into one inline child.
    @struct section(section_title, ids) = begin
        items = [find_item(__appdata__.gallery, id) for id in ids]

        # Cross-inline-child calls (`entries` is a sibling `@include`
        # of AppContext) require `__parent__` — bare names only resolve
        # for parent *fields/methods*, not parent indexed children.
        normal = h.section(
            h.h3(section_title),
            [__parent__.entries(it.id).card for it in items]...,
        )

        static = h.div(; class="aov-static-section")(
            h.h3(section_title),
            h.div(; class="htmxo-grid aov-grid-static")(
                [__parent__.entries(it.id).static_card for it in items]...,
            ),
        )
    end

    # === Per-demo rendering ===
    # Bundled mount: each variant is its own @include with its data,
    # routes, and the @get index that serves its body. Gallery cards are
    # built by the demo bundle's `card` IP.
    @include demo = begin
        @include brush = begin
            label       = "Brush → Server Stats"
            description = "Brush a scatter plot, server computes stats on selection"
            plot_spec   = data(cars()) *
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

            @get index() = h.div(; class="aov-demo-page")(
                __parent__.__parent__.plot_nav("demo_brush"),
                h.h2("Brush → Server Stats"),
                h.p("Drag a selection on the scatter plot. The brush bounds are sent to the server via HTMX, ",
                    "which computes summary statistics in Julia and returns them as HTML."),
                vdraw(plot_spec;
                    id="brush-demo",
                    signals=[(signal="brush", url=string(__self__/"stats"), target="#brush-stats", debounce=200)],
                ),
                h.div(; id="brush-stats", class="aov-brush-stats")(
                    h.p(h.small("Drag a rectangle on the plot to select points.")),
                ),
                h.h4("How it works"),
                h.pre(h.code("""# In the @htmx struct:
vdraw(spec;
    id="brush-demo",
    signals=[(signal="brush", url=string(__self__/"stats"), target="#brush-stats")],
)

# The signal listener sends brush bounds as query params:
#   GET /demo/brush/stats?horsepower=[50,200]&mpg=[15,30]
# Server computes stats and returns HTML fragment.""")),
            )

            @get stats(; horsepower="", mpg="") = begin
                c = cars()
                hp_range = isempty(horsepower) ? nothing : JSON.parse(horsepower)
                mpg_range = isempty(mpg) ? nothing : JSON.parse(mpg)

                if isnothing(hp_range) || isnothing(mpg_range)
                    h.div(; id="brush-stats")(
                        h.p(h.small("Drag a rectangle on the plot to select points.")),
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
        end

        @include update = begin
            label       = "Server-Side Data Update"
            description = "Buttons fetch filtered data from server, plot animates update"
            origins     = ["All", "USA", "Europe", "Japan"]

            @get index() = h.div(; class="aov-demo-page")(
                __parent__.__parent__.plot_nav("demo_update"),
                h.h2("Server-Side Data Filtering"),
                h.p("Click a button to fetch filtered data from the server. ",
                    "The Vega view's dataset is swapped without re-creating the plot — axes animate smoothly."),
                vdraw(
                    data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
                    config(width=550, height=350, title="Click a button to filter");
                    id="update-demo",
                ),
                h.div(; role="group")(
                    [h.button(o;
                        hx_get=__self__/"filter/$o",
                        hx_target="#update-script",
                        hx_swap="innerHTML",
                        class="outline",
                    ) for o in origins]...
                ),
                h.div(; id="update-script"),
                h.h4("How it works"),
                h.pre(h.code("""# Button triggers HTMX GET:
#   <button hx-get="/demo/update/filter/USA" hx-target="#update-script">

# Server filters data and returns a script that updates the view:
@get filter(origin) = begin
    filtered = origin == "All" ? cars() : filter_by_origin(cars(), origin)
    update_data("update-demo", filtered)
end""")),
            )

            @get filter(origin) = begin
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
        end

        @include responsive = begin
            label       = "Responsive Width"
            description = "Plots adapt to container width — 50%, side-by-side, faceted"
            scatter_spec  = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter)
            faceted_spec  = data(cars()) * mapping(:horsepower, :mpg, col=:origin) * visual(Scatter)

            @get index() = h.div(; class="aov-demo-page")(
                h.h2("Responsive Width Demo"),
                h.p("Plots adapt to their container width. Resize the browser to see them reflow."),

                h.h4("Full width (layered)"),
                vdraw(scatter_spec + (data(cars()) * mapping(:horsepower, :mpg) * linear())),

                h.h4("50% width"),
                h.div(; data_cell="half")(vdraw(scatter_spec)),

                h.h4("Side by side (50% each)"),
                h.div(; data_cell="row")(
                    h.div(vdraw(scatter_spec)),
                    h.div(vdraw(scatter_spec + (data(cars()) * mapping(:horsepower, :mpg) * linear()))),
                ),

                h.h4("Faceted — full width"),
                vdraw(faceted_spec),

                h.h4("Faceted — 60% width"),
                h.div(; data_cell="three-fifths")(vdraw(faceted_spec)),

                h.h4("Saveable (actions=true)"),
                h.p("Click the ⋯ menu to Save as PNG/SVG."),
                vdraw(scatter_spec; actions=true),
            )
        end

        card(name::Symbol) = let d = getproperty(__self__, name); href = __self__/string(name)
            h.article(
                h.h4(h.a(d.label; href=href, hx_get=href,
                    hx_target="#content", hx_swap="innerHTML", hx_push_url="true")),
                h.p(d.description),
            )
        end
    end

    @get index() = h.div(; class="htmxo-gallery")(
        h.p("$(length(__appdata__.gallery.items)) examples of AlgebraOfGraphics.jl specs translated to Vega-Lite. ",
            h.a("Data Explorer →"; href=__self__/"explorer"),
            " · ",
            h.a("View flagged plots →"; href=__self__/"flagged"),
        ),
        [section(title, ids).normal for (title, ids) in __appdata__.plot_sections]...,
        h.section(
            h.h3("HTMX + Vega Demos"),
            [demo.card(name) for name in (:brush, :update, :responsive)]...,
        ),
    )

    plot_nav(active_id) = h.nav(; class="aov-plot-nav")(
        h.a("← Gallery"; href=__self__, hx_get=__self__, hx_target="#content", hx_swap="innerHTML", hx_push_url="true", role="button", class="outline secondary"),
        [h.a(it.title;
            href=__self__/"entries/$(it.id)/plot",
            hx_get=__self__/"entries/$(it.id)/plot",
            hx_target="#content",
            hx_swap="innerHTML",
            hx_push_url="true",
            role="button",
            class=(it.id == active_id ? "contrast" : "secondary outline"),
        ) for it in __appdata__.gallery.items]...
    )

    __page__(content) = htmx(
        h.main(class="container-fluid")(
            h.div(content; id="content"),
        );
        pico_version="2",
        extra_head=(vega_head()..., htmxo_gallery_styles(), htmxo_syntax_head()...),
    )

    # Serve the AoV vega-embed runtime JS as a plain script so external
    # docs (VitePress, README inserts, etc.) can pull it in alongside
    # vega-embed without scraping it out of `htmx(…)`'s page wrapper.
    # Strips the wrapping `<script>...</script>` and serves the body
    # with `Content-Type: application/javascript`.
    @get aov_runtime_js() = let
        wrapped = sprint(show, MIME"text/html"(), vega_runtime())
        body = replace(wrapped, r"^\s*<script[^>]*>"i => "")
        body = replace(body, r"</script>\s*$"i => "")
        MIMEResponse("application/javascript; charset=utf-8", body)
    end

    @get compact() = h.div(; class="aov-grid-page")(
        h.h2("AlgebraOfVega Gallery"),
        h.div(; class="htmxo-grid aov-grid-dense")(
            [entries(it.id).compact for it in __appdata__.gallery_items]...,
        ),
    )

    @get static_compact() = h.div(; class="aov-grid-page")(
        h.h2("AlgebraOfVega Static Gallery"),
        h.div(; class="htmxo-grid aov-grid-dense")(
            [entries(it.id).static_compact for it in __appdata__.gallery_items]...,
        ),
    )

    # === Captioned-plot demos ===
    # Bundled mount: three named variants own the per-variant data, and
    # the single route lives in the same scope. URLs: /captioned/<name>.
    @include captioned = begin
        @struct preagg = begin
            id            = "captioned-demo"
            the_spec      = data(_preaggregate(faceted_regression_predictions(), :x, :panel, :site)) *
                            mapping(:x, :median, color=:panel, row=:site) *
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
            filename_base = "lineribbon_summary"
            auto_remap    = (; dims=[:panel => "Condition", :site => "Site"])
            page_title    = "Captioned plot demo"
            page_intro    = "Verifies the HTMXObjects caption integration on the most common " *
                            "bruno path: pre-aggregated lineribbon + auto_remap_node via spec dispatch."
        end

        @struct spec = begin
            id            = "captioned-spec-demo"
            the_spec      = data(sample_posterior_draws()) *
                            mapping(:value, y=:parameter, color=:chain) * pointinterval() *
                            config(title="Captioned pointinterval (spec dispatch)")
            caption = HTMXObjects.CaptionSpec(;
                title = "Captioned pointinterval via spec dispatch",
                short = "Exercises `with_plot_caption(spec::VegaSpec, caption; auto_remap, summary_table=:auto)` — " *
                        "controls hoist above the figure, auto-summary table below the plot.",
                long = "The `::VegaSpec` dispatch builds the plot internally, detects the " *
                       "PointIntervalAnalysis transformation, and auto-generates a `draws_summary_table` " *
                       "with one column per parameter (grouped by :chain via the color mapping).",
            )
            filename_base = "pointinterval"
            auto_remap    = (; dims=[:chain => "Chain"])
            page_title    = "Captioned spec-dispatch demo"
            page_intro    = "Verifies auto-summary + auto_remap placement (controls above, caption+plot+summary below)."
        end

        @struct lineribbon = begin
            id            = "captioned-lineribbon-demo"
            the_spec      = data(grouped_regression_predictions()) *
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
            filename_base = "lineribbon"
            auto_remap    = nothing
            page_title    = "Captioned lineribbon (raw draws) demo"
            page_intro    = "Verifies auto-summary on raw-draws lineribbon (LineRibbonAnalysis)."
        end

        @get index(name::Symbol) = let c = getproperty(__self__, name)
            # No <main> wrapper here — AppContext's __page__ already
            # supplies the page's single <main class="container-fluid">.
            # A <section> is the semantic fit for "this captioned demo".
            h.section(
                h.h1(c.page_title),
                h.p(c.page_intro),
                with_plot_caption(c.the_spec, c.caption;
                    plot_id=c.id, filename_base=c.filename_base, auto_remap=c.auto_remap),
                HTMXObjects.caption_style(),
                HTMXObjects.sortable_table_js(),
                HTMXObjects.download_table_js(),
            )
        end
    end

    # `/record_gallery` is provided by the @include below. It mounts
    # HTMXObjects's `RecordingRoutes` (from HTMXObjectsTreebarsExt) at the
    # `/record_gallery` prefix and supplies the gallery path enumerator
    # plus the docs-deploy `record_base` URL prefix. `?force=true`
    # invalidates the cached run and re-records.

    @get flagged() = begin
        flags = __appdata__.flags.load()
        if isempty(flags)
            h.div(
                h.h1("Flagged Plots"),
                h.p("No flagged plots."),
                h.a("← Back to gallery"; href=__self__, class="htmxo-back-link"),
            )
        else
            flagged_ids = sort(collect(flags))
            h.div(
                h.h1("Flagged Plots ($(length(flagged_ids)))"),
                h.a("← Back to gallery"; href=__self__, class="htmxo-back-link"),
                h.div(; class="htmxo-grid aov-grid-static")(
                    [entries(id).card for id in flagged_ids]...,
                ),
            )
        end
    end

    @get inspect_layer(expr::Symbol) = let
        layer = (; linear, smooth, density, histogram, frequency, expectation)[expr]()
        t = layer.transformation
        lines = String[
            "typeof: $(typeof(layer))",
            "fields: $(fieldnames(typeof(layer)))",
            "transformation: $t",
            "transformation type: $(typeof(t))",
        ]
        if t isa ComposedFunction
            push!(lines, "  outer: $(t.outer) ($(typeof(t.outer)))")
            push!(lines, "  inner: $(t.inner) ($(typeof(t.inner)))")
        end
        hasproperty(layer, :positional) && push!(lines, "positional: $(layer.positional)")
        hasproperty(layer, :named)      && push!(lines, "named: $(layer.named)")
        join(lines, "\n")
    end

    # --- Pregrouped debug page ---
    @get debug_pregrouped() = begin
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
        # vega_head() is already injected by AppContext.__page__ (extra_head);
        # don't duplicate it here (HTMX fragments reuse the runtime already in page).
        h.div(
            h.h2("Pregrouped Debug"),
            [h.div(; class="aov-static-section")(
                vdraw(s),
                h.details(
                    h.summary("Spec JSON"),
                    h.pre(h.code(JSON.json(to_vegalite(s), 2)); class="aov-code-scroll"),
                ),
            ) for s in specs]...,
        )
    end

    # --- Data Explorer (fully client-side) ---

    @get explorer() = h.div(
        explorer_widget(__appdata__.explorer_datasets),
        h.a("← Back to gallery"; href=__self__, class="htmxo-back-link"),
    )

    @get plot_img(filename) = let path = joinpath(__appdata__.plots_dir, filename)
        if isfile(path)
            HTTP.Response(200, ["Content-Type" => "image/png"], read(path))
        else
            HTTP.Response(404, "Not found")
        end
    end

    @get static_gallery() = h.div(
        h.h2("Static Gallery (Makie/CairoMakie)"),
        [section(title, ids).static for (title, ids) in __appdata__.plot_sections]...,
    )

    @include tests = TestRoutes(; __req__, test_module=@__MODULE__)

    @include record_gallery = RecordingRoutes(;
        app_type=AppContext,
        paths=__appdata__.recording_paths,
        record_dir=__appdata__.recording_dir,
        record_base=__appdata__.recording_base,
        label="Recording AoV gallery",
    )
end

function __init__()
    route!(AppContext())
end

end # module AlgebraOfVegaGallery
