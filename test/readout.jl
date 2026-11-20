using TestItemRunner

# The readout: a figure with a line or area layer on a continuous x shows, in
# the browser, a rule at the nearest x under the pointer and one box with every
# series' value there (`_readoutPlan` and friends in vendor/aov-runtime.js).
# `config(readout=…)` turns it off or on. With a link group keyed by the x
# field, the readout announces and shows x values instead of dimming lines.
# A link key of dates is compared as Julia writes it (`_aov.link.temporal`):
# before, a plot announced Vega's epoch milliseconds and no table row matched.
# A layer drawn with `visual(...; inspectable=false)` is left out of the
# readout: a `Band` from 0 to a line's value is a wash under the line, and the
# line reads as a line. Before 0.2.58 the wash was read as the line's interval,
# `0.41 (0.00–0.41)`, or as a series of its own (snag `draw-a-line-with-66afe965`).
# A `vconcat` stack whose panels are coloured by one field lists each panel's
# series under that panel's y title. Before 0.2.67 a name shared by panels was
# one row with the last panel's median and the widest panel's interval,
# `S1: −50 (60–240)` (snag `vconcat-readout-7dc3b818`, decision `0lhkthg`).
@testitem "config(readout=…) and temporal link keys lower to _aov metadata" tags=[:interactivity] begin
    using AlgebraOfVega, Dates
    import AlgebraOfGraphics
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
    using AlgebraOfVega, Dates, JSON
    import AlgebraOfGraphics
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
    # A line with a light wash down to zero under it, as Makie draws
    # `band(x, 0, y)` plus `lines(x, y)`; 0.4096 at hour 11.
    hours = (; hour=collect(0.0:23), base=zeros(24), added=[h < 6 ? 0.0 : 40.0 * 0.4^(h - 6) for h in 0:23],
        mm=[6 <= h <= 7 ? 1.5 : 0.0 for h in 0:23])
    wash(title; passive=true) = mapping(:hour => "Hour", :base => title, :added => title) *
        visual(Band; color="#CC79A7", alpha=0.35, inspectable=!passive)
    washed = data(hours) * (wash("Added dose rate") +
        mapping(:hour => "Hour", :added => "Added dose rate") * visual(Lines; color="#CC79A7"))
    banded = data(hours) * (wash("Added dose rate"; passive=false) +
        mapping(:hour => "Hour", :added => "Added dose rate") * visual(Lines; color="#CC79A7"))
    labelled = data(hours) * (wash("nSv/h") +
        mapping(:hour => "Hour", :added => "nSv/h") * visual(Lines; color="#CC79A7", label="Added dose rate"))
    rain = data(hours) * mapping(:hour => "Hour", :mm => "Rain (mm/h)") * visual(BarPlot) *
        config(height=60, readout=true)
    # Three quantities coloured by one scenario field, as Bruno web-sim's time
    # course stacks its outputs, over an uncoloured panel whose rows carry a
    # `scenario` column too (the stack's first colour field must not name it).
    days = collect(0.0:4)
    column(s1, s2, i) = repeat(Float64[s1[i], s2[i]], inner=5)
    quantity(title, s1, s2) = data((; day=repeat(days, 2), scenario=repeat(["S1", "S2"], inner=5),
            q50=column(s1, s2, 1), q025=column(s1, s2, 2), q975=column(s1, s2, 3),
            q25=column(s1, s2, 4), q75=column(s1, s2, 5))) *
        mapping(:day => "Day", :q50 => title; color=:scenario) *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75]) * config(width=360, height=80)
    scenarios = vconcat(
        quantity("Plasma (ng/mL)", (120, 60, 240, 90, 160), (1200, 900, 1500, 1000, 1400)),
        quantity("PBMC (%)", (-49.8, -53.5, -46.5, -51, -48), (-40, -44, -36, -42, -38)),
        quantity("CSF (%)", (-50.2, -53.3, -45.1, -52, -48), (-30, -35, -25, -32, -28)),
        data((; day=days, dose=fill(100.0, 5), scenario=fill("S1", 5))) *
            mapping(:day => "Day", :dose => "Dose (mg)") * visual(Lines) * config(width=360, height=60))

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
                    visual(Scatter) * size * config(link=(; group="days", key=:d)); id="ro-dates"),
                vdraw(washed * size; id="ro-wash"),
                vdraw(labelled * size; id="ro-wash-label"),
                vdraw(banded * size; id="ro-band"),
                vdraw(vconcat(rain, washed * config(height=120)); id="ro-wash-stack"),
                vdraw(scenarios; id="ro-stack-scenarios"),
                vdraw(data(hours) * mapping(:hour, :added) * visual(Lines; inspectable=false) * size;
                    id="ro-passive")]
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
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "readout browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
