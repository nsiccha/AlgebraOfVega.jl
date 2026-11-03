using TestItemRunner

# Vega views a plot element keeps alive (snag `attachtouch-clos-f2d7a0dc`,
# reporter Bruno:arv393). The element listeners `_attachTouch` added once per
# plot element shared a scope with the first embed's touchstart handler, so
# every element kept its first embed's view (data, dataflow, scenegraph)
# reachable for as long as it stayed in the page: two views per live plot after
# any re-embed, and one per plot disposed in place. A long report that releases
# offscreen plots with `AoV.disposeWithin` and keeps their snapshots ran
# Chromium out of memory at 4 GB of JS heap.
@testitem "view retention in the browser: re-embeds and in-place disposal release replaced views" tags=[:regression, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    n = 400
    rows = (; x=Float64.(1:n), y=Float64.(mod.((1:n) .* 7919, 1000)), g=["g$(mod(i, 5))" for i in 1:n])

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-view-retention-") do dir
            plots = [vdraw(data(rows) * mapping(:x, :y; color=:g) * visual(Scatter) *
                config(width=240, height=160); id="vr-$i") for i in 1:4]
            head = join(html(h) for h in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "view_retention.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'><div id='retention-plots'>" * join(html(p) for p in plots) *
                "</div><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --js-flags=--expose-gc
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-view-retention-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 8
                @test isempty(report["failures"])
                @info "view retention browser checks" checks=report["checks"] counts=report["counts"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
