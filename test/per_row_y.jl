using TestItemRunner

# Per-row Y scale types: `scales(Y=(; scale=Dict(<row value> => log10)))` on a
# figure faceted by `row=` alone (snag `per-panel-y-scal-81725851`). Bruno
# web-sim's "Exposure by dose" draws Cmax, AUC₂₄ and Ctrough in a row each
# against the dose; shiny-rk draws Cmax and AUC on a log y axis and a quantity
# reaching zero on a linear one. Before, the `Dict` keyed only a column facet:
# on a row facet it threw "per-column Y scales need a column facet", so the app
# chose one type for the whole figure, and Cmax and AUC₂₄ lay flat under a
# linear axis whenever Ctrough could not take a log one. The row facet now
# lowers to a stack of one panel per row (`_per_row_y_vconcat!`), still one
# figure with its Ribbons | Intervals switch, legend, caption and readout.
@testsnippet AoVPerRowYFixtures begin
    using AlgebraOfVega, JSON, Tables
    const AoV = AlgebraOfVega

    PANELS = ["Cmax (ng/mL)", "AUC₂₄ (ng/mL·h)", "Ctrough (ng/mL)"]
    LOG = Dict(PANELS[1] => log10, PANELS[2] => log10)
    PCTS = ["5th", "50th", "95th"]
    DOSES = [5.0, 10, 20, 40, 80, 100, 160, 320]
    # Ctrough spans eighteen decades and reaches 1e-12: no log axis suits it.
    exposure = let rows = NamedTuple[]
        for (i, p) in enumerate(PANELS), (k, pc) in enumerate(PCTS), d in DOSES
            m = p == PANELS[3] ? 1e-13 * d^(4 + k) : (10.0i) * d * (0.3k)^2
            push!(rows, (; panel=p, quantity=string("Q", i), percentile=pc, dose=d, q50=m,
                q025=0.5m, q975=2m, q25=0.8m, q75=1.25m))
        end
        rows
    end
    marks = [(; dose=40.0, panel=p) for p in PANELS]
    span = [(; from=10.0, to=160.0, panel=p) for p in PANELS]
    rows_facet(label="") = (; row=:panel => sorter(PANELS) => label)
    # Bruno web-sim's `dose_figure` with `rows = true`: a coloured ribbon per
    # panel, the Time course's dose as a dashed rule, the fit's doses as a bar.
    function exposure_figure(; yscale=LOG, labels=:panel, label="", extra=config())
        x = :dose => "Dose (mg)"
        (data(exposure) * mapping(x, :q50 => "Exposure"; rows_facet(label)...,
                color=:percentile => sorter(PCTS) => "Population percentile") *
            lineribbon(bands=[:q025 => :q975, :q25 => :q75], probs=[0.95, 0.5], point=:median) +
         data(marks) * mapping(x; rows_facet(label)...) * visual(VLines; linestyle=:dash, color=:ink) +
         data(span) * mapping(:from => "Dose (mg)", :to => "Dose (mg)"; rows_facet(label)...) *
            visual(VSpan; color=:ink, alpha=0.45, ymin=0.975, ymax=1.0)) *
        config(scales=scales(; X=(; scale=log10, nice=false), Y=(; scale=yscale))) *
        config(facet=(; linkyaxes=:none, (isnothing(labels) ? (;) : (; ylabels=labels))...)) * extra
    end

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    # Each panel's y scale types and the titles its y encodings carry.
    yscale_types(panel) = unique([get(get(u["encoding"]["y"], "scale", Dict()), "type", "linear")
        for u in units(panel) if haskey(get(u, "encoding", Dict()), "y") && haskey(u["encoding"]["y"], "field")])
    ytitles(panel) = unique([get(u["encoding"]["y"], "title", nothing)
        for u in units(panel) if haskey(get(u, "encoding", Dict()), "y") && haskey(u["encoding"]["y"], "field")])
    xaxes(panel) = [get(u["encoding"]["x"], "axis", nothing) for u in units(panel)
        if haskey(get(u, "encoding", Dict()), "x") && haskey(u["encoding"]["x"], "field")]
    have_vl_convert() = !isnothing(get(ENV, "AOV_VL_CONVERT", nothing)) || !isnothing(Sys.which("vl-convert"))
end

@testitem "A row facet with per-row Y scales lowers to a stack of one panel per row" setup=[AoVPerRowYFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(exposure_figure())
    @test haskey(vl, "vconcat") && !haskey(vl, "facet") && !haskey(vl, "hconcat")
    panels = vl["vconcat"]
    @test length(panels) == 3
    # Listed rows log, the unlisted one linear, in the facet's order.
    @test [yscale_types(p) for p in panels] == [["log"], ["log"], ["linear"]]
    @test [p["_aovPanel"]["panel"] for p in panels] == PANELS
    # One x scale for the stack, the plot areas aligned, the facet's spacing.
    @test vl["resolve"]["scale"]["x"] == "shared"
    @test vl["bounds"] == "flush" && vl["spacing"] == 20
    # Each panel shows its own rows, and rows without the row field in every panel.
    @test panels[2]["transform"][1]["filter"] ==
        "!isDefined(datum[\"panel\"]) || datum[\"panel\"] === '$(PANELS[2])'"
    # The x axis is labelled under the bottom panel only.
    @test all(ax -> ax isa Dict && ax["labels"] === false && ax["title"] === nothing, xaxes(panels[1]))
    @test all(ax -> !(ax isa Dict) || get(ax, "labels", true) !== false, xaxes(panels[3]))
    # The runtime sizes and reads it as a stack.
    @test length(vl["_aov"]["panels"]) == 3
    @test haskey(vl, "data") && !haskey(panels[1], "data")
end

@testitem "Each panel's axis takes its title; the readout and tooltips follow" setup=[AoVPerRowYFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(exposure_figure())
    # The panel's row value titles its y axis, and its row header leaves.
    @test [ytitles(p) for p in vl["vconcat"]] == [[p] for p in PANELS]
    @test all(p -> !haskey(p, "title"), vl["vconcat"])
    meta = vl["_aov"]["panelLabels"]["y"]
    @test meta["field"] == "panel" && meta["facet"] == ["panel"] && meta["titles"] == ["Exposure"]
    # Another column titles the axes; the row header stays as each panel's title.
    vq = to_vegalite(exposure_figure(labels=:quantity))
    @test [ytitles(p) for p in vq["vconcat"]] == [["Q1"], ["Q2"], ["Q3"]]
    @test [p["title"]["text"] for p in vq["vconcat"]] == PANELS
    @test all(p -> p["title"]["orient"] == "left", vq["vconcat"])
    # Without `ylabels` the panels keep the mapping's title and their headers.
    vn = to_vegalite(exposure_figure(labels=nothing))
    @test all(p -> ytitles(p) == ["Exposure"] && p["title"]["text"] in PANELS, vn["vconcat"])
end

@testitem "Both drawings of the Ribbons | Intervals switch keep each row's scale" setup=[AoVPerRowYFixtures] tags=[:translation, :regression] begin
    fig = exposure_figure()
    v = ribbon_view(fig)
    @test v.offered && v.start === :ribbons
    vl = to_vegalite(fig)
    alt = vl["_aov"]["ribbonView"]["alt"]
    @test haskey(alt, "vconcat")
    @test [yscale_types(p) for p in alt["vconcat"]] == [["log"], ["log"], ["linear"]]
    @test [ytitles(p) for p in alt["vconcat"]] == [[p] for p in PANELS]
    # The overlap score reads each panel on its own axis: the linear Ctrough
    # panel's bands count (in log units its 1e-12 values were all but dropped).
    @test AoV._stack_panel_logs(vl, AoV._ribbon_view_source(fig)) ==
        Dict((PANELS[1],) => true, (PANELS[2],) => true, (PANELS[3],) => false)
end

@testitem "Per-row Y scales: positional form, single layer, headers and unlinked x" setup=[AoVPerRowYFixtures] tags=[:translation, :regression] begin
    # The second-positional Scales form lowers the same stack.
    base = exposure_figure(yscale=identity)
    pos = to_vegalite(base, scales(Y=(; scale=LOG)))
    @test [yscale_types(p) for p in pos["vconcat"]] == [["log"], ["log"], ["linear"]]
    # A single-layer `row=` figure (an encoding facet) lowers too; the row
    # field's title sits once on the stack, on the left.
    one = to_vegalite(data(exposure) * mapping(:dose, :q50; row=:panel) * visual(Scatter) *
        config(scales=scales(Y=(; scale=LOG))))
    @test [yscale_types(p) for p in one["vconcat"]] == [["log"], ["log"], ["linear"]]
    @test one["title"]["text"] == "panel" && one["title"]["orient"] == "left"
    @test [p["title"]["text"] for p in one["vconcat"]] == PANELS
    # `row = :panel => ""` draws no row title; `header: nothing` drops the headers.
    @test !haskey(to_vegalite(exposure_figure(labels=nothing)), "title")
    nohead = to_vegalite(exposure_figure(labels=nothing,
        extra=config(encoding=Dict("row" => Dict("header" => nothing)))))
    @test all(p -> !haskey(p, "title"), nohead["vconcat"])
    # `linkxaxes=:none` keeps each panel's x scale and axis.
    free = to_vegalite(exposure_figure(extra=config(facet=(; linkxaxes=:none))))
    @test free["resolve"]["scale"]["x"] == "independent"
    @test all(ax -> !(ax isa Dict) || get(ax, "labels", true) !== false, xaxes(free["vconcat"][1]))
    # A key no row has does nothing, as for columns.
    odd = to_vegalite(exposure_figure(yscale=merge(LOG, Dict("Cmin" => log10))))
    @test [yscale_types(p) for p in odd["vconcat"]] == [["log"], ["log"], ["linear"]]
end

@testitem "Per-panel Y scales keep the column form, wrap a layout= facet and refuse figures without a facet" setup=[AoVPerRowYFixtures] tags=[:translation, :regression] begin
    import AlgebraOfGraphics   # with Makie, loads the static path (AlgebraOfVegaMakieExt)
    # With a column facet the `Dict` keys the columns, as before.
    grid = data(exposure) * mapping(:dose, :q50; col=:panel, row=:percentile) * visual(Scatter) *
        config(scales=scales(Y=(; scale=LOG)))
    vg = to_vegalite(grid)
    @test haskey(vg, "hconcat") && length(vg["hconcat"]) == 3
    @test [yscale_types(c) for c in vg["hconcat"]] == [["log"], ["log"], ["linear"]]
    flat = data(exposure) * mapping(:dose, :q50) * visual(Scatter) * config(scales=scales(Y=(; scale=LOG)))
    @test_throws "has no facet" to_vegalite(flat)
    # A wrap keys its panels (test/per_wrap_y.jl).
    wrap = data(exposure) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) * config(scales=scales(Y=(; scale=LOG)))
    @test [yscale_types(p) for p in to_vegalite(wrap)["concat"]] == [["log"], ["log"], ["linear"]]
    @test_throws "static Makie path" sdraw_file(exposure_figure(), joinpath(mktempdir(), "x.png"))
end

@testitem "vsave draws each row on its own y scale" setup=[AoVPerRowYFixtures] tags=[:static, :regression] begin
    if !have_vl_convert()
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(exposure_figure(), joinpath(dir, "rows.svg")), String)
            @test sort!([m[1] for m in eachmatch(r"aria-label=\"Y-axis titled '([^']*)'", svg)]) == sort(PANELS)
            # Log ticks in the Cmax and AUC₂₄ panels, linear ones in Ctrough's.
            @test occursin("Y-axis titled 'Cmax (ng/mL)' for a log scale", svg)
            @test occursin("Y-axis titled 'AUC₂₄ (ng/mL·h)' for a log scale", svg)
            @test occursin("Y-axis titled 'Ctrough (ng/mL)' for a linear scale", svg)
            # The x axis is drawn once.
            @test count("X-axis titled 'Dose (mg)'", svg) == 1
            # A rule without the row field reaches every panel.
            rule = (data(exposure) * mapping(:dose, :q50; row=:panel) * visual(Scatter) +
                data([(; dose=20.0)]) * mapping(:dose) * visual(VLines; color="#00aa00")) *
                config(scales=scales(Y=(; scale=LOG)))
            @test count("#00aa00", read(vsave(rule, joinpath(dir, "rule.svg")), String)) == 3
        end
    end
end

@testitem "Per-row Y scales in the browser: one figure, its switch, readout, tooltips and picker" setup=[AoVPerRowYFixtures] tags=[:regression, :browser, :auto_remap] begin
    using HTMX, HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-per-row-y-") do dir
            rule = (data(exposure) * mapping(:dose => "Dose (mg)", :q50; row=:panel, color=:percentile) * visual(Scatter) +
                data([(; dose=20.0)]) * mapping(:dose => "Dose (mg)") * visual(VLines; color="#00aa00")) *
                config(scales=scales(X=(; scale=log10), Y=(; scale=LOG)))
            picker = (data(exposure) * mapping(:dose => "Dose (mg)", :q50; row=:panel, color=:percentile) * visual(Lines) +
                data(exposure) * mapping(:dose => "Dose (mg)", :q50; row=:panel, color=:percentile) * visual(Scatter)) *
                config(scales=scales(X=(; scale=log10), Y=(; scale=LOG)), facet=(; linkyaxes=:none, ylabels=:panel))
            capture = "<script>window.AOV_ERRORS = []; ['error', 'warn'].forEach(k => { const o = console[k]; " *
                "console[k] = function () { window.AOV_ERRORS.push(k + ': ' + [...arguments].map(String).join(' ')); " *
                "return o.apply(console, arguments); }; });</script>"
            page = "<div style='width:900px'>" *
                html(with_plot_caption(exposure_figure(), CaptionSpec(; title="Exposure by dose"); plot_id="pr-caption")) *
                "</div><div style='width:700px'>" * html(vdraw(exposure_figure(); id="pr-bare")) * "</div>" *
                "<div style='width:700px'>" * html(vdraw(rule; id="pr-rule")) * "</div>" *
                "<div style='width:700px'>" * html(auto_remap_node("pr-picker", picker;
                    dims=["percentile" => "Percentile"], fixed=Dict(:row => "panel"), pinned=:detail)) * "</div>"
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "per_row_y_browser.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * capture * head * "<body>" * page *
                "<script>window.AOV_PANELS = " * JSON.json(PANELS) * "; window.AOV_LOG = " * JSON.json(collect(keys(LOG))) *
                ";</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-per-row-y-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "per-row Y browser checks" checks=report["checks"] samples=JSON.json(get(report, "samples", nothing))
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
