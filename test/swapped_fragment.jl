using TestItemRunner

"""
A spec's `text/html` show (`to_html(spec)`) is a self-contained fragment: the
Vega script tags, then the embed script. HTMXObjects' `SemanticPlot` writes
exactly that, so apps swap it into pages with htmx.

Regression (snag `swapped-figure-w-07a0d2c6`, reporter
`Bruno:brmixr:simulator:websim-ux`): swapped into a page without `vega_head()`,
the first such figure stayed empty. htmx runs a swapped inline script at once
and the swapped `<script src>` tags only once they have downloaded, so the embed
threw `ReferenceError: vegaEmbed is not defined` and nothing on the page said a
figure had failed; later swaps drew, once the scripts had arrived. The embed now
waits for its own script tags, and when one fails to load it says so in the
plot's container and the console, naming `vega_head()`. The swaps use
HTMXObjects' vendored htmx and AoV's vendored Vega, so the item needs no network.
"""
@testitem "a swapped spec fragment draws once its own Vega scripts load" setup=[AoVBrowserServer] tags=[:standalone, :browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    import HTMX

    t = collect(0.0:1.0:12.0)
    rows = (; time=vcat(t, t), q50=vcat(sin.(t), cos.(t)), lo=vcat(sin.(t) .- 0.5, cos.(t) .- 0.5),
        hi=vcat(sin.(t) .+ 0.5, cos.(t) .+ 0.5), output=repeat(["a", "b"], inner=length(t)))
    ribbon = data(rows) * mapping(:time, :q50; row=:output) * lineribbon(bands=[:lo => :hi])
    points = data(rows) * mapping(:time, :q50; color=:output) * visual(Scatter)
    driver = read(joinpath(@__DIR__, "swapped_fragment.js"), String)
    html(x) = sprint(show, MIME"text/html"(), x)

    # The fragment `show` writes is `to_html(spec)`; the item serves the same
    # fragment with the vendored trio instead of the CDN.
    @test html(ribbon) == to_html(ribbon)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-swap-") do dir
            HTMXObjects.copy_vendorfiles(joinpath(dir, "htmxo"); packages=(:htmx,), runtime=false)
            htmx_head = join(html.(HTMXObjects.vendor_head("htmxo"; packages=(:htmx,))))
            write(joinpath(dir, "broken.html"), to_html(points; id="swap-broken", source=:vendor, base="/missing"))
            write(joinpath(dir, "first.html"), to_html(ribbon; id="swap-first", source=:vendor, base="/vendor"))
            write(joinpath(dir, "second.html"), to_html(points; id="swap-second", source=:vendor, base="/vendor"))
            page(mode, body) = """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8">$htmx_head</head>
                <body>$body
                <pre id="aov-swap-results"></pre>
                <script>window.AOV_FIXTURE = $(JSON.json((; mode)));</script>
                <script>$driver</script>
                </body></html>
                """
            # Swapped: no Vega in the page until a fragment brings it.
            write(joinpath(dir, "swap.html"), page("swap", """
                <div id="broken"></div><div id="first"></div><div id="second"></div>"""))
            # Parsed with the page, as a notebook or a saved file shows it.
            write(joinpath(dir, "parsed.html"), page("parsed",
                to_html(points; id="swap-parsed", source=:vendor, base="/vendor")))
            with_page_server(dir) do root
                for (name, min_checks) in (("swap", 12), ("parsed", 3))
                    output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                        --user-data-dir=$(joinpath(dir, "profile-$name")) --window-size=1200,1400
                        --virtual-time-budget=30000 --dump-dom $(root * "/$name.html")`,
                        stderr=joinpath(dir, "chrome-$name.log")), String)
                    result = match(r"<pre id=\"aov-swap-results\">([^<]+)</pre>", output)
                    @test !isnothing(result)
                    isnothing(result) && continue
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= min_checks
                    @test isempty(report["failures"])
                    @info "swapped fragment browser checks" name checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
