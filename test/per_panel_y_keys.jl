using TestItemRunner

# Per-panel Y domain and clamp: any `scales(Y=(; …))` key may be a `Dict` keyed
# by the facet panel's value, as `scale` is (snag `per-panel-y-doma-41192758`).
# Bruno web-sim's "Exposure by dose" draws Cmax, AUC₂₄ and Ctrough in a row
# each. Ctrough spans eighteen decades down to 1e-12, so a full log axis does
# not suit it; the app wants a log axis cut at 0.3 whose lower values are drawn
# at the axis edge, while the other panels keep their own axes. Before, only
# `scale` was read per panel: a `domain`/`clamp` `Dict` was written into
# Vega-Lite as an object, and a `scale` `Dict` dropped every other Y key, so a
# shared `domain` or `nice` beside it was lost too (todo `16z8s5l`).
@testsnippet AoVPerPanelYKeysFixtures begin
    using AlgebraOfVega, JSON, Tables
    const AoV = AlgebraOfVega

    PANELS = ["Cmax (ng/mL)", "AUC₂₄ (ng/mL·h)", "Ctrough (ng/mL)"]
    ALL_LOG = Dict(p => log10 for p in PANELS)
    CUT = Dict(PANELS[3] => (0.3, 3e5))
    CLAMP = Dict(PANELS[3] => true)
    PCTS = ["5th", "50th", "95th"]
    DOSES = [5.0, 10, 20, 40, 80, 100, 160, 320]
    # Ctrough's bands reach down to 1.6e-10, far below a cut at 0.3.
    exposure = let rows = NamedTuple[]
        for (i, p) in enumerate(PANELS), (k, pc) in enumerate(PCTS), d in DOSES
            m = p == PANELS[3] ? 1e-13 * d^(4 + k) : (10.0i) * d * (0.3k)^2
            push!(rows, (; panel=p, quantity=string("Q", i), percentile=pc, dose=d, q50=m,
                q025=0.5m, q975=2m, q25=0.8m, q75=1.25m))
        end
        rows
    end
    marks = [(; dose=40.0, panel=p) for p in PANELS]
    # The reporter's figure: a coloured ribbon per row, a dashed dose rule, the
    # per-panel scale types, and Ctrough's cut-off, clamped domain.
    function exposure_figure(; y=(; scale=ALL_LOG, domain=CUT, clamp=CLAMP), facet=:row, extra=config())
        x = :dose => "Dose (mg)"
        f = (; facet => :panel => sorter(PANELS) => "")
        (data(exposure) * mapping(x, :q50 => "Exposure"; f...,
                color=:percentile => sorter(PCTS) => "Population percentile") *
            lineribbon(bands=[:q025 => :q975, :q25 => :q75], probs=[0.95, 0.5], point=:median, intervals=false) +
         data(marks) * mapping(x; f...) * visual(VLines; linestyle=:dash, color=:ink)) *
        config(scales=scales(; X=(; scale=log10, nice=false), Y=y)) *
        config(facet=(; linkyaxes=:none, ylabels=:panel)) * extra
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
    # The distinct y `scale` objects a panel's field-bearing y encodings carry.
    yscales(panel) = unique([get(u["encoding"]["y"], "scale", Dict{String,Any}())
        for u in units(panel) if haskey(get(u, "encoding", Dict()), "y") && haskey(u["encoding"]["y"], "field")])
    # A panel's single y scale, with AoV's own `zero`/axis defaults left out.
    function yscale(panel)
        s = yscales(panel)
        length(s) == 1 || return s
        Dict{String,Any}(k => v for (k, v) in only(s) if k != "zero")
    end
    ytickvalues(panel) = unique([get(get(u["encoding"]["y"], "axis", Dict()), "values", nothing)
        for u in units(panel) if haskey(get(u, "encoding", Dict()), "y") && haskey(u["encoding"]["y"], "field")])
    panels(vl) = something(get(vl, "vconcat", nothing), get(vl, "concat", nothing), get(vl, "hconcat", nothing))
    have_vl_convert() = !isnothing(get(ENV, "AOV_VL_CONVERT", nothing)) || !isnothing(Sys.which("vl-convert"))
end

@testitem "A row facet takes a per-panel Y domain and clamp beside per-panel scale types" setup=[AoVPerPanelYKeysFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(exposure_figure())
    @test haskey(vl, "vconcat") && length(vl["vconcat"]) == 3
    ps = vl["vconcat"]
    # Ctrough: a log axis from 0.3 to 3e5 that draws lower values at its edge.
    @test yscale(ps[3]) == Dict("type" => "log", "domain" => [0.3, 3e5], "clamp" => true)
    # Cmax and AUC₂₄ keep their own fitted domains (no domain, no clamp).
    @test yscale(ps[1]) == Dict("type" => "log") && yscale(ps[2]) == Dict("type" => "log")
    # Each panel's domain is its own array, not one shared between layers.
    doms = [u["encoding"]["y"]["scale"]["domain"] for u in units(ps[3])
            if haskey(get(u, "encoding", Dict()), "y") && haskey(get(u["encoding"]["y"], "scale", Dict()), "domain")]
    @test length(doms) >= 2 && allunique(objectid.(doms))
    # The rows stay as given: what the tooltips, CSV and readout read is unclipped.
    @test minimum(r["q025"] for r in vl["data"]["values"] if get(r, "panel", nothing) == PANELS[3] && haskey(r, "q025")) < 1e-9
    # Both drawings of the Ribbons | Intervals switch keep it.
    alt = vl["_aov"]["ribbonView"]["alt"]
    @test yscale(alt["vconcat"][3]) == Dict("type" => "log", "domain" => [0.3, 3e5], "clamp" => true)
    @test yscale(alt["vconcat"][1]) == Dict("type" => "log")
    # The second-positional Scales form lowers the same stack.
    base = exposure_figure(y=(;))
    pos = to_vegalite(base, scales(Y=(; scale=ALL_LOG, domain=CUT, clamp=CLAMP)))
    @test [yscale(p) for p in pos["vconcat"]] == [yscale(p) for p in ps]
end

@testitem "Shared Y keys survive a per-panel Dict; a panel's own value wins" setup=[AoVPerPanelYKeysFixtures] tags=[:translation, :regression] begin
    # todo `16z8s5l`: a `scale` Dict used to drop a shared `domain` and `nice`.
    vl = to_vegalite(exposure_figure(y=(; scale=Dict(PANELS[1] => log10), domain=(1.0, 3.0), nice=false)))
    # (A shared `domain` is written as given; JSON writes the tuple as an array.)
    @test yscale(vl["vconcat"][1]) == Dict("type" => "log", "domain" => (1.0, 3.0), "nice" => false)
    @test yscale(vl["vconcat"][2]) == Dict("domain" => (1.0, 3.0), "nice" => false)
    # A panel's own domain replaces the shared one there only.
    mix = to_vegalite(exposure_figure(y=(; domain=merge(Dict{String,Any}(), CUT), clamp=true)))
    @test yscale(mix["vconcat"][3]) == Dict("domain" => [0.3, 3e5], "clamp" => true)
    @test yscale(mix["vconcat"][1]) == Dict("clamp" => true)
    # Axis limits are shared too; a panel's own domain wins over them.
    lim = to_vegalite(exposure_figure(y=(; domain=CUT), extra=config(axis=(; limits=(nothing, (0, 100))))))
    @test yscale(lim["vconcat"][1])["domain"] == [0, 100]
    @test yscale(lim["vconcat"][3])["domain"] == [0.3, 3e5]
    # A figure that gives no Y key per panel keeps one facet, as before.
    one = to_vegalite(exposure_figure(y=(; scale=log10, domain=(1.0, 1e6))))
    @test haskey(one, "facet") && !haskey(one, "vconcat")
end

@testitem "A per-panel domain alone re-lowers row, column and wrapped facets" setup=[AoVPerPanelYKeysFixtures] tags=[:translation, :regression] begin
    for (facet, key) in ((:row, "vconcat"), (:layout, "concat"), (:col, "hconcat"))
        vl = to_vegalite(exposure_figure(y=(; domain=CUT, clamp=CLAMP), facet=facet))
        @test haskey(vl, key)
        ps = vl[key]
        @test length(ps) == 3
        # Only the listed panel is cut; the others keep a fitted linear axis.
        @test yscale(ps[3]) == Dict("domain" => [0.3, 3e5], "clamp" => true)
        @test yscale(ps[1]) == Dict{String,Any}() && yscale(ps[2]) == Dict{String,Any}()
    end
    # A single-layer figure (an encoding facet) lowers too.
    one = to_vegalite(data(exposure) * mapping(:dose, :q50; row=:panel) * visual(Scatter) *
        config(scales=scales(Y=(; domain=CUT))))
    @test [yscale(p) for p in one["vconcat"]] == [Dict{String,Any}(), Dict{String,Any}(), Dict{String,Any}("domain" => [0.3, 3e5])]
    # A key no panel has does nothing, as for `scale`.
    odd = to_vegalite(exposure_figure(y=(; scale=ALL_LOG, domain=Dict("Cmin" => (1, 2)))))
    @test all(p -> !haskey(yscale(p), "domain"), odd["vconcat"])
end

@testitem "Per-panel Y keys: what is refused" setup=[AoVPerPanelYKeysFixtures] tags=[:translation, :regression] begin
    flat = data(exposure) * mapping(:dose, :q50) * visual(Scatter)
    @test_throws "has no facet" to_vegalite(flat * config(scales=scales(Y=(; domain=CUT))))
    # Only the Y scale is per panel: the panels share their x scale.
    @test_throws "only the Y scale takes" to_vegalite(exposure_figure(y=(;)) *
        config(scales=scales(X=(; domain=Dict(PANELS[1] => (1, 2))))))
    @test_throws "only the Y scale takes" to_vegalite(exposure_figure(y=(;)) *
        config(scales=scales(X=(; scale=Dict(PANELS[1] => log10)))))
    # A domain is two (or more) values, named by its panel.
    @test_throws "of panel \"Ctrough (ng/mL)\"" to_vegalite(exposure_figure(y=(; domain=Dict(PANELS[3] => 0.3))))
    # The static Makie path refuses it loudly.
    @test_throws "static Makie path" sdraw_file(exposure_figure(y=(; domain=CUT)), joinpath(mktempdir(), "x.png"))
end

@testitem "The ribbon switch and log ticks read each panel's own domain" setup=[AoVPerPanelYKeysFixtures] tags=[:translation, :regression] begin
    fig = exposure_figure()
    vl = to_vegalite(fig)
    src = AoV._ribbon_view_source(fig)
    s = AoV._panel_y_scales(vl, src)
    @test s[(PANELS[3],)].domain == [0.3, 3e5] && s[(PANELS[3],)].clamp && s[(PANELS[3],)].log
    @test isnothing(s[(PANELS[1],)].domain) && !s[(PANELS[1],)].clamp
    v = ribbon_view(fig)
    @test v.offered && 0 <= v.score <= 1
    # The overlap score measures a panel on its own domain, and a clamped one
    # as drawn: two groups whose bands overlap only below Ctrough's cut at 0.3
    # (1e-10 to 1e-6, four decades of the domain's six) overlap 2/3 of the y
    # range unclamped, and not at all once both are drawn at the edge.
    low = [(; panel=PANELS[3], percentile=pc, dose=d, q50=(pc == "5th" ? 1e-9 : 1e-8),
            q025=(pc == "5th" ? 1e-12 : 1e-10), q975=(pc == "5th" ? 1e-6 : 1e-5))
           for pc in PCTS[1:2] for d in DOSES]
    lowfig(clamped) = data(low) * mapping(:dose, :q50; row=:panel, color=:percentile) *
        lineribbon(bands=[:q025 => :q975]) * config(scales=scales(Y=(; scale=Dict(PANELS[3] => log10),
            domain=CUT, clamp=Dict(PANELS[3] => clamped))))
    @test ribbon_view(lowfig(false)).score ≈ 0.667 atol=0.001
    @test ribbon_view(lowfig(true)).score == 0.0
    # A per-column hconcat reads each column's own scale as well.
    col = exposure_figure(facet=:col)
    sc = AoV._panel_y_scales(to_vegalite(col), AoV._ribbon_view_source(col))
    @test sc[(PANELS[3],)].domain == [0.3, 3e5] && sc[(PANELS[1],)].log && isnothing(sc[(PANELS[1],)].domain)
    # A log y axis cut to at most two decades is labelled at 1, 2 and 5 times
    # each power of ten, though its rows span eighteen.
    narrow = to_vegalite(exposure_figure(y=(; scale=ALL_LOG, domain=Dict(PANELS[3] => (1.0, 50.0)), clamp=CLAMP)))
    ticks = only(filter(!isnothing, ytickvalues(narrow["vconcat"][3])))
    @test 2.0 in ticks && 5.0 in ticks && 20.0 in ticks
    @test !(2.0 in only(filter(!isnothing, ytickvalues(narrow["vconcat"][1]))))
end

@testitem "vsave draws the cut-off panel on its own clamped domain" setup=[AoVPerPanelYKeysFixtures] tags=[:static, :regression] begin
    if !have_vl_convert()
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(exposure_figure(), joinpath(dir, "rows.svg")), String)
            # Every row is a log axis now, Ctrough's from 0.3 up.
            @test occursin("Y-axis titled 'Ctrough (ng/mL)' for a log scale", svg)
            m = match(r"Y-axis titled 'Ctrough \(ng/mL\)' for a log scale with values from ([^ ]+) to ([^ ;\"]+)", svg)
            @test !isnothing(m) && m[1] == "0.3"
        end
    end
end

@testitem "Per-panel Y domain and clamp in the browser" setup=[AoVPerPanelYKeysFixtures] tags=[:regression, :browser] begin
    using HTMX, HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-per-panel-y-keys-") do dir
            capture = "<script>window.AOV_ERRORS = []; ['error', 'warn'].forEach(k => { const o = console[k]; " *
                "console[k] = function () { window.AOV_ERRORS.push(k + ': ' + [...arguments].map(String).join(' ')); " *
                "return o.apply(console, arguments); }; });</script>"
            page = "<div style='width:900px'>" *
                html(with_plot_caption(exposure_figure(), CaptionSpec(; title="Exposure by dose"); plot_id="pk-row")) *
                "</div><div style='width:900px'>" * html(vdraw(exposure_figure(facet=:layout); id="pk-wrap")) * "</div>"
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "per_panel_y_keys_browser.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * capture * head * "<body>" * page *
                "<script>window.AOV_PANELS = " * JSON.json(PANELS) * ";</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-per-panel-y-keys-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 20
                @test isempty(report["failures"])
                @info "per-panel Y keys browser checks" checks=report["checks"] samples=JSON.json(get(report, "samples", nothing))
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
