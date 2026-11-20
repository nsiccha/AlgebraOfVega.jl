# `config(axis=(; limits=((xlo, xhi), (ylo, yhi))))` reaches only the layers drawn with that
# axis, as the X/Y `scales` keys do (snag `axis-limits-inje-a456c174`, reporter
# Portfolio:brr-dose). Before the fix the limits went through the raw `config(encoding=…)`
# merge, so a response curve beside a patient `VLines` rule gave the rule a field-less
# `"y": {"scale": {"domain": [0, 100]}}`, and Vega-Lite logged `Dropping … from channel "y"
# since it does not contain any data field, datum, value, or signal.` on every render.

@testsnippet AoVAxisLimitsFixtures begin
    using AlgebraOfVega
    import AlgebraOfGraphics
    import Makie

    curve = data((; exposure=[0.0, 5.0, 10.0, 20.0], response=[2.0, 30.0, 70.0, 95.0])) *
        mapping(:exposure => "Exposure", :response => "Response (%)") *
        visual(Lines; color="#0072B2", label="Tumour response")
    patient = data((; at=[7.5])) * mapping(:at) *
        visual(VLines; color=:ink, linestyle=:dash, label="This patient")
    level = data((; lo=[50.0])) * mapping(:lo) * visual(HLines)
    channel(vl, ch) = [get(l["encoding"], ch, nothing) for l in vl["layer"]]
end

@testitem "axis limits never give a layer an axis it was not drawn with" setup=[AoVAxisLimitsFixtures] tags=[:translation, :regression] begin
    # The reporter's figure: y limits over a curve and a VLines rule that has no y.
    vl = to_vegalite((curve + patient) * config(height=280, axis=(; limits=(nothing, (0, 100)))))
    curve_y, rule_y = channel(vl, "y")
    @test curve_y["field"] == "response"
    @test collect(curve_y["scale"]["domain"]) == [0, 100]
    @test isnothing(rule_y)
    # The rule keeps its own x, without an x domain, since no x limits were given.
    @test !haskey(get(channel(vl, "x")[2], "scale", Dict()), "domain")

    # x limits beside an HLines rule (which has no x): every x that has a field takes them.
    vx = to_vegalite((curve + patient + level) * config(axis=(; limits=((0, 25), nothing), clamp=true)))
    xs = channel(vx, "x")
    @test collect(xs[1]["scale"]["domain"]) == [0, 25] && xs[1]["scale"]["clamp"] === true
    @test collect(xs[2]["scale"]["domain"]) == [0, 25]
    @test isnothing(xs[3])

    # A rule limited to part of the plot carries its y as a mark expression, never as an encoding.
    partial = data((; at=[7.5])) * mapping(:at) * visual(VLines; ymin=0.0, ymax=0.9)
    vp = to_vegalite((curve + partial) * config(axis=(; limits=(nothing, (0, 100)))))
    @test isnothing(channel(vp, "y")[2])
    @test haskey(vp["layer"][2]["mark"], "y")

    # Each layer gets its own scale object, not one shared dict.
    a, b = (x["scale"] for x in xs[1:2])
    @test a == b && a !== b
end

@testitem "axis limits reach a faceted figure's field-bearing layers" setup=[AoVAxisLimitsFixtures] tags=[:translation, :regression] begin
    rows = (; exposure=[0.0, 10.0, 0.0, 10.0], response=[5.0, 60.0, 10.0, 80.0], arm=["A", "A", "B", "B"])
    lines = data(rows) * mapping(:exposure, :response; col=:arm) * visual(Lines)
    marks = data((; at=[5.0, 5.0], arm=["A", "B"])) * mapping(:at; col=:arm) * visual(VLines)
    vl = to_vegalite((lines + marks) * config(axis=(; limits=(nothing, (0, 100)))))
    inner = vl["spec"]["layer"]
    @test collect(inner[1]["encoding"]["y"]["scale"]["domain"]) == [0, 100]
    @test !haskey(inner[2]["encoding"], "y")
end
