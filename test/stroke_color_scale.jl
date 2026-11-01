using TestItemRunner

# `strokecolor=` shares the `Color` scale with `color=`, as in AlgebraOfGraphics, where
# both aesthetics are `AesColor`. Before, `scales(Color=…)` reached the `color` encoding
# only: a choropleth stroked in its own colours got a scale on the fill and Vega-Lite's
# default on the stroke, so the cells took a differently coloured lattice and a second
# legend, and a stroke-only figure lost the scale without a word (snag
# `geoshape-strokec-3ca728d0`).
@testsnippet AoVStrokeScaleFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    cell(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    grid(ks) = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("k" => k),
            "geometry" => cell(9.0 + i)) for (i, k) in enumerate(ks)])
    ks = ["a", "b", "c", "d", "e"]
    cells = (; k=ks, v=[-1.0, 0.5, 1.5, 2.5, 9.0], w=[10.0, 20.0, 30.0, 40.0, 50.0],
               g=["x", "y", "x", "y", "x"])
    viridis = scales(Color=(; colormap=:viridis, colorrange=(0.0, 3.0)))
    seamless(sc; tbl=cells) = data(tbl) * mapping(:k; color=:v => "W", strokecolor=:v => "W") *
        geoshape(grid(tbl.k)) * visual(; strokeWidth=0.7) * config(width=300, height=80, scales=sc)
    points = (; x=[1.0, 2.0, 3.0], y=[1.0, 2.0, 3.0], g=["x", "y", "x"], v=[0.5, 1.5, 2.5])
end

@testitem "a Color scale reaches a mapped stroke" setup=[AoVStrokeScaleFixtures] tags=[:regression, :translation, :geoshape] begin
    resolved = Dict{String,Any}("scheme" => "viridis", "domain" => [0.0, 3.0], "clamp" => true)

    # The reported figure, inline and in the positional form.
    for vl in (to_vegalite(seamless(viridis)),
               to_vegalite(data(cells) * mapping(:k; color=:v, strokecolor=:v) * geoshape(grid(ks)), viridis))
        @test vl["encoding"]["color"]["scale"] == resolved
        @test vl["encoding"]["stroke"]["scale"] == resolved
    end

    # A stroke alone, and a stroke on another column: `Color` is the one colour scale.
    alone = data(cells) * mapping(:k; strokecolor=:v) * geoshape(grid(ks)) * config(scales=viridis)
    @test to_vegalite(alone)["encoding"]["stroke"]["scale"] == resolved
    other = data(cells) * mapping(:k; color=:v, strokecolor=:w) * geoshape(grid(ks)) * config(scales=viridis)
    @test to_vegalite(other)["encoding"]["stroke"]["scale"] == resolved

    # Not map-specific: categories and palette, every layer, and each facet's inner spec.
    cat_scale = scales(Color=(; categories=["y", "x"], palette=["red", "blue"]))
    pinned = Dict{String,Any}("domain" => ["y", "x"], "range" => ["red", "blue"])
    stroked = data(points) * mapping(:x, :y; strokecolor=:g)
    @test to_vegalite(stroked * visual(Scatter) * config(scales=cat_scale))["encoding"]["stroke"]["scale"] == pinned
    layered = to_vegalite(stroked * (visual(Scatter) + visual(Lines)) * config(scales=cat_scale))
    @test all(l -> l["encoding"]["stroke"]["scale"] == pinned, layered["layer"])
    faceted = data(merge(cells, (; year=[1, 1, 2, 2, 2]))) *
        mapping(:k; color=:v, strokecolor=:v, col=:year) * geoshape(grid(ks)) * config(scales=viridis)
    inner = to_vegalite(faceted)["spec"]
    @test inner["encoding"]["stroke"]["scale"] == resolved

    # The channel picker's lowering keeps it.
    picked = to_vegalite(seamless(viridis); auto_remap=(; dims=["g" => "G"], pinned=:row))
    enc = haskey(picked, "spec") ? picked["spec"]["encoding"] : picked["encoding"]
    @test enc["stroke"]["scale"] == resolved
end

@testitem "lowclip, highclip and nan_color reach a mapped stroke" setup=[AoVStrokeScaleFixtures] tags=[:regression, :translation, :geoshape] begin
    sc = scales(Color=(; colormap=:viridis, colorrange=(0.0, 3.0), lowclip=:red, highclip="green", nan_color=:grey))
    vl = to_vegalite(seamless(sc))
    @test vl["encoding"]["stroke"]["condition"] == Any[
        Dict{String,Any}("test" => "isValid(datum[\"v\"]) && datum[\"v\"] < 0.0", "value" => "red"),
        Dict{String,Any}("test" => "isValid(datum[\"v\"]) && datum[\"v\"] > 3.0", "value" => "green")]
    invalid = vl["config"]["scale"]["invalid"]
    @test invalid["color"] == invalid["stroke"] == Dict{String,Any}("value" => "grey")

    # Each channel's config comes with a continuous encoding on that channel.
    alone = to_vegalite(data(cells) * mapping(:k; strokecolor=:v) * geoshape(grid(ks)) * config(scales=sc))
    @test collect(keys(alone["config"]["scale"]["invalid"])) == ["stroke"]
    filled = to_vegalite(data(cells) * mapping(:k; color=:v) * geoshape(grid(ks)) * config(scales=sc))
    @test collect(keys(filled["config"]["scale"]["invalid"])) == ["color"]
    nominal = scales(Color=(; colormap=:viridis, nan_color=:grey, palette=["red", "blue"]))
    mixed = to_vegalite(data(cells) * mapping(:k; color=:g, strokecolor=:v) * geoshape(grid(ks)) * config(scales=nominal))
    @test collect(keys(mixed["config"]["scale"]["invalid"])) == ["stroke"]
    @test mixed["encoding"]["color"]["scale"] == Dict{String,Any}("range" => ["red", "blue"])
    @test mixed["encoding"]["stroke"]["scale"] == Dict{String,Any}("scheme" => "viridis")
end

@testitem "a Color scale's kinds count a mapped stroke" setup=[AoVStrokeScaleFixtures] tags=[:regression, :translation] begin
    # refused: AoG rejects `colormap` when every `AesColor` field is categorical (decision `0qhmti5`)
    stroked = data(points) * mapping(:x, :y; strokecolor=:g) * visual(Scatter)
    err = try to_vegalite(stroked * config(scales=scales(Color=(; colormap=:viridis)))); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("`colormap`", sprint(showerror, err))
    @test occursin("`g`", sprint(showerror, err))
    # A numeric stroke is the continuous field `colormap` asks for.
    mixed = data(points) * mapping(:x, :y; color=:g, strokecolor=:v) * visual(Scatter)
    @test to_vegalite(mixed * config(scales=scales(Color=(; colormap=:viridis))))["encoding"]["stroke"]["scale"] ==
        Dict{String,Any}("scheme" => "viridis")
end

@testitem "everything else about a stroke stays as written" setup=[AoVStrokeScaleFixtures] tags=[:regression, :translation, :geoshape] begin
    # No `Color` scale: no scale on either channel.
    plain = data(cells) * mapping(:k; color=:v, strokecolor=:v) * geoshape(grid(ks))
    @test !haskey(to_vegalite(plain)["encoding"]["stroke"], "scale")

    # A fixed border is a mark property, never an encoding.
    fixed = to_vegalite(data(cells) * mapping(:k; color=:v) * geoshape(grid(ks)) *
        visual(; stroke="white", strokeWidth=0.5) * config(scales=viridis))
    @test !haskey(fixed["encoding"], "stroke")
    @test fixed["mark"]["stroke"] == "white"

    # A stroke written by hand, the workaround consumers already use, is left alone.
    hand = Dict("field" => "v", "type" => "quantitative", "legend" => nothing,
                "scale" => Dict("scheme" => "viridis", "domain" => [0.0, 3.0]))
    vl = to_vegalite(data(cells) * mapping(:k; color=:v) * geoshape(grid(ks)) *
        config(encoding=Dict("stroke" => hand)) * config(scales=viridis))
    @test vl["encoding"]["stroke"]["scale"] == hand["scale"]
    @test isnothing(vl["encoding"]["stroke"]["legend"])
end

@testitem "a mapped stroke paints the fill's colours in the browser" setup=[AoVStrokeScaleFixtures] tags=[:regression, :browser, :geoshape] begin
    using HTMX, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    clips = scales(Color=(; colormap=:viridis, colorrange=(0.0, 3.0), lowclip=:red, highclip=:green, nan_color=:grey))
    with_nan = merge(cells, (; v=[-1.0, 0.5, 1.5, NaN, 9.0]))
    cat_scale = scales(Color=(; categories=["y", "x"], palette=["red", "blue"]))
    framed = (; k=repeat(ks[1:3], 2), v=[0.0, 1.0, 2.0, 2.0, 4.0, 6.0], year=[1, 1, 1, 2, 2, 2])
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-stroke-scale-") do dir
            page = [vdraw(seamless(viridis); id="st-same"),
                vdraw(seamless(clips; tbl=with_nan); id="st-clip"),
                vdraw(data(cells) * mapping(:k; strokecolor=:v => "W") * geoshape(grid(ks)) *
                    visual(; fill="white", strokeWidth=2) * config(width=300, height=80, scales=viridis); id="st-alone"),
                vdraw(data(cells) * mapping(:k; color=:v => "W", strokecolor=:w => "Other") * geoshape(grid(ks)) *
                    config(width=300, height=80, scales=viridis); id="st-other"),
                vdraw(data(cells) * mapping(:k; color=:g => "G", strokecolor=:g => "G") * geoshape(grid(ks)) *
                    visual(; strokeWidth=2) * config(width=300, height=80, scales=cat_scale); id="st-cat"),
                vdraw(data(framed) * mapping(:k; color=:v => "W", strokecolor=:v => "W") * geoshape(grid(ks[1:3])) *
                    visual(; strokeWidth=2) *
                    config(width=300, height=80, scales=scales(Color=(; colormap=:viridis)), frame=:year); id="st-frame")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "stroke_color_scale.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-stroke-scale-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 20
                @test isempty(report["failures"])
                @info "mapped stroke browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
