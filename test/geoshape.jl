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
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0 + 1, 0.0], [x0 + 1, 1.0], [x0, 1.0], [x0, 0.0]]])
    features = [Dict{String,Any}("type" => "Feature",
        "properties" => Dict{String,Any}("AGS" => ags),
        "geometry" => square(Float64(i))) for (i, ags) in enumerate(effects.AGS)]
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => features)
end

@testitem "geoshape: inline GeoJSON joined on the positional key" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(:AGS; color=:effect) * geoshape(geojson))
    @test vl["mark"] == "geoshape"
    @test vl["projection"] == Dict("type" => "mercator")
    @test vl["data"]["values"] == geojson
    @test vl["data"]["format"] == Dict("property" => "features")
    # The lookup joins the geometry's AGS onto the table's AGS and pulls in
    # exactly the mapped value field. GeoJSON Feature tuples keep their key
    # under `properties`, so the lookup addresses that path (a bare key
    # misses every feature at runtime and the map paints blank).
    @test vl["transform"] == [Dict{String,Any}("lookup" => "properties.AGS",
        "from" => Dict{String,Any}(
            "data" => Dict{String,Any}("values" =>
                AlgebraOfVega.table_to_rows(effects)),
            "key" => "AGS", "fields" => ["effect"]))]
    enc = vl["encoding"]
    @test enc["color"] == Dict{String,Any}("field" => "effect", "type" => "quantitative")
    # A geoshape has no Cartesian axes: the positional key must NOT lower to x.
    @test !haskey(enc, "x") && !haskey(enc, "y")
    @test [t["field"] for t in enc["tooltip"]] == ["properties.AGS", "effect"]
    @test enc["tooltip"][1]["title"] == "AGS"
end

@testitem "geoshape: URL geometry, explicit key and projection" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(color=:effect) *
        geoshape("https://example.invalid/districts.geojson"; key=:AGS, projection=:albers))
    @test vl["data"] == Dict{String,Any}("url" => "https://example.invalid/districts.geojson",
        "format" => Dict{String,Any}("type" => "json", "property" => "features"))
    @test vl["projection"] == Dict("type" => "albers")
    @test vl["transform"][1]["lookup"] == "properties.AGS"
end

@testitem "geoshape: feature-vector geometry, pair key, no projection" setup=[AoVGeoshapeFixtures] tags=[:translation, :geoshape] begin
    vl = to_vegalite(data(effects) * mapping(color=:effect) *
        geoshape(features; key=:AGS => :AGS, projection=nothing))
    @test vl["data"] == Dict{String,Any}("values" => features)
    @test !haskey(vl, "projection")
    @test vl["mark"] == "geoshape"
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
end
