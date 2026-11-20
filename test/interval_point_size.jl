using TestItemRunner

# A fixed `visual(; markersize=…)` on `pointinterval()` (raw draws and `bands=`)
# and `gradient_interval()` sizes the median point, with the conversion
# `visual(Scatter; markersize)` uses (Vega area `ms²/2`), and thins its ring with
# it. Before, the analyses drew the point at a fixed Vega `size` (80 px², 8.9 px
# across) and dropped `markersize` with "applies only a fixed `color`", so on an
# axis where the intervals are a few pixels long the white point covered them,
# in the browser and in `vsave` files alike (snag `pointinterval-na-6aea7e31`).
@testsnippet AoVIntervalPointSizeFixtures begin
    using AlgebraOfVega
    import AlgebraOfGraphics

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
    median_point(vl) = only(filter(is_point, units(vl)))
    rules(vl) = [u for u in units(vl) if mark_type(u) == "rule"]

    draws = (; v=collect(1.0:60.0), g=repeat(["a", "b", "c"], 20), s=repeat(["F", "M"], 30))
    summary = (; m=[2.0, 5.0, 8.0], lo=[1.0, 4.0, 7.0], hi=[3.0, 6.0, 9.0],
                 lo50=[1.5, 4.5, 7.5], hi50=[2.5, 5.5, 8.5], g=["a", "b", "c"])
    horizontal(a) = data(draws) * mapping(:v; y=:g) * a
    vertical(a) = data(draws) * mapping(:g, :v) * a
    precomputed = data(summary) * mapping(:m; y=:g) *
        pointinterval(bands=[:lo => :hi, :lo50 => :hi50], probs=[0.95, 0.5], point=:mean)
    # Each analysis whose point is its median, with its default point area.
    analyses = ["pointinterval()" => (horizontal(pointinterval()), 80),
        "pointinterval(orientation=:vertical)" => (vertical(pointinterval(orientation=:vertical)), 80),
        "pointinterval(bands=…)" => (precomputed, 80),
        "gradient_interval()" => (horizontal(gradient_interval()), 50)]
end

@testitem "visual markersize sizes the interval median point" setup=[AoVIntervalPointSizeFixtures] tags=[:regression, :translation] begin
    for (name, (spec, default)) in analyses
        base = to_vegalite(spec)
        # The default point is unchanged: its analysis's own area and a 1.5 px ring.
        pt = median_point(base)
        @test pt["mark"]["size"] == default && pt["mark"]["strokeWidth"] == 1.5

        # markersize 3 → area 4.5 (as visual(Scatter; markersize=3)), 2.1 px across,
        # with a ring a sixth of that; no warning.
        vl = @test_logs to_vegalite(spec * visual(; markersize=3))
        pt = median_point(vl)
        @test pt["mark"]["size"] == 4.5
        @test pt["mark"]["strokeWidth"] == round(sqrt(4.5) / 6; digits=3)
        @test pt["mark"]["color"] == "white" && pt["mark"]["stroke"] == "#333"
        # Only the point changes: the rules (and the rest of the spec) are as before.
        @test rules(vl) == rules(base)
        @test pt["encoding"] == median_point(base)["encoding"]

        # A point larger than the default keeps the 1.5 px ring.
        @test median_point(to_vegalite(spec * visual(; markersize=20)))["mark"]["strokeWidth"] == 1.5
    end

    # One markersize draws the median point and a scatter dot alike.
    scatter = only(units(to_vegalite(data(draws) * mapping(:v, :g) * visual(Scatter; markersize=8))))
    @test median_point(to_vegalite(horizontal(pointinterval()) * visual(; markersize=8)))["mark"]["size"] ==
        scatter["mark"]["size"] == 32

    # With a fixed colour: the rules take the colour, the point the size, no warning.
    vl = @test_logs to_vegalite(precomputed * visual(; color=:ink, markersize=2))
    @test median_point(vl)["mark"]["size"] == 2.0
    @test all(u -> u["mark"]["style"] == "aov-ink", rules(vl))

    # With a colour mapping, a marker mapping and a facet the point keeps its
    # encodings and takes the size.
    vl = to_vegalite(data(draws) * mapping(:v; y=:g, color=:s, marker=:s) * pointinterval() * visual(; markersize=3))
    pt = median_point(vl)
    @test pt["mark"]["size"] == 4.5 && pt["encoding"]["shape"]["field"] == "s"
    panels = merge(draws, (; p=repeat(["P1", "P2"], inner=30)))
    vl = to_vegalite(data(panels) * mapping(:v; y=:g, col=:p) * pointinterval() * visual(; markersize=3))
    @test haskey(vl, "facet") && median_point(vl)["mark"]["size"] == 4.5

    # The ridgeline figure (density with y=, plus a pointinterval) draws its own
    # median point; markersize reaches it too.
    ridge = data(draws) * mapping(:v; y=:g) * (density() + pointinterval() * visual(; markersize=3))
    @test median_point(to_vegalite(ridge))["mark"]["size"] == 4.5
    ridge = data(draws) * mapping(:v; y=:g) * (density() + pointinterval())
    @test median_point(to_vegalite(ridge))["mark"]["size"] == 60
end

@testitem "interval markersize must be one positive number" setup=[AoVIntervalPointSizeFixtures] tags=[:regression, :translation] begin
    for bad in ([2, 3], 0, -1, NaN, Inf, :small)
        err = @test_throws ArgumentError to_vegalite(horizontal(pointinterval()) * visual(; markersize=bad))
        @test occursin("pointinterval() takes one positive number as `visual(...; markersize)`", sprint(showerror, err.value))
    end
    @test_throws ArgumentError to_vegalite(horizontal(gradient_interval()) * visual(; markersize=0))
    # dotinterval's markersize could mean its quantile dots (sized by count), so it
    # stays unapplied and reported, as do the other attributes.
    @test_logs (:warn, r"dotinterval\(\) applies only a fixed `color` from.*ignoring `markersize`") to_vegalite(
        horizontal(dotinterval()) * visual(; markersize=3))
    @test_logs (:warn, r"pointinterval\(\) applies only a fixed `color` and `markersize` from.*ignoring `linewidth`") to_vegalite(
        horizontal(pointinterval()) * visual(; markersize=3, linewidth=2))
end

@testitem "vsave: a small interval point leaves short intervals visible" setup=[AoVIntervalPointSizeFixtures] tags=[:static, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        # The reported shape: means near 11 on a fixed 0–14 axis, with 95 % intervals
        # a few pixels long and 50 % intervals one or two.
        rows = (; mean=[10.96, 11.20, 11.48], q025=[10.69, 10.97, 11.25], q975=[11.23, 11.44, 11.69],
                  q25=[10.87, 11.10, 11.41], q75=[11.05, 11.29, 11.56], cases=["60", "100", "250"])
        fig(extra) = data(rows) * mapping(:mean, y=:cases) *
            pointinterval(bands=[:q025 => :q975, :q25 => :q75], probs=[0.95, 0.5], point=:mean) *
            visual(; color=:ink, extra...) *
            config(height=220, width=200, scales=scales(X=(; domain=[0.0, 14.0], nice=false)))
        # A point mark is a path `M r,0A r,r,…`; a rule a line from its translate by (x2, y2).
        radii(svg) = [parse(Float64, m[1]) for m in eachmatch(r"aria-roledescription=\"point\"[^>]*d=\"M([0-9.]+),0A", svg)]
        lengths(svg, layer) = let g = match(Regex("class=\"mark-rule role-mark [^\"]*layer_$(layer)_marks\"[^>]*>(.*?)</g>"), svg)
            [abs(parse(Float64, m[1])) for m in eachmatch(r"<line [^>]*x2=\"(-?[0-9.]+)\"", g[1])]
        end
        mktempdir() do dir
            default_svg = read(vsave(fig((;)), joinpath(dir, "default.svg")), String)
            small_svg = read(vsave(fig((; markersize=2)), joinpath(dir, "small.svg")), String)
            # Control: the default point (area 80) is wider than every 95 % interval.
            r_default = radii(default_svg)
            l95 = lengths(default_svg, 0)
            @test length(r_default) == 3 && all(≈(sqrt(80) / 2; atol=1e-3), r_default)
            @test length(l95) == 3 && all(<(2 * first(r_default)), l95)
            # markersize=2: area 2, 1.41 px across, inside each interval; the rules are unchanged.
            r_small = radii(small_svg)
            @test length(r_small) == 3 && all(≈(sqrt(2) / 2; atol=1e-3), r_small)
            @test lengths(small_svg, 0) == l95 && lengths(small_svg, 1) == lengths(default_svg, 1)
            @test all(>(2 * first(r_small)), l95)
            @test occursin("stroke-width=\"0.236\"", small_svg)
        end
    end
end
