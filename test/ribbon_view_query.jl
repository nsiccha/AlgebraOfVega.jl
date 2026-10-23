using TestItemRunner

"""
`ribbon_view(spec)`: the Julia-side reading of a coloured ribbon's "Ribbons |
Intervals" switch (src/ribbon_view.jl) — whether the figure carries it, which
drawing it starts in, the overlap score and threshold the tooltip shows, and
otherwise the condition the figure misses. A consumer pins the automatic pick
in its own tests and calibrates `intervals=` from a script with it (snag
`no-julia-query-f-77c6d213`). The fixtures are `test/ribbon_view.jl`'s.
"""

@testitem "ribbon_view reads the switch's decision" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    over = ribbon_view(ribbon_fig(overlapping()))
    @test over.offered && isnothing(over.why_not)
    @test over.start === :intervals && over.threshold == 0.1
    @test over.score ≈ 0.5 atol=0.01
    # The facts the finished spec carries for the browser's switch.
    rv = view_meta(to_vegalite(ribbon_fig(overlapping())))
    @test over.score == rv["score"] && over.threshold == rv["threshold"]

    sig = ribbon_view(ribbon_fig(sigmoids()))
    @test sig.offered && sig.start === :ribbons && sig.score < 0.05

    # A fixed start keeps its score; only :auto has a threshold.
    fixed = ribbon_view(ribbon_fig(sigmoids(); intervals=true))
    @test fixed.start === :intervals && fixed.score == sig.score && isnothing(fixed.threshold)
    @test ribbon_view(ribbon_fig(overlapping(); intervals=0.9)) ==
        (; offered=true, why_not=nothing, start=:ribbons, score=over.score, threshold=0.9)

    # The positional scales form: a fixed y domain ten times wider scores a tenth.
    wide = ribbon_view(ribbon_fig(overlapping()), scales(Y=(; domain=(-450, 450))))
    @test wide.offered
    @test wide.score ≈ over.score * 90 / 900 atol=0.005
end

@testitem "ribbon_view names the condition a figure without the switch misses" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    using Dates
    function why(spec; kw...)
        v = ribbon_view(spec; kw...)
        @test !v.offered && isnothing(v.start) && isnothing(v.score) && isnothing(v.threshold)
        v.why_not
    end
    t = overlapping()
    @test why(data(t) * mapping(:dose, :med; color=:group) * visual(Scatter)) === :no_ribbon
    @test why(ribbon_fig(overlapping()) + ribbon_fig(sigmoids())) === :several_ribbons
    @test why(data(t) * mapping(:dose, :med) * lineribbon(bands=BANDS)) === :no_color
    @test why(data(t) * mapping(:dose, :med; color=:group) * lineribbon(bands=BANDS, detail=[:group])) === :detail
    # A date x, and a text x.
    t4 = overlapping(; doses=[5, 10, 20, 40])
    days = Date(2026, 1, 1) .+ Day.(0:3)
    dated = merge(t4, (; day=[days[findfirst(==(d), [5, 10, 20, 40])] for d in t4.dose]))
    @test why(data(dated) * mapping(:day, :med; color=:group) * lineribbon(bands=BANDS)) === :not_numeric_x
    texted = merge(t4, (; label=string.(t4.dose, " mg")))
    @test why(data(texted) * mapping(:label, :med; color=:group) * lineribbon(bands=BANDS)) === :not_numeric_x
    # A typed-empty table, before the first rows stream in.
    empty_rows = (; (k => similar(getproperty(t, k), 0) for k in keys(t))...)
    @test why(ribbon_fig(empty_rows)) === :no_x_values
    # A dense x grid (a time course).
    @test why(ribbon_fig(overlapping(; doses=1:13))) === :too_many_x
    # An observation off the dose ladder, on a doubling ladder over a linear x.
    @test why(ribbon_fig(t) + data((; dose=[7], y=[1.0])) * mapping(:dose, :y) * visual(Scatter)) === :x_off_slots
end

@testitem "ribbon_view reads the picker's figure under auto_remap" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon, :auto_remap] begin
    t = overlapping()
    t2 = merge(t, (; study=fill("S1", length(t.dose))))
    spec = data(t2) * mapping(:dose, :med; color=:group) * lineribbon(bands=BANDS)
    remap = (; dims=["group" => "Group", "study" => "Study"], pinned=:row)
    v = ribbon_view(spec; auto_remap=remap)
    @test v.offered && v.start === Symbol(view_meta(to_vegalite(spec; auto_remap=remap))["start"])
    # The picker starts with the groups on facet rows (the pinned channel takes
    # them): no colour groups to dodge, although the authored figure has them.
    rows = (; remap..., color=String[])
    moved = ribbon_view(spec; auto_remap=rows)
    @test !moved.offered && moved.why_not === :no_color
    @test isnothing(view_meta(to_vegalite(spec; auto_remap=rows)))
    @test ribbon_view(spec).offered
end
