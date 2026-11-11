using TestItemRunner

"""
A coloured `lineribbon`/`ribbon` paints by kind across its colour groups: every
group's outer band, then each narrower band, then every median line.

Snag `coloured-linerib-16df559b` (decision `05w7kaw`): each group's bands and
line were emitted together, group after group, so wherever two scenarios
overlapped, the later scenario's bands (the 50 % band at 60 % opacity) covered
the earlier scenario's median line and it could not be followed. The groups
keep one filtered layer each (`87465a0`), so within a kind they still paint in
colour order. `sdraw` (one AoG Band layer per band level, then one Lines layer,
each across every group) already painted in this order. The runtime keeps it
when it rebuilds group layers (`test/replace_data.js`, "paint order").
"""
@testitem "a coloured ribbon paints every band below every median line" tags=[:regression, :translation, :tidybayes] begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    import Makie

    days = collect(0.0:0.5:10.0)
    scen = ["Daily", "Twice daily", "Weekly"]
    n = length(days)
    q50 = vcat((days .* 0 .+ k for k in 1:3)...)
    rows = (; day=repeat(days, 3), q50, q2_5=q50 .- 1, q97_5=q50 .+ 1, q25=q50 .- 0.5, q75=q50 .+ 0.5,
        scenario=repeat(scen, inner=n), series=repeat(["PBMC", "CSF"], cld(3n, 2))[1:3n])
    bands = [:q2_5 => :q97_5, :q25 => :q75]
    colour = :scenario => sorter(scen) => "Scenario"

    # The ribbon's group layers as (mark type, band opacity, group), in paint order.
    order(layers) = [(l["mark"]["type"], get(l["mark"], "opacity", nothing), l["_lr_group"])
        for l in layers if get(l, "_lr_layer", false)]
    by_kind(kinds, groups) = [(k..., g) for k in kinds for g in groups]

    # The reporter's shape: two bands and a median line, three scenarios.
    vl = to_vegalite(data(rows) * mapping(:day, :q50; color=colour) * lineribbon(bands=bands))
    @test order(vl["layer"]) == by_kind([("area", 0.2), ("area", 0.6), ("line", nothing)], scen)
    @test all(l -> l["transform"][end]["filter"] == "datum[\"scenario\"] === \"$(l["_lr_group"])\"",
        filter(l -> get(l, "_lr_layer", false), vl["layer"]))

    # Faceted: the same order inside each panel's layer.
    fv = to_vegalite(data(rows) * mapping(:day, :q50; color=colour, row=:series) * lineribbon(bands=bands))
    @test order(fv["spec"]["layer"]) == by_kind([("area", 0.2), ("area", 0.6), ("line", nothing)], scen)

    # Bands only.
    rv = to_vegalite(data(rows) * mapping(:day, :q50; color=colour) * ribbon(bands=bands))
    @test order(rv["layer"]) == by_kind([("area", 0.2), ("area", 0.6)], scen)

    # Raw draws summarized in Julia: three probability levels (more than 12 x
    # values, so the figure has no Ribbons | Intervals view).
    cells = [(x, d, g) for g in ("a", "b") for d in 1:20 for x in 1.0:15.0]
    draws = (; x=first.(cells), y=[x + d / 10 for (x, d, _) in cells], draw=getindex.(cells, 2), g=last.(cells))
    dv = to_vegalite(data(draws) * mapping(:x, :y; group=:draw, color=:g) * lineribbon())
    @test order(dv["layer"]) == by_kind([("area", 0.2), ("area", 0.4), ("area", 0.6), ("line", nothing)], ["a", "b"])

    # A group drawn as a single-x glyph keeps its glyph layers after every line
    # (the ribbon drawing fixed as the start: three x values offer the switch).
    single = (; day=[1.0, 2.0, 3.0, 1.0], q50=[1.0, 2.0, 3.0, 5.0], lo=[0.0, 1.0, 2.0, 4.0],
        hi=[2.0, 3.0, 4.0, 6.0], g=["a", "a", "a", "b"])
    sv = to_vegalite(data(single) * mapping(:day, :q50; color=:g) * lineribbon(bands=[:lo => :hi], intervals=false))
    @test [l["mark"]["type"] for l in sv["layer"]] == ["area", "area", "line", "line", "rule", "point"]

    # An uncoloured ribbon is one group: bands, then line, untagged.
    uv = to_vegalite(data(rows) * mapping(:day, :q50) * lineribbon(bands=bands))
    @test [l["mark"]["type"] for l in uv["layer"]] == ["area", "area", "line"]
    @test !any(l -> haskey(l, "_lr_group"), uv["layer"])

    # The static path paints the same order: a Band layer per band level, then
    # Lines, each across every colour group.
    c = AlgebraOfVega._convert_drawable(first(AlgebraOfVega._extract_drawable(
        data(rows) * mapping(:day, :q50; color=colour) * lineribbon(bands=bands))))
    @test [AlgebraOfVega.extract_visual(l).plottype for l in c.layers] == [Makie.Band, Makie.Band, Makie.Lines]
end
