using TestItemRunner

# A fixed `visual(; color=…)` on the interval analyses — `pointinterval()`,
# `pointinterval(bands=…)`, `gradient_interval()`, `dotinterval()` — colours
# their rules (and `dotinterval`'s dots) in place of the hidden per-group colour;
# `color=:ink` becomes the theme-following ink. Before, the interval emitters
# never read the layer's visual: the colour was silently dropped and each group
# drew in its own palette colour (todo `09i202c`; the ribbon family's twin is
# snag `lineribbon-fixed-fcf78a96`).
@testsnippet AoVIntervalColorFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

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
    mark_type(u) = u["mark"]["type"]
    is_point(u) = mark_type(u) == "point"

    draws = (; v=collect(1.0:60.0), g=repeat(["a", "b", "c"], 20))
    summary = (; m=[2.0, 5.0, 8.0], lo=[1.0, 4.0, 7.0], hi=[3.0, 6.0, 9.0], g=["a", "b", "c"])
    horizontal(a) = data(draws) * mapping(:v; y=:g) * a
    vertical(a) = data(draws) * mapping(:g, :v) * a
    precomputed = data(summary) * mapping(:m; y=:g) * pointinterval(bands=[:lo => :hi])
    # Each interval analysis, as authored, with its user-facing name.
    analyses = ["pointinterval()" => horizontal(pointinterval()),
        "pointinterval(orientation=:vertical)" => vertical(pointinterval(orientation=:vertical)),
        "pointinterval(bands=…)" => precomputed,
        "gradient_interval()" => horizontal(gradient_interval()),
        "dotinterval()" => horizontal(dotinterval())]
end

@testitem "fixed colour reaches every interval rule and dot" setup=[AoVIntervalColorFixtures] tags=[:regression, :translation, :theme] begin
    for (name, spec) in analyses, c in ("black", :black)
        us = units(to_vegalite(spec * visual(; color=c)))
        coloured = filter(!is_point, us)
        @test !isempty(coloured)
        # Rules and dots take the colour; the per-group fallback colour encoding
        # is gone, since an encoding would beat the mark colour.
        @test all(u -> u["mark"]["color"] == "black", coloured)
        @test all(u -> !haskey(u["encoding"], "color"), coloured)
        # The median point keeps its white fill and dark ring.
        pt = only(filter(is_point, us))
        @test pt["mark"]["color"] == "white" && pt["mark"]["stroke"] == "#333"
        # The group axis is untouched.
        @test all(u -> haskey(u["encoding"], startswith(name, "pointinterval(orientation") ? "x" : "y"), us)
    end
    # The analysis keeps its own rule widths and gradient opacities.
    us = units(to_vegalite(horizontal(pointinterval()) * visual(; color="black")))
    @test [u["mark"]["strokeWidth"] for u in us if mark_type(u) == "rule"] == collect(range(1.5, 8, length=3))
    us = units(to_vegalite(horizontal(gradient_interval()) * visual(; color="black")))
    @test [u["encoding"]["opacity"]["value"] for u in us if mark_type(u) == "rule"] == collect(range(0.2, 0.7, length=3))
    dots = only(u for u in units(to_vegalite(horizontal(dotinterval()) * visual(; color="black"))) if mark_type(u) == "circle")
    @test dots["mark"]["opacity"] == 0.6 && dots["mark"]["size"] == 30

    # Theme ink: the named style on every rule and dot, no literal colour.
    for (name, spec) in analyses
        vl = to_vegalite(spec * visual(; color=:ink))
        coloured = filter(!is_point, units(vl))
        @test all(u -> u["mark"]["style"] == "aov-ink" && !haskey(u["mark"], "color"), coloured)
        @test all(u -> !haskey(u["encoding"], "color"), coloured)
        @test vl["config"]["style"]["aov-ink"]["color"] == "#333"
    end

    # Faceted: the inner spec's marks carry it.
    panels = merge(draws, (; p=repeat(["P1", "P2"], inner=30)))
    vl = to_vegalite(data(panels) * mapping(:v; y=:g, col=:p) * pointinterval() * visual(; color="black"))
    @test haskey(vl, "facet")
    @test all(u -> u["mark"]["color"] == "black", filter(!is_point, units(vl)))

    # Without a fixed colour each group keeps its hidden palette colour and the
    # dotinterval rules their default ink (the control for the cases above).
    for (name, spec) in analyses
        coloured = filter(!is_point, units(to_vegalite(spec)))
        @test all(u -> u["encoding"]["color"]["field"] == "g" && !haskey(u["mark"], "color"), coloured)
    end
    @test all(u -> u["mark"]["style"] == "aov-ink",
        filter(u -> mark_type(u) == "rule", units(to_vegalite(horizontal(dotinterval())))))
end

@testitem "interval colour mapping wins over a fixed colour" setup=[AoVIntervalColorFixtures] tags=[:regression, :translation] begin
    coloured = merge(draws, (; k=repeat(["x", "y"], inner=30)))
    for a in (pointinterval(), gradient_interval(), dotinterval())
        spec = data(coloured) * mapping(:v; y=:g, color=:k) * a
        # As for a plain mark (Vega-Lite encoding over mark colour; AoG mapping
        # over visual attribute): the coloured interval lowers exactly as without it.
        @test to_vegalite(spec * visual(; color="black")) == to_vegalite(spec)
    end
    spec = data(merge(summary, (; k=["x", "y", "x"]))) * mapping(:m; y=:g, color=:k) * pointinterval(bands=[:lo => :hi])
    @test to_vegalite(spec * visual(; color="black")) == to_vegalite(spec)
end

@testitem "other visual attributes on an interval are reported" setup=[AoVIntervalColorFixtures] tags=[:regression, :translation] begin
    vl = @test_logs (:warn, r"pointinterval\(\) applies only a fixed `color`.*ignoring `linewidth`") to_vegalite(
        horizontal(pointinterval()) * visual(; color="black", linewidth=3))
    @test all(u -> u["mark"]["color"] == "black", filter(!is_point, units(vl)))
    @test_logs (:warn, r"gradient_interval\(\) applies only a fixed `color`.*ignoring `alpha`") to_vegalite(
        horizontal(gradient_interval()) * visual(; alpha=0.5))
    @test_logs (:warn, r"dotinterval\(\) applies only a fixed `color`.*ignoring `markersize`") to_vegalite(
        horizontal(dotinterval()) * visual(; markersize=4))
    # Colour alone, or no visual, is silent.
    for (name, spec) in analyses
        @test_logs to_vegalite(spec * visual(; color="black"))
        @test_logs to_vegalite(spec)
    end
end
