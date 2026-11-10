using TestItemRunner

# Makie's `VSpan`/`HSpan` (AoG `visual(VSpan)`): a band between two values on one
# axis, across the whole other axis. AoV had no lowering for them, so a figure with
# report-window bands over a nominal-y schedule failed `Unsupported plot type for
# Vega-Lite: Makie.VSpan`, and the consumer prepended a hand-written Vega-Lite rect
# layer (snag `aov-vspan-hspan-3522a3cf`).
@testsnippet AoVSpanFixtures begin
    using AlgebraOfVega, JSON
    import Makie

    windows = (; from=[5.5, 11.5], to=[6.0, 12.0])
    steps = (; x=[1.0, 8.0, 13.0], row=["plan", "build", "report"])
    vspans(; kw...) = data(windows) * mapping(:from, :to) * visual(VSpan; kw...)
    hspans(; kw...) = data((; lo=[2.0], hi=[4.0])) * mapping(:lo, :hi) * visual(HSpan; kw...)
    schedule = vspans(color="grey", alpha=0.3) + data(steps) * mapping(:x, :row) * visual(Scatter)

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    rect_units(vl) = [u for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == "rect"]
end

@testitem "VSpan and HSpan lower to a Vega-Lite rect on one axis" setup=[AoVSpanFixtures] tags=[:translation, :regression] begin
    # The reporter's figure: bands over a schedule whose y axis is nominal.
    vl = to_vegalite(schedule)
    span = only(rect_units(vl))
    @test span["mark"] == Dict{String,Any}("type" => "rect", "color" => "grey", "opacity" => 0.3)
    enc = span["encoding"]
    # AoV's no-zero default holds: Makie's span limits are its edges, not 0.
    @test enc["x"] == Dict{String,Any}("field" => "from", "type" => "quantitative",
        "scale" => Dict{String,Any}("zero" => false))
    @test enc["x2"]["field"] == "to"
    # No y: Vega-Lite draws the rect over the whole plot height, nominal y or not.
    @test !haskey(enc, "y") && !haskey(enc, "y2")
    # The tooltip names both edges.
    @test [t["field"] for t in enc["tooltip"]] == ["from", "to"]
    # The scatter layer keeps its own nominal y.
    pts = only(u for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == "point")
    @test pts["encoding"]["y"] == Dict{String,Any}("field" => "row", "type" => "nominal")

    # HSpan: both positionals are y, no x.
    enc = only(rect_units(to_vegalite(hspans())))["encoding"]
    @test enc["y"]["field"] == "lo" && enc["y"]["type"] == "quantitative"
    @test enc["y2"]["field"] == "hi"
    @test !haskey(enc, "x") && !haskey(enc, "x2")

    # Makie's poly attributes lower as on any plain mark; a colour mapping is an encoding.
    @test only(rect_units(to_vegalite(vspans(strokecolor="black", strokewidth=2))))["mark"] ==
          Dict{String,Any}("type" => "rect", "stroke" => "black", "strokeWidth" => 2)
    mapped = data((; windows..., kind=["review", "report"])) * mapping(:from, :to; color=:kind) * visual(VSpan)
    @test only(rect_units(to_vegalite(mapped)))["encoding"]["color"]["field"] == "kind"
    # Dates are temporal on both edges.
    using Dates: Date
    dated = data((; a=[Date(2026, 3, 1)], b=[Date(2026, 4, 1)])) * mapping(:a, :b) * visual(VSpan)
    @test only(rect_units(to_vegalite(dated)))["encoding"]["x"]["type"] == "temporal"
end

@testitem "VSpan/HSpan extent: Makie's whole-axis default is silent and adds nothing" setup=[AoVSpanFixtures] tags=[:translation] begin
    # ymin = 0, ymax = 1 is Makie's default, the whole axis, which the rect draws.
    @test (@test_logs only(rect_units(to_vegalite(vspans(ymin=0, ymax=1.0))))["mark"]) == "rect"
    @test (@test_logs only(rect_units(to_vegalite(hspans(xmin=0.0, xmax=1))))["mark"]) == "rect"
    # Any other fraction lowers to the band's own y/y2 (x/x2): test/axis_fractions.jl.
    # The extent names belong to the span on the other axis only.
    @test_logs (:warn, r"`visual\(VSpan\)` sets `xmin`") to_vegalite(vspans(xmin=0))
end

@testitem "VSpan in a faceted figure spans every panel's height" setup=[AoVSpanFixtures] tags=[:translation] begin
    rows = (; x=[1.0, 8.0], row=["a", "b"], p=["P1", "P2"])
    spans = data((; from=[5.5, 5.5], to=[6.0, 6.0], p=["P1", "P2"])) * mapping(:from, :to; col=:p) * visual(VSpan)
    vl = to_vegalite(spans + data(rows) * mapping(:x, :row; col=:p) * visual(Scatter))
    @test vl["facet"]["column"]["field"] == "p"
    enc = only(rect_units(vl))["encoding"]
    @test enc["x"]["field"] == "from" && enc["x2"]["field"] == "to"
    @test !haskey(enc, "y") && !haskey(enc, "column")
end

@testitem "a band drawn first leaves the other layers' axes their zoom and pan" setup=[AoVSpanFixtures] tags=[:translation, :interactive, :regression] begin
    # Vega-Lite projects a zoom/pan selection only on the channels of the unit that
    # defines it, so on the x-only band (drawn first, behind the points) the y axis
    # had none ("Cannot project a selection on encoding channel y, which has no field").
    grid(l) = [p for p in get(l, "params", Any[]) if get(p, "name", "") == "grid"]
    pts = data((; x=[1.0, 8.0], y=[2.0, 5.0])) * mapping(:x, :y) * visual(Scatter)
    vl = to_vegalite(vspans() + pts)
    @test isempty(grid(vl["layer"][1]))
    @test only(grid(vl["layer"][2]))["select"]["encodings"] == ["x", "y"]
    # The same for a VLines rule, and in a faceted figure.
    rules = data((; at=[3.0])) * mapping(:at) * visual(VLines)
    @test only(grid(to_vegalite(rules + pts)["layer"][2]))["select"]["encodings"] == ["x", "y"]
    panel = data((; from=[5.5, 5.5], to=[6.0, 6.0], p=["a", "b"])) * mapping(:from, :to; col=:p) * visual(VSpan) +
        data((; x=[1.0, 8.0], y=[2.0, 5.0], p=["a", "b"])) * mapping(:x, :y; col=:p) * visual(Scatter)
    inner = to_vegalite(panel)["spec"]["layer"]
    @test isempty(grid(inner[1])) && only(grid(inner[2]))["select"]["encodings"] == ["x", "y"]
    # A figure whose first layer encodes every zoomed channel keeps it there.
    vl = to_vegalite(pts + vspans())
    @test only(grid(vl["layer"][1]))["select"]["encodings"] == ["x", "y"] && isempty(grid(vl["layer"][2]))
    # The reporter's figure: y is nominal, so only x zooms, on the band layer.
    @test only(grid(to_vegalite(schedule)["layer"][1]))["select"]["encodings"] == ["x"]
end

@testitem "sdraw! draws VSpan/HSpan with Makie's own span plots" setup=[AoVSpanFixtures] tags=[:static] begin
    fig = Makie.Figure()
    grid = sdraw!(fig[1, 1], schedule + hspans())
    plots = [p for ax in fig.content if ax isa Makie.Axis for p in ax.scene.plots]
    @test count(p -> p isa Makie.VSpan, plots) == 1
    @test count(p -> p isa Makie.HSpan, plots) == 1
end

@testitem "vsave: a VSpan band covers the whole plot height over a nominal y" setup=[AoVSpanFixtures] tags=[:static, :vsave] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(schedule * config(width=300, height=120), joinpath(dir, "spans.svg")), String)
            # Each rect item is a path `M<x>,<y>h<w>v<h>h-<w>Z` in plot coordinates.
            rects = collect(eachmatch(r"aria-roledescription=\"rect mark\" d=\"M([-\d.]+),([-\d.]+)h([-\d.]+)v([-\d.]+)", svg))
            @test length(rects) == 2
            for m in rects
                @test parse(Float64, m[2]) == 0          # from the top of the plot …
                @test parse(Float64, m[4]) == 120        # … over its whole height
            end
            # From 5.5 to 6.0 on the shared x scale: the two bands are equally wide.
            widths = [parse(Float64, m[3]) for m in rects]
            @test widths[1] ≈ widths[2] && widths[1] > 0
        end
    end
end
