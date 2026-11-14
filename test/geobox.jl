using TestItemRunner

# `geobox(boxes; key, projection)` draws each table row as the
# longitude/latitude box its key names: a map's grid cells as Vega-Lite `rect`
# marks, where `geoshape` draws one GeoJSON polygon per cell (snag
# `rect-grid-cells-dba5d398`, reporter RegionExplorer, from Bewerbungen's
# 16,100-cell map; design picked on RegionExplorer decision `0pzsovk`). Before
# it, a map figure refused every `rect` layer and nothing lowered to
# `longitude2`/`latitude2`, so a grid could only be drawn as polygons, about
# twice as slow to draw and redraw.
@testsnippet AoVGeoboxFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # A 3 × 2 grid of 0.1° cells, 9.9–10.2°E × 54.0–54.2°N; `c<i><j>` is
    # column i (west to east), row j (south to north).
    grid = [(i, j) for j in 0:1 for i in 0:2]
    boxes = (; cell=["c$(i)$(j)" for (i, j) in grid], west=[9.9 + 0.1i for (i, j) in grid],
        south=[54.0 + 0.1j for (i, j) in grid], east=[10.0 + 0.1i for (i, j) in grid],
        north=[54.1 + 0.1j for (i, j) in grid])
    vals = (; cell=boxes.cell, v=collect(1.0:6.0))
    years = (; cell=repeat(boxes.cell, 2), year=repeat(["2020", "2021"], inner=6), v=[1.0:6.0; 6.0:-1:1.0])
    sites = (; lon=[10.05, 10.15], lat=[54.05, 54.15], name=["A", "B"])
    site_years = (; lon=repeat(sites.lon, 2), lat=repeat(sites.lat, 2), year=repeat(["2020", "2021"], inner=2))
    outline_geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => "a"),
            "geometry" => Dict{String,Any}("type" => "Polygon", "coordinates" =>
                [[[9.9, 54.0], [9.9, 54.2], [10.2, 54.2], [10.2, 54.0], [9.9, 54.0]]]))])
    outline = data((; AGS=["a"])) * mapping(:AGS) * geoshape(outline_geo) * visual(; fill="#ddd")
    cells = data(vals) * mapping(:cell; color=:v => "Wert") * geobox(boxes)
    edges = Dict(ch => Dict{String,Any}("field" => f, "type" => "quantitative") for (ch, f) in
        zip(("longitude", "latitude", "longitude2", "latitude2"), ("__west__", "__south__", "__east__", "__north__")))
    message(f) = try
        f()
        ""
    catch err
        err isa ArgumentError ? sprint(showerror, err) : rethrow()
    end
end

@testitem "geobox: rows look up their box and draw as rects at its corners" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(cells; interactive=false)
    @test vl["data"] == Dict{String,Any}("values" => AlgebraOfVega.table_to_rows(vals))
    # One lookup joins each value row to its key's box, into AoV's own fields,
    # so a value column called `west` would keep its meaning.
    @test vl["transform"] == [Dict{String,Any}("lookup" => "cell",
        "from" => Dict{String,Any}("data" => Dict{String,Any}("values" => AlgebraOfVega.table_to_rows(boxes)),
            "key" => "cell", "fields" => ["west", "south", "east", "north"]),
        "as" => ["__west__", "__south__", "__east__", "__north__"])]
    enc = vl["encoding"]
    # South-west corner to north-east corner; no x/y on a map.
    @test all(enc[ch] == e for (ch, e) in edges)
    @test !haskey(enc, "x") && !haskey(enc, "y") && !haskey(enc, "shape")
    @test enc["color"]["field"] == "v" && enc["color"]["title"] == "Wert"
    # Tooltips: the key, then the mapped values, never the box edges.
    @test [t["field"] for t in enc["tooltip"]] == ["cell", "v"]
    # A rect with the style that tells the runtime's zoom clip it is a map's area.
    @test vl["mark"] == Dict{String,Any}("type" => "rect", "style" => "aov-geobox")
    @test vl["projection"] == Dict{String,Any}("type" => "mercator")
    # A map: its zoom, not an x/y selection.
    @test [p["name"] for p in to_vegalite(cells)["params"]] == ["aov_zoom_drag", "aov_zoom"]

    # The own-colour seam stroke (aov-use §4a) shares the fill's scale and legend.
    seams = to_vegalite(data(vals) * mapping(:cell; color=:v, strokecolor=:v) * geobox(boxes) *
        visual(; strokeWidth=0.7, clip=true) * config(scales=scales(Color=(; colormap=:viridis, colorrange=(0.0, 6.0)))))
    @test seams["encoding"]["stroke"]["field"] == "v" && seams["encoding"]["stroke"]["legend"] === nothing
    @test seams["encoding"]["color"]["scale"] ==
        Dict{String,Any}("scheme" => "viridis", "domain" => [0.0, 6.0], "clamp" => true)
    @test seams["encoding"]["stroke"]["scale"] ==
        Dict{String,Any}("scheme" => "viridis", "domainMin" => 0.0, "domainMax" => 6.0, "clamp" => true)
    @test seams["mark"]["strokeWidth"] == 0.7 && seams["mark"]["type"] == "rect"
    # A fixed colour fills the cells; an authored clip stays the author's.
    fixed = to_vegalite(data(vals) * mapping(:cell) * geobox(boxes) * visual(; color="red", clip=true))["mark"]
    @test fixed["fill"] == "red" && fixed["clip"] === true && "aov-geobox" in vcat(fixed["style"])
end

@testitem "geobox: boxes from a URL, by_url, a pair key and a projection" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape] begin
    # The URL of the box table's JSON rows: loaded once by the browser.
    url = to_vegalite(data(vals) * mapping(:cell; color=:v) * geobox("/geo/boxes.json"))
    @test url["transform"][1]["from"]["data"] == Dict{String,Any}("url" => "/geo/boxes.json",
        "format" => Dict{String,Any}("type" => "json"))
    # `by_url`: read from the address, checked in Julia, and inlined by `vsave`.
    addressed = to_vegalite(data(by_url(vals, "/vals.json")) * mapping(:cell; color=:v) *
        geobox(by_url(boxes, "/boxes.json")))
    @test addressed["data"]["url"] == "/vals.json"
    @test addressed["transform"][1]["from"]["data"]["url"] == "/boxes.json"
    inline = AlgebraOfVega._with_rows_inline(() -> to_vegalite(data(vals) * mapping(:cell; color=:v) *
        geobox(by_url(boxes, "/boxes.json"))))
    @test inline["transform"][1]["from"]["data"]["values"] == AlgebraOfVega.table_to_rows(boxes)
    # `rows_json` writes what the URL serves.
    @test AlgebraOfVega.JSON.parse(rows_json(boxes)) == AlgebraOfVega.table_to_rows(boxes)
    # `key = data_column => box_column`, with no positional.
    paired = to_vegalite(data((; k=vals.cell, v=vals.v)) * mapping(; color=:v) *
        geobox(boxes; key=:k => :cell, projection=:albers); interactive=false)
    @test paired["transform"][1]["lookup"] == "k" && paired["transform"][1]["from"]["key"] == "cell"
    @test [t["field"] for t in paired["encoding"]["tooltip"]] == ["k", "v"]
    @test paired["projection"] == Dict{String,Any}("type" => "albers")
    @test !haskey(to_vegalite(data(vals) * mapping(:cell) * geobox(boxes; projection=nothing)), "projection")
end

@testitem "geobox map: one projection with geoshapes and lon/lat marks" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape] begin
    points = data(sites) * mapping(:lon, :lat; text=:name) * visual(AlgebraOfVega.Makie.Text; inspectable=false)
    # A geobox alone makes a map: summed lon/lat layers stand on it.
    only_cells = to_vegalite(cells + points; interactive=false)["layer"]
    @test only_cells[1]["mark"]["type"] == "rect"
    @test haskey(only_cells[2]["encoding"], "longitude") && !haskey(only_cells[2]["encoding"], "x")
    @test all(l -> l["projection"] == Dict{String,Any}("type" => "mercator"), only_cells)
    # A geoshape that sets the projection sets it for the cells, and the
    # reverse: one fitted projection for the whole map.
    region = outline_geo["features"][1]
    fitted = (; type="mercator", fit=region)
    want = Dict{String,Any}("type" => "mercator", "fit" => region)
    for spec in (data((; AGS=["a"])) * mapping(:AGS) * geoshape(outline_geo; projection=fitted) + cells + points,
            outline + data(vals) * mapping(:cell; color=:v) * geobox(boxes; projection=fitted) + points)
        @test all(l -> l["projection"] == want, to_vegalite(spec; interactive=false)["layer"])
    end
    # Two area layers that set different projections cannot share one map.
    m = message(() -> to_vegalite(data(vals) * mapping(:cell) * geobox(boxes; projection=:albers) +
        data((; AGS=["a"])) * mapping(:AGS) * geoshape(outline_geo; projection=:mercator)))
    @test occursin("differ in `type`", m) && occursin("geoshape/geobox layers", m)
    # Every map unit zooms through the one projection.
    zoomed = to_vegalite(outline + cells + points)
    @test allequal(l["projection"] for l in zoomed["layer"])
    @test haskey(zoomed["layer"][2]["projection"], "extent")
    # The picker keeps x/y off: a map has none.
    @test AlgebraOfVega._has_axis_blocker((cells,))
end

@testitem "geobox map: facets partition the rows, and a layered facet hoists each lookup" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape, :facet] begin
    # A single-layer facet keeps its lookup: Vega-Lite compiles it there.
    single = to_vegalite(data(years) * mapping(:cell; color=:v, col=:year) * geobox(boxes))
    @test single["facet"]["column"]["field"] == "year"
    @test only(single["spec"]["transform"])["as"] == ["__west__", "__south__", "__east__", "__north__"]
    # In a layered facet whose layers share a projection, Vega-Lite 5.23 cannot
    # compile a lookup inside the layer ("Undefined data set name:
    # child_layer_0_lookup_0"), so it runs on the merged rows first, into
    # fields of its own; a second area layer gets the next ones.
    layered = to_vegalite(data(years) * mapping(:cell; color=:v, col=:year) * geobox(boxes) +
        data((; AGS=["a", "a"], year=["2020", "2021"])) * mapping(:AGS; col=:year) * geoshape(outline_geo) +
        data(site_years) * mapping(:lon, :lat; col=:year) * visual(Scatter))
    box_lookup, geo_lookup = layered["transform"]
    @test box_lookup["lookup"] == "cell" && box_lookup["as"] == ["__west_1__", "__south_1__", "__east_1__", "__north_1__"]
    @test geo_lookup["lookup"] == "AGS" && geo_lookup["as"] == "__geometry_2__"
    cell_layer, geo_layer, pts = layered["spec"]["layer"]
    @test [cell_layer["encoding"][ch]["field"] for ch in ("longitude", "latitude", "longitude2", "latitude2")] ==
        box_lookup["as"]
    @test geo_layer["encoding"]["shape"]["field"] == "__geometry_2__"
    @test !any(haskey(t, "lookup") for t in cell_layer["transform"])
    @test haskey(pts["encoding"], "longitude") && pts["projection"] == cell_layer["projection"]
    # A frame filters the rows, which keep their key.
    framed = to_vegalite(data(years) * mapping(:cell; color=:v) * geobox(boxes) * config(frame=:year))
    @test framed["_aov"]["frame"]["values"] == ["2020", "2021"]
end

@testitem "geobox: malformed boxes, keys and channels fail loud" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape] begin
    # refused: GeoJSON is geoshape's input, and the message says so.
    @test occursin("draw GeoJSON polygons with `geoshape`", message(() -> geobox(outline_geo)))
    @test occursin("must be a table", message(() -> geobox(1)))
    @test occursin("URL must not be empty", message(() -> geobox("")))
    @test occursin("data_column => box_column", message(() -> geobox(boxes; key=:a => 1)))
    @test occursin("`projection`", message(() -> geobox(boxes; projection=1)))
    # refused: a box table without its edges, or with text edges, draws nothing.
    m = message(() -> to_vegalite(data(vals) * mapping(:cell; color=:v) * geobox((; cell=boxes.cell, west=boxes.west))))
    @test occursin("no columns \"south\", \"east\", \"north\"", m) && occursin("(columns: cell, west)", m)
    @test occursin("no column \"cell\"", message(() -> to_vegalite(data(vals) * mapping(:cell) *
        geobox((; id=boxes.cell, west=boxes.west, south=boxes.south, east=boxes.east, north=boxes.north)))))
    @test occursin("`south` column must hold numbers",
        message(() -> to_vegalite(data(vals) * mapping(:cell) * geobox(merge(boxes, (; south=string.(boxes.south)))))))
    # refused: Vega joins equal values only, so a numeric key never finds a text one.
    @test occursin("holds numbers in the data table (\"cell\") but text in the box table",
        message(() -> to_vegalite(data((; cell=1:6, v=vals.v)) * mapping(:cell; color=:v) * geobox(boxes))))
    # refused, as on a geoshape: no table, no key, an x/y positional, other channels.
    @test occursin("needs a `data(...)` table", message(() -> to_vegalite(mapping(:cell) * geobox(boxes))))
    @test occursin("name the join key", message(() -> to_vegalite(data(vals) * mapping(; color=:v) * geobox(boxes))))
    @test occursin("at most one positional", message(() -> to_vegalite(data(vals) * mapping(:cell, :v) * geobox(boxes))))
    @test occursin("mapping channel `markersize`",
        message(() -> to_vegalite(data(vals) * mapping(:cell; markersize=:v) * geobox(boxes))))
    @test occursin("no key column \"nope\"", message(() -> to_vegalite(data(vals) * mapping(:cell) * geobox(boxes; key=:nope))))
end

@testitem "geobox: the static path refuses loudly instead of drawing a non-map" setup=[AoVGeoboxFixtures] tags=[:translation, :geoshape] begin
    err = try
        sdraw_file(cells, joinpath(tempdir(), "aov-geobox-never.png"))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    msg = sprint(showerror, err)
    @test occursin("geobox", msg) && occursin("vdraw", msg) && occursin("vsave", msg)
end

@testitem "geobox: vsave writes the cells, from an inline table, a box file and by_url" setup=[AoVGeoboxFixtures] tags=[:static, :geoshape, :vsave] begin
    using JSON
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            cd(dir) do
                write("boxes.json", rows_json(boxes))
                cell_map(b) = (outline + data(vals) * mapping(:cell; color=:v) * geobox(b)) *
                    config(width=300, height=200)
                cells_in(svg) = count("aria-roledescription=\"rect mark\"", read(svg, String))
                vsave(cell_map(boxes), "inline.svg")
                @test cells_in("inline.svg") == length(boxes.cell)
                # vl-convert loads no local file and no address: both are read in.
                vsave(cell_map("boxes.json"), "file.svg")
                @test read("file.svg") == read("inline.svg")
                vsave(cell_map(by_url(boxes, "/nowhere/boxes.json")), "byurl.svg")
                @test read("byurl.svg") == read("inline.svg")
                # A framed figure is written at its start frame.
                vsave(data(years) * mapping(:cell; color=:v) * geobox(boxes) *
                    config(frame=(; field=:year, start=:last)), "frame.svg")
                @test cells_in("frame.svg") == 6
            end
        end
    end
end

@testitem "geobox in the browser: cells in place, from every source, with hover, click, zoom, CSV, facets and frames" setup=[AoVBrowserServer, AoVGeoboxFixtures] tags=[:regression, :browser, :geoshape, :facet] begin
    using HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    seamed = data(vals) * mapping(:cell; color=:v => "Wert", strokecolor=:v => "Wert") * geobox(boxes) *
        visual(; strokeWidth=0.7)
    names = data(sites) * mapping(:lon, :lat; text=:name) * visual(AlgebraOfVega.Makie.Text; inspectable=false)
    plots = [
        # Polygons, cells and lon/lat marks on one map.
        "gb-map" => (outline + seamed + data(sites) * mapping(:lon, :lat) * visual(Scatter) + names) *
            config(width=300, height=200),
        # A map of cells alone, its boxes from a URL.
        "gb-url" => data(vals) * mapping(:cell; color=:v) * geobox("boxes.json") * config(width=300, height=200),
        # Both tables from their addresses.
        "gb-byurl" => data(by_url(vals, "vals.json")) * mapping(:cell; color=:v) *
            geobox(by_url(boxes, "boxes.json")) * config(width=300, height=200),
        "gb-facet" => (data(years) * mapping(:cell; color=:v, col=:year) * geobox(boxes) +
            data(site_years) * mapping(:lon, :lat; col=:year) * visual(Scatter)) * config(width=200, height=140),
        "gb-frame" => data(years) * mapping(:cell; color=:v) * geobox(boxes) *
            config(width=300, height=200, frame=:year),
        # A hover link group keyed on the cell, as a map beside its table.
        "gb-link" => cells * config(width=300, height=200, link=(; group="cells", key=:cell)),
    ]
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-geobox-") do dir
            write(joinpath(dir, "boxes.json"), rows_json(boxes))
            write(joinpath(dir, "vals.json"), rows_json(vals))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "geobox.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:900px'>" * join(html(vdraw(spec; id)) for (id, spec) in plots) *
                "<script>" * driver * "</script></body>")
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                    --virtual-time-budget=30000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-geobox-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= 70
                    @test isempty(report["failures"])
                    @info "geobox browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
