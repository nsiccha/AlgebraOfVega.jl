using TestItemRunner

# The readout: a figure with a line or area layer on a continuous x shows, in
# the browser, a rule at the nearest x under the pointer and one box with every
# series' value there (`_readoutPlan` and friends in vendor/aov-runtime.js).
# `config(readout=…)` turns it off or on. With a link group keyed by the x
# field, the readout announces and shows x values instead of dimming lines.
# A link key of dates is compared as Julia writes it (`_aov.link.temporal`):
# before, a plot announced Vega's epoch milliseconds and no table row matched.
@testitem "config(readout=…) and temporal link keys lower to _aov metadata" tags=[:interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, Dates
    rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0])
    lines = data(rows) * mapping(:x, :y) * visual(Lines)
    @test !haskey(get(to_vegalite(lines), "_aov", Dict()), "readout")      # the runtime decides
    @test to_vegalite(lines * config(readout=false))["_aov"]["readout"] === false
    @test to_vegalite(lines * config(readout=true))["_aov"]["readout"] === true
    @test !haskey(to_vegalite(lines * config(readout=false)), "readout")    # no Vega-Lite property
    @test_throws ArgumentError config(readout=:x)
    @test_throws ArgumentError config(readout="yes")

    t = DateTime(2026, 3, 15) .+ Hour.(0:2)
    timed = data((; t, v=[1.0, 2.0, 3.0], k=["a", "b", "c"])) * mapping(:t, :v) * visual(Lines)
    @test to_vegalite(timed * config(link=(; group="hours", key=:t)))["_aov"]["link"] ==
        Dict("group" => "hours", "key" => "t", "temporal" => "datetime")
    dated = data((; d=Date(2026, 3, 1) .+ Day.(0:2), v=[1.0, 2.0, 3.0])) * mapping(:d, :v) * visual(Scatter)
    @test to_vegalite(dated * config(link=(; group="days", key=:d)))["_aov"]["link"]["temporal"] == "date"
    # Other keys carry no `temporal`: the runtime compares their String().
    @test !haskey(to_vegalite(timed * config(link=(; group="items", key=:k)))["_aov"]["link"], "temporal")
end

@testitem "readout box, rule and link group in the browser" tags=[:regression, :browser, :interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, Dates, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    size = config(width=360, height=180)
    t = DateTime(2026, 3, 15) .+ Hour.(0:3)
    bands = (; t=vcat(t, t), scenario=repeat(["A", "B"], inner=4),
        q50=[10.0, 11, 12, 13, 20, 21, 22, 23])
    bands = (; bands..., q025=bands.q50 .- 2, q975=bands.q50 .+ 2, q25=bands.q50 .- 1, q75=bands.q50 .+ 1)
    observed = (; t, level=[15.5, 16.25, 17.0, 17.5])
    series(extra) = (data(bands) * mapping(:t => "Time", :q50 => "Level (cm)"; color=:scenario) *
            lineribbon(bands=[:q025 => :q975, :q25 => :q75]) +
        data(observed) * mapping(:t => "Time", :level => "Level (cm)") *
            (visual(Lines; color=:ink) + visual(Scatter; color=:ink))) * size * extra
    facet_rows = (; x=repeat([1.0, 2, 3, 4], 2), v=[1.0, 2, 3, 4, 10, 20, 30, 40], g=repeat(["p", "q"], inner=4))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-readout-") do dir
            page = [
                vdraw(series(config(link=(; group="hours", key=:t))); id="ro-series"),
                vdraw(data(facet_rows) * mapping(:x, :v; col=:g) * visual(Lines) * size; id="ro-facet"),
                vdraw(series(config(readout=false)); id="ro-off"),
                vdraw(data((; t, mm=[0.0, 0.5, 1.5, 0.25])) * mapping(:t => "Time", :mm => "Rain (mm/h)") *
                    visual(BarPlot) * size * config(readout=true); id="ro-bars"),
                vdraw(data((; d=Date(2026, 3, 1) .+ Day.(0:2), v=[1.0, 2.0, 3.0])) * mapping(:d, :v) *
                    visual(Scatter) * size * config(link=(; group="days", key=:d)); id="ro-dates")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "readout.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1800
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-readout-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 24
                @test isempty(report["failures"])
                @info "readout browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
