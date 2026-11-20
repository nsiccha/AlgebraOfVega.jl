using TestItemRunner

"""
A figure whose axis lists its tick values, swapped in under the same plot id
with other rows and another tick list, is updated in place like a figure
whose rows alone change: its view and element stay, the new rows are drawn,
and the axis shows the new ticks, every one of them.

Snag `same-id-figure-w-ca30c584` (reporter Bruno web-sim): the Dose–response
figure lists the doses it draws plus the dose its dashed marker shows as the
x axis's tick values (Vega-Lite's own log ticks name doses nobody simulated).
Moving the marked dose to one off the ladder adds a tick, and that one change
made the swap structural: the figure embedded afresh, the reader's zoom was
reset and the change paid an embed instead of a data swap. Rows-only swaps
of the same figure were kept.

The driver swaps with the vendored htmx 2: Bruno's figure shape (a wrapped
`layout=` facet over three quantities, a log x without nice rounding, bands
coloured by scenario, a dashed `VLines` marker, ticks = doses ∪ marker) with
the reader's Ribbons | Intervals choice made; the marker moving off the
ladder (a fifth tick) and back; an `update_spec` refresh; a re-embed after
those (the new ticks stay); a temporal axis listing hours; and a wrapped
facet with a per-panel Y scale type (one view per panel). The control: a
changed axis title still embeds afresh, and a swap whose ticks did not change
was kept before too. Red on base: 10 of 71 checks (the kept view and element
at each tick-changing swap, the kept view at the `update_spec`, and the
reader's drawing, which the fresh embed reset to the starting one).
"""
@testitem "a same-id swap or update_spec whose listed axis tick values follow the rows is kept in place" setup=[AoVBrowserServer] tags=[:browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON, Dates
    import HTMX

    ladder = [10.0, 20.0, 40.0, 60.0]
    # A ladder with other gaps: the interval drawing's dodge step changes.
    other_ladder = [10.0, 20.0, 40.0, 80.0, 160.0]
    quantities = ["AUC", "Maximum", "Time of maximum"]
    function rows(doses=ladder)
        r = (; dose=Float64[], scenario=String[], quantity=String[], q50=Float64[], lo=Float64[],
            hi=Float64[], lo50=Float64[], hi50=Float64[])
        for (qi, q) in enumerate(quantities), (si, s) in enumerate(["Daily", "Twice daily"]), d in doses
            m = d * 1000 * qi * (si == 1 ? 1.0 : 0.85)
            push!(r.dose, d); push!(r.scenario, s); push!(r.quantity, q); push!(r.q50, m)
            push!(r.lo, 0.2m); push!(r.hi, 3m); push!(r.lo50, 0.7m); push!(r.hi50, 1.5m)
        end
        r
    end
    # web-sim's `dose_figure`, reduced: the ticks are the doses drawn plus the marked dose.
    function dose_spec(marker; doses=ladder, xtitle="Dose (mg)", log_y=false)
        r = rows(doses)
        ticks = sort!(unique!(vcat(r.dose, marker)))
        marks = (; dose=fill(marker, length(quantities)), quantity=quantities)
        facet = (; layout=:quantity => sorter(quantities) => "")
        (data(r) * mapping(:dose => xtitle, :q50 => "Median"; color=:scenario => "Scenario", facet...) *
            lineribbon(bands=[:lo => :hi, :lo50 => :hi50]) +
         data(marks) * mapping(:dose => xtitle; facet...) * visual(VLines; linestyle=:dash, color=:ink)) *
            config(scales=scales(; X=(; scale=log10, nice=false),
                (log_y ? (; Y=(; scale=Dict("AUC" => log10))) : (;))...)) *
            config(encoding=(; x=(; axis=(; values=ticks)))) * config(facet=(; linkyaxes=:none))
    end
    hours(hs) = [DateTime(2026, 3, 15, h) for h in hs]
    function time_spec(ticks)
        t = hours(0:3:24)
        data((; t, level=[100.0 + 3i for i in eachindex(t)])) * mapping(:t => "Time", :level => "Level (cm)") *
            visual(Lines) * config(encoding=(; x=(; axis=(; values=hours(ticks)))))
    end
    html(x) = sprint(show, MIME"text/html"(), x)
    figure(spec, id, title) = html(with_plot_caption(spec, CaptionSpec(; title); plot_id=id))
    fixtures = Dict(
        "a" => figure(dose_spec(60.0), "dr-plot", "Dose 60 mg"),
        "b" => figure(dose_spec(85.0), "dr-plot", "Dose 85 mg"),
        "b_again" => figure(dose_spec(85.0), "dr-plot", "Dose 85 mg again"),
        "back" => figure(dose_spec(40.0), "dr-plot", "Dose 40 mg"),
        "update_c" => html(update_spec("dr-plot", dose_spec(30.0))),
        "ladder" => figure(dose_spec(30.0; doses=other_ladder), "dr-plot", "Other ladder"),
        "title" => figure(dose_spec(30.0; doses=other_ladder, xtitle="Dose (mg/day)"), "dr-plot", "Other title"),
        "time_a" => figure(time_spec([6, 12, 18]), "time-plot", "Hours a"),
        "time_b" => figure(time_spec([3, 9, 15, 21]), "time-plot", "Hours b"),
        "panel_a" => figure(dose_spec(60.0; log_y=true), "panel-plot", "Panels 60 mg"),
        "panel_b" => figure(dose_spec(85.0; log_y=true), "panel-plot", "Panels 85 mg"))
    ticks(marker, l=ladder) = sort!(unique!(vcat(l, marker)))
    expected = Dict("a" => ticks(60.0), "b" => ticks(85.0), "back" => ticks(40.0), "c" => ticks(30.0),
        "ladder" => ticks(30.0, other_ladder),
        "time_a" => string.(hours([6, 12, 18])), "time_b" => string.(hours([3, 9, 15, 21])))
    driver = read(joinpath(@__DIR__, "axis_values_swap.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-axis-values-") do dir
            HTMXObjects.copy_vendorfiles(joinpath(dir, "htmxo"); packages=(:htmx,), runtime=false)
            head = join(html.(HTMXObjects.vendor_head("htmxo"; packages=(:htmx,)))) *
                   join(html.(vega_head(; source=:vendor, base="/vendor")))
            write(joinpath(dir, "page.html"), """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8"><link rel="icon" href="data:,">$head
                <style>body{margin:0} main{width:1040px}</style></head>
                <body><main><div id="result"></div><div id="time"></div><div id="panels"></div>
                <div id="sink" hidden></div></main>
                <pre id="aov-axis-values-results"></pre>
                <script>window.AOV_FIXTURES = $(replace(JSON.json(fixtures), "</" => "<\\/"));
                window.AOV_TICKS = $(JSON.json(expected));</script>
                <script>$driver</script>
                </body></html>
                """)
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1440,1400
                    --virtual-time-budget=90000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-axis-values-results\">([^<]+)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= 71
                    @test isempty(report["failures"])
                    @info "listed tick values swap browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
