using TestItemRunner

@testsnippet AoVRibbonAxisSpacing begin
    using AlgebraOfVega, AlgebraOfGraphics
    AoV = AlgebraOfVega
    # The reported figure's exact time grid, two channels sampled at different
    # times, twelve panels, and an observation over each predicted interval.
    times = [4.0, 49 / 12, 4.5, 6.0, 22.0, 46.0, 71.0, 95.0, 143.0, 167.0]
    rows = [(; time=t, panel="Panel $p", channel=i in (2, 3) ? "air" : "blood",
        med=100 / t, lo=70 / t, hi=140 / t, innerlo=85 / t, innerhi=115 / t,
        observed=105 / t) for p in 1:12 for (i, t) in enumerate(times)]
    table = (; (k => [getproperty(r, k) for r in rows] for k in keys(first(rows)))...)
    mapped(y) = data(table) * mapping(:time => "Time (hours)", y; color=:channel, layout=:panel)
    axis_figure = mapped(:med) * lineribbon(bands=[:lo => :hi, :innerlo => :innerhi]) +
        mapped(:observed) * visual(Scatter)
    log_figure = axis_figure * config(width=150, height=120, columns=3,
        scales=scales(X=(; scale=log10), Y=(; scale=log10)))
end

@testitem "uneven ribbon times retain numeric axes, observations and authored ticks" setup=[AoVRibbonAxisSpacing] tags=[:ribbon, :translation, :regression] begin
    for (fig, kind) in ((axis_figure, "linear"), (log_figure, "log"))
        vl = to_vegalite(fig)
        rv = vl["_aov"]["ribbonView"]
        @test rv["view"] == "ribbons"
        alt = rv["alt"]
        @test alt["facet"] == vl["facet"]
        @test alt["_aov"]["dodgeX"]["scale"] == kind
        gap = kind == "log" ? log(times[2]) - log(times[1]) : times[2] - times[1]
        @test alt["_aov"]["dodgeX"]["span"] ≈ 0.7gap
        @test alt["data"]["values"] == vl["data"]["values"]
        AoV._each_encoded(alt) do d, _
            x = get(d["encoding"], "x", nothing)
            isnothing(x) && return
            @test x["type"] == "quantitative"
            @test get(x["scale"], "type", "linear") == kind
            @test !haskey(d["encoding"], "xOffset")
            @test x["field"] == (haskey(d["encoding"], "y2") ||
                get(get(d["encoding"], "y", Dict()), "field", "") == "med" ? "__aov_x" : "time")
        end
    end
    ticks = Dict("values" => [4, 10, 100], "format" => ".2~g", "labelAngle" => 0)
    vl = to_vegalite(log_figure * config(encoding=Dict("x" => Dict("axis" => ticks))))
    alt = vl["_aov"]["ribbonView"]["alt"]
    AoV._each_encoded(alt) do d, _
        x = get(d["encoding"], "x", nothing)
        isnothing(x) || @test all(x["axis"][k] == v for (k, v) in ticks)
    end
end

@testitem "narrow faceted ribbon intervals use readable log ticks in both themes" setup=[AoVRibbonAxisSpacing] tags=[:ribbon, :browser, :regression] begin
    using HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-ribbon-axis-") do dir
            html(x) = sprint(show, MIME"text/html"(), x)
            page = "<!doctype html><meta charset='utf-8'><style>" *
                "body{color:#222;background:#fff}html[data-theme=dark] body{color:#ddd;background:#111}" *
                "</style>" * join(html(n) for n in vega_head(source=:inline)) *
                "<script>const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>embed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" *
                html(vdraw(log_figure; id="ribbon-axis")) *
                "<script>" * read(joinpath(@__DIR__, "ribbon_axis_spacing.js"), String) * "</script>"
            path = joinpath(dir, "test.html")
            write(path, page)
            evidence = get(ENV, "AOV_RIBBON_AXIS_OUTPUT", "")
            isempty(evidence) || write(evidence, page)
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1100
                --virtual-time-budget=30000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-ribbon-axis-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 12
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
