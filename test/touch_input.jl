using TestItemRunner

# Touch input (snag `touch-input-tap-7e25466e`, reporter VerkehrsStrukturdaten:ux:touch).
# Vega picks a canvas mark only on pointermove, which a finger tap never
# sends, so on a phone a tap on a map district sent no `aov:click` (no
# drill-down) and no `aov:hover`, and a tooltip showed only while a finger
# dragged, under the finger. A tap now opens the mark's tooltip above the
# finger and hovers its row until a tap elsewhere; a long press is its click.
@testitem "touch input in the browser: a tap opens the tooltip and hovers, a long press clicks" tags=[:regression, :browser, :interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    ags = ["01001", "01002", "01003"]
    # Clockwise rings: d3-geo reads a counter-clockwise ring as the whole
    # globe minus the square (see test/mark_click.jl).
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0, 1.0], [x0 + 1, 1.0], [x0 + 1, 0.0], [x0, 0.0]]])
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => square(Float64(i))) for (i, a) in enumerate(ags)])
    points = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "c"])
    bars = (; k=["a", "b", "c"], v=[1.0, 2.0, 4.0])

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-touch-input-") do dir
            page = [
                # A map in a link group, as RegionExplorer's choropleth draws one.
                vdraw(data((; AGS=ags, effect=[-0.4, 0.1, 0.7])) * mapping(:AGS; color=:effect) *
                    geoshape(geojson) * config(width=300, height=100) *
                    config(link=(; group="districts", key=:AGS)); id="tt-map"),
                # A scatter with AoV's nearest-point overlay.
                vdraw(data(points) * mapping(:x, :y; color=:g) * visual(Scatter) *
                    config(width=240, height=160); id="tt-scatter"),
                # Bars: the space above a bar is no mark.
                vdraw(data(bars) * mapping(:k, :v) * visual(BarPlot) *
                    config(scales=scales(Y=(; zero=true))) * config(width=240, height=160); id="tt-bars")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "touch_input.js"), String)
            # Room above the map for its tooltip, and below the plots to scroll.
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'><div style='height:200px'></div>" * join(html(p) for p in page) *
                "<div style='height:2400px'></div><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-touch-input-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "touch input browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
