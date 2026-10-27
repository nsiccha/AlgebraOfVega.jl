using TestItemRunner

# `geoshape(geometry; key, projection)` is AoV's choropleth term: GeoJSON
# polygons coloured by a data column joined on a shared key (snag
# `aov-geoshape-cho-252d8ce7`). The geometry source owns the polygons, the
# layer's table owns the values, and the emitter joins them with a Vega-Lite
# `lookup` transform. Before the term existed, the only routes were a
# hand-written Vega-Lite spec or an undocumented `config(mark="geoshape", …)`
# escape that duplicated the table into the lookup by hand.
@testsnippet AoVGeoshapeFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    effects = (; AGS=["01001", "01002", "01003"], effect=[-0.4, 0.1, 0.7])
    # Counter-clockwise rings, as RFC 7946 winds them (and WFS servers write them).
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0 + 1, 0.0], [x0 + 1, 1.0], [x0, 1.0], [x0, 0.0]]])
    feature_collection(geometry) = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => ags),
            "geometry" => geometry(Float64(i))) for (i, ags) in enumerate(effects.AGS)])
    geojson = feature_collection(square)
    features = geojson["features"]
    # What AoV lowers them to: the same squares wound clockwise, d3-geo's winding,
    # so each district is its square rather than the globe minus it.
    cw_square(x0) = Dict{String,Any}("type" => "Polygon",
        "coordinates" => [reverse(only(square(x0)["coordinates"]))])
    lowered_geojson = feature_collection(cw_square)
    lowered_features = lowered_geojson["features"]
end

@testitem "geoshape: inline GeoJSON joined on the positional key" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(:AGS; color=:effect) * geoshape(geojson))
    @test vl["mark"] == "geoshape"
    @test vl["projection"] == Dict("type" => "mercator")
    # The table drives the layer: each row looks up its feature by AGS. GeoJSON
    # Feature tuples keep their key under `properties`, so the lookup key
    # addresses that path (a bare key matches no feature and paints nothing).
    @test vl["data"] == Dict{String,Any}("values" => AlgebraOfVega.table_to_rows(effects))
    @test vl["transform"] == [Dict{String,Any}("lookup" => "AGS",
        "from" => Dict{String,Any}(
            "data" => Dict{String,Any}("values" => lowered_geojson,
                "format" => Dict{String,Any}("property" => "features")),
            "key" => "properties.AGS"),
        "as" => "__geometry__")]
    enc = vl["encoding"]
    @test enc["shape"] == Dict{String,Any}("field" => "__geometry__", "type" => "geojson")
    @test enc["color"] == Dict{String,Any}("field" => "effect", "type" => "quantitative")
    # A geoshape has no Cartesian axes: the positional key must NOT lower to x.
    @test !haskey(enc, "x") && !haskey(enc, "y")
    @test [t["field"] for t in enc["tooltip"]] == ["AGS", "effect"]
end

# d3-geo, which draws Vega's geoshapes, reads a ring on the sphere: the polygon is
# the region on its right, so a counter-clockwise exterior ring (RFC 7946's
# winding) is the whole globe minus the region. Every such district filled the
# projection in one colour, with no error (snag `a-choropleth-of-89e8fdc1`,
# todo `0jjyv1k`). AoV now draws each polygon as the smaller region its rings
# enclose, as AlgebraOfGraphics/Makie does.
@testitem "geoshape: every winding draws the region its rings enclose" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    using JSON
    lowered(geo) = only(to_vegalite(data(effects) * mapping(:AGS; color=:effect) *
        geoshape(geo))["transform"])["from"]["data"]["values"]
    # Planar signed area in lon/lat: positive is counter-clockwise.
    signed(ring) = sum(ring[i][1] * ring[i + 1][2] - ring[i + 1][1] * ring[i][2] for i in 1:length(ring) - 1) / 2
    polygon(rings...) = Dict{String,Any}("type" => "Polygon", "coordinates" => collect(rings))
    feature(geometry) = Dict{String,Any}("type" => "Feature",
        "properties" => Dict{String,Any}("AGS" => "01001"), "geometry" => geometry)
    collection(geometries...) = Dict{String,Any}("type" => "FeatureCollection",
        "features" => [feature(g) for g in geometries])
    ccw(x0, y0, w) = [[x0, y0], [x0 + w, y0], [x0 + w, y0 + w], [x0, y0 + w], [x0, y0]]
    cw(x0, y0, w) = reverse(ccw(x0, y0, w))

    # RFC 7946 input is rewound to clockwise exterior rings; d3-wound input is kept.
    before = JSON.json(geojson)
    @test lowered(geojson) == lowered_geojson
    @test all(f -> signed(only(f["geometry"]["coordinates"])) < 0, lowered(geojson)["features"])
    @test lowered(lowered_geojson) == lowered_geojson
    @test lowered(features) == lowered_features
    # The caller's geometry is never written to.
    @test JSON.json(geojson) == before

    # Holes are wound the other way round, whatever the input did.
    outer, hole = ccw(0.0, 0.0, 4.0), cw(1.0, 1.0, 1.0)          # RFC 7946
    d3 = polygon(reverse(outer), reverse(hole))
    for given in (polygon(outer, hole), d3, polygon(reverse(outer), hole), polygon(outer, reverse(hole)))
        @test only(lowered(collection(given))["features"])["geometry"] == d3
    end
    # MultiPolygons and GeometryCollections, polygon by polygon.
    multi = Dict{String,Any}("type" => "MultiPolygon", "coordinates" => [[ccw(0.0, 0.0, 1.0)], [cw(2.0, 0.0, 1.0)]])
    @test only(lowered(collection(multi))["features"])["geometry"]["coordinates"] ==
        [[cw(0.0, 0.0, 1.0)], [cw(2.0, 0.0, 1.0)]]
    gc = Dict{String,Any}("type" => "GeometryCollection", "geometries" => [polygon(ccw(0.0, 0.0, 1.0)),
        Dict{String,Any}("type" => "LineString", "coordinates" => ccw(5.0, 0.0, 1.0))])
    got = only(lowered(collection(gc))["features"])["geometry"]["geometries"]
    @test got[1] == polygon(cw(0.0, 0.0, 1.0))
    # A line has no inside: its order is kept.
    @test got[2]["coordinates"] == ccw(5.0, 0.0, 1.0)

    # The test is d3's spherical area, not the plane: a clockwise box across the
    # antimeridian (179°E to 179°W) is a small box on the globe and is kept, though
    # in the plane it reads as a 358°-wide counter-clockwise one.
    fiji = [[179.0, -17.0], [179.0, -16.0], [-179.0, -16.0], [-179.0, -17.0], [179.0, -17.0]]
    @test signed(fiji) > 0
    @test only(lowered(collection(polygon(fiji)))["features"])["geometry"] == polygon(fiji)
    @test only(lowered(collection(polygon(reverse(fiji))))["features"])["geometry"] == polygon(fiji)
    # d3-geo's area of a 1°×1° square on the equator, in steradians: about the
    # cell between two meridians and two parallels (d3's edges are great-circle
    # arcs, so the top edge bulges slightly poleward), and the rest of the globe
    # for the counter-clockwise ring.
    cell = (π / 180) * sin(π / 180)
    @test AlgebraOfVega._ring_area(cw(0.0, 0.0, 1.0)) ≈ cell rtol=1e-4
    @test 4π - AlgebraOfVega._ring_area(ccw(0.0, 0.0, 1.0)) ≈ AlgebraOfVega._ring_area(cw(0.0, 0.0, 1.0)) rtol=1e-9
end

@testitem "geoshape: URL geometry, explicit key and projection" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(color=:effect) *
        geoshape("https://example.invalid/districts.geojson"; key=:AGS, projection=:albers))
    lookup = only(vl["transform"])
    @test lookup["from"]["data"] == Dict{String,Any}("url" => "https://example.invalid/districts.geojson",
        "format" => Dict{String,Any}("type" => "json", "property" => "features"))
    @test lookup["lookup"] == "AGS" && lookup["from"]["key"] == "properties.AGS"
    @test vl["projection"] == Dict("type" => "albers")
end

@testitem "geoshape: feature-vector geometry, pair key, no projection" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(color=:effect) *
        geoshape(features; key=:AGS => :AGS, projection=nothing))
    @test only(vl["transform"])["from"]["data"] == Dict{String,Any}("values" => lowered_features)
    @test !haskey(vl, "projection")
    @test vl["mark"] == "geoshape"
    # The pair's sides land on their own sides of the lookup.
    renamed = (; code=effects.AGS, effect=effects.effect)
    lookup = only(to_vegalite(data(renamed) * mapping(color=:effect) *
        geoshape(features; key=:code => :AGS))["transform"])
    @test lookup["lookup"] == "code" && lookup["from"]["key"] == "properties.AGS"
end

@testitem "geoshape: col/row/layout facet the table rows, one map per level" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape, :facet] begin
    # Two years of effects for the same three districts. The facet must
    # partition the TABLE (whose rows carry `year`), with the lookup inside
    # each panel; faceting the geometry draws a single panel instead.
    years = (; AGS=repeat(effects.AGS, 2), year=repeat(["2020", "2021"], inner=3),
        effect=[-0.4, 0.1, 0.7, 0.5, -0.2, 0.3])
    rows = AlgebraOfVega.table_to_rows(years)
    for (kw, facet) in ((; col=:year) => Dict("column" => "year"),
                        (; row=:year) => Dict("row" => "year"),
                        (; layout=:year) => nothing)
        vl = to_vegalite(data(years) * mapping(:AGS; color=:effect, kw...) * geoshape(geojson))
        @test vl["data"] == Dict{String,Any}("values" => rows)
        if isnothing(facet)
            @test vl["facet"]["field"] == "year"          # wrap form
        else
            ch, field = only(facet)
            @test vl["facet"][ch]["field"] == field
        end
        inner = vl["spec"]
        @test !haskey(inner, "data")
        @test only(inner["transform"])["lookup"] == "AGS"
        @test inner["mark"] == "geoshape"
        @test inner["encoding"]["shape"]["field"] == "__geometry__"
    end
end

@testitem "geoshape: fixed visual stroke reaches the mark" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(:AGS; color=:effect) * geoshape(geojson) *
        visual(; stroke="white", strokeWidth=0.5))
    @test vl["mark"] == Dict{String,Any}("type" => "geoshape",
        "stroke" => "white", "strokeWidth" => 0.5)
end

@testitem "geoshape: missing or ambiguous key and extra positionals fail loud" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    # No positional key and no `key=` — nothing to join on.
    @test_throws ArgumentError to_vegalite(data(effects) * mapping(color=:effect) * geoshape(geojson))
    # A second positional would be an x/y channel a geoshape cannot use.
    @test_throws ArgumentError to_vegalite(data(effects) * mapping(:AGS, :effect) * geoshape(geojson))
    # A data column the table does not have.
    @test_throws ArgumentError to_vegalite(data(effects) * mapping(:NOPE; color=:effect) * geoshape(geojson))
end

@testitem "geoshape: the static path refuses loudly instead of drawing a non-map" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    spec = data(effects) * mapping(:AGS; color=:effect) * geoshape(geojson)
    err = try
        sdraw_file(spec, joinpath(tempdir(), "aov-geoshape-never.png"))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("geoshape", sprint(showerror, err))
    @test occursin("vdraw", sprint(showerror, err))
    # …and names the file export that does draw it.
    @test occursin("vsave", sprint(showerror, err))
end

@testitem "geoshape in the browser: each facet panel draws its own year" tags=[:regression, :browser, :geoshape, :facet] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    ags = ["01001", "01002", "01003"]
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0 + 1, 0.0], [x0 + 1, 1.0], [x0, 1.0], [x0, 0.0]]])
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => square(Float64(i))) for (i, a) in enumerate(ags)])
    single = (; AGS=ags, effect=[-0.4, 0.1, 0.7])
    years = (; AGS=repeat(ags, 2), year=repeat(["2020", "2021"], inner=3),
        effect=[-0.4, 0.1, 0.7, 0.5, -0.2, 0.3])
    faceted(kw) = data(years) * mapping(:AGS; color=:effect, kw...) * geoshape(geojson) *
        config(width=160, height=80)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-geoshape-") do dir
            page = [vdraw(data(single) * mapping(:AGS; color=:effect) * geoshape(geojson) *
                    config(width=160, height=80); id="geo-plain"),
                vdraw(faceted((; col=:year)); id="geo-col"),
                vdraw(faceted((; row=:year)); id="geo-row"),
                vdraw(faceted((; layout=:year)); id="geo-layout")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "geoshape.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-geoshape-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 34
                @test isempty(report["failures"])
                @info "geoshape browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

# RFC 7946 geometry from a URL is fetched by the browser, where AoV's runtime
# rewinds it before Vega reads it (snag `a-choropleth-of-89e8fdc1`). A file://
# page cannot fetch, so the page and its GeoJSON files are served over HTTP.
@testitem "geoshape in the browser: any winding draws each district in place, inline and from a URL" setup=[AoVBrowserServer] tags=[:regression, :browser, :geoshape] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    ags = ["01001", "01002", "01003"]
    ccw(x0, y0, w) = [[x0, y0], [x0 + w, y0], [x0 + w, y0 + w], [x0, y0 + w], [x0, y0]]
    cw(x0, y0, w) = reverse(ccw(x0, y0, w))
    polygon(rings...) = Dict{String,Any}("type" => "Polygon", "coordinates" => collect(rings))
    collection(geometries) = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a), "geometry" => g)
        for (a, g) in zip(ags, geometries)])
    # Three districts side by side, west to east, near Berlin.
    rfc7946 = collection([polygon(ccw(12.0 + i, 52.0, 0.5)) for i in 1:3])
    d3 = collection([polygon(cw(12.0 + i, 52.0, 0.5)) for i in 1:3])
    rows = (; AGS=ags, effect=[-0.4, 0.1, 0.7])
    years = (; AGS=repeat(ags, 2), year=repeat([2020, 2021], inner=3), effect=[-0.4, 0.1, 0.7, 0.5, -0.2, 0.3])
    width = 300
    district_map(geo; table=rows, kw...) = data(table) * mapping(:AGS; color=:effect) * geoshape(geo) *
        config(; width, height=100, kw...)
    plots = ["wind-d3-inline" => district_map(d3), "wind-rfc-inline" => district_map(rfc7946),
        "wind-rfc-url" => district_map("rfc7946.geojson"), "wind-d3-url" => district_map("d3.geojson"),
        "wind-rfc-url-frame" => district_map("rfc7946.geojson"; table=years, frame=:year)]

    # The runtime must rewind exactly as Julia does.
    fiji = [[179.0, -17.0], [179.0, -16.0], [-179.0, -16.0], [-179.0, -17.0], [179.0, -17.0]]
    multi = Dict{String,Any}("type" => "MultiPolygon", "coordinates" => [[ccw(0.0, 0.0, 1.0)], [cw(2.0, 0.0, 1.0)]])
    gc = Dict{String,Any}("type" => "GeometryCollection", "geometries" => [polygon(ccw(0.0, 0.0, 1.0)),
        Dict{String,Any}("type" => "LineString", "coordinates" => ccw(5.0, 0.0, 1.0))])
    cases = [rfc7946, d3, polygon(ccw(0.0, 0.0, 4.0), cw(1.0, 1.0, 1.0)),
        polygon(cw(0.0, 0.0, 4.0), cw(1.0, 1.0, 1.0)), multi, gc, polygon(fiji), polygon(reverse(fiji))]
    fixture = (; width, plots=first.(plots), cases=[(; input=c,
        expected=AlgebraOfVega._rewind_geojson!(AlgebraOfVega._owned_copy(c))) for c in cases])
    expected_checks = 3 * length(plots) + (length(plots) - 2) + 2 * length(cases) + 1

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-geoshape-winding-") do dir
            open(io -> JSON.print(io, rfc7946), joinpath(dir, "rfc7946.geojson"), "w")
            open(io -> JSON.print(io, d3), joinpath(dir, "d3.geojson"), "w")
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "geoshape_winding.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" *
                join(html(vdraw(spec; id)) for (id, spec) in plots) *
                "<script>window.AOV_FIXTURE=" * replace(JSON.json(fixture), "</" => "<\\/") * ";</script>" *
                "<script>" * driver * "</script></body>")
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-geoshape-winding-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] == expected_checks
                    @test isempty(report["failures"])
                    @info "geoshape winding browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end

# A map with marks on it (snag `aov-lonlat-point-6bf6c1c0`, design decision
# `0or46rr`): in a `+` sum holding a geoshape, every other layer's two
# positionals are longitude then latitude, as on an AlgebraOfGraphics
# `GeoAxis`. Before this, `mapping(:lon, :lat)` beside a geoshape lowered to
# Cartesian x/y, so the points spread over the plot's linear range instead of
# standing on the map, and AoV's x/y zoom parameter landed on the geoshape.
@testsnippet AoVGeoshapeMapFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # Clockwise rings (d3's exterior winding), 9–12°E × 54–55°N.
    district(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    kreise = (; AGS=["01001", "01002", "01003"], effect=[-0.4, 0.1, 0.7])
    kreise_geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => district(9.0 + i)) for (i, a) in enumerate(kreise.AGS)])
    sites = (; name=["A", "B", "C", "D"], kind=["x", "y", "x", "y"],
        lon=[10.5, 11.2, 11.8, 12.6], lat=[54.5, 54.2, 54.9, 54.4])
    kreis_map = data(kreise) * mapping(:AGS; color=:effect) * geoshape(kreise_geo)
    points = data(sites) * mapping(:lon, :lat; color=:kind) * visual(Scatter)
end

@testitem "geoshape map: summed layers draw at longitude/latitude through the map's projection" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(kreis_map + points)
    geo, pts = vl["layer"]
    @test geo["mark"] == "geoshape"
    enc = pts["encoding"]
    @test enc["longitude"] == Dict{String,Any}("field" => "lon", "type" => "quantitative")
    @test enc["latitude"] == Dict{String,Any}("field" => "lat", "type" => "quantitative")
    @test !any(haskey(enc, ch) for ch in ("x", "y"))
    @test enc["color"]["field"] == "kind"
    @test [t["field"] for t in enc["tooltip"]] == ["lon", "lat", "kind"]
    # One projection for the whole map; Vega-Lite fits it to both layers.
    @test pts["projection"] == geo["projection"] == Dict{String,Any}("type" => "mercator")
    # A map has no x/y scales to zoom, so no x/y zoom parameter anywhere.
    @test !any(any(p -> get(p, "name", "") == "grid", get(l, "params", Any[])) for l in vl["layer"])

    # Order and projection choice do not matter.
    first_pts, first_geo = to_vegalite(points + kreis_map)["layer"]
    @test haskey(first_pts["encoding"], "longitude") && first_geo["mark"] == "geoshape"
    @test first_pts["projection"] == Dict{String,Any}("type" => "mercator")
    albers = to_vegalite(data(kreise) * mapping(:AGS; color=:effect) *
        geoshape(kreise_geo; projection=:albers) + points)
    @test albers["layer"][2]["projection"] == Dict{String,Any}("type" => "albers")
    # Lines and labels stand on the map too.
    @test haskey(to_vegalite(kreis_map + data(sites) * mapping(:lon, :lat) * visual(Lines))["layer"][2]["encoding"], "longitude")
    labels = to_vegalite(kreis_map + data(sites) * mapping(:lon, :lat; text=:name) *
        visual(AlgebraOfVega.Makie.Text))["layer"][2]
    @test labels["mark"] == "text" && labels["encoding"]["text"]["field"] == "name"

    # Without a geoshape in the figure, positionals keep their x/y meaning.
    plain = to_vegalite(points)["encoding"]
    @test haskey(plain, "x") && haskey(plain, "y") && !haskey(plain, "longitude")
end

@testitem "geoshape map: a faceted map runs each lookup before the facet" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape, :facet] begin
    # Vega-Lite cannot compile a lookup inside a layered facet whose layers
    # share a projection ("Undefined data set name: child_layer_0_lookup_0"),
    # so the lookup runs on the merged rows, into a field of its own.
    years = (; AGS=repeat(kreise.AGS, 2), year=repeat(["2020", "2021"], inner=3),
        effect=[-0.4, 0.1, 0.7, 0.5, -0.2, 0.3])
    site_years = (; name=repeat(sites.name, 2), year=repeat(["2020", "2021"], inner=4),
        lon=repeat(sites.lon, 2), lat=repeat(sites.lat, 2))
    vl = to_vegalite(data(years) * mapping(:AGS; color=:effect, col=:year) * geoshape(kreise_geo) +
        data(site_years) * mapping(:lon, :lat; col=:year) * visual(Scatter))
    @test vl["facet"]["column"]["field"] == "year"
    lookup = only(vl["transform"])
    @test lookup["lookup"] == "AGS" && lookup["from"]["key"] == "properties.AGS"
    @test lookup["as"] == "__geometry_1__"
    geo, pts = vl["spec"]["layer"]
    @test geo["encoding"]["shape"]["field"] == "__geometry_1__"
    @test !any(haskey(t, "lookup") for t in geo["transform"])
    @test haskey(pts["encoding"], "longitude") && pts["projection"] == geo["projection"]
end

@testitem "geoshape map: layers that cannot stand on a map fail loud" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape] begin
    # refused: a map has no x/y axes, so a layer on it is placed by
    # longitude/latitude alone; each of these shapes has no such placement
    # (design decision `0or46rr`).
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(:lon, :lat) * linear())
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(:lon, :lat) * visual(BarPlot))
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(:lon) * visual(Scatter))
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(:lon, :lat, :name) * visual(Scatter))
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(:name, :lat) * visual(Scatter))
    @test_throws ArgumentError to_vegalite(kreis_map + data(sites) * mapping(; x=:lon, y=:lat) * visual(Scatter))
    # refused: one map draws through one projection (design decision `0or46rr`),
    # and these two geoshapes each set a different one.
    @test_throws ArgumentError to_vegalite(
        data(kreise) * mapping(:AGS; color=:effect) * geoshape(kreise_geo; projection=:mercator) +
        data(kreise) * mapping(:AGS) * geoshape(kreise_geo; projection=:albers))
end

# A map with an outline over a fitted choropleth (snag `lower-a-map-with-1d819e87`,
# reporter RegionExplorer): before, a geoshape that left `projection=` out set
# the default `:mercator`, so beside one fitted with
# `projection=(; type="mercator", fit)` the map was refused with
# "must share a projection; got mercator, mercator.", naming neither the `fit`
# that differed nor a fix.
@testitem "geoshape map: a geoshape without projection= draws through the map's" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape] begin
    region = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}(),
        "geometry" => Dict{String,Any}("type" => "MultiPoint", "coordinates" => [[10.1, 54.1], [11.9, 54.9]]))
    fitted = (; type="mercator", fit=region)
    choropleth = data(kreise) * mapping(:AGS; color=:effect) * geoshape(kreise_geo; projection=fitted)
    outline = data((; AGS=["01002"])) * mapping(:AGS) * geoshape(kreise_geo) *
        visual(; fill=nothing, stroke="red")
    want = Dict{String,Any}("type" => "mercator", "fit" => region)
    for spec in (choropleth + outline, outline + choropleth, choropleth + outline + points)
        @test all(l -> l["projection"] == want, to_vegalite(spec)["layer"])
    end
    # Each unit owns its copy, so a later pass that edits one leaves the rest.
    l1, l2 = to_vegalite(choropleth + outline)["layer"]
    @test l1["projection"] !== l2["projection"]
    # Leaving it out emits exactly what repeating it on every geoshape emits.
    @test to_vegalite(choropleth + outline) == to_vegalite(choropleth +
        data((; AGS=["01002"])) * mapping(:AGS) * geoshape(kreise_geo; projection=fitted) *
        visual(; fill=nothing, stroke="red"))
    # A map where no geoshape sets one draws through the default.
    @test all(l -> l["projection"] == Dict{String,Any}("type" => "mercator"),
        to_vegalite(kreis_map + outline + points)["layer"])
    # `nothing` still emits no projection on that geoshape.
    bare = to_vegalite(choropleth + data(kreise) * mapping(:AGS) * geoshape(kreise_geo; projection=nothing))
    @test !haskey(bare["layer"][2], "projection")
end

@testitem "geoshape map: geoshapes that set different projections name what differs" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape] begin
    region = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}(),
        "geometry" => Dict{String,Any}("type" => "MultiPoint", "coordinates" => [[10.1, 54.1], [11.9, 54.9]]))
    fitted = data(kreise) * mapping(:AGS; color=:effect) *
        geoshape(kreise_geo; projection=(; type="mercator", fit=region))
    outline(projection) = data((; AGS=["01002"])) * mapping(:AGS) * geoshape(kreise_geo; projection)
    message(spec) = try
        to_vegalite(spec)
        ""
    catch err
        err isa ArgumentError ? sprint(showerror, err) : rethrow()
    end
    # refused: one map draws through one projection (design decision `0or46rr`).
    m = message(fitted + points + outline(:mercator))
    @test occursin("differ in `fit`:", m)
    @test occursin("layer 1 of the sum: projection = {type: \"mercator\", fit: a GeoJSON Feature}", m)
    @test occursin("layer 3 of the sum: projection = {type: \"mercator\"}", m)
    @test occursin("leave it out on the others", m)
    # The GeoJSON is named, not printed.
    @test !occursin("coordinates", m)
    m = message(outline(:albers) + fitted)
    @test occursin("differ in `type` and `fit`:", m)
    @test occursin("layer 1 of the sum: projection = {type: \"albers\"}", m)
    m = message(outline((; type="mercator", center=[10, 54])) + outline(:mercator))
    @test occursin("projection = {type: \"mercator\", center: [10,54]}", m)
end

@testitem "geoshape map in the browser: points stand inside their districts" tags=[:regression, :browser, :geoshape, :facet] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    district(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    ags = ["01001", "01002", "01003"]
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => district(9.0 + i)) for (i, a) in enumerate(ags)])
    # Each site carries the AGS of the district it stands in.
    sites = (; name=["A", "B", "C", "D"], AGS=["01001", "01002", "01002", "01003"],
        lon=[10.5, 11.2, 11.8, 12.6], lat=[54.5, 54.2, 54.9, 54.4])
    years = (; AGS=repeat(ags, 2), year=repeat(["2020", "2021"], inner=3),
        effect=[-0.4, 0.1, 0.7, 0.5, -0.2, 0.3])
    site_years = merge(map(c -> repeat(c, 2), sites), (; year=repeat(["2020", "2021"], inner=4)))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-geoshape-points-") do dir
            page = [vdraw(data((; AGS=ags, effect=[-0.4, 0.1, 0.7])) * mapping(:AGS; color=:effect) *
                    geoshape(geojson) + data(sites) * mapping(:lon, :lat; color=:name) * visual(Scatter) *
                    config(width=300, height=120); id="geo-points"),
                vdraw(data(years) * mapping(:AGS; color=:effect, col=:year) * geoshape(geojson) +
                    data(site_years) * mapping(:lon, :lat; col=:year) * visual(Scatter) *
                    config(width=200, height=80); id="geo-points-col")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "geoshape_points.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-geoshape-points-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 20
                @test isempty(report["failures"])
                @info "geoshape map browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
