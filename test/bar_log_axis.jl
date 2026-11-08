using TestItemRunner

# Bars on a log value axis. Vega-Lite stacks bars from zero, so the stack's 0
# entered the log domain and every bar's position became NaN: the figure showed
# axes and labels but no bars, with no warning (snag `aov-barplot-on-l-bfd0ef74`,
# a horizontal cost panel over 8e-6 … 8.6 s). Makie starts such bars at half the
# smallest positive value (`smart_log_fillto`), and so does AoV now. The same
# snag found `visual(BarPlot; direction=:x)` ignored and `fillto=` not lowered.
@testsnippet AoVBarLogFixtures begin
    using AlgebraOfVega, JSON

    cost = (; method=["a", "b", "c"], seconds=[8e-6, 3e-4, 8.6], lo=[1e-6, 1e-4, 1.0])
    logx = config(scales=scales(X=(; scale=log10)))
    logy = config(scales=scales(Y=(; scale=log10)))
    hbars = data(cost) * mapping(:method => "", :seconds => "s") * visual(BarPlot; direction=:x)
    vbars = data(cost) * mapping(:method => "", :seconds => "s") * visual(BarPlot)
    panels = (; m=repeat(["a", "b", "c"], 2), p=repeat(["P1", "P2"]; inner=3),
              v=[1.0, 10.0, 100.0, 1000.0, 2000.0, 4000.0])

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    bar_units(vl) = filter(u -> AlgebraOfVega._mark_type(u["mark"]) == "bar", units(vl))
    base_transform(u) = filter(t -> haskey(t, "joinaggregate"), get(u, "transform", Any[]))

    have_vl_convert() = !isnothing(Sys.which("vl-convert")) || haskey(ENV, "AOV_VL_CONVERT")
    # Each bar of a `vsave` SVG as (x, y, width, height): Vega writes a bar as
    # `M x,y h w v h h -w Z`.
    function svg_bars(path)
        num = raw"(-?[\d.]+(?:e-?\d+)?)"
        re = Regex("aria-roledescription=\"bar\" d=\"M$num,$(num)h$(num)v$(num)h")
        [parse.(Float64, Tuple(m.captures)) for m in eachmatch(re, read(path, String))]
    end
end

@testitem "bars on a log axis start at half the smallest value, per panel" setup=[AoVBarLogFixtures] tags=[:translation, :config, :regression] begin
    vl = to_vegalite(hbars * logx)
    @test vl["mark"] == Dict("type" => "bar", "orient" => "horizontal")
    @test vl["encoding"]["x"]["field"] == "seconds" && vl["encoding"]["y"]["field"] == "method"
    @test vl["encoding"]["x2"] == Dict("field" => "__aov_fillto")
    @test vl["transform"] == [
        Dict("filter" => "isValid(datum[\"seconds\"]) && datum[\"seconds\"] > 0"),
        Dict("calculate" => "datum[\"seconds\"] / 2", "as" => "__aov_fillto_half"),
        Dict("joinaggregate" => [Dict("op" => "min", "field" => "__aov_fillto_half", "as" => "__aov_fillto")],
             "groupby" => Any[])]
    # Vertical bars take the base on y2.
    vl = to_vegalite(vbars * logy)
    @test vl["encoding"]["y2"] == Dict("field" => "__aov_fillto") && !haskey(vl["encoding"], "x2")

    # A unit faceted through its own encoding groups by its facet field; in a
    # facet operator Vega-Lite adds them to the empty groupby itself.
    vl = to_vegalite(data(panels) * mapping(:m, :v; col=:p) * visual(BarPlot) * logy)
    @test only(base_transform(only(units(vl))))["groupby"] == ["p"]
    vl = to_vegalite((data(panels) * mapping(:m, :v; col=:p) * visual(BarPlot) +
        data(panels) * mapping(:m, :v; col=:p) * visual(Scatter)) * logy)
    @test haskey(vl, "facet")
    @test only(base_transform(only(bar_units(vl))))["groupby"] == Any[]
    @test all(u -> !haskey(u["encoding"], "y2"), filter(u -> u ∉ bar_units(vl), units(vl)))

    # A bar the caller based or stacked keeps it; a linear axis is unchanged.
    for vl in (to_vegalite(vbars * visual(; fillto=1e-6) * logy),
               to_vegalite(vbars * logy * config(encoding=Dict("y" => Dict("stack" => "zero")))),
               to_vegalite(vbars), to_vegalite(data(cost) * mapping(:seconds, :method) * visual(BarPlot)))
        @test isempty(base_transform(only(units(vl))))
    end
    @test !haskey(to_vegalite(vbars)["encoding"], "y2")
    # Aggregated bars carry no value field to read (follow-up in the snag's decision).
    @test isempty(base_transform(only(units(to_vegalite(
        data(cost) * mapping(:method) * frequency() * logy)))))
end

@testitem "visual(BarPlot): direction and fillto lower as in AlgebraOfGraphics" setup=[AoVBarLogFixtures] tags=[:translation, :regression] begin
    # Both are read, so neither is reported as ignored.
    @test_logs to_vegalite(data(cost) * mapping(:method, :seconds) *
        visual(BarPlot; direction=:x, fillto=1e-6) * logx)
    # direction=:x: the first positional stands on y, the second reaches along x.
    enc = to_vegalite(hbars)["encoding"]
    @test (enc["y"]["field"], enc["x"]["field"]) == ("method", "seconds")
    # A lone positional is the bars' length, on x.
    vl = to_vegalite(data(cost) * mapping(:seconds) * visual(BarPlot; direction=:x))
    @test vl["encoding"]["x"]["field"] == "seconds" && !haskey(vl["encoding"], "y")
    # Without a direction the output is what it was.
    @test to_vegalite(vbars)["mark"] == "bar"
    @test to_vegalite(data(cost) * mapping(:seconds, :method) * visual(BarPlot))["encoding"]["x"]["field"] == "seconds"

    # Written the other way round, AoG draws the categories' positions as the bar
    # lengths: refused with the spelling that draws the bars.
    err = try
        to_vegalite(data(cost) * mapping(:seconds => "s", :method => "") * visual(BarPlot; direction=:x) * logx)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("mapping(:method, :seconds) * visual(BarPlot; direction=:x)", sprint(showerror, err))
    @test_throws ArgumentError to_vegalite(data(cost) * mapping(:method, :seconds) * visual(BarPlot; direction=:z))

    # fillto: a number is every bar's base (x2/y2 datum), a mapped column each bar's.
    @test to_vegalite(vbars * visual(; fillto=1.0))["encoding"]["y2"] == Dict("datum" => 1.0)
    @test to_vegalite(data(cost) * mapping(:method, :seconds) * visual(BarPlot; direction=:x, fillto=2))["encoding"]["x2"] ==
        Dict("datum" => 2)
    enc = to_vegalite(data(cost) * mapping(:method, :seconds; fillto=:lo) * visual(BarPlot; direction=:x))["encoding"]
    @test enc["x2"]["field"] == "lo" && !haskey(enc, "fillto")
    # A mapped fillto wins over a fixed one; a vector has no spelling and is reported.
    enc = to_vegalite(data(cost) * mapping(:method, :seconds; fillto=:lo) * visual(BarPlot; fillto=1.0))["encoding"]
    @test enc["y2"]["field"] == "lo"
    vl = @test_logs (:warn, r"fillto") to_vegalite(vbars * visual(; fillto=[1, 2, 3]))
    @test !haskey(vl["encoding"], "y2")
end

@testitem "vsave: log-axis bars are drawn, from Makie's base" setup=[AoVBarLogFixtures] tags=[:static, :vsave, :regression] begin
    if !have_vl_convert()
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            # The reported cost panel (in the AoG spelling): three bars, each
            # from the same x, reaching further for a larger value.
            bars = svg_bars(vsave(hbars * config(width=340, height=70) * logx, joinpath(dir, "h.svg")))
            @test length(bars) == 3
            @test all(b -> b[3] > 0, bars) && allequal(b[1] for b in bars)
            @test issorted([b[3] for b in bars])
            # The smallest bar runs from half its value to its value: log10(2)
            # of the 7 decades the axis shows (1e-6 … 10 after `nice`).
            @test bars[1][3] / 340 ≈ log10(2) / 7 atol=0.005

            # A zero (counts) is left out instead of putting 0 into the domain.
            z = (; m=["a", "b", "c"], v=[0.0, 10.0, 1000.0])
            bars = svg_bars(vsave(data(z) * mapping(:m, :v) * visual(BarPlot) * logy, joinpath(dir, "z.svg")))
            @test length(bars) == 2 && all(b -> b[4] > 0, bars)

            # A layered facet compiles (Vega-Lite 5.23 refuses a facet child's
            # joinaggregate without `groupby`), and each panel has its own base.
            fig = (data(panels) * mapping(:m, :v; col=:p) * visual(BarPlot) +
                data(panels) * mapping(:m, :v; col=:p) * visual(Scatter)) * logy
            bars = svg_bars(vsave(fig, joinpath(dir, "f.svg")))
            @test length(bars) == 6 && all(b -> b[4] > 0, bars)
            bottoms = [b[2] + b[4] for b in bars]
            @test allequal(bottoms[1:3]) && allequal(bottoms[4:6]) && bottoms[1] != bottoms[4]
        end
    end
end
