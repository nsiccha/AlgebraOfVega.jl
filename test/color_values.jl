using TestItemRunner

@testsnippet AoVColorValueFixtures begin
    using AlgebraOfVega
    import Makie

    plan = (; row=["a"], start=[1.0], stop=[3.0])
    planned(; kw...) = data(plan) * mapping(:row, :stop; fillto=:start) *
        visual(BarPlot; direction=:x, kw...)
    mark(spec) = to_vegalite(spec; interactive=false)["mark"]
    css_components(s) = parse.(Float64, split(chop(s; head=5, tail=1), ','))
    red10 = "rgba(255.0, 0.0, 0.0, 0.1)"
end

@testitem "Makie colour tuples and Colorants lower to CSS without fading the outline" setup=[AoVColorValueFixtures] tags=[:translation, :regression] begin
    for c in ((:red, 0.1), ("red", 0.1), Makie.RGBAf(1, 0, 0, 0.1))
        m = @test_logs mark(planned(color=c, strokecolor=:red, strokewidth=2))
        @test m["color"] == red10
        @test m["stroke"] == "red" && m["strokeWidth"] == 2
        @test !haskey(m, "opacity") && !haskey(m, "fillOpacity")
    end
    @test mark(planned(color=(:red, 0.1), alpha=0.5))["opacity"] == 0.5
    for a in (0.0, 0.25, 1.0)
        @test css_components(mark(planned(color=(:red, a)))["color"]) ≈ [255, 0, 0, a]
    end
    for c in (Makie.RGBf(1, 0, 0), Makie.Colors.HSV(0, 1, 1),
              Makie.Colors.colorant"red")
        @test css_components(mark(planned(color=c))["color"]) ≈ [255, 0, 0, 1]
    end
    @test css_components(mark(planned(color=Makie.Colors.Gray(0.5)))["color"]) ≈ [127.5, 127.5, 127.5, 1]
    # The tuple follows Makie's own treatment of a colour which already has alpha.
    c = (Makie.RGBAf(1, 0, 0, 0.5), 0.25)
    @test last(css_components(mark(planned(color=c))["color"])) ≈ Makie.alpha(Makie.to_color(c))
    @test mark(planned(strokecolor=(:red, 0.1)))["stroke"] == red10
    @test mark(planned(stroke=Makie.RGBAf(1, 0, 0, 0.1)))["stroke"] == red10
    @test mark(planned(fill=(:red, 0.1)))["fill"] == red10
    @test mark(planned(fill=nothing))["fill"] === nothing
    expr = Dict("expr" => "'red'")
    @test mark(planned(fill=expr))["fill"] == expr
    for c in (:red, "red", "#c03040", "rgba(1, 2, 3, 0.4)")
        @test mark(planned(color=c))["color"] == string(c)
    end
    @test mark(planned(color=:ink))["style"] == "aov-ink"
    @test mark(planned(strokecolor=:ink))["style"] == "aov-ink-stroke"
end

@testitem "fixed ribbon and interval colours accept Makie alpha tuples" setup=[AoVRibbonColorFixtures] tags=[:translation, :regression] begin
    fixed = (:red, 0.1)
    css = "rgba(255.0, 0.0, 0.0, 0.1)"
    for a in (precomputed..., lineribbon(), ribbon())
        base = a in precomputed ? band_ribbon(a) : data(draws) * mapping(:x, :y) * a
        ms = marks(to_vegalite(base * visual(; color=fixed)))
        @test all(m -> m["color"] == css, filter(!is_point, ms))
        # The static renderer still receives the authored tuple, not a CSS rewrite.
        @test all(l -> static_color(l) == fixed, static_layers(base * visual(; color=fixed)))
    end
    base = data((; g=repeat(["a", "b"], inner=10), v=collect(1.0:20.0))) * mapping(:v; y=:g)
    for a in (pointinterval(), gradient_interval(), dotinterval())
        ms = marks(to_vegalite(base * a * visual(; color=fixed)))
        @test all(m -> m["color"] == css, filter(!is_point, ms))
        @test only(filter(is_point, ms))["color"] == "white"
    end
end

@testitem "colour scale palette and clip colours accept Makie values" setup=[AoVColorValueFixtures] tags=[:translation, :regression] begin
    tbl = (; x=[1, 2, 3], y=[1, 2, 3], g=["a", "b", "c"])
    spec = data(tbl) * mapping(:x, :y; color=:g) * visual(Scatter)
    palette = Any[(:red, 0.1), Makie.RGBf(0, 0, 1), :green]
    before = copy(palette)
    sc = scales(Color=(; palette, categories=["a", "b", "c"]))
    vl = to_vegalite(spec, sc)
    @test vl["encoding"]["color"]["scale"]["range"] == [red10, "rgba(0.0, 0.0, 255.0, 1.0)", "green"]
    @test palette == before
    @test sc.dict[:Color][:palette] == before
    numeric = data(tbl) * mapping(:x, :y; color=:x) * visual(Scatter)
    vl = to_vegalite(numeric, scales(Color=(; colorrange=(1, 2), lowclip=(:red, 0.1),
        highclip=Makie.RGBf(0, 0, 1), nan_color=Makie.RGBAf(1, 0, 0, 0.1))))
    @test [c["value"] for c in vl["encoding"]["color"]["condition"]] == [red10, "rgba(0.0, 0.0, 255.0, 1.0)"]
    @test vl["config"]["scale"]["invalid"]["color"]["value"] == red10
end

@testitem "vsave renders Makie colour alpha in the fill and keeps an opaque outline" setup=[AoVColorValueFixtures] tags=[:static, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            for (i, c) in enumerate(((:red, 0.1), Makie.RGBAf(1, 0, 0, 0.1), (:red, 0.0)))
                spec = planned(color=c, strokecolor=:red, strokewidth=2) *
                    config(width=200, height=100, background="white",
                        encoding=Dict("x" => Dict("axis" => nothing), "y" => Dict("axis" => nothing)))
                png = vsave(spec, joinpath(dir, "bar-$i.png"))
                pixels = Makie.FileIO.load(png)
                center = pixels[cld(size(pixels, 1), 2), cld(size(pixels, 2), 2)]
                @test Makie.red(center) ≈ 1 atol=1/255
                expected = i == 3 ? 1.0 : 0.9
                @test Makie.green(center) ≈ expected atol=2/255
                @test Makie.blue(center) ≈ expected atol=2/255
                @test any(p -> Makie.red(p) > 0.95 && Makie.green(p) < 0.05 && Makie.blue(p) < 0.05, pixels)
            end
        end
    end
end
