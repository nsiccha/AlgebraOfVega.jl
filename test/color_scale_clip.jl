using TestItemRunner

# A continuous `scales(Color=(; colormap, colorrange))` paints values outside
# `colorrange` in the colormap's end colours, as AlgebraOfGraphics/Makie do
# (`lowclip`/`highclip` default to them). Before, the Vega-Lite scale had no
# `clamp`, so Vega extrapolated past the domain and out-of-range regions drew
# near-black (`rgb(0, 0, 41)`, `rgb(0, 0, 0)` for blueorange over [-20, 20]),
# while `sdraw` drew the end colours. `scale`, `lowclip`, `highclip` and
# `nan_color` were dropped without a word, and so was any unknown key, including
# `clamp`, which AoG rejects on a colour scale (snag `aov-color-scale-5492bf71`,
# design decision `0zeeod8`).
@testsnippet AoVColorClipFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # Clockwise rings (d3's exterior winding), side by side at 54–55°N.
    district(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    geojson(keys) = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("ags" => a),
            "geometry" => district(9.0 + i)) for (i, a) in enumerate(keys)])
    ags = ["01001", "01002", "01003", "01004", "01005"]
    regions = (; ags, estimate=[-28.0, -20.0, 5.0, 20.0, 66.0])
    choropleth(sc; tbl=regions) = data(tbl) * mapping(:ags; color=:estimate => "% per year") *
        geoshape(geojson(tbl.ags)) * config(width=300, height=80, scales=sc)
    blueorange = scales(Color=(; colormap=:blueorange, colorrange=(-20, 20)))

    # Route segments coloured by a category, drawn over the choropleth.
    segs = (; seg=["s1", "s1", "s2", "s2"], lon=[10.2, 14.8, 10.2, 14.8], lat=[54.6, 54.6, 54.3, 54.3],
              check=["ok", "ok", "manual check", "manual check"])
    routes = data(segs) * mapping(:lon, :lat; group=:seg, color=:check => "Check") * visual(Lines; linewidth=3)
    map_with_routes(sc) = (data(regions) * mapping(:ags; color=:estimate => "% per year") *
        geoshape(geojson(regions.ags)) + routes) * config(width=300, height=80, scales=sc)
end

@testitem "colorrange clips out-of-range colours on the Vega-Lite path" setup=[AoVColorClipFixtures] tags=[:regression, :translation, :geoshape] begin
    color = to_vegalite(choropleth(blueorange))["encoding"]["color"]
    @test color["scale"] == Dict{String,Any}("scheme" => "blueorange", "domain" => [-20, 20], "clamp" => true)
    @test !haskey(color, "condition")

    # Every field-bearing colour encoding of a layered figure, and the
    # positional `scales` form.
    tbl = (; x=[1.0, 2.0, 3.0], v=[-1.0, 0.5, 9.0])
    layered = data(tbl) * mapping(:x, :x; color=:v) * (visual(Scatter) + visual(Lines))
    for vl in (to_vegalite(layered * config(scales=blueorange)), to_vegalite(layered, blueorange))
        @test all(l -> l["encoding"]["color"]["scale"]["clamp"] === true, vl["layer"])
    end

    # A categorical palette is unchanged: no clamp on a nominal scale.
    cat = data((; ags=ags[1:2], g=["a", "b"])) * mapping(:ags; color=:g) * geoshape(geojson(ags[1:2])) *
        config(scales=scales(Color=(; palette=["red", "blue"], categories=["a", "b"])))
    @test to_vegalite(cat)["encoding"]["color"]["scale"] ==
        Dict{String,Any}("domain" => ["a", "b"], "range" => ["red", "blue"])
end

@testitem "Color scale lowclip/highclip/nan_color/scale reach Vega-Lite" setup=[AoVColorClipFixtures] tags=[:regression, :translation, :geoshape] begin
    sc = scales(Color=(; colormap=:blueorange, colorrange=(-20, 20), lowclip=:red, highclip="green", nan_color=:grey))
    vl = to_vegalite(choropleth(sc))
    color = vl["encoding"]["color"]
    @test color["condition"] == Any[
        Dict{String,Any}("test" => "isValid(datum[\"estimate\"]) && datum[\"estimate\"] < -20", "value" => "red"),
        Dict{String,Any}("test" => "isValid(datum[\"estimate\"]) && datum[\"estimate\"] > 20", "value" => "green")]
    @test color["scale"]["clamp"] === true
    @test vl["config"]["scale"]["invalid"]["color"] == Dict{String,Any}("value" => "grey")

    # Without `colorrange` nothing lies outside the data's own range, as in AoG.
    @test !haskey(to_vegalite(choropleth(scales(Color=(; lowclip=:red))))["encoding"]["color"], "condition")

    @test to_vegalite(choropleth(scales(Color=(; scale=log10))))["encoding"]["color"]["scale"] ==
        Dict{String,Any}("type" => "log")
end

@testitem "Color scale keys AlgebraOfGraphics rejects fail loudly" setup=[AoVColorClipFixtures] tags=[:regression, :translation] begin
    # refused: AoG has no colour `clamp`, and `colorrange` already clips (decision `0zeeod8`)
    err = try to_vegalite(choropleth(scales(Color=(; colorrange=(-20, 20), clamp=true)))); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("lowclip", sprint(showerror, err))
    # refused: an unknown key was dropped silently before (decision `0zeeod8`)
    @test_throws ArgumentError to_vegalite(choropleth(scales(Color=(; colormap=:viridis, bogus=1))))
    # AoG's guide keys are valid but not lowered yet: a warning, not silence.
    @test_logs (:warn, r"`label` is not lowered") match_mode=:any to_vegalite(choropleth(scales(Color=(; label="x"))))
end

# A figure that colours one layer by a number and another by a category takes each
# `Color` key on the layer of its kind. Before, every key landed on every colour
# encoding: `colorrange` put a numeric domain on the nominal routes, so they painted
# nothing and their legend listed the bounds, and `categories` put a string domain on
# the numeric choropleth (snag `color-scale-suga-d3529048`, decision `0qhmti5`).
@testitem "Color scale keys reach only the colour encodings of their kind" setup=[AoVColorClipFixtures] tags=[:regression, :translation, :geoshape] begin
    colours(vl) = Dict(l["encoding"]["color"]["field"] => l["encoding"]["color"] for l in vl["layer"])

    c = colours(to_vegalite(map_with_routes(blueorange); interactive=false))
    @test c["estimate"]["scale"] == Dict{String,Any}("scheme" => "blueorange", "domain" => [-20, 20], "clamp" => true)
    @test !haskey(c["check"], "scale")

    both = scales(Color=(; colormap=:blueorange, colorrange=(-20, 20), lowclip=:red, nan_color=:grey,
                           palette=["#1b9e77", "#d95f02"], categories=["ok", "manual check"]))
    vl = to_vegalite(map_with_routes(both); interactive=false)
    c = colours(vl)
    @test c["estimate"]["scale"] == Dict{String,Any}("scheme" => "blueorange", "domain" => [-20, 20], "clamp" => true)
    @test length(c["estimate"]["condition"]) == 1
    @test c["check"]["scale"] == Dict{String,Any}("domain" => ["ok", "manual check"], "range" => ["#1b9e77", "#d95f02"])
    @test !haskey(c["check"], "condition")
    @test vl["config"]["scale"]["invalid"]["color"] == Dict{String,Any}("value" => "grey")

    # Not map-specific; the positional form agrees.
    pts = (; x=[1.0, 2.0], y=[1.0, 2.0], demand=[10.0, 90.0])
    plain = data(pts) * mapping(:x, :y; color=:demand) * visual(Scatter) +
            data(segs) * mapping(:lon, :lat; group=:seg, color=:check) * visual(Lines)
    sc = scales(Color=(; colormap=:viridis, colorrange=(0, 100), categories=["manual check", "ok"]))
    for c in (colours(to_vegalite(plain * config(scales=sc))), colours(to_vegalite(plain, sc)))
        @test c["demand"]["scale"]["domain"] == [0, 100]
        @test c["check"]["scale"] == Dict{String,Any}("domain" => ["manual check", "ok"])
    end

    # Untyped encodings take Vega-Lite's default type.
    @test AlgebraOfVega._color_kind(Dict{String,Any}("field" => "g")) === :categorical
    @test AlgebraOfVega._color_kind(Dict{String,Any}("field" => "v", "aggregate" => "mean")) === :continuous
    @test AlgebraOfVega._color_kind(Dict{String,Any}("field" => "d", "type" => "ordinal")) === :categorical

    # refused: AoG rejects colormap/colorrange on a categorical colour scale (decision `0qhmti5`)
    err = try to_vegalite(routes * config(scales=blueorange)); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("`colormap`, `colorrange`", sprint(showerror, err))
    @test occursin("`check`", sprint(showerror, err))
    @test occursin("palette=:viridis", sprint(showerror, err))
    # refused: AoG rejects palette/categories on a continuous colour scale (decision `0qhmti5`)
    err = try to_vegalite(choropleth(scales(Color=(; palette=["red", "blue"])))); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("attribute `palette` describes", sprint(showerror, err))
    @test occursin("`colormap`", sprint(showerror, err))
    # A named scheme on a categorical colour is AoG's `palette`, and stays a scheme.
    @test colours(to_vegalite(map_with_routes(scales(Color=(; palette=:tableau10)))))["check"]["scale"] ==
        Dict{String,Any}("scheme" => "tableau10")

    # A figure with no colour encoding (a picker state with colour off) is left alone.
    nocolour = data(pts) * mapping(:x, :y) * visual(Scatter) * config(scales=blueorange)
    @test !haskey(to_vegalite(nocolour)["encoding"], "color")
end

@testitem "colour clipping in the browser" setup=[AoVColorClipFixtures] tags=[:regression, :browser, :geoshape] begin
    using HTMX, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    nan_regions = (; ags=ags[1:4], estimate=[-28.0, 5.0, 66.0, NaN])
    colours = scales(Color=(; colormap=:blueorange, colorrange=(-20, 20), lowclip=:red, highclip=:green, nan_color=:grey))
    points = (; id=["a", "b", "c", "d"], x=[1.0, 2.0, 3.0, NaN], v=[-28.0, 66.0, NaN, 5.0])
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-color-clip-") do dir
            page = [vdraw(choropleth(blueorange); id="clip-default"),
                vdraw(choropleth(colours; tbl=nan_regions); id="clip-colours"),
                vdraw(data(points) * mapping(:x, :x; color=:v) * visual(Scatter) *
                    config(width=300, height=80, scales=colours); id="clip-points"),
                vdraw(map_with_routes(blueorange); id="clip-mixed")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "color_scale_clip.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-color-clip-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 16
                @test isempty(report["failures"])
                @info "colour clipping browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
