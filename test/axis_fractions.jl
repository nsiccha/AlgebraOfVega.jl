using TestItemRunner

# Makie's `VLines`/`VSpan` reach from `ymin` to `ymax`, and `HLines`/`HSpan` from
# `xmin` to `xmax`: fractions of the axis, 0 its start and 1 its end. AoV dropped
# them with a warning, so a dashed rule meant to stop short of the plot's top
# drew over the whole height on `vdraw` and `vsave` (snag
# `vlines-ymin-ymax-d2819705`, reporter ProjectPlans). They lower to the mark's
# own `y`/`y2` (`x`/`x2`) as an expression on the size of the group the mark is
# drawn in (`item.mark.group`), which is each facet cell's own size; the
# `height`/`width` signals collapse the mark in a facet cell.
@testsnippet AoVAxisFractionFixtures begin
    using AlgebraOfVega, JSON
    import Makie

    vlines(; kw...) = data((; at=[1.0, 3.0])) * mapping(:at) * visual(VLines; kw...)
    hlines(; kw...) = data((; at=[2.0, 8.0])) * mapping(:at) * visual(HLines; kw...)
    vspans(; kw...) = data((; lo=[1.0], hi=[2.0])) * mapping(:lo, :hi) * visual(VSpan; kw...)
    hspans(; kw...) = data((; lo=[2.0], hi=[4.0])) * mapping(:lo, :hi) * visual(HSpan; kw...)
    pts = data((; x=[0.0, 4.0], y=[0.0, 10.0])) * mapping(:x, :y) * visual(Scatter)
    # Faceted: the rules and the points in two column panels.
    paneled = data((; at=[1.0, 3.0], p=["a", "b"])) * mapping(:at; col=:p) * visual(VLines; ymin=0.25, ymax=0.9) +
        data((; x=[0.0, 4.0], y=[0.0, 10.0], p=["a", "b"])) * mapping(:x, :y; col=:p) * visual(Scatter)

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    unit_of(vl, type) = only(u for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == type)
    mark_of(vl, type) = unit_of(vl, type)["mark"]
    # The expected expressions: Vega's y runs down the plot, Makie's fractions up.
    gh(f) = Dict{String,Any}("expr" => "item.mark.group.height * (1 - $f)")
    gw(f) = Dict{String,Any}("expr" => "item.mark.group.width * $f")
    nowarn(f) = Test.@test_logs min_level=Base.CoreLogging.Warn f()
end

@testitem "VLines ymin/ymax and HLines xmin/xmax lower to the rule's own extent" setup=[AoVAxisFractionFixtures] tags=[:translation, :regression] begin
    # The reporter's figure: dashed rules from the bottom to 90% of the height.
    vl = nowarn(() -> to_vegalite(vlines(ymin=0.0, ymax=0.9, linestyle=:dash)))
    rule = unit_of(vl, "rule")
    @test rule["mark"]["y"] == gh(0.9) && rule["mark"]["y2"] == gh(0.0)
    @test haskey(rule["mark"], "strokeDash")
    # The position stays an encoding on x only.
    @test haskey(rule["encoding"], "x") && !haskey(rule["encoding"], "y") && !haskey(rule["encoding"], "y2")

    m = mark_of(nowarn(() -> to_vegalite(hlines(xmin=0.25, xmax=0.75))), "rule")
    @test m["x"] == gw(0.25) && m["x2"] == gw(0.75)
    # One end given: the other keeps Makie's default.
    m = mark_of(to_vegalite(vlines(ymax=0.5)), "rule")
    @test m["y"] == gh(0.5) && m["y2"] == gh(0.0)
    m = mark_of(to_vegalite(hlines(xmin=0.5)), "rule")
    @test m["x"] == gw(0.5) && m["x2"] == gw(1.0)
    # Any real number is written as a JavaScript number.
    m = mark_of(to_vegalite(vlines(ymin=0, ymax=1//2)), "rule")
    @test m["y"] == gh(0.5) && m["y2"] == gh(0.0)
    # Makie's whole-axis default adds nothing: the bare rule, as without them.
    @test nowarn(() -> mark_of(to_vegalite(vlines(ymin=0, ymax=1.0)), "rule")) == "rule"
    @test nowarn(() -> mark_of(to_vegalite(hlines(xmin=0.0, xmax=1)), "rule")) == "rule"
    @test to_vegalite(vlines(ymin=0, ymax=1)) == to_vegalite(vlines())
    # Beside a layer that encodes y, the rule still takes no y scale.
    rule = unit_of(to_vegalite(vlines(ymax=0.9) + pts), "rule")
    @test !haskey(rule["encoding"], "y") && rule["mark"]["y"] == gh(0.9)
end

@testitem "VSpan/HSpan fractions lower to the band's own extent" setup=[AoVAxisFractionFixtures] tags=[:translation] begin
    m = mark_of(nowarn(() -> to_vegalite(vspans(ymin=0.1, ymax=0.4, alpha=0.3))), "rect")
    @test m["y"] == gh(0.4) && m["y2"] == gh(0.1) && m["opacity"] == 0.3
    m = mark_of(nowarn(() -> to_vegalite(hspans(xmin=0.2))), "rect")
    @test m["x"] == gw(0.2) && m["x2"] == gw(1.0)
    @test nowarn(() -> mark_of(to_vegalite(vspans(ymin=0.0, ymax=1)), "rect")) == "rect"
end

@testitem "axis fractions: what has no reading is still reported" setup=[AoVAxisFractionFixtures] tags=[:translation] begin
    # The names of the other axis: Makie's VLines has no xmin.
    Test.@test_logs (:warn, r"`visual\(VLines\)` sets `xmax`") to_vegalite(vlines(xmax=0.5))
    Test.@test_logs (:warn, r"`visual\(HSpan\)` sets `ymin`") to_vegalite(hspans(ymin=0.5))
    # A value that is not one finite number: the line keeps the whole axis.
    for bad in (NaN, Inf, [0.2, 0.5], :top)
        vl = Test.@test_logs (:warn, r"`visual\(VLines\)` sets `ymax`") to_vegalite(vlines(ymax=bad))
        @test mark_of(vl, "rule") == "rule"
    end
end

@testitem "axis fractions hold in every facet panel" setup=[AoVAxisFractionFixtures] tags=[:translation] begin
    vl = nowarn(() -> to_vegalite(paneled))
    @test vl["facet"]["column"]["field"] == "p"
    rule = unit_of(vl, "rule")
    @test rule["mark"]["y"] == gh(0.9) && rule["mark"]["y2"] == gh(0.25)
end

@testitem "vsave: rules and bands stop at their fraction of each panel" setup=[AoVAxisFractionFixtures] tags=[:static, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        # Each rule item: `<line … aria-roledescription="rule mark" transform="translate(x,y)" x2=… y2=…`.
        rules(svg) = [parse.(Float64, (m[1], m[2], m[3], m[4])) for m in eachmatch(
            r"aria-roledescription=\"rule mark\" transform=\"translate\(([-\d.e]+),([-\d.e]+)\)\" x2=\"([-\d.e]+)\" y2=\"([-\d.e]+)\"",
            read(svg, String))]
        mktempdir() do dir
            # 120 px high: from 90% of the height (12 px from the top) down to 25% (90 px).
            svg = vsave((vlines(ymin=0.25, ymax=0.9, linestyle=:dash) + pts) * config(width=200, height=120),
                joinpath(dir, "vlines.svg"))
            rs = rules(svg)
            @test length(rs) == 2
            @test all(r -> r[2] ≈ 12 && r[3] == 0 && r[4] ≈ 78, rs)
            @test occursin("stroke-dasharray", read(svg, String))
            # Every facet panel: the same extent of its own height.
            rs = rules(vsave(paneled * config(width=150, height=100), joinpath(dir, "paneled.svg")))
            @test length(rs) == 2
            @test all(r -> r[2] ≈ 10 && r[4] ≈ 65, rs)
            # HLines: from 25% to 75% of a 200 px width.
            rs = rules(vsave((hlines(xmin=0.25, xmax=0.75) + pts) * config(width=200, height=120),
                joinpath(dir, "hlines.svg")))
            @test length(rs) == 2
            @test all(r -> r[1] ≈ 50 && r[3] ≈ 100 && r[4] == 0, rs)
            # A band: `M<x>,<y>h<w>v<h>h-<w>Z`, from 40% of 120 px (72 px) up to 90% (12 px).
            svg = read(vsave((vspans(ymin=0.4, ymax=0.9) + pts) * config(width=200, height=120),
                joinpath(dir, "vspan.svg")), String)
            m = match(r"aria-roledescription=\"rect mark\" d=\"M[-\d.e]+,([-\d.e]+)h[-\d.e]+v([-\d.e]+)", svg)
            @test !isnothing(m) && parse(Float64, m[1]) ≈ 12 && parse(Float64, m[2]) ≈ 60
        end
    end
end

@testitem "vdraw: the browser draws the fractions per panel and keeps them on resize" setup=[AoVAxisFractionFixtures] tags=[:browser, :regression] begin
    using HTMX, HTMXObjects
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-axis-fractions-") do dir
            page = [vdraw((vlines(ymin=0.25, ymax=0.9) + pts) * config(width=200, height=120); id="af-single"),
                vdraw(paneled * config(width=150, height=100); id="af-paneled")]
            head = join(html(n) for n in vega_head(; source=:inline))
            # The y/y2 (in plot coordinates) of every rule item, per view, before
            # and after the view's height signal changes.
            driver = """
            (async function () {
                const sleep = ms => new Promise(r => setTimeout(r, ms));
                async function view(id) {
                    for (let i = 0; i < 500; i++) { const v = AoV.views[id]; if (v && !AoV._inFlight[id]) return v; await sleep(10); }
                    throw new Error(id + ': no view');
                }
                function rules(v) {
                    const out = [];
                    (function walk(node) {
                        for (const it of node.items || []) {
                            if (node.marktype === 'rule' && node.role === 'mark') out.push([it.y, it.y2]);
                            if (node.marktype === 'group' || it.items) walk(it);
                        }
                    })(v.scenegraph().root);
                    return out;
                }
                const report = {};
                try {
                    const single = await view('af-single'), paneled = await view('af-paneled');
                    report.single = rules(single);
                    report.paneled = rules(paneled);
                    await single.height(240).runAsync();
                    report.resized = rules(single);
                } catch (e) { report.error = String(e); }
                const pre = document.createElement('pre');
                pre.id = 'af-results'; pre.textContent = JSON.stringify(report);
                document.body.appendChild(pre);
            })();
            """
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1000
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"af-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\""))
                @test !haskey(report, "error")
                spans(key) = [Tuple(Float64.(r)) for r in report[key]]
                @test length(spans("single")) == 2 && all(r -> r[1] ≈ 12 && r[2] ≈ 90, spans("single"))
                # Each panel is 100 px high: 10 … 75 in its own coordinates.
                @test length(spans("paneled")) == 2 && all(r -> r[1] ≈ 10 && r[2] ≈ 75, spans("paneled"))
                # Twice the height: twice the offsets.
                @test length(spans("resized")) == 2 && all(r -> r[1] ≈ 24 && r[2] ≈ 180, spans("resized"))
                isempty(get(report, "error", "")) || println(report["error"])
            end
        end
    end
end

@testitem "sdraw! hands the fractions to Makie's own plots" setup=[AoVAxisFractionFixtures] tags=[:static] begin
    fig = Makie.Figure()
    sdraw!(fig[1, 1], vlines(ymin=0.25, ymax=0.9, linestyle=:dash) + hlines(xmin=0.5) + pts)
    plots = [p for ax in fig.content if ax isa Makie.Axis for p in ax.scene.plots]
    v = only(p for p in plots if p isa Makie.VLines)
    @test v.ymin[] == 0.25 && v.ymax[] == 0.9
    h = only(p for p in plots if p isa Makie.HLines)
    @test h.xmin[] == 0.5 && h.xmax[] == 1
end
