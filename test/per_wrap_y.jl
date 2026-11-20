using TestItemRunner

# Per-panel Y scale types on a wrapped `layout=` facet: `scales(Y=(; scale=
# Dict(<panel value> => log10)))` (snag `per-panel-y-scal-81725851`, todo
# `0svhytl`). Bruno web-sim's "Exposure by dose" draws Cmax, AUC₂₄ and Ctrough
# against the dose, Cmax and AUC₂₄ on a log y axis and Ctrough, which reaches
# zero, on a linear one. The row facet got per-row scales in 0.2.69; a wrap
# given the `Dict` raised an `ArgumentError`. It now lowers to a `concat` of one
# panel per wrap value laid out `columns` to a row (`_per_wrap_y_concat!`),
# still one figure with its Ribbons | Intervals switch, legend, caption, link
# group, panel titles and readout, re-wrapped to the plot's width in the browser.
@testsnippet AoVPerWrapYFixtures begin
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
    wrap_facet(label="") = (; layout=:panel => sorter(PANELS) => label)
    # Bruno web-sim's `dose_figure` as a wrap: a coloured ribbon per panel, the
    # Time course's dose as a dashed rule, the fit's doses as a bar.
    function exposure_figure(; yscale=LOG, labels=:panel, label="", extra=config())
        x = :dose => "Dose (mg)"
        (data(exposure) * mapping(x, :q50 => "Exposure"; wrap_facet(label)...,
                color=:percentile => sorter(PCTS) => "Population percentile") *
            lineribbon(bands=[:q025 => :q975, :q25 => :q75], probs=[0.95, 0.5], point=:median) +
         data(marks) * mapping(x; wrap_facet(label)...) * visual(VLines; linestyle=:dash, color=:ink) +
         data(span) * mapping(:from => "Dose (mg)", :to => "Dose (mg)"; wrap_facet(label)...) *
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

@testitem "A wrapped layout= facet with per-panel Y scales lowers to a concat of one panel per wrap value" setup=[AoVPerWrapYFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(exposure_figure())
    @test haskey(vl, "concat") && !haskey(vl, "facet") && !haskey(vl, "vconcat") && !haskey(vl, "hconcat")
    panels = vl["concat"]
    @test length(panels) == 3
    # Listed panels log, the unlisted one linear, in the facet's order.
    @test [yscale_types(p) for p in panels] == [["log"], ["log"], ["linear"]]
    @test [p["_aovPanel"]["panel"] for p in panels] == PANELS
    # AoG's near-square count, which the browser replaces to fit the width.
    @test vl["columns"] == AoV._aog_wrap_columns(3, 1.0) == 2
    @test vl["_aov"]["autoColumns"] === true
    # One x scale, the facet's spacing.
    @test vl["resolve"]["scale"]["x"] == "shared"
    @test vl["spacing"] == 20 && !haskey(vl, "bounds")
    # Each panel shows its own rows, and rows without the wrap field in every panel.
    @test panels[2]["transform"][1]["filter"] ==
        "!isDefined(datum[\"panel\"]) || datum[\"panel\"] === '$(PANELS[2])'"
    # Every panel keeps its own x axis, as a wrap facet draws one under each panel.
    @test all(p -> all(ax -> !(ax isa Dict) || get(ax, "labels", true) !== false, xaxes(p)), panels)
    # The runtime sizes, reads and remaps it as panels.
    @test length(vl["_aov"]["panels"]) == 3
    @test haskey(vl, "data") && !haskey(panels[1], "data")
    @test AoV._is_panel_concat(vl) && AoV._panel_kids(vl) === panels
    # The legend selection is kept.
    @test haskey(vl["_aov"], "legendInteraction")
end

@testitem "Per-wrap Y scales: authored column counts, headers and titles" setup=[AoVPerWrapYFixtures] tags=[:translation, :regression] begin
    import AlgebraOfGraphics   # with Makie, loads the static path (AlgebraOfVegaMakieExt)
    # An authored count is kept and never marked automatic.
    three = to_vegalite(exposure_figure(extra=config(columns=3)))
    @test three["columns"] == 3 && !haskey(three["_aov"], "autoColumns")
    one = to_vegalite(exposure_figure(extra=config(scales=scales(Layout=(; palette=wrapped(cols=1))))))
    @test one["columns"] == 1 && !haskey(one["_aov"], "autoColumns")
    # Authored panel sizes reach every panel and set AoG's aspect.
    wide = to_vegalite(exposure_figure(extra=config(width=300, height=100)))
    @test all(p -> p["width"] == 300 && p["height"] == 100, wide["concat"])
    @test wide["columns"] == AoV._aog_wrap_columns(3, 3.0)
    # Without `ylabels` each panel keeps the mapping's y title and its value as
    # a header-styled title on top.
    vn = to_vegalite(exposure_figure(labels=nothing))
    @test all(p -> ytitles(p) == ["Exposure"], vn["concat"])
    @test [p["title"]["text"] for p in vn["concat"]] == PANELS
    # Styled as the facet's header labels (AoV's `config.header`), on top.
    label_size = get(get(vn["config"], "header", Dict()), "labelFontSize", 10)
    @test all(p -> p["title"]["fontSize"] == label_size && p["title"]["fontWeight"] == "normal" &&
        !haskey(p["title"], "orient"), vn["concat"])
    # `layout = :panel => ""` draws no field title; a labelled wrap draws it once on top.
    @test !haskey(vn, "title")
    titled = to_vegalite(exposure_figure(labels=nothing, label="Quantity"))
    @test titled["title"]["text"] == "Quantity" && titled["title"]["fontWeight"] == "bold"
    # `header: nothing` drops the panel titles and the field title.
    nohead = to_vegalite(data(exposure) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) *
        config(scales=scales(Y=(; scale=LOG)), encoding=Dict("facet" => Dict("header" => nothing))))
    @test all(p -> !haskey(p, "title"), nohead["concat"]) && !haskey(nohead, "title")
    # `linkxaxes=:none` gives each panel its own x scale.
    free = to_vegalite(exposure_figure(extra=config(facet=(; linkxaxes=:none))))
    @test free["resolve"]["scale"]["x"] == "independent"
    # A key no panel has does nothing.
    odd = to_vegalite(exposure_figure(yscale=merge(LOG, Dict("Cmin" => log10))))
    @test [yscale_types(p) for p in odd["concat"]] == [["log"], ["log"], ["linear"]]
    # The static Makie path refuses it loudly, naming the wrapped panels.
    @test_throws "wrapped panel" sdraw_file(exposure_figure(), joinpath(mktempdir(), "x.png"))
end

@testitem "Each wrapped panel's axis takes its title; the ribbon switch keeps each panel's scale" setup=[AoVPerWrapYFixtures] tags=[:translation, :regression] begin
    fig = exposure_figure()
    vl = to_vegalite(fig)
    # The panel's value titles its y axis, and its header leaves.
    @test [ytitles(p) for p in vl["concat"]] == [[p] for p in PANELS]
    @test all(p -> !haskey(p, "title"), vl["concat"])
    meta = vl["_aov"]["panelLabels"]["y"]
    @test meta["field"] == "panel" && meta["facet"] == ["panel"] && meta["titles"] == ["Exposure"]
    # Another column titles the axes; the header stays as each panel's title.
    vq = to_vegalite(exposure_figure(labels=:quantity))
    @test [ytitles(p) for p in vq["concat"]] == [["Q1"], ["Q2"], ["Q3"]]
    @test [p["title"]["text"] for p in vq["concat"]] == PANELS
    # Both drawings of the Ribbons | Intervals switch are wrapped panels.
    v = ribbon_view(fig)
    @test v.offered && v.start === :ribbons
    alt = vl["_aov"]["ribbonView"]["alt"]
    @test haskey(alt, "concat") && alt["columns"] == vl["columns"]
    @test [yscale_types(p) for p in alt["concat"]] == [["log"], ["log"], ["linear"]]
    @test [ytitles(p) for p in alt["concat"]] == [[p] for p in PANELS]
    # The overlap score reads each panel on its own axis.
    @test AoV._stack_panel_logs(vl, AoV._ribbon_view_source(fig)) ==
        Dict((PANELS[1],) => true, (PANELS[2],) => true, (PANELS[3],) => false)
end

@testitem "Per-wrap Y scales: positional form, single layer, link group, sizing and embedding" setup=[AoVPerWrapYFixtures] tags=[:translation, :regression] begin
    # The second-positional Scales form lowers the same concat.
    pos = to_vegalite(exposure_figure(yscale=identity), scales(Y=(; scale=LOG)))
    cfg = to_vegalite(exposure_figure())
    @test [yscale_types(p) for p in pos["concat"]] == [["log"], ["log"], ["linear"]]
    @test pos["columns"] == cfg["columns"] && pos["_aov"]["autoColumns"] === true
    # A single-layer `layout=` figure (an encoding facet) lowers too, its mark,
    # tooltips and hover kept in every panel.
    single = to_vegalite(data(exposure) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) *
        config(scales=scales(Y=(; scale=LOG))))
    @test [yscale_types(p) for p in single["concat"]] == [["log"], ["log"], ["linear"]]
    @test [p["title"]["text"] for p in single["concat"]] == PANELS
    @test single["title"]["text"] == "panel"
    @test all(p -> length(p["layer"]) == 1 && haskey(p["layer"][1]["encoding"], "tooltip"), single["concat"])
    # An encoding facet's own column count is kept.
    counted = to_vegalite(data(exposure) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) *
        config(scales=scales(Y=(; scale=LOG)), encoding=Dict("facet" => Dict("columns" => 3))))
    @test counted["columns"] == 3 && !haskey(counted["_aov"], "autoColumns")
    # The link group is the figure's.
    linked = to_vegalite(exposure_figure(extra=config(link=(; group="doses", key=:dose))))
    @test linked["_aov"]["link"] == Dict("group" => "doses", "key" => "dose")
    # plot_size lays the panels out in the grid: two to a row, two rows.
    one_panel = AoV.plot_size(cfg["concat"][1])
    sz = AoV.plot_size(cfg)
    @test sz.width ≈ 2 * one_panel.width + 20
    @test sz.height ≈ 2 * one_panel.height + 20
    # The embedded spec is sized by the runtime, panel by panel.
    emb = AoV._embed_spec(cfg)
    @test emb["_aov"]["fitWidth"] === true && all(p -> !haskey(p, "width"), emb["concat"])
    @test !haskey(AoV._embed_spec(to_vegalite(exposure_figure(extra=config(width=250))))["_aov"], "fitWidth")
end

@testitem "vsave draws each wrapped panel on its own y scale" setup=[AoVPerWrapYFixtures] tags=[:static, :regression] begin
    if !have_vl_convert()
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(exposure_figure(), joinpath(dir, "wrap.svg")), String)
            @test sort!([m[1] for m in eachmatch(r"aria-label=\"Y-axis titled '([^']*)'", svg)]) == sort(PANELS)
            # Log ticks in the Cmax and AUC₂₄ panels, linear ones in Ctrough's.
            @test occursin("Y-axis titled 'Cmax (ng/mL)' for a log scale", svg)
            @test occursin("Y-axis titled 'AUC₂₄ (ng/mL·h)' for a log scale", svg)
            @test occursin("Y-axis titled 'Ctrough (ng/mL)' for a linear scale", svg)
            # An x axis under every panel.
            @test count("X-axis titled 'Dose (mg)'", svg) == 3
            # A rule without the wrap field reaches every panel.
            rule = (data(exposure) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) +
                data([(; dose=20.0)]) * mapping(:dose) * visual(VLines; color="#00aa00")) *
                config(scales=scales(Y=(; scale=LOG)))
            @test count("#00aa00", read(vsave(rule, joinpath(dir, "rule.svg")), String)) == 3
        end
    end
end

@testitem "Per-wrap Y scales in the browser: one figure that re-wraps, its switch, readout, link, tooltips and picker" setup=[AoVPerWrapYFixtures] tags=[:regression, :browser, :auto_remap] begin
    using HTMX, HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-per-wrap-y-") do dir
            link = config(link=(; group="doses", key=:dose))
            rule = (data(exposure) * mapping(:dose => "Dose (mg)", :q50; layout=:panel, color=:percentile) * visual(Scatter) +
                data([(; dose=20.0)]) * mapping(:dose => "Dose (mg)") * visual(VLines; color="#00aa00")) *
                config(scales=scales(X=(; scale=log10), Y=(; scale=LOG)))
            picker = (data(exposure) * mapping(:dose => "Dose (mg)", :q50; layout=:panel, color=:percentile) * visual(Lines) +
                data(exposure) * mapping(:dose => "Dose (mg)", :q50; layout=:panel, color=:percentile) * visual(Scatter)) *
                config(scales=scales(X=(; scale=log10), Y=(; scale=LOG)), facet=(; linkyaxes=:none, ylabels=:panel))
            capture = "<script>window.AOV_ERRORS = []; ['error', 'warn'].forEach(k => { const o = console[k]; " *
                "console[k] = function () { window.AOV_ERRORS.push(k + ': ' + [...arguments].map(String).join(' ')); " *
                "return o.apply(console, arguments); }; });</script>"
            page = "<div style='width:1000px'>" *
                html(with_plot_caption(exposure_figure(extra=link), CaptionSpec(; title="Exposure by dose"); plot_id="pw-caption")) *
                "</div><div id='pw-bare-box' style='width:700px'>" * html(vdraw(exposure_figure(extra=link); id="pw-bare")) * "</div>" *
                "<div style='width:700px'>" * html(vdraw(rule; id="pw-rule")) * "</div>" *
                "<div style='width:900px'>" * html(auto_remap_node("pw-picker", picker;
                    dims=["percentile" => "Percentile"], pinned=:detail)) * "</div>"
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "per_wrap_y_browser.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * capture * head * "<body>" * page *
                "<script>window.AOV_PANELS = " * JSON.json(PANELS) * "; window.AOV_LOG = " * JSON.json(collect(keys(LOG))) *
                ";</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-per-wrap-y-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 50
                @test isempty(report["failures"])
                @info "per-wrap Y browser checks" checks=report["checks"] samples=JSON.json(get(report, "samples", nothing))
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
