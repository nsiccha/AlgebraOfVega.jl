using TestItemRunner

# Vega views a plot element keeps alive. A long synthetic report that
# releases offscreen plots with `AoV.disposeWithin` and keeps their drawings
# ran Chromium out of memory at 4 GB of JS heap. Two things held the views:
# - the element listeners `_attachTouch` added once per plot element shared a
#   scope with the first embed's touchstart handler, so every element kept its
#   first embed's view (data, dataflow, scenegraph) for as long as it stayed in
#   the page: two views per live plot after any re-embed, one per plot
#   disposed in place;
# - a disposed plot's drawing: Vega's `View.finalize` leaves the canvas and svg
#   handlers' listeners and the svg nodes' `__data__` items, and vega-embed's
#   finalize leaves the actions menu's export links, each holding the view.
#   `dispose` now swaps the drawing for a static copy and drops the menu.
# One page per renderer × actions-menu case.
@testitem "view retention in the browser: re-embeds and in-place disposal release views" tags=[:regression, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    n = 400
    rows = (; x=Float64.(1:n), y=Float64.(mod.((1:n) .* 7919, 1000)), g=["g$(mod(i, 5))" for i in 1:n])

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        plots = [vdraw(data(rows) * mapping(:x, :y; color=:g) * visual(Scatter) *
            config(width=240, height=160); id="vr-$i") for i in 1:4]
        driver = read(joinpath(@__DIR__, "view_retention.js"), String)
        # The SVG renderer is a vega-embed option of `AoV.embed`; the plots'
        # own embed scripts pass `{actions: false}`, so the page adds it.
        svg_shim = "AoV.embed = (function (embed) { return function (id, spec, opts) { " *
            "return embed.call(this, id, spec, Object.assign({}, opts, {renderer: 'svg'})); }; })(AoV.embed);"
        @testset "$renderer, actions menu $actions" for renderer in ("canvas", "svg"), actions in (false, true)
            mktempdir(prefix="kb-view-retention-") do dir
                head = join(html(h) for h in vega_head(; source=:inline, actions))
                setup = "window.AOV_RETENTION_CASE = {renderer: '$renderer', actions: $actions};" *
                    (renderer == "svg" ? svg_shim : "")
                write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                    "<script>" * setup * "</script>" *
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
                    @test report["checks"] >= 16
                    @test isempty(report["failures"])
                    @info "view retention browser checks" renderer actions checks=report["checks"] counts=report["counts"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
