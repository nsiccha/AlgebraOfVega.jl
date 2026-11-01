using TestItemRunner

# A plot wider than its frame scrolls in place (snag `scrollable-plot-8aede8f5`,
# reporter ODLPlaus:review:ux: axe's `scrollable-region-focusable` on a map's
# `.aov-plot-area`). A canvas holds nothing that takes the focus, so the frame
# is itself a named tab stop while it scrolls, and only then.
@testitem "a plot that scrolls in its frame is a named tab stop, and only then" tags=[:regression, :browser, :caption, :texts] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; x=string.('a':'z'), y=collect(1.0:26.0))
    bars(; kw...) = data(rows) * mapping(:x, :y) * visual(BarPlot) * config(; height=60, kw...)
    facets = data((; x=repeat(1.0:4.0, 12), y=repeat(1.0:4.0, 12), panel=repeat(string.("p", 1:12), inner=4))) *
        mapping(:x, :y; col=:panel) * visual(Scatter) * config(height=60)
    de = plot_texts(:de)

    # The accessible name lives in the words the runtime writes.
    @test plot_texts().scrollable == "Scrollable plot" && de.scrollable == "Scrollbare Grafik"
    @test plot_texts(:de; scrollable="Verschiebbar").scrollable == "Verschiebbar"
    # The runtime sets the tab stop's attributes; the node's bytes stay plain.
    @test !occursin("tabindex", html(vdraw(bars(width=900); id="sf-bytes")))
    # The focus ring is drawn inside the frame.
    @test occursin(".aov-plot-area:focus-visible { outline: 2px solid currentColor; outline-offset: -2px; }",
        read(joinpath(vega_vendor_dir(), "aov.css"), String))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-scroll-frame-") do dir
            cards = h.div(; id="sf-wrap", style="width:390px")(
                with_plot_caption(bars(width=900), "Run times"; plot_id="sf-en"),
                with_plot_caption(bars(width=900), "Laufzeiten"; plot_id="sf-de", texts=de),
                vdraw(bars(width=900, title="Doses"); id="sf-titled"),
                vdraw(bars(width=900); id="sf-bare"),
                vdraw(facets; id="sf-facets"),
                vdraw(bars(width=100); id="sf-narrow"),
                vdraw(bars(); id="sf-fit"),
                h.div(; class="aov-plot-area")(h.div(; id="sf-title-object")),
                h.div(; class="aov-plot-area")(h.div(; id="sf-grow")),
                h.div(; class="aov-plot-area")(h.div(; id="sf-slow")),
                h.div(; id="sf-direct", class="aov-plot-area"),
                h.div(; id="sf-frameless"),
            )
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            page = replace(to_html(cards; source=:inline), "<head>" => "<head><link rel='stylesheet' href='pico.min.css'>"; count=1)
            fixture = (; names=Dict("sf-en" => "Scrollable plot: Run times", "sf-de" => "Scrollbare Grafik: Laufzeiten",
                    "sf-titled" => "Scrollable plot: Doses", "sf-bare" => "Scrollable plot", "sf-facets" => "Scrollable plot"),
                fits=["sf-narrow", "sf-fit"])
            driver = read(joinpath(@__DIR__, "scroll_frame.js"), String)
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "page.html"), page[1:prevind(page, cut)] *
                "<script>window.AOV_FIXTURE=" * replace(JSON.json(fixture), "</" => "<\\/") * ";</script><script>" * driver * "</script>" *
                page[cut:end])
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1500,1600
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-scroll-frame-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 80
                @test isempty(report["failures"])
                @info "scroll frame browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
