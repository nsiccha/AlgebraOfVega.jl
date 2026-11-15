using TestItemRunner

# AoV's own look defaults (user decision 0qrccve, prong `defaults`): type
# sizes nearer the page's text, normal-weight axis titles and a label
# separation (`_apply_type_default!`), log axes labelled at 1-2-5 or decades
# from the rows (`_apply_log_ticks!`), and a tick count of 7 on x and 5 on y
# (`_apply_tick_cap!`; the runtime's `_capTicks` for container sizes).
# Before, a figure took Vega-Lite's 10-11 px type, a tick per 40 px (35 on a
# 1,400 px plot) and a label at every multiple on a log axis (`90100`).
@testitem "type, log-axis and tick-count defaults" tags=[:defaults] begin
    using AlgebraOfVega, AlgebraOfGraphics
    rows = (; x=[25.0, 50, 100, 200, 400], y=[0.5, 0.21, 0.1, 0.048, 0.012])
    plot = data(rows) * mapping(:x, :y) * visual(Lines)

    cfg = to_vegalite(plot)["config"]
    @test cfg["axis"]["labelFontSize"] == 11 && cfg["axis"]["titleFontSize"] == 12
    @test cfg["axis"]["titleFontWeight"] == "normal" && cfg["axis"]["labelSeparation"] == 4
    @test cfg["legend"]["labelFontSize"] == 12 && cfg["header"]["labelFontSize"] == 12
    @test cfg["title"]["fontSize"] == 14
    # An authored config wins key by key; font_scale scales AoV's sizes.
    own = to_vegalite(plot * config(config=Dict("axis" => Dict("labelFontSize" => 9))))["config"]["axis"]
    @test own["labelFontSize"] == 9 && own["titleFontSize"] == 12
    @test to_vegalite(plot * config(font_scale=2))["config"]["axis"]["labelFontSize"] == 22

    # Log axes: 1-2-5 within two decades, decades beyond; linear axes untouched.
    logged = to_vegalite(plot * config(scales=scales(X=(; scale=log10), Y=(; scale=log10))))
    enc = logged["encoding"]
    @test enc["x"]["axis"]["values"] == [10.0, 20, 50, 100, 200, 500, 1000]
    @test enc["y"]["axis"]["values"] == [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]
    @test !haskey(get(to_vegalite(plot)["encoding"]["x"], "axis", Dict()), "values")
    wide = data((; x=[1.0, 10, 100, 1000, 1e5], y=[1.0, 2, 3, 4, 5])) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(X=(; scale=log10)))
    @test to_vegalite(wide)["encoding"]["x"]["axis"]["values"] == [1.0, 10, 100, 1000, 1e4, 1e5]
    # A band's y2 field counts towards the extent; layers sharing the scale agree.
    bands = (; x=[1.0, 2, 3], m=[1.0, 2, 3], lo=[0.5, 1, 1.5], hi=[2.0, 40, 60])
    layered = (data(bands) * mapping(:x, :m) * lineribbon(bands=[:lo => :hi]) +
        data(bands) * mapping(:x, :m) * visual(Scatter)) * config(scales=scales(Y=(; scale=log10)))
    ys = [l["encoding"]["y"]["axis"]["values"] for l in to_vegalite(layered)["layer"] if haskey(l["encoding"], "y")]
    @test !isempty(ys) && all(==(first(ys)), ys) && last(first(ys)) == 100.0 && first(first(ys)) == 0.1
    # Both drawings of a ribbon over a log x (the interval drawing is built later).
    rib = data((; n=repeat([25.0, 50, 100], 2), g=repeat(["a", "b"], inner=3), m=[1.0, 2, 3, 1.5, 2.5, 3.5])) *
        mapping(:n, :m; color=:g) * lineribbon(bands=[:m => :m]) * config(scales=scales(X=(; scale=log10)))
    rvl = to_vegalite(rib)
    for drawing in (rvl, rvl["_aov"]["ribbonView"]["alt"])
        xs = [l["encoding"]["x"] for l in drawing["layer"] if haskey(get(l, "encoding", Dict()), "x")]
        @test !isempty(xs) && all(x -> get(get(x, "axis", Dict()), "values", nothing) == [10.0, 20, 50, 100], xs)
    end
    # Authored tick values or counts stay.
    mine = plot * config(scales=scales(X=(; scale=log10)), encoding=Dict("x" => Dict("axis" => Dict("values" => [25, 400]))))
    @test to_vegalite(mine)["encoding"]["x"]["axis"]["values"] == [25, 400]

    # Tick cap for an authored size; the runtime caps container sizes.
    capped = to_vegalite(plot * config(width=1200, height=400))["config"]
    @test capped["axisX"]["tickCount"] == 7 && capped["axisY"]["tickCount"] == 5
    small = to_vegalite(plot * config(width=200, height=200))["config"]
    @test !haskey(get(small, "axisX", Dict()), "tickCount") && !haskey(get(small, "axisY", Dict()), "tickCount")
    @test to_vegalite(plot * config(width=1200, config=Dict("axisX" => Dict("tickCount" => 20))))["config"]["axisX"]["tickCount"] == 20
    @test !haskey(get(to_vegalite(plot * config(width=1200, config=Dict("axis" => Dict("tickCount" => 3))))["config"], "axisX", Dict()), "tickCount")
    hist = data((; v=randn(200))) * mapping(:v) * histogram() * config(width=1200)
    @test !haskey(get(to_vegalite(hist)["config"], "axisX", Dict()), "tickCount")
end

@testitem "a container-sized plot asks for 7 x ticks, not one per 40 px" tags=[:defaults, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-look-defaults-") do dir
            rows = (; x=collect(0.0:1:100), y=sin.(0.0:1:100))
            page = [vdraw(data(rows) * mapping(:x, :y) * visual(Lines); id="ld-wide"),
                vdraw(data(rows) * mapping(:x, :y) * visual(Lines) + data(rows) * mapping(:x, :y) * visual(Scatter); id="ld-layered")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = """
            (async function () {
                const out = {};
                for (const id of ['ld-wide', 'ld-layered']) {
                    for (let i = 0; i < 500 && !(AoV.views[id] && !AoV._inFlight[id]); i++) await new Promise(r => setTimeout(r, 10));
                    await new Promise(r => setTimeout(r, 300));
                    // Axis labels per scale: an axis group's datum names its scale.
                    const view = AoV.views[id], labels = {x: 0, y: 0};
                    (function walk(it, scale) {
                        const s = it.datum && it.datum.scale ? it.datum.scale : scale;
                        if (it.mark && it.mark.role === 'axis-label') labels[scale] = (labels[scale] || 0) + 1;
                        (it.items || []).forEach(c => walk(c, it.mark && it.mark.role === 'axis' ? s : scale));
                    })(view.scenegraph().root, null);
                    out[id] = {width: view.width(), labels};
                }
                const pre = document.createElement('pre'); pre.id = 'aov-look-results';
                pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
            })();
            """
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:1400px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1500,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-look-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\""))
                @info "look defaults in the browser" report
                for id in ("ld-wide", "ld-layered")
                    @test report[id]["width"] > 1000
                    # Vega rounds the asked-for 7 to a nice step: 0–100 by 20 is 6 labels
                    # (26 before, one per 40 px of a 1,000+ px plot).
                    @test 3 <= report[id]["labels"]["x"] <= 8
                    @test 2 <= report[id]["labels"]["y"] <= 7
                end
            end
        end
    end
end
