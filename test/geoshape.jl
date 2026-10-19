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
    # The table drives the layer: each row looks up its feature by AGS. GeoJSON
    # Feature tuples keep their key under `properties`, so the lookup key
    # addresses that path (a bare key matches no feature and paints nothing).
    @test vl["data"] == Dict{String,Any}("values" => AlgebraOfVega.table_to_rows(effects))
    @test vl["transform"] == [Dict{String,Any}("lookup" => "AGS",
        "from" => Dict{String,Any}(
            "data" => Dict{String,Any}("values" => geojson,
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
    @test only(vl["transform"])["from"]["data"] == Dict{String,Any}("values" => features)
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
                @test report["checks"] >= 27
                @test isempty(report["failures"])
                @info "geoshape browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
