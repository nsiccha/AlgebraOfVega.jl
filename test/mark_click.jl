using TestItemRunner

# A click on a data mark reaches app code as a bubbling `aov:click` DOM event
# on the plot element, carrying the mark's row (snag `aov-mark-click-h-42ead2bc`,
# design decision `14jo691`). Before it, an app that opened a table row from a
# chart polled `window.AoV.views` every 500 ms to re-attach Vega click
# listeners, because every re-embed (resize, picker, theme, `update_spec`)
# replaces the view and drops them.
@testitem "mark clicks in the browser: one aov:click per data-mark click, on every view" tags=[:regression, :browser, :interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    points = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "c"])
    scatter = data(points) * mapping(:x, :y; color=:g) * visual(Scatter)
    # The click lands on AoV's nearest-point overlay (a Vega-Lite Voronoi
    # path over the points), whose item datum is the point's scenegraph item.
    @test any(p -> get(p, "name", nothing) == "hover_nearest", to_vegalite(scatter)["params"])

    ags = ["01001", "01002", "01003"]
    # Clockwise rings: d3-geo reads a counter-clockwise ring as the whole
    # globe minus the square, so every district would paint the same area.
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0, 1.0], [x0 + 1, 1.0], [x0 + 1, 0.0], [x0, 0.0]]])
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => square(Float64(i))) for (i, a) in enumerate(ags)])
    bars = (; k=["a", "b", "c"], v=[1.0, 2.0, 4.0])
    panels = (; k=repeat(["a", "b"], 2), v=[1.0, 2.0, 3.0, 4.0], panel=repeat(["1", "2"], inner=2))
    zero_y = config(scales=scales(Y=(; zero=true)))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-mark-click-") do dir
            page = [vdraw(scatter; id="mc-scatter"),
                vdraw(data((; AGS=ags, effect=[-0.4, 0.1, 0.7])) * mapping(:AGS; color=:effect) *
                    geoshape(geojson) * config(width=240, height=80); id="mc-map"),
                vdraw(data(bars) * mapping(:k, :v) * visual(BarPlot) * zero_y *
                    config(width=240, height=160); id="mc-bars"),
                vdraw(data(panels) * mapping(:k, :v; col=:panel) * visual(BarPlot) * zero_y *
                    config(width=160, height=160); id="mc-facet")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "mark_click.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-mark-click-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 15
                @test isempty(report["failures"])
                @info "mark click browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
