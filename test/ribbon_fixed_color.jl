using TestItemRunner

# A fixed `visual(; color=…)` on `lineribbon()` / `ribbon()` colours the bands and
# the median line, on both renderers, as a fixed colour does on a plain mark;
# `color=:ink` becomes the theme-following ink. Before, the ribbon emitters never
# read the layer's visual: the colour was silently dropped and the ribbon drew in
# Vega's default blue (snag `lineribbon-fixed-fcf78a96`).
@testsnippet AoVRibbonColorFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    import Makie

    # Every Vega-Lite unit (a dict with a `mark`), in emission order.
    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            for child in get(node, key, Any[])
                units(child, out)
            end
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    marks(vl) = [u["mark"] for u in units(vl)]
    is_point(m) = m["type"] == "point"

    bands = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], q025=[0.0, 2.0, 7.0],
        q975=[2.0, 6.0, 11.0], q25=[0.5, 3.0, 8.0], q75=[1.5, 5.0, 10.0])
    draws = (; x=repeat([1.0, 2.0, 3.0], 20), y=collect(1.0:60.0), draw=repeat(1:20, inner=3))
    band_ribbon(analysis) = data(bands) * mapping(:x, :y) * analysis
    precomputed = (lineribbon(bands=[:q025 => :q975, :q25 => :q75]),
        ribbon(bands=[:q025 => :q975, :q25 => :q75]))
    static_layers(spec) = let c = AlgebraOfVega._convert_drawable(first(AlgebraOfVega._extract_drawable(spec)))
        c isa AlgebraOfGraphics.Layers ? c.layers : [c]
    end
    static_color(l) = get(AlgebraOfVega.extract_visual(l).attributes, :color, nothing)
end

@testitem "fixed colour reaches every ribbon mark" setup=[AoVRibbonColorFixtures] tags=[:regression, :translation, :theme] begin
    for a in precomputed, c in ("black", :black)
        ms = marks(to_vegalite(band_ribbon(a) * visual(; color=c)))
        @test length(ms) == (a.transformation.show_line ? 3 : 2)
        @test all(m -> m["color"] == "black", ms)
        # The analysis keeps its own graduated band opacities and line width.
        @test [m["opacity"] for m in ms if m["type"] == "area"] == [0.2, 0.6]
        a.transformation.show_line && @test only(m for m in ms if m["type"] == "line")["strokeWidth"] == 2
    end
    # Raw draws summarized in Julia take the same colour.
    raw = marks(to_vegalite(data(draws) * mapping(:x, :y; group=:draw) * lineribbon() * visual(; color="#123456")))
    @test length(raw) == 4 && all(m -> m["color"] == "#123456", raw)

    # Theme ink: the named style on every mark, no literal colour.
    for a in precomputed
        vl = to_vegalite(band_ribbon(a) * visual(; color=:ink))
        @test all(m -> m["style"] == "aov-ink" && !haskey(m, "color"), marks(vl))
        @test vl["config"]["style"]["aov-ink"]["color"] == "#333"
    end

    # Faceted: the inner spec's marks carry it.
    panels = (; x=repeat([1.0, 2.0, 3.0], 2), y=collect(1.0:6.0), lo=collect(0.0:5.0),
        hi=collect(2.0:7.0), p=repeat(["P1", "P2"], inner=3))
    vl = to_vegalite(data(panels) * mapping(:x, :y; col=:p) * lineribbon(bands=[:lo => :hi]) * visual(; color="black"))
    @test haskey(vl, "facet")
    @test length(marks(vl)) == 2 && all(m -> m["color"] == "black", marks(vl))

    # Single-x glyph: the rules take the colour, the median point keeps its
    # white fill and dark ring.
    single = (; x=[1.0], y=[1.0], lo=[0.0], hi=[2.0])
    ms = marks(to_vegalite(data(single) * mapping(:x, :y) * lineribbon(bands=[:lo => :hi]) * visual(; color="black")))
    @test all(m -> m["color"] == "black", filter(!is_point, ms))
    @test only(filter(is_point, ms))["color"] == "white"
    @test only(filter(is_point, ms))["stroke"] == "#333"

    # Layered with a scatter: only the ribbon's marks are coloured.
    vl = to_vegalite(band_ribbon(precomputed[1]) * visual(; color="black") +
        data(bands) * mapping(:x, :y) * visual(Scatter))
    ms = marks(vl)
    @test all(m -> get(m, "color", nothing) == "black", filter(!is_point, ms))
    @test !haskey(only(filter(is_point, ms)), "color")
end

@testitem "ribbon colour mapping wins over a fixed colour" setup=[AoVRibbonColorFixtures] tags=[:regression, :translation] begin
    groups = (; x=[1.0, 2.0, 3.0, 1.0, 2.0, 3.0], y=[1.0, 2.0, 3.0, 2.0, 3.0, 4.0],
        lo=[0.0, 1.0, 2.0, 1.0, 2.0, 3.0], hi=[2.0, 3.0, 4.0, 3.0, 4.0, 5.0], g=["a", "a", "a", "b", "b", "b"])
    coloured = data(groups) * mapping(:x, :y; color=:g) * lineribbon(bands=[:lo => :hi])
    # As for a plain mark (Vega-Lite encoding over mark colour; AoG mapping over
    # visual attribute): the coloured ribbon lowers exactly as without it.
    @test to_vegalite(coloured * visual(; color="black")) == to_vegalite(coloured)
    @test all(l -> isnothing(static_color(l)), static_layers(coloured * visual(; color="black")))
end

@testitem "other visual attributes on a ribbon are reported" setup=[AoVRibbonColorFixtures] tags=[:regression, :translation] begin
    spec = band_ribbon(precomputed[1]) * visual(; color="black", linewidth=3)
    vl = @test_logs (:warn, r"lineribbon\(\) applies only a fixed `color`.*ignoring `linewidth`") to_vegalite(spec)
    @test all(m -> m["color"] == "black", marks(vl))
    @test only(m for m in marks(vl) if m["type"] == "line")["strokeWidth"] == 2
    @test_logs (:warn, r"ribbon\(\) applies only a fixed `color`.*ignoring `alpha`") to_vegalite(
        band_ribbon(precomputed[2]) * visual(; alpha=0.5))
    # Colour alone, or no visual, is silent.
    @test_logs to_vegalite(band_ribbon(precomputed[1]) * visual(; color="black"))
    @test_logs to_vegalite(band_ribbon(precomputed[1]))
end

@testitem "sdraw ribbon fixed colour" setup=[AoVRibbonColorFixtures] tags=[:regression, :static, :theme] begin
    for a in precomputed, c in ("black", :black)
        ls = static_layers(band_ribbon(a) * visual(; color=c))
        @test length(ls) == (a.transformation.show_line ? 3 : 2)
        @test all(l -> static_color(l) == c, ls)
    end
    raw = static_layers(data(draws) * mapping(:x, :y; group=:draw) * lineribbon() * visual(; color="black"))
    @test length(raw) == 4 && all(l -> static_color(l) == "black", raw)
    # `:ink` follows the active Makie theme's text colour.
    @test all(l -> static_color(l) == :black, static_layers(band_ribbon(precomputed[1]) * visual(; color=:ink)))
    Makie.with_theme(Makie.theme_black()) do
        @test all(l -> static_color(l) == :white, static_layers(band_ribbon(precomputed[2]) * visual(; color=:ink)))
    end
    # Without a fixed colour the rebuilt layers stay uncoloured, as before.
    @test all(l -> isnothing(static_color(l)), static_layers(band_ribbon(precomputed[1])))
end
