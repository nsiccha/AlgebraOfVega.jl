using TestItemRunner

"""
A captioned figure that a swap replaces with one of the same structure under
the same plot id is updated in place: its element, its Vega view and what the
reader set on it stay, only the new rows are swapped in, and the caption,
tables and everything else come from the new fragment.

Snag `same-id-figure-r-3a736927` (reporter Bruno web-sim): every control
change re-GETs a tab whose answer holds the same figure under the same plot id,
a slow read sends the same figure ahead part by part, and the finished answer
replaces the parts. Each of those swaps embedded the figure afresh: a new
view, the reader's Ribbons | Intervals choice, zoom and legend selection
lost, and the full embed paid again, where `update_spec` swaps the rows into
the live view.

The driver swaps with the vendored htmx 2 and HTMXObjects' own
`sent_ahead_script()`: a control's refresh (innerHTML of the live target), the
first part sent ahead (which empties the live target before its figure's
script runs), a second part out of band, the finished answer, an outerHTML
swap, and an `update_spec` script right after the figure in one answer. Each
keeps the view and element and draws the new rows. The controls: an app that
disposes what htmx cleans up, a changed structure and a second figure beside
the first each embed afresh, as before. Red on base: 19 of 114 checks (the
kept view, element and drawing at each of the six swaps but the first).
"""
@testitem "a figure swapped in under the same plot id with the same structure is updated in place" setup=[AoVBrowserServer] tags=[:browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    import HTMX

    doses = [5.0, 10.0, 20.0, 40.0, 60.0]
    quantities = ["AUC", "Maximum", "Time of maximum"]
    # The same rows scaled by `k`: the largest median is 180000k.
    function rows(k)
        r = (; dose=Float64[], scenario=String[], quantity=String[], q50=Float64[], lo=Float64[],
            hi=Float64[], lo50=Float64[], hi50=Float64[])
        for (qi, q) in enumerate(quantities), (si, s) in enumerate(["Daily", "Twice daily"]), d in doses
            m = k * d * 1000 * qi * (si == 1 ? 1.0 : 0.85)
            push!(r.dose, d); push!(r.scenario, s); push!(r.quantity, q); push!(r.q50, m)
            push!(r.lo, 0.2m); push!(r.hi, 3m); push!(r.lo50, 0.7m); push!(r.hi50, 1.5m)
        end
        r
    end
    spec(r; color=true) = data(r) * mapping(:dose => "Dose (mg)", :q50 => "Median";
            (color ? (; color=:scenario => "Scenario") : (;))...,
            layout=:quantity => sorter(quantities) => "") *
        lineribbon(bands=[:lo => :hi, :lo50 => :hi50]) *
        config(scales=scales(X=(; scale=log10, nice=false))) * config(facet=(; linkyaxes=:none))
    html(x) = sprint(show, MIME"text/html"(), x)
    figure(k, title; kw...) = html(with_plot_caption(spec(rows(k); kw...), CaptionSpec(; title); plot_id="dr-plot"))
    scales_k = (; a=1.0, b=1.4, c=0.7, d=1.1, update_b=2.0)
    fixtures = Dict(
        "a" => figure(scales_k.a, "Dose 60 mg"), "b" => figure(scales_k.b, "Dose 80 mg"),
        "c" => figure(scales_k.c, "Dose 40 mg"), "d" => figure(scales_k.d, "Dose 66 mg"),
        "nocolor" => figure(1.0, "No colour"; color=false),
        "update_b" => html(update_spec("dr-plot", spec(rows(scales_k.update_b)))))
    maxima = Dict(string(k) => maximum(rows(v).q50) for (k, v) in pairs(scales_k))
    driver = read(joinpath(@__DIR__, "same_id_swap.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-same-id-") do dir
            HTMXObjects.copy_vendorfiles(joinpath(dir, "htmxo"); packages=(:htmx,), runtime=false)
            head = join(html.(HTMXObjects.vendor_head("htmxo"; packages=(:htmx,)))) *
                   join(html.(vega_head(; source=:vendor, base="/vendor"))) * html(HTMXObjects.sent_ahead_script())
            # 1040 px: an app's content column at a 1440 px window.
            write(joinpath(dir, "page.html"), """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8"><link rel="icon" href="data:,">$head
                <style>body{margin:0} main{width:1040px}</style></head>
                <body><main><div id="result" data-htmxo-live></div></main>
                <pre id="aov-same-id-results"></pre>
                <script>window.AOV_FIXTURES = $(replace(JSON.json(fixtures), "</" => "<\\/"));
                window.AOV_MAX = $(JSON.json(maxima));</script>
                <script>$driver</script>
                </body></html>
                """)
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1440,1400
                    --virtual-time-budget=90000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-same-id-results\">([^<]+)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= 114
                    @test isempty(report["failures"])
                    @info "same-id swap browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
