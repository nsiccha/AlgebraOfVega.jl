using TestItemRunner

"""
A figure's authored height is its plot area's, for one mark layer as for
several, and a y title longer than that plot area cannot shrink it.

Snag `draw-a-low-figur-e0c74bcc`: an hourly precipitation chart,
`mapping(:hour => "Hour", :fall => "Precipitation (mm per hour)") *
visual(BarPlot) * config(height = 130)`, drew an empty plot area. A single
view was sized with Vega-Lite's `autosize: "fit"`, where the height is the
whole figure's. The rotated y title, centred on the plot area and longer than
it, overhung it above and below, and Vega took that overhang from the plot
area. Every layout pass (each data change, each container resize) measured the
overhang again around the smaller plot area: 73, then 36, then 0 px. The same
figure with a second layer kept a 130 px plot area, since layered, faceted and
stacked figures, `vsave` and `plot_size` all read the height as the plot
area's. A single view now fits only its width (`"fit-x"`).
"""
@testitem "a low figure keeps its plot area whatever its y title" tags=[:browser, :regression] begin
    using AlgebraOfVega, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]

    rain = (; hour=collect(0.0:47.0), fall=[i == 7 ? 6.0 : 0.0 for i in 1:48])
    later = (; hour=collect(0.0:47.0), fall=[i == 30 ? 4.0 : 0.0 for i in 1:48])
    dose = (; dose=collect(1.0:20.0), auc=collect(1.0:20.0) .^ 1.3)
    long(t) = data(t) * mapping(:hour => "Hour", :fall => "Precipitation (mm per hour)")
    short(t) = data(t) * mapping(:hour => "Hour", :fall => "mm per hour")
    exposure = data(dose) * mapping(:dose => "Dose (mg)", :auc => "Exposure (ng/mL·h)")

    single = long(rain) * visual(BarPlot) * config(height=130)
    # The embedded spec sizes only the width to the container.
    emb = AlgebraOfVega._embed_spec(to_vegalite(single))
    @test emb["width"] == "container"
    @test emb["autosize"] == Dict("type" => "fit-x", "contains" => "padding")
    @test emb["height"] == 130
    # An authored width keeps Vega-Lite's own sizing, as before.
    @test !haskey(AlgebraOfVega._embed_spec(to_vegalite(single * config(width=500))), "autosize")

    # id => (spec, the plot-area height it must keep, the bars it must draw)
    plots = [
        "low-long" => (single, 130, 1),
        "low-short" => (short(rain) * visual(BarPlot) * config(height=130), 130, 1),
        "low-layered" => (long(rain) * (visual(BarPlot) + visual(Scatter)) * config(height=130), 130, 1),
        "low-80" => (exposure * visual(Scatter) * config(height=80), 80, 0),
        "low-update" => (single, 130, 1),
        "low-default" => (exposure * visual(Scatter), nothing, 0),
        "low-default-layered" => (exposure * (visual(Scatter) + visual(Lines)), nothing, 0),
    ]
    fixture = (; plots=[(; id, height) for (id, (_, height, _)) in plots],
        bars=Dict(id => n for (id, (_, _, n)) in plots if n > 0),
        # The reporter's real page: rows replaced in the browser, one layout pass each.
        update=script(update_data("low-update", later)))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-low-figure-") do dir
            column(id, spec) = "<div style='width:900px'>" * html(vdraw(spec; id)) * "</div>"
            page = join(column(id, spec) for (id, (spec, _, _)) in plots)
            runtime = join(html(n) for n in vega_head(source=:inline))
            payload = replace(JSON.json(fixture), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "low_figure_height.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>window.AOV_EMBEDS={};const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>{" *
                "const k=String(el).slice(1);AOV_EMBEDS[k]=(AOV_EMBEDS[k]||0)+1;return embed(el,spec,opts);};</script>" *
                page * "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1300,2400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-low-figure-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "low figure browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
