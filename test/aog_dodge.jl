using TestItemRunner

# AlgebraOfGraphics' own `dodge` mapping (BarPlot by `direction`; BoxPlot,
# Violin and CrossBar by `orientation`) reached the spec as an encoding channel
# named "dodge". Vega-Lite has no such channel and drops it without an error, so
# `mapping(:cap, :share; color=:scheme, dodge=:scheme) * visual(BarPlot)` drew
# three bars stacked to about 280 % where AoG draws them grouped (snag
# `aov-emits-aog-do-6019d128`). `dodge` now lowers to the offset channel of the
# axis the marks stand on, and a mapping keyword that lowers to no Vega-Lite
# channel is an ArgumentError, as AoG refuses a mapped attribute outside the
# plot type's aesthetic mapping.
@testsnippet AoVDodgeFixtures begin
    using AlgebraOfVega, JSON
    # The reporter's rows (Portfolio:vortest, "Useful share of paid gradient evaluations").
    rows = [(; cap="max depth 8", scheme="by transition", share=19.8),
            (; cap="max depth 8", scheme="by evaluation", share=24.2),
            (; cap="max depth 8", scheme="by evaluation + refill", share=88.4),
            (; cap="max depth 6", scheme="by transition", share=52.1),
            (; cap="max depth 6", scheme="by evaluation", share=61.0),
            (; cap="max depth 6", scheme="by evaluation + refill", share=96.9)]
    enc(p) = to_vegalite(p; interactive=false)["encoding"]
    grouped(kw) = data(rows) * mapping(:cap => "Tree-depth cap", :share => "Share (%)";
        color=:scheme => "Batching", kw...) * visual(BarPlot) * config(height=280)
    refusal(f) = try
        f(); ""
    catch err
        err isa ArgumentError || rethrow()
        sprint(showerror, err)
    end
end

@testitem "AoG's dodge on BarPlot lowers as dodge_x and dodge_y do" setup=[AoVDodgeFixtures] tags=[:translation, :regression] begin
    e = enc(grouped((; dodge=:scheme)))
    @test !haskey(e, "dodge")
    @test e["xOffset"] == Dict{String,Any}("field" => "scheme", "type" => "nominal")
    # The whole figure is the one `dodge_x` gives.
    @test JSON.json(to_vegalite(grouped((; dodge=:scheme)); interactive=false)) ==
          JSON.json(to_vegalite(grouped((; dodge_x=:scheme)); interactive=false))
    # The tooltip names the column by the label the legend shows, although the
    # offset channel, which carries no label, comes first.
    @test Dict{String,Any}("field" => "scheme", "type" => "nominal", "title" => "Batching") in e["tooltip"]

    # Horizontal bars dodge along y: `direction=:x`, or a value-first mapping
    # Vega-Lite draws horizontally.
    h = enc(data(rows) * mapping(:cap, :share; color=:scheme, dodge=:scheme) * visual(BarPlot; direction=:x))
    @test haskey(h, "yOffset") && !haskey(h, "xOffset")
    v = enc(data(rows) * mapping(:share, :cap; color=:scheme, dodge=:scheme) * visual(BarPlot))
    @test haskey(v, "yOffset") && !haskey(v, "xOffset")

    # The bar analyses, as AoG draws them with BarPlot.
    @test enc(data(rows) * mapping(:cap; color=:scheme, dodge=:scheme) * frequency())["xOffset"]["field"] == "scheme"
    @test enc(data(rows) * mapping(:cap, :share; color=:scheme, dodge=:scheme) * expectation())["xOffset"]["field"] == "scheme"
    # Box plots dodge natively in AoG too.
    @test enc(data(rows) * mapping(:cap, :share; color=:scheme, dodge=:scheme) * visual(BoxPlot))["xOffset"]["field"] == "scheme"
end

@testitem "a mapping keyword that lowers to no Vega-Lite channel is refused" setup=[AoVDodgeFixtures] tags=[:translation, :regression] begin
    # `dodge` on a plot type AoG gives no `dodge` names the spelling it has.
    m = refusal(() -> to_vegalite(data(rows) * mapping(:cap, :share; dodge=:scheme) * visual(Scatter)))
    @test occursin("dodge", m) && occursin("dodge_x", m) && occursin("Scatter", m)
    # A layer without a visual is a scatter, as in AoG.
    @test occursin("on a Scatter layer", refusal(() -> to_vegalite(data(rows) * mapping(:cap, :share; dodge=:scheme))))
    # Two dodges along one axis, as AoG refuses them.
    m = refusal(() -> to_vegalite(data(rows) * mapping(:cap, :share; dodge=:scheme, dodge_x=:scheme) * visual(BarPlot)))
    @test occursin("`dodge` and `dodge_x`", m)
    # Any other keyword Vega-Lite would drop.
    m = refusal(() -> to_vegalite(data(rows) * mapping(:cap, :share; alpha=:share) * visual(Scatter)))
    @test occursin("alpha", m) && occursin("no Vega-Lite encoding channel", m)
    @test occursin("fillto", refusal(() -> to_vegalite(data(rows) * mapping(:cap, :share; fillto=:share) * visual(Lines))))
    @test occursin("width", refusal(() -> to_vegalite(data(rows) * mapping(:cap; width=:share) * frequency())))

    # Vega-Lite channel names pass as written, and a bar's `fillto` is its base.
    e = enc(data(rows) * mapping(:cap, :share; size=:share, opacity=:share, order=:share, x2=:share) * visual(Scatter))
    @test all(haskey(e, k) for k in ("size", "opacity", "order", "x2"))
    @test haskey(enc(data(rows) * mapping(:cap, :share; fillto=:share) * visual(BarPlot)), "y2")
end

@testitem "every channel AoV lowers to is one Vega-Lite reads" setup=[AoVDodgeFixtures] tags=[:translation] begin
    for ch in values(AlgebraOfVega._CHANNEL_MAP)
        @test isnothing(ch) || ch in AlgebraOfVega._VL_ENCODING_CHANNELS
    end
end
