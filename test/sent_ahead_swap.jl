using TestItemRunner

"""
A captioned figure that an htmx swap replaces with a new one under the same
plot id: a part HTMXObjects' `send_ahead` replaces out of band, and the
finished answer that replaces the parts.

Regression (snag `opened-the-same-c95278ca`): an app sent its dose figure ahead
dose by dose under one plot id, then answered with the whole figure. htmx 2 runs
a swapped fragment's scripts as
it inserts them, before it removes what they replace, and HTMXObjects keeps the
parts above the finished answer until that swap ends. So each embed ran while
the old figure, with the same id and its own Ribbons | Intervals buttons, was
still in the page:

- every replaced part reused the old figure's buttons, which then left with it:
  no switch from the second part on;
- the finished answer embedded under the old element, which `getElementById`
  names first. The removal sweep disposed that embed as the old element left,
  so the figure was a dead drawing: no switch, no fit correction (wider than
  its column, the legend off-screen), no view.

An answer within the grace period (a cached one) sends no parts and looked right,
in either colour scheme. The item lands parts through HTMXObjects' own
`sent_ahead_script()` and swaps the finished answer as Treebars does (outerHTML
of the polling inner, `select` of `.treebar-terminal-content`), with the
vendored htmx 2.
"""
@testitem "a figure swapped in under the same plot id keeps its switch, its view and its fit" setup=[AoVBrowserServer] tags=[:browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    import HTMX

    doses = [5.0, 10.0, 20.0, 40.0, 60.0]
    quantities = ["AUC", "Maximum", "Time of maximum", "Minimum", "Average"]
    function figure(n)
        rows = (; dose=Float64[], scenario=String[], quantity=String[], q50=Float64[], lo=Float64[],
            hi=Float64[], lo50=Float64[], hi50=Float64[])
        for (qi, q) in enumerate(quantities), (si, s) in enumerate(["Daily", "Twice daily"]), d in doses[1:n]
            m = d * 1000 * qi * (si == 1 ? 1.0 : 0.85)
            push!(rows.dose, d); push!(rows.scenario, s); push!(rows.quantity, q); push!(rows.q50, m)
            push!(rows.lo, 0.2m); push!(rows.hi, 3m); push!(rows.lo50, 0.7m); push!(rows.hi50, 1.5m)
        end
        spec = data(rows) * mapping(:dose => "Dose (mg)", :q50 => "Median"; color=:scenario => "Scenario",
                   layout=:quantity => sorter(quantities) => "") *
               lineribbon(bands=[:lo => :hi, :lo50 => :hi50]) *
               config(scales=scales(X=(; scale=log10, nice=false))) * config(facet=(; linkyaxes=:none))
        sprint(show, MIME"text/html"(), with_plot_caption(spec, CaptionSpec(; title="Dose–response");
            plot_id="dr-plot"))
    end
    # The fixture is a figure with the switch.
    rows3 = (; dose=[5.0, 10.0, 20.0], scenario=["a", "a", "a"], q50=[1.0, 2.0, 3.0], lo=[0.0, 1.0, 2.0],
        hi=[2.0, 3.0, 4.0])
    @test ribbon_view(data(rows3) * mapping(:dose, :q50; color=:scenario) * lineribbon(bands=[:lo => :hi])).offered
    html(x) = sprint(show, MIME"text/html"(), x)
    driver = read(joinpath(@__DIR__, "sent_ahead_swap.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-ahead-") do dir
            HTMXObjects.copy_vendorfiles(joinpath(dir, "htmxo"); packages=(:htmx,), runtime=false)
            head = join(html.(HTMXObjects.vendor_head("htmxo"; packages=(:htmx,)))) *
                   join(html.(vega_head(; source=:vendor, base="/vendor"))) * html(HTMXObjects.sent_ahead_script())
            parts = (; part1="<div id=\"dr-ahead\">$(figure(3))</div>",
                part2="<div id=\"dr-ahead\" hx-swap-oob=\"true\">$(figure(4))</div>",
                final="<div class=\"treebar-terminal-content\">$(figure(5))</div>")
            # 1040 px: an app's content column at a 1440 px window.
            write(joinpath(dir, "page.html"), """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8">$head
                <style>body{margin:0} main{width:1040px}</style></head>
                <body><main>
                <div class="treebar-poller"><div class="treebar-poller-inner" hx-get="/never">running</div></div>
                </main>
                <pre id="aov-ahead-results"></pre>
                <script>window.AOV_PARTS = $(replace(JSON.json(parts), "</" => "<\\/"));</script>
                <script>$driver</script>
                </body></html>
                """)
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1440,1400
                    --virtual-time-budget=60000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-ahead-results\">([^<]+)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= 29
                    @test isempty(report["failures"])
                    @info "sent-ahead swap browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
