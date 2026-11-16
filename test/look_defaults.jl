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
    # The whole 1-2-5 sequence (Vega draws the values inside the domain), so a
    # data-only refresh leaves the spec alone.
    in_range(v, lo, hi) = filter(t -> lo <= t <= hi, v)
    @test in_range(enc["x"]["axis"]["values"], 10, 1000) == [10.0, 20, 50, 100, 200, 500, 1000]
    @test in_range(enc["y"]["axis"]["values"], 0.01, 1) == [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]
    @test enc["x"]["axis"]["values"] == to_vegalite(data((; x=2 .* rows.x, y=rows.y)) * mapping(:x, :y) * visual(Lines) *
        config(scales=scales(X=(; scale=log10))))["encoding"]["x"]["axis"]["values"]
    @test !haskey(get(to_vegalite(plot)["encoding"]["x"], "axis", Dict()), "values")
    wide = data((; x=[1.0, 10, 100, 1000, 1e5], y=[1.0, 2, 3, 4, 5])) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(X=(; scale=log10)))
    @test in_range(to_vegalite(wide)["encoding"]["x"]["axis"]["values"], 1, 1e5) == [1.0, 10, 100, 1000, 1e4, 1e5]
    # A band's y2 field counts towards the extent; layers sharing the scale agree.
    bands = (; x=[1.0, 2, 3], m=[1.0, 2, 3], lo=[0.5, 1, 1.5], hi=[2.0, 40, 60])
    layered = (data(bands) * mapping(:x, :m) * lineribbon(bands=[:lo => :hi]) +
        data(bands) * mapping(:x, :m) * visual(Scatter)) * config(scales=scales(Y=(; scale=log10)))
    ys = [l["encoding"]["y"]["axis"]["values"] for l in to_vegalite(layered)["layer"] if haskey(l["encoding"], "y")]
    @test !isempty(ys) && all(==(first(ys)), ys) && in_range(first(ys), 0.1, 100) == [0.1, 1, 10, 100]
    # Both drawings of a ribbon over a log x (the interval drawing is built later).
    rib = data((; n=repeat([25.0, 50, 100], 2), g=repeat(["a", "b"], inner=3), m=[1.0, 2, 3, 1.5, 2.5, 3.5])) *
        mapping(:n, :m; color=:g) * lineribbon(bands=[:m => :m]) * config(scales=scales(X=(; scale=log10)))
    rvl = to_vegalite(rib)
    for drawing in (rvl, rvl["_aov"]["ribbonView"]["alt"])
        xs = [l["encoding"]["x"] for l in drawing["layer"] if haskey(get(l, "encoding", Dict()), "x")]
        @test !isempty(xs) && all(x -> in_range(get(get(x, "axis", Dict()), "values", Float64[]), 10, 100) == [10.0, 20, 50, 100], xs)
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

    # An axis that lists its tick values states their count, so no `config`
    # count thins them: Vega halves a listed set to fit a count, and twelve
    # monthly values under the cap of 7 drew six (snag `draw-a-line-figu-9ca9fcd0`).
    months = [11, 42, 70, 101, 131, 162, 192, 223, 254, 284, 315, 345]
    year = (; day=collect(0:5:365), a=sin.(0:5:365), b=cos.(0:5:365))
    listed = to_vegalite(data(year) * (mapping(:day, :a) * visual(Lines) + mapping(:day, :b) * visual(Lines)) *
        config(width=1200, encoding=(; x=(; axis=(; values=months)))))
    @test listed["config"]["axisX"]["tickCount"] == 7
    @test length(listed["layer"]) == 2
    @test all(l -> l["encoding"]["x"]["axis"]["values"] == months && l["encoding"]["x"]["axis"]["tickCount"] == 12, listed["layer"])
    # A count written beside the values stays; an axis that lists none gets none.
    counted = to_vegalite(data(year) * mapping(:day, :a) * visual(Lines) *
        config(width=1200, encoding=(; x=(; axis=(; values=months, tickCount=6)))))
    @test counted["encoding"]["x"]["axis"]["tickCount"] == 6
    @test !haskey(get(to_vegalite(plot * config(width=1200))["encoding"]["x"], "axis", Dict()), "tickCount")
    # The log values state theirs.
    @test enc["x"]["axis"]["tickCount"] == length(enc["x"]["axis"]["values"])
    @test enc["y"]["axis"]["tickCount"] == length(enc["y"]["axis"]["values"])
    # A stack has one config for all its panels: a tall panel's cap reaches
    # the panel under it, whose listed values stay.
    quarters = collect(-1:0.25:1)
    stack = to_vegalite(vconcat(data(year) * mapping(:day, :a) * visual(Lines) * config(height=300),
        data(year) * mapping(:day, :b) * visual(Lines) * config(height=120, encoding=(; y=(; axis=(; values=quarters))))))
    @test stack["config"]["axisY"]["tickCount"] == 5
    @test stack["vconcat"][2]["encoding"]["y"]["axis"]["tickCount"] == length(quarters)
    @test !haskey(get(stack["vconcat"][1]["encoding"]["y"], "axis", Dict()), "tickCount")
end

@testitem "listed tick values are all drawn, whatever the tick count" tags=[:defaults, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-listed-ticks-") do dir
            # One tick per month on a day-of-year axis (snag `draw-a-line-figu-9ca9fcd0`).
            months = [11, 42, 70, 101, 131, 162, 192, 223, 254, 284, 315, 345]
            day = collect(0:5:365)
            year = (; day, a=3 .- cos.(2pi .* day ./ 365), b=6 .- cos.(2pi .* day ./ 365))
            axis = (; values=months, labelExpr="utcFormat(utc(2025, 11, 21) + datum.value * 86400000, '%-d %b')")
            figure = data(year) * (mapping(:day, :a) * visual(Lines) + mapping(:day, :b) * visual(Lines; linestyle=:dash)) *
                config(height=150, encoding=(; x=(; axis)))
            logrows = (; x=[25.0, 50, 100, 200, 400], y=[0.5, 0.21, 0.1, 0.048, 0.012])
            # A spec AoV did not lower: the runtime states the count itself.
            raw = Dict{String,Any}("width" => "container", "height" => 150,
                "data" => Dict("values" => [Dict("day" => d, "a" => a) for (d, a) in zip(year.day, year.a)]), "mark" => "line",
                "encoding" => Dict("x" => Dict("field" => "day", "type" => "quantitative", "axis" => Dict("values" => months)),
                    "y" => Dict("field" => "a", "type" => "quantitative")))
            page = [vdraw(figure; id="lt-months"),
                vdraw(figure * config(width=1200); id="lt-width"),
                vdraw(data(logrows) * mapping(:x, :y) * visual(Lines) * config(height=400, scales=scales(Y=(; scale=log10))); id="lt-log"),
                vdraw(raw; id="lt-raw"),
                vdraw(data(year) * mapping(:day, :a) * visual(Lines) * config(height=150); id="lt-plain")]
            ids = ["lt-months", "lt-width", "lt-log", "lt-raw", "lt-plain"]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = """
            (async function () {
                const out = {};
                for (const id of $(JSON.json(ids))) {
                    for (let i = 0; i < 500 && !(AoV.views[id] && !AoV._inFlight[id]); i++) await new Promise(r => setTimeout(r, 10));
                    await new Promise(r => setTimeout(r, 300));
                    // Axis labels per scale: an axis group's datum names its scale.
                    const view = AoV.views[id], labels = {x: [], y: []};
                    (function walk(it, scale) {
                        const s = it.datum && it.datum.scale ? it.datum.scale : scale;
                        if (it.mark && it.mark.role === 'axis-label' && it.opacity !== 0 && labels[scale]) labels[scale].push(it.text);
                        (it.items || []).forEach(c => walk(c, it.mark && it.mark.role === 'axis' ? s : scale));
                    })(view.scenegraph().root, null);
                    out[id] = {width: view.width(), labels};
                }
                // The channel picker drops a field's tick values with their count.
                const moved = {field: 'a', axis: {values: [1, 2, 3], tickCount: 3, title: 't'}};
                AoV._clearRemappedAxisDomain(moved, 'b');
                const thinned = {field: 'a', axis: {values: [1, 2, 3], tickCount: 2}};
                AoV._clearRemappedAxisDomain(thinned, 'b');
                out.picker = {moved: moved.axis, thinned: thinned.axis};
                const pre = document.createElement('pre'); pre.id = 'aov-listed-results';
                pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
            })();
            """
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:1400px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1500,2400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-listed-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\""))
                @info "listed tick values in the browser" report
                monthly = ["1 Jan", "1 Feb", "1 Mar", "1 Apr", "1 May", "1 Jun", "1 Jul", "1 Aug", "1 Sep", "1 Oct", "1 Nov", "1 Dec"]
                # Container-sized (the runtime's cap) and an authored width (the lowering's).
                @test report["lt-months"]["width"] > 1000
                @test report["lt-months"]["labels"]["x"] == monthly
                @test report["lt-width"]["labels"]["x"] == monthly
                # AoV's own log values: 1-2-5 within two decades, under the y cap of 5.
                @test report["lt-log"]["labels"]["y"] == ["0.01", "0.02", "0.05", "0.1", "0.2", "0.5", "1"]
                @test report["lt-raw"]["width"] > 1000
                @test length(report["lt-raw"]["labels"]["x"]) == 12
                # An axis that lists nothing keeps the default count.
                @test 3 <= length(report["lt-plain"]["labels"]["x"]) <= 9
                @test report["picker"]["moved"] == Dict("title" => "t")
                @test report["picker"]["thinned"] == Dict("tickCount" => 2)
            end
        end
    end
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
