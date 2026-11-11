using TestItemRunner

# AoG's heatmap from three columns, `mapping(:x, :y, :z) * visual(Heatmap)`:
# Makie draws one cell per row, coloured by `z`, on the grid of the distinct x
# and y values. AoV dropped the third positional (the encoding had x and y only,
# so no colour, no legend and no value in the tooltip), and a Vega-Lite rect
# placed by a continuous x alone reaches from the axis origin to the value, so
# the cells overlapped into one block of Vega's default blue (snag
# `heatmap-position-0f5b34fc`).
@testsnippet AoVHeatmapFixtures begin
    using AlgebraOfVega, JSON
    import Makie

    grid = [(; east=x, north=y, value=x - y) for y in (0.0, 50.0, 100.0) for x in (0.0, 50.0, 100.0)]
    field(rows=grid) = data(rows) * mapping(:east => "East (km)", :north => "North (km)", :value => "Field value") *
        visual(Heatmap)

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    rect_units(vl) = [u for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == "rect"]
    kinds(u) = [only(k for k in ("window", "joinaggregate", "calculate", "filter") if haskey(t, k))
        for t in get(u, "transform", Any[])]
end

@testitem "Heatmap: the third positional colours the cells, which the dataflow edges as Makie does" setup=[AoVHeatmapFixtures] tags=[:translation, :regression] begin
    u = only(rect_units(to_vegalite(field())))
    enc = u["encoding"]
    # The value is the colour, titled with its label, and in the tooltip.
    @test (enc["color"]["field"], enc["color"]["type"], enc["color"]["title"]) == ("value", "quantitative", "Field value")
    @test [t["field"] for t in enc["tooltip"]] == ["east", "north", "value"]
    # Each axis is placed by the cell's edges and keeps the column's title.
    @test enc["x"]["field"] == "__aov_x0" && enc["x2"] == Dict{String,Any}("field" => "__aov_x1")
    @test enc["y"]["field"] == "__aov_y0" && enc["y2"] == Dict{String,Any}("field" => "__aov_y1")
    @test enc["x"]["title"] == "East (km)" && enc["y"]["title"] == "North (km)"
    @test enc["x"]["type"] == "quantitative"
    # Cut at the frame as Makie cuts it, which matters under authored axis limits.
    @test u["mark"] == Dict{String,Any}("type" => "rect", "clip" => true, "style" => "aov-own-clip")
    @test only(rect_units(to_vegalite(field() * visual(; clip=false))))["mark"]["clip"] === false
    # Computed in the dataflow: x's window, join and two edges, then y's.
    @test kinds(u) == repeat(["window", "joinaggregate", "calculate", "calculate"], 2)
    win = u["transform"][1]
    @test win["sort"] == [Dict{String,Any}("field" => "east", "order" => "ascending")]
    @test win["groupby"] == Any[]
    @test u["transform"][2]["groupby"] == Any["east"]
    # The rows are written as given.
    @test Set(keys(first(u["data"]["values"]))) == Set(["east", "north", "value"])

    # An unlabelled axis is titled with its column, not the edge field.
    plain = only(rect_units(to_vegalite(data(grid) * mapping(:east, :north, :value) * visual(Heatmap))))
    @test plain["encoding"]["x"]["title"] == "east"
end

@testitem "Heatmap cells: facets, categorical axes and figures coloured by config" setup=[AoVHeatmapFixtures] tags=[:translation, :regression] begin
    # A unit faceted through its encoding computes each panel's grid on its own.
    timed = [(; r..., time=t) for t in ("Time 1", "Time 3") for r in grid]
    u = only(rect_units(to_vegalite(data(timed) * mapping(:east, :north, :value; col=:time) * visual(Heatmap))))
    @test u["encoding"]["column"]["field"] == "time"
    @test u["transform"][1]["groupby"] == Any["time"]
    @test u["transform"][2]["groupby"] == Any["time", "east"]

    # The reporter's figure: cells and station points in row/column facets. The
    # merged dataset's source filter runs first, so a grid sees its own rows only.
    stations = data([(; east=30.0, north=40.0, time=t) for t in ("Time 1", "Time 3")]) *
        mapping(:east, :north; row=:time) * visual(Scatter)
    vl = to_vegalite(data(timed) * mapping(:east, :north, :value; row=:time) * visual(Heatmap) + stations)
    @test vl["facet"]["row"]["field"] == "time"
    u = only(rect_units(vl))
    @test kinds(u)[1] == "filter" && kinds(u)[2] == "window"
    @test u["encoding"]["color"]["field"] == "value"
    pts = only(x for x in units(vl) if AlgebraOfVega._mark_type(x["mark"]) == "point")
    @test pts["encoding"]["x"]["field"] == "east"

    # A categorical axis keeps its band scale: the gallery's month × city heatmap.
    temps = (; month=["Jan", "Feb", "Jan", "Feb"], city=["A", "A", "B", "B"], temp=[1.0, 2.0, 3.0, 4.0])
    u = only(rect_units(to_vegalite(data(temps) * mapping(:month, :city; color=:temp) * visual(Heatmap))))
    @test u["encoding"]["x"] == Dict{String,Any}("field" => "month", "type" => "nominal")
    @test !haskey(u, "transform") && !haskey(u["encoding"], "x2") && u["mark"] == "rect"
    # One numeric axis: only that axis is edged.
    mixed = (; t=[1.0, 2.0, 1.0, 2.0], city=["A", "A", "B", "B"], v=[1.0, 2.0, 3.0, 4.0])
    u = only(rect_units(to_vegalite(data(mixed) * mapping(:t, :city, :v) * visual(Heatmap))))
    @test u["encoding"]["x"]["field"] == "__aov_x0" && u["encoding"]["y"]["field"] == "city"
    @test !haskey(u["encoding"], "y2") && kinds(u) == ["window", "joinaggregate", "calculate", "calculate"]
    # A named `color=` (AoV's older spelling) places the cells as well.
    named = only(rect_units(to_vegalite(data(grid) * mapping(:east, :north; color=:value) * visual(Heatmap))))
    @test named["encoding"]["x2"]["field"] == "__aov_x1"

    # A figure whose colour comes from `config(encoding=…)`, the gallery's 2D
    # histogram that bins x and y there, is left as it was.
    cars = (; hp=[100.0, 150.0, 200.0], mpg=[30.0, 25.0, 15.0])
    hist = only(rect_units(to_vegalite(data(cars) * mapping(:hp, :mpg) * visual(Heatmap) * config(encoding=Dict(
        "x" => Dict("bin" => Dict("maxbins" => 15)), "y" => Dict("bin" => Dict("maxbins" => 15)),
        "color" => Dict("aggregate" => "count", "type" => "quantitative"))))))
    @test hist["encoding"]["x"]["field"] == "hp" && !haskey(hist, "transform")
end

@testitem "Heatmap cells are drawn on Makie's grid in the browser, and follow update_data" setup=[AoVHeatmapFixtures] tags=[:regression, :browser] begin
    using HTMX
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-heatmap-cells-") do dir
            # An uneven grid: Makie's edges are the midpoints, and the ends extend
            # by half the neighbouring gap.
            uneven = [(; east=x, north=y, value=x + y) for y in (0.0, 1.0) for x in (0.0, 10.0, 40.0)]
            timed = [(; r..., time=t) for t in ("Time 1", "Time 3") for r in grid]
            stations = data([(; east=30.0, north=40.0, time=t) for t in ("Time 1", "Time 3")]) *
                mapping(:east, :north; col=:time) * visual(Scatter)
            figures = Dict(
                "grid" => field() * config(width=300, height=300),
                "uneven" => data(uneven) * mapping(:east, :north, :value) * visual(Heatmap) * config(width=300, height=100),
                "panels" => (data(timed) * mapping(:east, :north, :value; col=:time) * visual(Heatmap) + stations) *
                    config(width=200, height=200),
                "single" => data([(; east=5.0, north=5.0, value=1.0)]) * mapping(:east, :north, :value) *
                    visual(Heatmap) * config(width=100, height=100),
                "update" => field() * config(width=300, height=300))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "heatmap_cells.js"), String)
            plots = join(html(vdraw(figures[id]; id)) for id in keys(figures))
            update_rows = JSON.json([(; east=x, north=y, value=x * y) for y in (0.0, 20.0) for x in (0.0, 20.0, 40.0)])
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" * plots *
                "<script>window.AOV_UPDATE_ROWS=" * update_rows * "</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,2000
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-heatmap-cells-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "heatmap cell browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
