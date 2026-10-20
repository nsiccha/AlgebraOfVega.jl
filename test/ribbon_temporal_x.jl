using TestItemRunner

# A `lineribbon()` / `ribbon()` over a Date/DateTime x column encodes x as
# `temporal`, as a plain mark of the same column does, so a band layered with a
# scatter of the observations shares one time axis. Before, the ribbon emitter
# hardcoded `quantitative`: Vega-Lite split x into independent scales (extra
# axes at the top) and the ribbon's ISO-string x values became NaN, so the band
# and the median line painted nothing (snag `a-posterior-band-e1686463`).
@testsnippet AoVRibbonTemporalFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    using Dates

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
    x_types(vl) = unique(u["encoding"]["x"]["type"] for u in units(vl))
    tooltip_x_types(vl) = unique(t["type"] for u in units(vl)
        for t in u["encoding"]["tooltip"] if t["field"] == u["encoding"]["x"]["field"])

    t0 = DateTime(2026, 10, 20)
    times = [t0 + Hour(i) for i in 0:3]
    bands = (; start=times, mu=[1.0, 2.0, 3.0, 4.0], lo=[0.5, 1.5, 2.5, 3.5],
        hi=[1.5, 2.5, 3.5, 4.5], y=[1.1, 2.1, 3.1, 4.1], g=["a", "b", "a", "b"])
    draws(x) = (; start=repeat(x, inner=10), y=collect(1.0:10.0length(x)), draw=repeat(1:10, length(x)))
end

@testitem "ribbon over a date/time x encodes it temporal" setup=[AoVRibbonTemporalFixtures] tags=[:regression, :translation, :tidybayes] begin
    # The reported figure: a precomputed band + median line, layered with a
    # scatter of the observations over the same DateTime column.
    vl = to_vegalite(data(bands) * mapping(:start => "Time (UTC)", :mu) * lineribbon(bands=[:lo => :hi]) +
        data(bands) * mapping(:start, :y; color=:g) * visual(Scatter))
    @test x_types(vl) == ["temporal"]
    @test tooltip_x_types(vl) == ["temporal"]
    # AoV's no-zero default is for quantitative axes only.
    @test !any(u -> haskey(u["encoding"]["x"], "scale"), units(vl))

    # Both precomputed forms, raw draws summarized in Julia, and a Date column.
    for spec in (data(bands) * mapping(:start, :mu) * ribbon(bands=[:lo => :hi]),
                 data(draws(times)) * mapping(:start, :y; group=:draw) * lineribbon(),
                 data(draws(Date.(times) .+ Day.(0:3))) * mapping(:start, :y; group=:draw) * ribbon())
        vl = to_vegalite(spec)
        @test x_types(vl) == ["temporal"]
        @test tooltip_x_types(vl) == ["temporal"]
    end

    # Colour groups: the per-group layers and the runtime's template layers,
    # which it copies for a group whose rows arrive later.
    vl = to_vegalite(data(bands) * mapping(:start, :mu; color=:g) * lineribbon(bands=[:lo => :hi]))
    @test x_types(vl) == ["temporal"]
    @test unique(l["encoding"]["x"]["type"] for l in vl["_aov"]["lineribbon"]["templateLayers"]) == ["temporal"]

    # A single-x group's pointinterval glyph shares the time axis.
    single = map(c -> c[1:1], bands)
    vl = to_vegalite(data(single) * mapping(:start, :mu) * lineribbon(bands=[:lo => :hi]))
    @test any(u -> u["mark"]["type"] == "rule", units(vl))
    @test x_types(vl) == ["temporal"]

    # Faceted.
    vl = to_vegalite(data(bands) * mapping(:start, :mu; col=:g) * lineribbon(bands=[:lo => :hi]))
    @test haskey(vl, "facet") && x_types(vl) == ["temporal"]
end

@testitem "ribbon over a numeric x stays quantitative" setup=[AoVRibbonTemporalFixtures] tags=[:regression, :translation, :tidybayes] begin
    nums = merge(bands, (; start=[1.0, 2.0, 3.0, 4.0]))
    vl = to_vegalite(data(nums) * mapping(:start, :mu) * lineribbon(bands=[:lo => :hi]))
    @test x_types(vl) == ["quantitative"]
    @test tooltip_x_types(vl) == ["quantitative"]
    @test all(u -> u["encoding"]["x"]["scale"] == Dict("zero" => false), units(vl))

    # `preaggregate` emits `Any`-eltype key columns; a numeric key keeps its
    # quantitative ribbon axis.
    agg = AlgebraOfVega.preaggregate((; x=repeat(1.0:3.0, inner=5), y=collect(1.0:15.0));
        y=:y, group_keys=[:x], probs=[0.025, 0.5, 0.975])
    @test eltype(agg.x) == Any
    med, lo, hi = (Symbol(AlgebraOfVega._quantile_colname(p)) for p in (0.5, 0.025, 0.975))
    @test x_types(to_vegalite(data(agg) * mapping(:x, med) * lineribbon(bands=[lo => hi]))) == ["quantitative"]
end

@testitem "precomputed ribbon names a missing x column" setup=[AoVRibbonTemporalFixtures] tags=[:regression, :tidybayes] begin
    err = try
        to_vegalite(data(bands) * mapping(:when, :mu) * lineribbon(bands=[:lo => :hi]))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("x column \"when\" not found", err.msg)
end
