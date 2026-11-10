# `scales(X=(; categories))` / `scales(Y=(; categories))` on a categorical axis, and X/Y scale
# keys that reach only layers drawn with that axis (snag `categorical-y-sc-55ea6237`, reporter
# ProjectPlans). Before the fix `categories` was dropped with "unknown `Y` scale option", so a
# Gantt figure's blank spacer row (a category no layer draws) could not keep its place, and
# `scales(Y=(; domain))` wrote a field-less `"y": {"scale": …}` into a `VLines` rule, which
# Vega-Lite dropped with a console warning.

@testsnippet AoVAxisCategoryRows begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # A blank (zero-width space) spacer row between two groups that no layer draws.
    rows = ["1.1  A", "1.2  B", "\u200b", "2.1  C"]
    steps = (; row=["1.1  A", "1.2  B", "2.1  C"], start=[0.0, 1.0, 2.0], stop=[1.0, 2.0, 4.0],
               group=["g1", "g1", "g2"])
    bars = data(steps) * mapping(:row => "", :stop; fillto=:start, color=:group) *
        visual(BarPlot; direction=:x)
    meet = data((; at=[1.0, 3.0])) * mapping(:at) * visual(VLines)
    ylayers(vl) = [get(l["encoding"], "y", nothing) for l in vl["layer"]]
end

@testitem "Y categories keep a level no layer draws, on the field-bearing categorical y only" setup=[AoVAxisCategoryRows] tags=[:translation, :regression] begin
    vl = to_vegalite((bars + meet) * config(scales=scales(Y=(; categories=rows))))
    bar_y, rule_y = ylayers(vl)
    @test bar_y["field"] == "row" && bar_y["type"] == "nominal"
    @test bar_y["scale"]["domain"] == rows
    @test bar_y["sort"] == rows
    @test isnothing(rule_y)
    # The positional `scales(...)` form lowers the same.
    @test ylayers(to_vegalite(bars + meet, scales(Y=(; categories=rows)))) == ylayers(vl)
    # With a `sorter` in the mapping (AoG's spelling of the order of present values), the
    # categories still add the spacer and agree with the sort. (AoG's own `draw`, so `sdraw`,
    # refuses this pair, since it does not unwrap the sorter's values; the docs say to drop
    # the sorter. vdraw draws it as the reporter wrote it.)
    sorted = data(steps) * mapping(:row => sorter(rows) => "", :stop; fillto=:start) *
        visual(BarPlot; direction=:x)
    sy = ylayers(to_vegalite((sorted + meet) * config(scales=scales(Y=(; categories=rows)))))[1]
    @test sy["scale"]["domain"] == rows && sy["sort"] == rows
    # No "unknown scale option" warning.
    @test_logs to_vegalite((bars + meet) * config(scales=scales(Y=(; categories=rows))))
    # The emitted arrays are fresh: editing one encoding reaches neither the other nor the input.
    push!(bar_y["sort"], "x")
    @test bar_y["scale"]["domain"] == rows && rows == ["1.1  A", "1.2  B", "\u200b", "2.1  C"]

    # X categories on a vertical bar chart, beside a horizontal rule that has no x.
    cols = data(steps) * mapping(:row, :stop) * visual(BarPlot)
    level = data((; at=[2.0])) * mapping(:at) * visual(HLines)
    vx = to_vegalite((cols + level) * config(scales=scales(X=(; categories=rows))))
    @test vx["layer"][1]["encoding"]["x"]["scale"]["domain"] == rows
    @test !haskey(vx["layer"][2]["encoding"], "x")
end

@testitem "X/Y scale keys never give a layer an axis it was not drawn with" setup=[AoVAxisCategoryRows] tags=[:translation, :regression] begin
    for sc in (scales(Y=(; domain=rows)), scales(Y=(; scale=log10, nice=false)))
        @test isnothing(ylayers(to_vegalite((bars + meet) * config(scales=sc)))[2])
    end
    # A Y domain still reaches the field-bearing y, and an X key every x that has a field.
    @test ylayers(to_vegalite((bars + meet) * config(scales=scales(Y=(; domain=rows)))))[1]["scale"]["domain"] == rows
    vx = to_vegalite((bars + meet) * config(scales=scales(X=(; domain=(0, 5)))))
    @test all(l -> collect(l["encoding"]["x"]["scale"]["domain"]) == [0, 5], vx["layer"])
    # A count with no field still takes the scale (frequency()'s y), and so does a datum.
    counted = to_vegalite(data(steps) * mapping(:group) * frequency() * config(scales=scales(Y=(; scale=log10))))
    @test counted["encoding"]["y"]["aggregate"] == "count" && counted["encoding"]["y"]["scale"]["type"] == "log"
    @test AlgebraOfVega._reads_scale(Dict{String,Any}("datum" => 0))
    @test !AlgebraOfVega._reads_scale(Dict{String,Any}("value" => 0))
    # Each layer gets its own scale object, not one shared dict.
    a, b = (l["encoding"]["x"]["scale"] for l in vx["layer"])
    @test a == b && a !== b
end

@testitem "Y categories on a numeric axis, as a function, or with labels" setup=[AoVAxisCategoryRows] tags=[:translation, :regression] begin
    # AlgebraOfGraphics rejects `categories` on a continuous scale; so does vdraw, naming the field.
    numeric = data(steps) * mapping(:start, :stop) * visual(Scatter)
    err = try to_vegalite(numeric * config(scales=scales(Y=(; categories=[1.0, 2.0])))); nothing catch e; e end
    @test err isa ArgumentError && occursin("`stop`", err.msg) && occursin("nonnumeric", err.msg)
    # A figure without that axis's field (a picker state, a lone rule) is left alone.
    @test !haskey(to_vegalite(meet * config(scales=scales(Y=(; categories=rows))))["encoding"], "y")
    # A function cannot be applied to the data on the Vega-Lite path yet: say so, do not crash.
    err = try to_vegalite(bars * config(scales=scales(Y=(; categories=reverse)))); nothing catch e; e end
    @test err isa ArgumentError && occursin("function", err.msg)
    # `value => label` pairs contribute their values; a differing label warns that it is not drawn.
    labelled = scales(Y=(; categories=["1.1  A" => "A", "1.2  B", "\u200b", "2.1  C" => "2.1  C"]))
    vl = @test_logs (:warn, r"category labels") to_vegalite(bars * config(scales=labelled))
    @test vl["encoding"]["y"]["scale"]["domain"] == rows
end
