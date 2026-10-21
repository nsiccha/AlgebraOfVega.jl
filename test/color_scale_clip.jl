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
                    config(width=300, height=80, scales=colours); id="clip-points")]
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
                @test report["checks"] >= 12
                @test isempty(report["failures"])
                @info "colour clipping browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
