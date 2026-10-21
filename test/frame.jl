using TestItemRunner

# `config(frame=:year)` animates a figure over a column's values: one frame at
# a time, a play/pause button and a slider, scales fixed across frames
# (snag `aov-animated-fra-0856abf4`, design decision `14ck1tp`). Before it,
# the only interactive filter was `config(select=…)`, a dropdown that re-fits
# the colour scale on every choice, and a hand-written `config(transform=…)`
# replaced a geoshape's own lookup, so the map painted nothing.

@testsnippet AoVFrameFixtures begin
    # Clockwise rings: d3-geo reads a counter-clockwise ring as the whole globe
    # minus the square (todo `0jjyv1k`), which breaks the projection fit.
    _frame_square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 50.0], [x0, 51.0], [x0 + 1, 51.0], [x0 + 1, 50.0], [x0, 50.0]]])
    frame_geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("land" => l),
            "geometry" => _frame_square(x0)) for (l, x0) in (("A", 0.0), ("B", 2.0), ("C", 4.0))])
    # 2000: A, B; 2001: A, B, C; 2002: A, C. A is 1.0 in both 2000 and 2002: the
    # lowest value of 2000 and the highest of 2002, so per-frame scales colour it apart.
    frame_rows = (; land=["A", "B", "A", "B", "C", "A", "C"],
        year=[2000, 2000, 2001, 2001, 2001, 2002, 2002],
        anomaly=[1.0, 2.0, 2.0, 0.0, 3.0, 1.0, -2.0])
    frame_map(rows=frame_rows; kw...) = data(rows) * mapping(:land; color=:anomaly) * geoshape(frame_geo) *
        config(height=100, frame=(; field=:year, interval=0.03, kw...))

    # Headless Chrome ("" when the host has none) and one page load in it: the
    # JSON report a driver wrote into `<pre id=results>`, or `nothing`.
    frame_chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    frame_run_page(dir, file, results) = begin
        output = read(pipeline(`$frame_chrome --headless=new --no-sandbox --disable-gpu
            --user-data-dir=$(joinpath(dir, "profile-" * file)) --window-size=1200,1600
            --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, file))`,
            stderr=joinpath(dir, file * ".log")), String)
        m = match(Regex("<pre id=\"$results\">([^<]*)</pre>"), output)
        isnothing(m) ? nothing : JSON.parse(replace(m[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
    end
end

@testitem "frame lowering: parameter, unit filters and player metadata" setup=[AoVFrameFixtures] tags=[:frame] begin
    using AlgebraOfVega, AlgebraOfGraphics, Dates
    v = to_vegalite(frame_map())
    # The frame filter comes first and the geoshape's own lookup survives.
    @test v["transform"][1] == Dict("filter" => "!isValid(datum[\"year\"]) || datum[\"year\"] === aov_frame")
    @test haskey(v["transform"][2], "lookup")
    @test v["params"][end] == Dict("name" => "aov_frame", "value" => 2000)
    @test v["_aov"]["frame"] == Dict("field" => "year", "values" => [2000, 2001, 2002], "temporal" => false,
        "interval" => 30, "loop" => false, "start" => 0)
    @test to_vegalite(frame_map(; loop=true, start=:last))["_aov"]["frame"]["start"] == 2
    @test to_vegalite(frame_map(; start=2001))["params"][end]["value"] == 2001

    # The short form, with the defaults.
    scatter = data((; x=[1, 2, 3], y=[1, 2, 3], g=["a", "b", "a"], t=[1, 1, 2])) *
        mapping(:x, :y; color=:g) * visual(Scatter)
    s = to_vegalite(scatter * config(frame=:t))
    @test s["_aov"]["frame"]["interval"] == 500 && s["_aov"]["frame"]["values"] == [1, 2]
    # AoV's own interactivity is kept: a parameter would otherwise switch it off.
    @test Set(p["name"] for p in s["params"]) == Set(["grid", "hover_nearest", "legend_selection", "aov_frame"])
    @test haskey(s["_aov"], "legendInteraction")
    # Every unit of a layered figure is filtered; a reference layer without the
    # column passes the filter and is drawn in every frame.
    layered = to_vegalite(scatter + data((; y=[2])) * mapping(:y) * visual(HLines) * config(frame=:t))
    @test all(l -> startswith(l["transform"][1]["filter"], "!isValid(datum[\"t\"])"), layered["layer"])
    @test any(p -> p["name"] == "aov_frame", layered["params"])
    # A later frame term wins, like any other config property.
    @test to_vegalite(scatter * config(frame=:t) * config(frame=:g))["_aov"]["frame"]["field"] == "g"
    # A sorter orders the frames; a value the sorter does not list is an error.
    months = data((; m=["Mar", "Jan", "Feb", "Jan"], v=[1, 2, 3, 4])) * mapping(:v) * visual(HLines)
    @test to_vegalite(months * config(frame=:m))["_aov"]["frame"]["values"] == ["Feb", "Jan", "Mar"]
    ordered = to_vegalite(months * config(frame=(; field=:m => sorter("Jan", "Feb", "Mar", "Apr"))))
    @test ordered["_aov"]["frame"]["values"] == ["Jan", "Feb", "Mar"]
    @test to_vegalite(months * config(frame=:m => sorter(["Jan", "Feb", "Mar"])))["params"][end]["value"] == "Jan"
    @test_throws ArgumentError to_vegalite(months * config(frame=:m => sorter("Jan", "Feb")))
    # Missing frame values are not frames.
    m = to_vegalite(data((; x=[1, 2, 3], t=[1.0, NaN, missing])) * mapping(:x) * visual(HLines) * config(frame=:t))
    @test m["_aov"]["frame"]["values"] == [1.0]

    # Dates compare as times: Vega-Lite parses an encoded temporal field into a Date.
    d = to_vegalite(data((; d=[Date(2020, 1, 2), Date(2020, 1, 1)], v=[1, 2])) * mapping(:d, :v) *
        visual(Scatter) * config(frame=:d))
    @test d["transform"][1]["filter"] == "!isValid(datum[\"d\"]) || time(datum[\"d\"]) === time(aov_frame)"
    @test d["_aov"]["frame"]["temporal"] && AlgebraOfVega._vl_json(d["_aov"]["frame"]["values"]) == "[\"2020-01-01\",\"2020-01-02\"]"

    # Faceted specs: the parameter is top-level, the filter sits in the units.
    f = to_vegalite(data((; x=[1, 2], y=[1, 2], p=["u", "v"], t=[1, 2])) * mapping(:x, :y; col=:p, color=:p) *
        (visual(Scatter) + visual(Lines)) * config(frame=:t))
    @test any(p -> p["name"] == "aov_frame", f["params"])
    @test all(l -> haskey(l, "transform"), f["spec"]["layer"])

    # Rows reach Vega-Lite as they are for the `bands=` summaries and VL-transform analyses.
    bands = (; x=[1, 2, 1, 2], year=[1, 1, 2, 2], q50=[1.0, 2, 3, 4], lo=[0.0, 1, 2, 3], hi=[2.0, 3, 4, 5], g=fill("a", 4))
    for spec in (data(bands) * mapping(:x, :q50) * lineribbon(bands=[:lo => :hi]),
                 data(bands) * mapping(:q50, y=:g) * pointinterval(bands=[:lo => :hi]),
                 data(bands) * mapping(:x, :q50) * linear(), data(bands) * mapping(:q50) * density())
        @test haskey(to_vegalite(spec * config(frame=:year))["_aov"], "frame")
    end
end

@testitem "frame refusals name the fix" setup=[AoVFrameFixtures] tags=[:frame] begin
    using AlgebraOfVega, AlgebraOfGraphics
    draws = (; v=randn(20), g=fill("a", 20), t=repeat([1, 2], 10))
    # A summary computed in Julia carries no frame value ...
    err = try
        to_vegalite(data(draws) * mapping(:v, y=:g) * pointinterval() * config(frame=:t)); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("bands=", err.msg)
    @test_throws ArgumentError to_vegalite(data(draws) * mapping(:v; col=:g) * density() * config(frame=:t))
    # ... but one without the frame column is a background shown in every frame.
    background = data((; v=randn(20), g=fill("a", 20))) * mapping(:v, y=:g) * pointinterval()
    @test haskey(to_vegalite(background + data(draws) * mapping(:v, :g) * visual(Scatter) * config(frame=:t))["_aov"], "frame")

    @test_throws ArgumentError to_vegalite(frame_map() * config(frame=:nope))
    @test_throws ArgumentError to_vegalite(frame_map(; start=1999))
    @test_throws ArgumentError config(frame=(; field=:year, speed=2))
    @test_throws ArgumentError config(frame=(; interval=1))
    @test_throws ArgumentError config(frame=(; field=:year, interval=0))
    @test_throws ArgumentError config(frame=1)

    # The picker cannot remap the frame column, and the static path refuses frames.
    scatter = data((; x=[1, 2, 3], y=[1, 2, 3], g=["a", "b", "a"], t=[1, 1, 2])) *
        mapping(:x, :y; color=:g) * visual(Scatter) * config(frame=:t)
    @test_throws ArgumentError to_vegalite(scatter; auto_remap=(; dims=["g" => "G", "t" => "T"]))
    @test_throws ArgumentError to_vegalite(scatter; auto_remap=(; dims=["g" => "G"], fixed=Dict(:column => "t")))
    @test haskey(to_vegalite(scatter; auto_remap=(; dims=["g" => "G"]))["_aov"], "frame")
    @test_throws ArgumentError AlgebraOfVega._draw_kwargs(scatter.config)
end

@testitem "frame players in the browser" setup=[AoVFrameFixtures] tags=[:frame, :browser, :regression] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON, Dates
    html(x) = sprint(show, MIME"text/html"(), x)
    script_text(node) = let s = html(node)
        s[last(findfirst(r"<script[^>]*>", s)) + 1:first(findlast("</script>", s)) - 1]
    end

    bars = data((; year=[1, 1, 2, 2], cat=["c0", "c1", "c0", "c1"], k=fill("a", 4), v=[1.0, 2.0, 5.0, 6.0])) *
        mapping(:k, :v; color=:cat) * visual(BarPlot) * config(width=200, height=120, frame=:year)
    ref = data((; x=[1.0, 2.0, 3.0], y=[1.0, 2.0, 3.0], t=[1, 1, 2])) * mapping(:x, :y) * visual(Scatter) +
        data((; y=[2.0])) * mapping(:y) * visual(HLines) * config(width=200, height=120, frame=:t)
    days = data((; d=[Date(2020, 1, 1), Date(2020, 1, 2), Date(2020, 1, 3)], v=[1.0, 4.0, 2.0])) *
        mapping(:d, :v) * visual(Scatter) * config(width=200, height=120, frame=:d)
    more = (; land=[frame_rows.land; "A"], year=[frame_rows.year; 2003], anomaly=[frame_rows.anomaly; 5.0])
    page = [vdraw(frame_map(); id="fr-map"),
        h.div(; id="fr-bars-wrap")(vdraw(bars; id="fr-bars")),
        vdraw(ref; id="fr-ref"), vdraw(days; id="fr-time"),
        with_plot_caption(frame_map(), "Karte"; plot_id="fr-de", texts=plot_texts(:de))]
    fixture = replace(JSON.json((; update=script_text(update_spec("fr-map", frame_map(more))))), "</" => "<\\/")

    if isempty(frame_chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-frame-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            # A dark theme the host-theme watcher sees (a `data-theme` change re-embeds).
            dark = "<style>html[data-theme=dark] body { color: #ddd; background: #111; }</style>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * dark *
                "<body style='width:800px'>" * join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * fixture * ";</script><script>" *
                read(joinpath(@__DIR__, "frame.js"), String) * "</script></body>")
            report = frame_run_page(dir, "page.html", "aov-frame-results")
            @test !isnothing(report)
            if !isnothing(report)
                @test report["checks"] == 26
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end

            # A standalone page plays with no server.
            export_page = to_html(frame_map(), "Map"; plot_id="fr-export", source=:inline)
            cut = first(findlast("</body>", export_page))
            write(joinpath(dir, "export.html"), export_page[1:prevind(export_page, cut)] * "<script>" *
                read(joinpath(@__DIR__, "frame_export.js"), String) * "</script>" * export_page[cut:end])
            report = frame_run_page(dir, "export.html", "aov-frame-export-results")
            @test !isnothing(report)
            if !isnothing(report)
                @test report["checks"] == 3
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

# Pico 2 fills every <button> with its primary azure (plus an azure focus ring)
# and turns a focused range thumb azure; a bare range input draws in the
# browser's accent blue. The player took those from whatever page it sat on
# (snag `aov-frame-play-b-68ebbfc1`). Now, light and dark, it never shows
# them: on a Pico page and on a page with no stylesheet the play button is a
# text-colour outline, and on a page that styles its own buttons (as
# HTMXObjects' `pico_bridge()` may, ahead of `vega_head` in the shell) it
# looks like the page's other buttons.
@testitem "frame controls never take a theme's primary blue" setup=[AoVFrameFixtures] tags=[:frame, :browser, :regression] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    if isempty(frame_chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-frame-neutral-") do dir
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            pico = "<link rel='stylesheet' href='pico.min.css'>"
            button_theme = "<style>:is(button, [type=button]):not(.secondary, .contrast) " *
                "{ background-color: rgb(82, 95, 122); border-color: rgb(82, 95, 122); color: rgb(255, 255, 255); }</style>" *
                "<script>window.AOV_BUTTON_THEME = {background: 'rgb(82, 95, 122)', color: 'rgb(255, 255, 255)'};</script>"
            head = join(html(n) for n in vega_head(; source=:inline))
            body = html(vdraw(frame_map(); id="fr-neutral"))
            driver = read(joinpath(@__DIR__, "frame_neutral.js"), String)
            for (file, theme) in (("pico.html", pico), ("themed.html", pico * button_theme),
                    ("plain.html", "<style>html[data-theme=dark] body { color: #ddd; background: #111; }</style>"))
                write(joinpath(dir, file), "<!doctype html><meta charset='utf-8'>" * theme * head *
                    "<body><main class='container'>" * body * "</main><script>" * driver * "</script></body>")
                report = frame_run_page(dir, file, "aov-frame-neutral-results")
                @test !isnothing(report)
                if !isnothing(report)
                    @test report["checks"] == 14
                    @test isempty(report["failures"])
                    isempty(report["failures"]) || println(file, ": ", JSON.json(report["failures"]))
                end
            end
        end
    end
end
