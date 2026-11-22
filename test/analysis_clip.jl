using TestItemRunner

# `visual(...; clip=true)` keeps a layer cut at the frame (aov-use, pan and
# zoom). An analysis builds its marks from scratch, so the attribute used to
# reach none of them: `pointinterval(bands=…) * visual(; clip=true)` with a
# narrow x domain emitted its rules and point unclipped, the pan/zoom patch drew
# every interval whole until the reader zoomed, and the page's canvas grew to
# hold them (a 23,612 px forest on a consumer's report). Every mark an
# analysis layer draws now carries the authored clip, and under pan/zoom the
# `aov-own-clip` style the runtime's patch skips (snag
# `pointinterval-ma-10864d08`).
@testsnippet AoVAnalysisClipFixtures begin
    using AlgebraOfVega
    marks(x) = Any[]
    marks(v::AbstractVector) = reduce(vcat, map(marks, v); init=Any[])
    function marks(d::AbstractDict)
        out = Any[]
        haskey(d, "mark") && push!(out, d["mark"])
        for k in ("layer", "spec", "hconcat", "vconcat", "concat")
            haskey(d, k) && append!(out, marks(d[k]))
        end
        out
    end
    clip_of(m) = m isa AbstractDict ? get(m, "clip", nothing) : nothing
    styles(m) = m isa AbstractDict ? (s = get(m, "style", String[]); s isa AbstractVector ? s : [s]) : String[]
    own(m) = "aov-own-clip" in styles(m)
    draws = (; g=repeat(["a", "b", "c"], inner=100), v=collect(range(-3, 3; length=300)),
        p=repeat(["P", "Q"], 150))
    xy = (; x=repeat(1.0:10, 30), y=collect(range(-1, 1; length=300)))
    # The reporter's forest: precomputed bands much wider than the zoom domain.
    forest = data((; parameter=repeat(["CL", "V", "ka"], 2), regime=repeat(["prior", "posterior"], inner=3),
            median=[1.0, 2, 3, 1.5, 2.5, 3.5], q025=fill(-40.0, 6), q975=fill(40.0, 6),
            q10=fill(-20.0, 6), q90=fill(20.0, 6), q25=fill(-5.0, 6), q75=fill(5.0, 6))) *
        mapping(:median; y=:parameter, color=:regime) *
        pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75])
    zoom = config(; width=400, encoding=Dict(:x => Dict("scale" => Dict("domain" => [0, 5]))))
    analyses = [
        "pointinterval(bands=)" => forest,
        "pointinterval()" => data(draws) * mapping(:v; y=:g) * pointinterval(),
        "gradient_interval()" => data(draws) * mapping(:v; y=:g) * gradient_interval(),
        "dotinterval()" => data(draws) * mapping(:v; y=:g) * dotinterval(),
        "lineribbon()" => data(xy) * mapping(:x, :y) * lineribbon(),
        "ribbon()" => data(xy) * mapping(:x, :y) * ribbon(),
        "density()" => data(xy) * mapping(:y) * density(),
        "histogram()" => data(xy) * mapping(:y) * histogram(),
        "linear()" => data(xy) * mapping(:x, :y) * linear(),
        "smooth()" => data(xy) * mapping(:x, :y) * smooth(),
    ]
end

@testitem "visual(; clip=true) cuts every mark an analysis draws, and pan/zoom keeps it cut" setup=[AoVAnalysisClipFixtures] tags=[:regression, :translation, :interactivity] begin
    for (name, layer) in analyses
        @testset "$name" begin
            # No warning: `clip` is applied, not ignored.
            vl = @test_logs to_vegalite(layer * visual(; clip=true))
            ms = marks(vl)
            @test !isempty(ms)
            @test all(m -> clip_of(m) === true, ms)
            @test all(own, ms)
            # Without the attribute nothing changes: the runtime owns the clip.
            @test all(m -> isnothing(clip_of(m)) && !own(m), marks(to_vegalite(layer)))
        end
    end

    # The reporter's zoomed forest, and the same through `to_html`'s bare embed.
    vl = to_vegalite(forest * visual(; clip=true) * zoom)
    @test length(marks(vl)) == 4 && all(own, marks(vl))
    @test occursin("aov-own-clip", to_html(forest * visual(; clip=true) * zoom; id="forest"))

    # Without pan/zoom the clip is Vega-Lite's own and needs no marker.
    flat = marks(to_vegalite(forest * visual(; clip=true); interactive=false))
    @test all(m -> clip_of(m) === true && !own(m), flat)

    # `clip=false` is written as authored: the marks stay whole even when zoomed.
    off = marks(to_vegalite(forest * visual(; clip=false)))
    @test all(m -> clip_of(m) === false && !own(m), off)

    # A fixed colour beside it still applies.
    coloured = marks(to_vegalite(data(draws) * mapping(:v; y=:g) * pointinterval() * visual(; color="red", clip=true)))
    @test all(own, coloured)
    @test any(m -> get(m, "color", nothing) == "red", coloured)

    # Faceted cells carry it too.
    faceted = marks(to_vegalite(data(draws) * mapping(:v; y=:g, col=:p) * pointinterval() * visual(; clip=true)))
    @test length(faceted) == 4 && all(own, faceted)

    # In a sum only the layer that authors it is cut.
    sum_marks = marks(to_vegalite(data(draws) * mapping(:v; y=:g) * pointinterval() * visual(; clip=true) +
        data((; v=[0.0, 1.0], g=["a", "b"])) * mapping(:v, :g) * visual(Scatter)))
    @test count(own, sum_marks) == 4
    @test count(m -> !own(m) && isnothing(clip_of(m)), sum_marks) == 1

    # A reference line's label stays outside the frame: it keeps `clip: false`.
    ref = marks(to_vegalite(data((; x=[1.0, 2], y=[0.0, 2])) * mapping(:x, :y) * visual(Scatter) +
        data((; y=[1.0], t=["ref"])) * mapping(:y; text=:t) * visual(HLines) * visual(; clip=true)))
    label = only(filter(m -> "aov-ref-label" in styles(m), ref))
    @test clip_of(label) === false && !own(label)
    @test count(own, ref) == 1
end

@testitem "an analysis' clip on sdraw: true holds by itself, false is reported" setup=[AoVAnalysisClipFixtures] tags=[:regression, :translation] begin
    # `sdraw` hands a ribbon to Makie, which cuts every plot at its axis.
    ribbon_layer(v) = data(xy) * mapping(:x, :y) * lineribbon() * v
    @test (@test_logs AlgebraOfVega._analysis_fixed_color(ribbon_layer(visual(; clip=true)), "lineribbon()"; static=true)) === nothing
    @test_logs (:warn, r"ignoring `clip`") AlgebraOfVega._analysis_fixed_color(
        ribbon_layer(visual(; clip=false)), "lineribbon()"; static=true)
    # On the Vega path both values are applied.
    @test_logs AlgebraOfVega._analysis_fixed_color(ribbon_layer(visual(; clip=false)), "lineribbon()")
end
