using TestItemRunner

# Every map pans and zooms by default, as x/y plots do (aov-use §4a/§9; snag
# `geoshape-maps-ge-f95ff077`, reporter RegionExplorer). AoV's automatic pan
# and zoom looked only at quantitative x/y encodings, so a geoshape map, and
# lon/lat marks drawn through its projection, ignored the wheel and the drag.

@testsnippet AoVMapZoomFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    # Clockwise rings: d3-geo reads a counter-clockwise ring as the whole
    # globe minus the square.
    square(k, x0, y0, d) = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("k" => k),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[x0, y0], [x0, y0 + d], [x0 + d, y0 + d], [x0 + d, y0], [x0, y0]]]))
    geo = Dict{String,Any}("type" => "FeatureCollection",
        "features" => [square("c$(i)_$(j)", 9.0 + 0.3i, 53.0 + 0.2j, 0.2) for i in 0:5 for j in 0:5])
    rows = (; k=["c$(i)_$(j)" for i in 0:5 for j in 0:5], v=[Float64(i + j) for i in 0:5 for j in 0:5])
    years = (; k=repeat(rows.k, 2), v=vcat(rows.v, rows.v .+ 1), year=repeat(["2020", "2021"], inner=length(rows.k)))
    towns = (; lon=[9.6, 10.35], lat=[53.5, 53.95], name=["A", "B"])
    regions = data(rows) * mapping(:k; color=:v) * geoshape(geo)
    town_map = regions + data(towns) * mapping(:lon, :lat) * visual(Scatter) +
        data(towns) * mapping(:lon, :lat; text=:name) * visual(AlgebraOfVega.Makie.Text; align=(:left, :bottom))
    facet_map = data(years) * mapping(:k; color=:v, col=:year) * geoshape(geo)
    # Every unit dict carrying a projection.
    function projected(d, out=Any[])
        d isa AbstractDict || return out
        haskey(d, "projection") && push!(out, d)
        for k in ("layer", "spec")
            v = get(d, k, nothing)
            v isa AbstractVector ? foreach(x -> projected(x, out), v) : projected(v, out)
        end
        out
    end
    param_names(vl) = [p["name"] for p in get(vl, "params", Any[])]
end

@testitem "map zoom: a map figure gets its gestures and a zoomable projection" setup=[AoVMapZoomFixtures] tags=[:translation, :geoshape, :interactivity] begin
    ext(w, h) = Dict{String,Any}("expr" => "[[aov_zoom.x, aov_zoom.y], [aov_zoom.x + aov_zoom.k * $w, aov_zoom.y + aov_zoom.k * $h]]")
    for (name, fig, w, h) in (("single", regions, "width", "height"), ("layered", town_map, "width", "height"),
            ("faceted", facet_map, "child_width", "child_height"))
        vl = to_vegalite(fig)
        @test param_names(vl) == ["aov_zoom_drag", "aov_zoom"]
        zoom = vl["params"][2]
        @test zoom["value"] == Dict("k" => 1, "x" => 0, "y" => 0)
        @test [on["events"]["type"] for on in zoom["on"]] == ["wheel", "mousemove"]
        # Touch is the runtime's: a spec handler would cancel one-finger scrolls.
        @test !occursin("touch", JSON.json(vl["params"]))
        units = projected(vl)
        @test length(units) == (name == "layered" ? 3 : 1)
        # Every unit draws through the same zoomed projection, so Vega-Lite
        # merges them into one.
        @test all(u -> u["projection"]["extent"] == ext(w, h), units)
        @test allequal(u["projection"] for u in units)
        # No x/y selection or nearest-point hover on a map.
        @test !any(n -> n in ("grid", "hover_nearest"), param_names(vl))
    end
    # The term's own projection is not written: each lowering gets a fresh one.
    fitted = data(rows) * mapping(:k; color=:v) * geoshape(geo; projection=(; type="mercator", fit=geo["features"][1]))
    @test !haskey(to_vegalite(fitted; interactive=false)["projection"], "extent")
    @test to_vegalite(fitted)["projection"]["fit"] == geo["features"][1]
    @test !haskey(to_vegalite(fitted; interactive=false)["projection"], "extent")
    # Opt-outs: interactive=false, a figure that carries params, a projection
    # the author placed (scale/translate are not fitted), no projection.
    @test !haskey(to_vegalite(regions; interactive=false), "params")
    @test !haskey(to_vegalite(regions; interactive=false)["projection"], "extent")
    own = to_vegalite(regions * config(params=[Dict("name" => "mine", "value" => 1)]))
    @test param_names(own) == ["mine"] && !haskey(own["projection"], "extent")
    placed = to_vegalite(data(rows) * mapping(:k; color=:v) *
        geoshape(geo; projection=(; type="mercator", scale=1000, translate=[0, 0])))
    @test !haskey(placed, "params") && !haskey(placed["projection"], "extent")
    bare = to_vegalite(data(rows) * mapping(:k; color=:v) * geoshape(geo; projection=nothing))
    @test !haskey(bare, "params")
    # An x/y plot keeps its own pan and zoom.
    xy = to_vegalite(data((; a=[1.0, 2.0], b=[3.0, 4.0])) * mapping(:a, :b) * visual(Scatter))
    @test "grid" in [p["name"] for p in xy["params"]] && !("aov_zoom" in param_names(xy))
    # A bare `to_html` map gets the patch that cuts its marks once zoomed, as
    # the runtime does; a still map does not need it.
    @test AlgebraOfVega._uses_pan_zoom(to_vegalite(regions)) && occursin("aov_zoom.k !== 1", to_html(regions))
    @test !AlgebraOfVega._uses_pan_zoom(to_vegalite(regions; interactive=false))
end

@testitem "map zoom in the browser: wheel, drag, pinch, reset, re-embed, clip, facets" setup=[AoVMapZoomFixtures] tags=[:regression, :browser, :geoshape, :interactivity] begin
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-map-zoom-") do dir
            german = JSON.json(Dict("reset_zoom" => "Zoom zurücksetzen"))
            page = [html(vdraw(town_map * config(width=420, height=300); id="mz-map")),
                html(vdraw(facet_map * config(width=220, height=200); id="mz-facet")),
                html(vdraw(regions * visual(; clip=true) * config(width=200, height=150); id="mz-clip")),
                "<div data-aov-texts='$german'>" * html(vdraw(regions * config(width=200, height=150); id="mz-de")) * "</div>",
                html(vdraw(data((; a=[1.0, 2.0], b=[3.0, 4.0])) * mapping(:a, :b) * visual(Scatter) *
                    config(width=200, height=150); id="mz-xy"))]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "map_zoom.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:900px'>" * join(page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-map-zoom-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "map zoom browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
