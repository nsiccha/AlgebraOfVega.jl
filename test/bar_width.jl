using TestItemRunner

# Makie draws `visual(BarPlot)` over a numeric or time axis `width * (1 - gap)`
# wide in data units: `width` defaults to the smallest step between the bars'
# positions (AlgebraOfGraphics computes it over the layer) and `gap` to 0.2. A
# Vega-Lite bar on a continuous axis is `continuousBandSize`, 5 px, whatever
# the axis, so hourly bars 27 px apart read as separate sticks and a one-hour
# shower as a thin line (snag `draw-hourly-amou-2b963e4e`). AoV places such bars
# by edges the dataflow computes (`_bar_edges!`, src/layer_to_vl.jl).
@testsnippet AoVBarWidthFixtures begin
    using AlgebraOfVega, JSON, Dates, Tables
    import Makie

    # The reporter's figure: 48 hours, twelve of them with steady rain.
    hours = (; hour=collect(0.0:47.0), fall=[6 <= h <= 17 ? 1.5 : 0.0 for h in 0:47])
    rain(rows=hours; vis=visual(BarPlot; color="#CC79A7")) =
        data(rows) * mapping(:hour => "Hour", :fall => "mm per hour") * vis *
        config(height=130, scales=scales(X=(; nice=false), Y=(; zero=true)))

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    bar_units(vl) = [u for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == "bar"]
    kinds(u) = [only(k for k in ("window", "joinaggregate", "calculate", "filter") if haskey(t, k))
        for t in get(u, "transform", Any[])]
    edge_kinds = ["window", "calculate", "joinaggregate", "calculate", "calculate"]
    calc(u, as) = only(t["calculate"] for t in u["transform"] if get(t, "as", nothing) == as)
end

@testitem "Bars on a numeric axis are placed by Makie's edges: the smallest step times 1 - gap" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(rain())
    u = only(bar_units(vl))
    enc = u["encoding"]
    # x is placed by the bar's edges and keeps the column's title and type.
    @test enc["x"]["field"] == "__aov_x0" && enc["x2"] == Dict{String,Any}("field" => "__aov_x1")
    @test enc["x"]["title"] == "Hour" && enc["x"]["type"] == "quantitative"
    @test enc["x"]["scale"]["nice"] === false
    @test enc["y"]["field"] == "fall" && enc["y"]["scale"]["zero"] === true
    # The tooltip names the bar's hour, not its edges.
    @test [t["field"] for t in enc["tooltip"]] == ["hour", "fall"]
    # Vega-Lite reads a bar ranged on x and not on y as horizontal, so the
    # orient is stated; the fixed colour stays.
    @test u["mark"]["type"] == "bar" && u["mark"]["orient"] == "vertical" && u["mark"]["color"] == "#CC79A7"
    @test !haskey(u["mark"], "width")
    # Computed in the dataflow, over all the layer's rows, window first.
    @test kinds(u) == edge_kinds
    win = u["transform"][1]
    @test win["sort"] == [Dict{String,Any}("field" => "hour", "order" => "ascending")]
    @test win["groupby"] == Any[] && u["transform"][3]["groupby"] == Any[]
    @test occursin("(isValid(datum.__aov_bar_step) ? datum.__aov_bar_step : 1) * 0.4", calc(u, "__aov_x0"))
    @test u["_aov_edges"] == Dict{String,Any}("channel" => "x", "field" => "hour", "lo" => "__aov_x0", "hi" => "__aov_x1")
    # The rows are written as given.
    @test Set(keys(first(u["data"]["values"]))) == Set(["hour", "fall"])
    # An unlabelled axis is titled with its column, not the edge field.
    plain = only(bar_units(to_vegalite(data(hours) * mapping(:hour, :fall) * visual(BarPlot))))
    @test plain["encoding"]["x"]["title"] == "hour"
end

@testitem "Bar width and gap as in Makie: data units, a time span on a time axis" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    # An authored width replaces the step; gap is the share left out.
    u = only(bar_units(to_vegalite(rain(; vis=visual(BarPlot; width=0.5, gap=0.1)))))
    @test occursin("datum[\"hour\"] - 0.5 * 0.45", calc(u, "__aov_x0"))
    @test occursin("datum[\"hour\"] + 0.5 * 0.45", calc(u, "__aov_x1"))
    @test !haskey(u["mark"], "width") && !haskey(u["mark"], "gap")
    u = only(bar_units(to_vegalite(rain(; vis=visual(BarPlot; gap=0)))))
    @test occursin(": 1) * 0.5", calc(u, "__aov_x0"))

    # A time axis: positions as epoch milliseconds, a width as a time span.
    t0 = DateTime(2026, 3, 15)
    timed = (; t=[t0 + Hour(h) for h in 0:5], mm=[0.0, 1.0, 2.0, 2.0, 0.5, 0.0])
    bars(vis) = data(timed) * mapping(:t => "Time", :mm) * vis
    u = only(bar_units(to_vegalite(bars(visual(BarPlot)))))
    @test u["encoding"]["x"]["type"] == "temporal" && u["encoding"]["x"]["field"] == "__aov_x0"
    @test occursin("time(datum[\"t\"]) - (isValid(", calc(u, "__aov_x0"))
    @test occursin("time(datum[\"t\"]) - time(datum.__aov_bar_lag)", calc(u, "__aov_bar_gap"))
    u = only(bar_units(to_vegalite(bars(visual(BarPlot; width=Hour(1), gap=0)))))
    @test occursin("time(datum[\"t\"]) - 3.6e6 * 0.5", calc(u, "__aov_x0"))

    # Values Makie could not draw, and a span on a numeric axis, are refused.
    @test_throws ArgumentError to_vegalite(rain(; vis=visual(BarPlot; width=Hour(1))))
    @test_throws ArgumentError to_vegalite(bars(visual(BarPlot; width=Month(1))))
    @test_throws ArgumentError to_vegalite(rain(; vis=visual(BarPlot; width=-1)))
    @test_throws ArgumentError to_vegalite(rain(; vis=visual(BarPlot; width=NaN)))
    @test_throws ArgumentError to_vegalite(rain(; vis=visual(BarPlot; gap=1)))
    @test_throws ArgumentError to_vegalite(rain(; vis=visual(BarPlot; gap=-0.1)))
end

@testitem "Bar edges: horizontal bars, bases, log axes, facets and layers" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    # Horizontal bars stand on y: their edges are y/y2, their length x.
    u = only(bar_units(to_vegalite(data(hours) * mapping(:hour, :fall) * visual(BarPlot; direction=:x))))
    @test u["encoding"]["y"]["field"] == "__aov_y0" && u["encoding"]["y2"]["field"] == "__aov_y1"
    @test u["encoding"]["x"]["field"] == "fall" && !haskey(u["encoding"], "x2")
    @test u["mark"]["orient"] == "horizontal" && u["_aov_edges"]["channel"] == "y"
    @test u["transform"][1]["sort"][1]["field"] == "hour"

    # A base, fixed or mapped, is the value axis's y2 beside the edges.
    based = [(; r..., base=0.5) for r in Tables.rowtable(hours)]
    u = only(bar_units(to_vegalite(data(based) * mapping(:hour, :fall; fillto=:base) * visual(BarPlot))))
    @test u["encoding"]["y2"]["field"] == "base" && u["encoding"]["x2"]["field"] == "__aov_x1"
    u = only(bar_units(to_vegalite(rain(; vis=visual(BarPlot; fillto=0.5)))))
    @test u["encoding"]["y2"] == Dict{String,Any}("datum" => 0.5) && u["encoding"]["x2"]["field"] == "__aov_x1"

    # On a log value axis the bars keep Makie's base after the edges.
    wet = (; hour=collect(0.0:5.0), fall=[0.2, 1.0, 3.0, 10.0, 2.0, 0.5])
    u = only(bar_units(to_vegalite(data(wet) * mapping(:hour, :fall) * visual(BarPlot) *
        config(scales=scales(Y=(; scale=log10))))))
    @test kinds(u) == [edge_kinds; "filter"; "calculate"; "joinaggregate"]
    @test u["encoding"]["y2"] == Dict{String,Any}("field" => "__aov_fillto") && u["encoding"]["x2"]["field"] == "__aov_x1"

    # A unit faceted through its own encoding takes one step over all panels,
    # as AlgebraOfGraphics computes one width per layer.
    two = (; hour=[collect(0.0:23.0); collect(0.0:23.0)], fall=rand(48), day=[fill("Mon", 24); fill("Tue", 24)])
    u = only(bar_units(to_vegalite(data(two) * mapping(:hour, :fall; col=:day) * visual(BarPlot))))
    @test u["encoding"]["column"]["field"] == "day"
    @test u["transform"][1]["groupby"] == Any[] && u["transform"][3]["groupby"] == Any[]

    # Several layers: only the bars are edged; a facet operator's merged
    # dataset filters its source first.
    level = data((; hour=collect(0.0:47.0), cm=collect(100.0:147.0), day=repeat(["Mon", "Tue"], 24))) *
        mapping(:hour, :cm; row=:day) * visual(Lines)
    vl = to_vegalite(data((; hours..., day=repeat(["Mon", "Tue"], 24))) * mapping(:hour, :fall; row=:day) * visual(BarPlot) + level)
    u = only(bar_units(vl))
    @test kinds(u) == ["filter"; edge_kinds]
    line = only(x for x in units(vl) if AlgebraOfVega._mark_type(x["mark"]) == "line")
    @test line["encoding"]["x"]["field"] == "hour" && !haskey(line, "_aov_edges")
end

@testitem "Bars Vega-Lite keeps drawing: categories, dodges, ranges and pixel widths" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    plainbars(rows, m, vis=visual(BarPlot)) = only(bar_units(to_vegalite(data(rows) * m * vis)))
    # A categorical axis keeps its bands; an authored Makie width warns there.
    cats = (; method=["a", "b", "c"], seconds=[1.0, 2.0, 3.0])
    u = plainbars(cats, mapping(:method, :seconds))
    @test u["encoding"]["x"]["field"] == "method" && !haskey(u["encoding"], "x2") && !haskey(u, "transform")
    @test !haskey(u, "_aov_edges")
    @test_logs (:warn, r"categorical") match_mode=:any plainbars(cats, mapping(:method, :seconds), visual(BarPlot; width=0.5))
    # Value first without a direction: Vega-Lite reads horizontal bars from the
    # column types, standing on the categories, and draws them as before.
    u = plainbars(cats, mapping(:seconds, :method))
    @test u["encoding"]["x"]["field"] == "seconds" && !haskey(u, "_aov_edges") && u["mark"] == "bar"
    # Two numeric columns stand on the first, as in AoG.
    u = plainbars(hours, mapping(:hour, :fall))
    @test u["_aov_edges"]["channel"] == "x"
    # A dodge on a continuous axis is left as Vega-Lite draws it.
    dodged = (; hour=[0.0, 0.0, 1.0, 1.0], fall=[1.0, 2.0, 3.0, 4.0], g=["p", "q", "p", "q"])
    u = plainbars(dodged, mapping(:hour, :fall; dodge_x=:g))
    @test u["encoding"]["x"]["field"] == "hour" && !haskey(u, "_aov_edges")
    # A Vega-Lite pixel width stays the mark's, and the bars are not edged.
    u = plainbars(hours, mapping(:hour, :fall), visual(BarPlot; width=Dict("band" => 0.5)))
    @test u["mark"]["width"] == Dict{String,Any}("band" => 0.5) && !haskey(u, "_aov_edges")
    # A pixel width in Vega-Lite's spelling keeps Vega-Lite's drawing.
    u = plainbars(hours, mapping(:hour, :fall), visual(BarPlot; continuousBandSize=8))
    @test u["mark"]["continuousBandSize"] == 8 && !haskey(u, "_aov_edges")
    # Horizontal bars sized in Vega-Lite's `height` keep it.
    u = plainbars(hours, mapping(:hour, :fall), visual(BarPlot; direction=:x, height=6))
    @test u["mark"]["height"] == 6 && !haskey(u, "_aov_edges")
    # Histograms are binned by Vega-Lite and unchanged.
    h = only(bar_units(to_vegalite(data(hours) * mapping(:fall) * histogram())))
    @test !haskey(h, "_aov_edges")
end

@testitem "Bar edges in frames, rows read by address, and the vsave file" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    # A frame's filter runs first, so each frame's bars take that frame's step.
    framed = (; hour=repeat(collect(0.0:23.0), 2), fall=fill(1.0, 48), day=[fill("Mon", 24); fill("Tue", 24)])
    u = only(bar_units(to_vegalite(data(framed) * mapping(:hour, :fall) * visual(BarPlot) * config(frame=:day))))
    @test kinds(u) == ["filter"; edge_kinds]
    # Rows read from an address are edged in the browser like written ones.
    u = only(bar_units(to_vegalite(data(by_url(hours, "/rows.json")) * mapping(:hour, :fall) * visual(BarPlot))))
    @test u["data"]["url"] == "/rows.json" && kinds(u) == edge_kinds && haskey(u, "_aov_edges")

    # The file vsave writes draws the same bars: 0.8 of the hour step wide.
    vlc = something(get(ENV, "AOV_VL_CONVERT", nothing), Sys.which("vl-convert"), "")
    if isempty(vlc) || !isfile(vlc)
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(rain() * config(width=480), joinpath(dir, "rain.svg")), String)
            bars = [parse.(Float64, m.captures) for m in
                eachmatch(r"aria-roledescription=\"bar\"[^>]*d=\"M([-0-9.e]+),[-0-9.e]+h([-0-9.e]+)", svg)]
            @test length(bars) == 48
            starts, widths = first.(bars), last.(bars)
            steps = diff(sort(starts))
            @test all(s -> isapprox(s, steps[1]; rtol=1e-6), steps)
            @test all(w -> isapprox(w, 0.8 * steps[1]; rtol=1e-6), widths)
            @test steps[1] > 9
        end
    end
end

@testitem "The axis picker is off for edged bars, whose edges follow their own column" setup=[AoVBarWidthFixtures] tags=[:translation, :regression] begin
    @test AlgebraOfVega._has_axis_blocker([data(hours) * mapping(:hour, :fall) * visual(BarPlot)])
    cats = (; method=["a", "b"], seconds=[1.0, 2.0])
    @test !AlgebraOfVega._has_axis_blocker([data(cats) * mapping(:method, :seconds) * visual(BarPlot)])
    @test !AlgebraOfVega._has_axis_blocker([data(hours) * mapping(:hour, :fall) * visual(Lines)])
end

@testitem "Bars are drawn Makie's width in the browser and follow the plot width, new rows and the readout" setup=[AoVBarWidthFixtures] tags=[:regression, :browser] begin
    using HTMX, HTMXObjects
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-bar-width-") do dir
            t0 = DateTime(2026, 3, 15)
            timed = (; t=[t0 + Hour(h) for h in 0:5], mm=[0.0, 1.0, 2.0, 2.0, 0.5, 0.0])
            level = data((; hour=collect(0.0:47.0), cm=collect(100.0:147.0))) *
                mapping(:hour => "Hour", :cm => "Level (cm)") * visual(Lines) * config(height=100)
            twin = (; hour=repeat(collect(0.0:5.0), inner=2), fall=fill(1.0, 12), g=repeat(["p", "q"], 6))
            figures = [
                "hours" => (900, rain()),
                "narrow" => (450, rain()),
                "authored" => (900, rain(; vis=visual(BarPlot; width=0.5, gap=0.1))),
                "timed" => (900, data(timed) * mapping(:t => "Time", :mm => "mm") * visual(BarPlot) * config(height=130)),
                "stacked" => (900, vconcat(level, rain())),
                "colours" => (900, data(twin) * mapping(:hour, :fall; color=:g) * visual(BarPlot) * config(height=130)),
                "update" => (900, rain()),
                "readout" => (900, rain() * config(readout=true, link=(; group="hours", key=:hour))),
            ]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "bar_width.js"), String)
            plots = join("<div style='width:$(w)px'>" * html(vdraw(spec; id)) * "</div>" for (id, (w, spec)) in figures)
            # The reporter's figure as captioned on the page, at the reporter's 1600 px viewport.
            plots *= "<div style='width:1500px'>" * html(with_plot_caption(rain(); title="Precipitation (mm per hour)",
                plot_id="washout-rain")) * "</div>"
            update_rows = JSON.json([(; hour=h, fall=1.0) for h in 0.0:0.5:9.5])
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" * plots *
                "<script>window.AOV_UPDATE_ROWS=" * update_rows * "</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,2400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-bar-width-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 630
                @test isempty(report["failures"])
                @info "bar width browser checks" checks=report["checks"] measured=JSON.json(report["measured"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
