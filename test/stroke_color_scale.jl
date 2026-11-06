using TestItemRunner

# `strokecolor=` shares the `Color` scale with `color=`, as in AlgebraOfGraphics, where
# both aesthetics are `AesColor`. Before, `scales(Color=…)` reached the `color` encoding
# only: a choropleth stroked in its own colours got a scale on the fill and Vega-Lite's
# default on the stroke, so the cells took a differently coloured lattice and a second
# legend, and a stroke-only figure lost the scale without a word (snag
# `geoshape-strokec-3ca728d0`). A stroke that paints what the fill paints adds no legend,
# and the two draw the fill's colour bar: Vega draws a legend of two scales as symbols.
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
    # The stroke on the fill's column: the same scale, its fixed range spelled so the two
    # scales keep one colour bar.
    resolved_stroke = Dict{String,Any}("scheme" => "viridis", "domainMin" => 0.0, "domainMax" => 3.0, "clamp" => true)

    # The reported figure, inline and in the positional form.
    for vl in (to_vegalite(seamless(viridis)),
               to_vegalite(data(cells) * mapping(:k; color=:v, strokecolor=:v) * geoshape(grid(ks)), viridis))
        @test vl["encoding"]["color"]["scale"] == resolved
        @test vl["encoding"]["stroke"]["scale"] == resolved_stroke
        @test isnothing(vl["encoding"]["stroke"]["legend"])
        @test !isnothing(get(vl["encoding"]["color"], "legend", Dict()))
    end

    # A stroke alone, and a stroke on another column: `Color` is the one colour scale, and
    # each keeps its legend.
    alone = data(cells) * mapping(:k; strokecolor=:v) * geoshape(grid(ks)) * config(scales=viridis)
    @test to_vegalite(alone)["encoding"]["stroke"]["scale"] == resolved
    @test !isnothing(get(to_vegalite(alone)["encoding"]["stroke"], "legend", Dict()))
    other = data(cells) * mapping(:k; color=:v, strokecolor=:w) * geoshape(grid(ks)) * config(scales=viridis)
    @test to_vegalite(other)["encoding"]["stroke"]["scale"] == resolved
    @test !isnothing(get(to_vegalite(other)["encoding"]["stroke"], "legend", Dict()))

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
    @test inner["encoding"]["stroke"]["scale"] == resolved_stroke

    # A categorical stroke keeps the merged legend: symbols are what its colour draws.
    both_cat = to_vegalite(data(cells) * mapping(:k; color=:g, strokecolor=:g) * geoshape(grid(ks)) * config(scales=cat_scale))
    @test both_cat["encoding"]["stroke"]["scale"] == pinned
    @test !haskey(both_cat["encoding"]["stroke"], "legend")

    # The channel picker's lowering keeps it.
    picked = to_vegalite(seamless(viridis); auto_remap=(; dims=["g" => "G"], pinned=:row))
    enc = haskey(picked, "spec") ? picked["spec"]["encoding"] : picked["encoding"]
    @test enc["stroke"]["scale"] == resolved_stroke
end

@testitem "a stroke on the fill's column draws one colour bar" setup=[AoVStrokeScaleFixtures] tags=[:regression, :translation, :geoshape] begin
    stroke_of(x) = to_vegalite(x)["encoding"]["stroke"]
    plain = data(cells) * mapping(:k; color=:v, strokecolor=:v) * geoshape(grid(ks))

    # A range from the data: the empty union adds no value and only tells the scales apart.
    union_scale = Dict{String,Any}("domain" => Dict{String,Any}("unionWith" => Any[]))
    @test stroke_of(plain)["scale"] == union_scale
    @test isnothing(stroke_of(plain)["legend"])
    @test stroke_of(plain * config(scales=scales(Color=(; colormap=:viridis))))["scale"] ==
        merge(union_scale, Dict{String,Any}("scheme" => "viridis"))
    @test stroke_of(plain * config(scales=scales(Color=(; scale=log10))))["scale"] ==
        merge(union_scale, Dict{String,Any}("type" => "log"))

    # A stroke that paints otherwise, or says what its legend is, is left as written.
    written = Dict("field" => "v", "type" => "quantitative", "legend" => Dict("title" => "Edge"))
    @test stroke_of(data(cells) * mapping(:k; color=:v) * geoshape(grid(ks)) *
        config(encoding=Dict("stroke" => written)))["legend"]["title"] == "Edge"
    own = Dict("field" => "v", "type" => "quantitative", "scale" => Dict("scheme" => "magma"))
    drawn = stroke_of(data(cells) * mapping(:k; color=:v) * geoshape(grid(ks)) *
        config(encoding=Dict("stroke" => own)) * config(scales=viridis))
    @test drawn["scale"] == Dict{String,Any}("scheme" => "magma")
    @test !isnothing(get(drawn, "legend", Dict()))
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
    # No `Color` scale: no scheme or range on either channel, and a stroke on another
    # column has no scale at all.
    plain = to_vegalite(data(cells) * mapping(:k; color=:v, strokecolor=:w) * geoshape(grid(ks)))
    @test !haskey(plain["encoding"]["color"], "scale")
    @test !haskey(plain["encoding"]["stroke"], "scale")

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
                    config(width=300, height=80, scales=scales(Color=(; colormap=:viridis)), frame=:year); id="st-frame"),
                vdraw(data(framed) * mapping(:k; color=:v => "W", strokecolor=:v => "W") * geoshape(grid(ks[1:3])) *
                    visual(; strokeWidth=2) * config(width=300, height=80, scales=viridis, frame=:year); id="st-frame-fixed"),
                vdraw(data(cells) * mapping(:k; color=:w => "W", strokecolor=:w => "W") * geoshape(grid(ks)) *
                    visual(; strokeWidth=2) * config(width=300, height=80); id="st-plain"),
                vdraw(data(cells) * mapping(:k; color=:w => "W", strokecolor=:w => "W") * geoshape(grid(ks)) *
                    visual(; strokeWidth=2) *
                    config(width=300, height=80, scales=scales(Color=(; colormap=:viridis, scale=log10))); id="st-log")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "stroke_color_scale.js"), String)
            # SVG, so the driver can click a legend label as a reader does.
            svg = "<script>const originalEmbed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "originalEmbed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * svg * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-stroke-scale-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 50
                @test isempty(report["failures"])
                @info "mapped stroke browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

@testitem "vsave writes one colour bar and the fill's colours on the stroke" setup=[AoVStrokeScaleFixtures] tags=[:regression, :static, :geoshape, :vsave] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir(prefix="kb-stroke-scale-") do dir
            function shapes(path)
                svg = read(path, String)
                cells = [m for m in eachmatch(r"<path [^>]*?aria-roledescription=\"geoshape\"[^>]*>", svg)]
                paint(c, k) = match(Regex("\\b$k=\"([^\"]*)\""), c.match)
                (; svg, paints=[(paint(c, "fill")[1], paint(c, "stroke")[1]) for c in cells])
            end
            # A fixed range, and a range from the data with no colorrange.
            for sc in (viridis, scales(Color=(; colormap=:viridis)))
                path = joinpath(dir, "map.svg")
                vsave(seamless(sc), path)
                drawn = shapes(path)
                @test length(drawn.paints) == 5
                @test all(p -> p[1] == p[2], drawn.paints)
                @test length(unique(first.(drawn.paints))) > 1
                @test count("<linearGradient", drawn.svg) == 1
            end
        end
    end
end
