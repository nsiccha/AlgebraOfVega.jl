using TestItemRunner

"""
A figure that an htmx swap brings in under the id of the one it replaces keeps
what its embed wrote on its element (snag `map-reset-button-4351fbe6`, reporter
RegionExplorer).

htmx settles such an element: it gives the new element the old one's `class`
and `style` at the swap and puts the served values back about 20 ms later
(`htmx.config.attributesToSettle`). The plot's script runs in between, so what
the embed wrote there was reverted whenever the embed got to it first:

- vega-embed's `vega-embed` class, which makes the element the reset button's
  positioned box: on every RegionExplorer drill-down (one map id per level) the
  "Reset zoom" button hung from the nearest positioned ancestor instead, 85 px
  above the map on the caption's title;
- vega-embed's `has-actions` class, which lays out the actions menu;
- the runtime's own `width: 100%` and `max-width` cap on a single view.

The item swaps fragments with htmx's own `htmx.swap`: once with the settle long
after the embeds (the order the reporter measured), once with htmx's default
settle delay, and checks each against a freshly loaded page.
"""
@testitem "a figure htmx swaps in under the same id keeps what its embed gave its element" tags=[:browser, :regression, :geoshape] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON

    square(k, x0, y0, d) = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("k" => k),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[x0, y0], [x0, y0 + d], [x0 + d, y0 + d], [x0 + d, y0], [x0, y0]]]))
    html(x) = sprint(show, MIME"text/html"(), x)
    # One level of a drill-down: a captioned map, a plot with vega-embed's
    # actions menu and a width-capped single view, under the same ids at
    # every level, with different data.
    function level(n)
        geo = Dict{String,Any}("type" => "FeatureCollection",
            "features" => [square("c$(i)_$(j)", 9.0 + 0.3i, 53.0 + 0.2j, 0.2) for i in 0:(3 + n) for j in 0:3])
        rows = (; k=[f["properties"]["k"] for f in geo["features"]], v=Float64.(n .+ (1:length(geo["features"]))))
        map = data(rows) * mapping(:k; color=:v) * geoshape(geo) * config(width=360, height=240)
        xy = data((; a=Float64.(1:3 + n), b=Float64.(n .+ (1:3 + n)))) * mapping(:a, :b) * visual(Scatter)
        join([html(with_plot_caption(map, CaptionSpec(; title="Level $n", short="A click drills down."); plot_id="ss-map")),
            html(to_node(xy * config(height=120); id="ss-act", actions=true)),
            html(to_node(xy * config(height=120, max_width=300); id="ss-cap"))])
    end
    driver = read(joinpath(@__DIR__, "settled_swap.js"), String)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-settle-") do dir
            HTMXObjects.copy_vendorfiles(joinpath(dir, "htmxo"); packages=(:htmx,), runtime=false)
            head = join(html.(HTMXObjects.vendor_head("htmxo"; packages=(:htmx,)))) *
                   join(html(n) for n in vega_head(; source=:inline))
            levels = (; level1=level(1), level2=level(2))
            # The column above the figure is positioned, as RegionExplorer's
            # sticky map column is: a button that misses the plot's own box
            # lands on it, far from the map.
            write(joinpath(dir, "page.html"), """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8">$head
                <style>body{margin:0;width:900px} #ss-column{position:relative;padding-top:60px}</style></head>
                <body><div id="ss-column"><div id="ss-target">$(levels.level1)</div></div>
                <pre id="aov-settle-results"></pre>
                <script>window.AOV_LEVELS = $(replace(JSON.json(levels), "</" => "<\\/"));</script>
                <script>$driver</script>
                </body></html>
                """)
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=60000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-settle-results\">([^<]+)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 42
                @test isempty(report["failures"])
                @info "settled swap browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
