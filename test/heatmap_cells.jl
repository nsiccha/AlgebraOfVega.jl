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
    # Cut at the frame as Makie cuts it, which matters under authored axis limits;
    # stroked in its own colour (the next item).
    @test u["mark"] == Dict{String,Any}("type" => "rect", "clip" => true, "strokeWidth" => 1.5,
        "style" => Any["aov-heatmap", "aov-own-clip"])
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
    @test !haskey(u, "transform") && !haskey(u["encoding"], "x2")
    # Its bands meet as numeric cells do, so it is stroked and cut at the frame too.
    @test u["mark"] == Dict{String,Any}("type" => "rect", "clip" => true, "strokeWidth" => 1.5, "style" => "aov-heatmap")
    @test u["encoding"]["stroke"]["field"] == "temp"
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
    @test hist["mark"] == "rect" && !haskey(hist["encoding"], "stroke")
end

# Vega antialiases each rect's edges on its own, so where two cells meet on a
# fractional pixel the page background showed through: a lattice of 1 px lines
# over every heatmap, light grey on a dark page (snag `draw-a-numeric-h-450a4bc9`).
# Each cell is stroked in its own colour, which covers the seam.
@testitem "Heatmap cells are stroked in their own colour, under one colour bar" setup=[AoVHeatmapFixtures] tags=[:translation, :regression] begin
    paint(e) = Dict(k => get(e, k, nothing) for k in ("field", "type", "title", "condition"))
    # The reporter's figure: a fixed range, row and column facets, station points.
    timed = [(; r..., time=t, panel=p) for t in ("Time 1", "Time 3") for p in ("Field", "Median") for r in grid]
    stations = data([(; east=30.0, north=40.0, time="Time 1", panel="Field")]) *
        mapping(:east, :north; row=:time, col=:panel) * visual(Scatter)
    sc = scales(Color=(; colormap=:blueorange, colorrange=(-2, 2)))
    vl = to_vegalite(data(timed) * mapping(:east, :north, :value; row=:time, col=:panel) * visual(Heatmap) + stations, sc)
    u = only(rect_units(vl))
    color, stroke = u["encoding"]["color"], u["encoding"]["stroke"]
    @test paint(stroke) == paint(color)
    @test u["mark"]["strokeWidth"] == 1.5
    # The same scale, its range spelled so Vega-Lite keeps the fill's colour bar
    # and the stroke draws no legend of its own (`_one_colour_bar!`).
    @test color["scale"] == Dict{String,Any}("scheme" => "blueorange", "domain" => [-2, 2], "clamp" => true)
    @test stroke["scale"] == Dict{String,Any}("scheme" => "blueorange", "domainMin" => -2, "domainMax" => 2, "clamp" => true)
    @test isnothing(stroke["legend"]) && color["legend"] isa Dict
    # A range from the data: the same.
    plain = only(rect_units(to_vegalite(field())))
    @test plain["encoding"]["stroke"]["scale"] == Dict{String,Any}("domain" => Dict{String,Any}("unionWith" => Any[]))
    @test isnothing(plain["encoding"]["stroke"]["legend"])

    # Clipped values and a NaN colour paint the stroke as they paint the fill;
    # without the NaN colour on the stroke Vega-Lite would drop a NaN cell.
    vl = to_vegalite(field(), scales(Color=(; colormap=:viridis, colorrange=(-10, 10), lowclip=:red, nan_color=:grey)))
    u = only(rect_units(vl))
    @test haskey(u["encoding"]["color"], "condition")
    @test u["encoding"]["stroke"]["condition"] == u["encoding"]["color"]["condition"]
    @test vl["config"]["scale"]["invalid"]["stroke"] == vl["config"]["scale"]["invalid"]["color"]
    # A raw colour override is part of what the fill paints.
    raw = only(rect_units(to_vegalite(field() * config(encoding=Dict("color" => Dict("scale" => Dict("scheme" => "magma")))))))
    @test raw["encoding"]["stroke"]["scale"]["scheme"] == "magma"

    # Left as written: a heatmap that strokes itself, a translucent one (the
    # stroke's overlap with the neighbour would show), and a categorical colour
    # (a legend selection dims fill and stroke together).
    for vis in (visual(; strokecolor="white"), visual(; stroke=:ink), visual(; alpha=0.5), visual(; fillOpacity=0.4))
        @test !haskey(only(rect_units(to_vegalite(field() * vis)))["encoding"], "stroke")
    end
    outlined = [(; r..., other=r.east) for r in grid]
    own = only(rect_units(to_vegalite(data(outlined) * mapping(:east, :north, :value; strokecolor=:other) * visual(Heatmap))))
    @test own["encoding"]["stroke"]["field"] == "other" && !haskey(own["mark"], "strokeWidth")
    classes = [(; r..., class=r.value > 0 ? "up" : "down") for r in grid]
    @test !haskey(only(rect_units(to_vegalite(data(classes) * mapping(:east, :north, :class) * visual(Heatmap))))["encoding"], "stroke")
    # An authored width is the stroke's width, and 0 draws none.
    wide = only(rect_units(to_vegalite(field() * visual(; strokewidth=3))))
    @test wide["mark"]["strokeWidth"] == 3 && haskey(wide["encoding"], "stroke")
    @test !haskey(only(rect_units(to_vegalite(field() * visual(; strokeWidth=0))))["encoding"], "stroke")
end

@testitem "Heatmap cells are drawn on Makie's grid in the browser, without seams, and follow update_data" setup=[AoVHeatmapFixtures] tags=[:regression, :browser] begin
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
                # The same plot without its own-colour stroke: the seam control.
                "bare" => field() * visual(; strokeWidth=0) * config(width=300, height=300),
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
                @test report["checks"] >= 120
                @test isempty(report["failures"])
                @info "heatmap cell browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
