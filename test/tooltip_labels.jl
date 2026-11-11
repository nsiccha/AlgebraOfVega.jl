using TestItemRunner

# A generated tooltip names each mapped column by its mapping label, the name its
# axis, legend or facet header shows. Before AoV 0.2.31 every generated tooltip
# listed raw column names: a heatmap cell of
# `mapping(:east => "East (km)", :north => "North (km)", :value => "Field value")`
# read "east | 55 | north | 5 | value | −0.31" while its axes read "East (km)" and
# "North (km)" and its colour legend "Field value" (snag
# `hover-a-cell-of-a723ea83`). A column mapped on two channels was also listed
# twice (AlgebraOfVega todo `0fw4kuo`).
@testsnippet AoVTooltipLabelFixtures begin
    using AlgebraOfVega, JSON
    import Makie

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    mark_of(u) = AlgebraOfVega._mark_type(u["mark"])
    # Each tooltip row as (column, the name it is shown under or `nothing` for the column's own).
    tips(u) = [(t["field"], get(t, "title", nothing)) for t in u["encoding"]["tooltip"]]
    only_unit(vl, mark) = only(u for u in units(vl) if mark_of(u) == mark)

    # The reporter's figure (BRM research/space_time_fields/figures.jl:13,
    # `field_maps`): cells and station points in row × column facets whose
    # headers are hidden with an empty label.
    times = ["Time 1", "Time 3"]
    panels = ["Generating field", "Posterior median"]
    cells = [(; east=e, north=n, value=round(sin(e / 10) * cos(n / 10); digits=2), time=t, panel=p)
        for t in times for p in panels for n in 5.0:10.0:95.0 for e in 5.0:10.0:95.0]
    stations = [(; east=e, north=n, time=t, panel=p) for t in times for p in panels for (e, n) in ((20.0, 30.0), (70.0, 60.0))]
    facets = (; row=:time => sorter(times) => "", col=:panel => sorter(panels) => "")
    field_maps() = data(cells) * mapping(:east => "East (km)", :north => "North (km)", :value => "Field value"; facets...) *
            visual(Heatmap) +
        data(stations) * mapping(:east => "East (km)", :north => "North (km)"; facets...) * visual(Scatter)

    draws = [(; dose=d, value=Float64(i % 7) + (a == "A" ? 0.0 : 3.0), arm=a)
        for d in ("10 mg", "20 mg") for a in ("A", "B") for i in 1:40]
    summary = [(; t, scen=s, q025=t - 1, q25=t - 0.5, q50=t, q75=t + 0.5, q975=t + 1)
        for t in 1.0:5.0 for s in ("S1", "S2")]
    square(x) = [[[x, 0.0], [x + 1, 0.0], [x + 1, 1.0], [x, 1.0], [x, 0.0]]]
    geo = Dict("type" => "FeatureCollection", "features" => [Dict("type" => "Feature",
        "properties" => Dict("AGS" => k), "geometry" => Dict("type" => "Polygon", "coordinates" => square(x)))
        for (k, x) in (("01", 0.0), ("02", 1.0))])
    effects = (; AGS=["01", "02"], eff=[0.3, -0.2])
end

@testitem "Tooltips name plain marks' columns by their mapping labels" setup=[AoVTooltipLabelFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(field_maps())
    # The reporter's figure: the cells' and the stations' rows read as the axes
    # and the colour legend do. The facet fields, whose headers are hidden with
    # an empty label, keep their column names: a row with no name reads worse.
    @test tips(only_unit(vl, "rect")) ==
        [("east", "East (km)"), ("north", "North (km)"), ("value", "Field value"), ("time", nothing), ("panel", nothing)]
    @test tips(only_unit(vl, "point")) == [("east", "East (km)"), ("north", "North (km)"), ("time", nothing), ("panel", nothing)]
    # A labelled facet header names its row too.
    labelled = to_vegalite(data(cells) * mapping(:east, :north, :value; row=:time => "Time") * visual(Heatmap))
    @test ("time", "Time") in tips(only_unit(labelled, "rect"))

    # An unlabelled mapping, and a label equal to its column, add no title: the
    # tooltip is the one AoV wrote before.
    pts = (; x=[1.0, 2.0], y=[3.0, 4.0], g=["a", "b"])
    plain = to_vegalite(data(pts) * mapping(:x, :y => "y"; color=:g) * visual(Scatter))
    @test plain["encoding"]["tooltip"] == [Dict{String,Any}("field" => "x", "type" => "quantitative"),
        Dict{String,Any}("field" => "y", "type" => "quantitative"), Dict{String,Any}("field" => "g", "type" => "nominal")]

    # One column on two channels is one row (AlgebraOfVega todo `0fw4kuo`).
    twice = to_vegalite(data(pts) * mapping(:x, :y; color=:g => "G", strokecolor=:g => "G") * visual(Scatter))
    @test tips(twice) == [("x", nothing), ("y", nothing), ("g", "G")]

    # Other plain marks and lowerings that build the tooltip from their encoding.
    lines = to_vegalite(data(pts) * mapping(:x => "Dose (mg)", :y => "AUC"; color=:g => "Arm") * visual(Lines))
    @test tips(lines) == [("x", "Dose (mg)"), ("y", "AUC"), ("g", "Arm")]
    ecdf = to_vegalite(data((; v=[1.0, 2.0, 3.0, 2.5], g=["a", "a", "b", "b"])) *
        mapping(:v => "Value"; color=:g => "Group") * visual(ECDFPlot))
    @test ("v", "Value") in tips(only_unit(ecdf, "line")) && ("g", "Group") in tips(only_unit(ecdf, "line"))

    # Marks on a map: longitude and latitude by their labels.
    on_map = to_vegalite(data(effects) * mapping(:AGS) * geoshape(geo) +
        data((; lon=[0.5], lat=[0.5], kind=["probe"])) * mapping(:lon => "Longitude", :lat => "Latitude"; color=:kind => "Kind") *
        visual(Scatter))
    @test tips(only_unit(on_map, "point")) == [("lon", "Longitude"), ("lat", "Latitude"), ("kind", "Kind")]
end

@testitem "Tooltips name analyses' and maps' columns by their mapping labels" setup=[AoVTooltipLabelFixtures] tags=[:translation, :regression] begin
    # Point intervals: the category and the colour read as the axis and legend.
    for (name, a) in (("pointinterval", pointinterval()), ("gradient_interval", gradient_interval()),
                      ("dotinterval", dotinterval()))
        vl = to_vegalite(data(draws) * mapping(:value => "MCFB (%)", y=:dose => "Dose"; color=:arm => "Arm") * a)
        us = [u for u in units(vl) if haskey(get(u, "encoding", Dict()), "tooltip")]
        @test !isempty(us)
        for u in us
            t = tips(u)
            @test ("dose", "Dose") in t && ("arm", "Arm") in t
            @test t[1] == ("__point__", "MCFB (%) (estimate)") || name == "dotinterval"
        end
    end
    vertical = to_vegalite(data(draws) * mapping(:dose => "Dose", :value => "MCFB (%)"; color=:arm => "Arm") *
        pointinterval(orientation=:vertical))
    @test all(u -> ("dose", "Dose") in tips(u) && ("arm", "Arm") in tips(u), units(vertical))
    # The `bands=` form.
    pre = to_vegalite(data(summary) * mapping(:q50 => "Conc", y=:t => "Time (h)"; color=:scen => "Scenario") *
        pointinterval(bands=[:q025 => :q975]))
    @test all(u -> ("t", "Time (h)") in tips(u) && ("scen", "Scenario") in tips(u), units(pre))

    # A coloured ribbon, in both its drawings (§8's Ribbons | Intervals switch).
    rib(intervals) = to_vegalite(data(summary) * mapping(:t => "Time (h)", :q50 => "Conc"; color=:scen => "Scenario") *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75]; intervals))
    ribbons = [u for u in units(rib(false)) if mark_of(u) in ("area", "line")]
    @test !isempty(ribbons)
    @test all(u -> ("t", "Time (h)") in tips(u) && ("scen", "Scenario") in tips(u), ribbons)
    intervals = [u for u in units(rib(true)) if mark_of(u) in ("rule", "point")]
    @test !isempty(intervals)
    @test all(u -> ("t", "Time (h)") in tips(u) && ("scen", "Scenario") in tips(u), intervals)

    # A choropleth: the key by its positional's label, the value by its channel's.
    @test tips(to_vegalite(data(effects) * mapping(:AGS => "District"; color=:eff => "Effect") * geoshape(geo))) ==
        [("AGS", "District"), ("eff", "Effect")]
    # A key named with `key=` has no label; a stroke on the fill's column is one row.
    seamless = to_vegalite(data(effects) * mapping(; color=:eff => "Effect", strokecolor=:eff => "Effect") *
        geoshape(geo; key=:AGS))
    @test tips(seamless) == [("AGS", nothing), ("eff", "Effect")]
end

@testitem "A hovered heatmap cell's tooltip names its rows by the mapping labels in the browser" setup=[AoVTooltipLabelFixtures] tags=[:regression, :browser] begin
    using HTMX
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-tooltip-labels-") do dir
            pts = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "a"], h=["p", "p", "q"])
            figures = Dict(
                "maps" => field_maps() * config(width=230, height=230),
                "pick" => data(pts) * mapping(:x => "Dose (mg)", :y => "AUC"; color=:g => "Arm") * visual(Scatter) *
                    config(width=300, height=200))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "tooltip_labels.js"), String)
            plots = join(html(vdraw(figures[id]; id)) for id in sort!(collect(keys(figures))))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" * plots *
                "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-tooltip-labels-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 8
                @test isempty(report["failures"])
                @info "tooltip label browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
