using TestItemRunner

# Error bars drawn with Makie's line attributes. Vega-Lite's `errorbar` is a
# composite mark: it draws a `rule` and optional `ticks` and reads their widths
# from its own `thickness` and `size`, never from `strokeWidth`. AoV lowered
# `visual(Rangebars; linewidth=3.5)` to `strokeWidth`, which Vega-Lite drops
# without a word, so a thick 50 % bar beside a thin 95 % bar drew both at the
# default width, with no warning (snag `aov-rangebars-li-830d8b72`).
@testsnippet AoVErrorbarFixtures begin
    using AlgebraOfVega, JSON

    bars = (; x=[1.0, 2.0, 3.0], lo=[0.5, 1.5, 1.0], hi=[1.5, 2.5, 3.0])
    ranged(; kw...) = data(bars) * mapping(:x, :lo, :hi) * visual(Rangebars; kw...)
    mark(spec) = to_vegalite(spec; interactive=false)["mark"]

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    errorbar_marks(vl) = [u["mark"] for u in units(vl) if AlgebraOfVega._mark_type(u["mark"]) == "errorbar"]
end

@testitem "Errorbars and Rangebars lower Makie's line attributes to the Vega-Lite error bar" setup=[AoVErrorbarFixtures] tags=[:translation, :regression] begin
    # The bar's width is the error bar's `thickness` (the rule's stroke width).
    @test (@test_logs mark(ranged(linewidth=3.5))) == Dict{String,Any}("type" => "errorbar", "thickness" => 3.5)
    @test mark(ranged(strokewidth=2)) == mark(ranged(strokeWidth=2)) == mark(ranged(linewidth=2))
    @test mark(data(bars) * mapping(:x, :lo, :hi) * visual(Errorbars; linewidth=2)) ==
          Dict{String,Any}("type" => "errorbar", "thickness" => 2)

    # Whiskers: Makie draws a `whiskerwidth` × `linewidth` rectangle at both ends
    # of each bar, in the bar's colour and opacity; Vega-Lite's ticks, `size` long.
    @test (@test_logs mark(ranged(linewidth=2, whiskerwidth=8))) == Dict{String,Any}("type" => "errorbar",
        "thickness" => 2, "size" => 8, "ticks" => Dict{String,Any}("opacity" => 1, "color" => "black"))
    # Makie's default `whiskerwidth = 0` draws none, as Vega-Lite's default does.
    @test mark(ranged(whiskerwidth=0)) == "errorbar"
    # A fixed colour or opacity on the mark reaches the ticks, so neither is set over it.
    @test mark(ranged(whiskerwidth=8, color="teal", alpha=0.5)) == Dict{String,Any}("type" => "errorbar",
        "color" => "teal", "opacity" => 0.5, "size" => 8, "ticks" => Dict{String,Any}())
    # A colour mapping wins over the ticks' colour (an encoding beats a mark property).
    mapped = to_vegalite(data((; bars..., g=["a", "b", "a"])) * mapping(:x, :lo, :hi; color=:g) *
        visual(Rangebars; whiskerwidth=8); interactive=false)
    @test mapped["encoding"]["color"]["field"] == "g"
    @test mapped["mark"]["ticks"]["color"] == "black"

    # A dash goes onto the rule: Makie dashes the bar, not the whiskers.
    @test mark(ranged(linestyle=:dash, linewidth=2)) == Dict{String,Any}("type" => "errorbar",
        "thickness" => 2, "rule" => Dict{String,Any}("strokeDash" => [6, 6]))
    @test mark(ranged(linestyle=:solid)) == "errorbar"
    @test mark(ranged(strokeDash=[2, 2])) == Dict{String,Any}("type" => "errorbar",
        "rule" => Dict{String,Any}("strokeDash" => [2, 2]))
    # A Vega-Lite `rule` object beside it keeps both.
    @test mark(ranged(linestyle=:dash, rule=(; strokeCap="round")))["rule"] ==
          Dict{String,Any}("strokeDash" => [6, 6], "strokeCap" => "round")

    # The theme ink still moves onto every drawn part, after the part's own style.
    inked = mark(ranged(color=:ink, linewidth=2, whiskerwidth=6, linestyle=:dot))
    @test inked == Dict{String,Any}("type" => "errorbar", "thickness" => 2, "size" => 6,
        "rule" => Dict{String,Any}("strokeDash" => [2, 4], "style" => ["errorbar-rule", "aov-ink"]),
        "ticks" => Dict{String,Any}("opacity" => 1, "style" => ["errorbar-ticks", "aov-ink"]))

    # The reporter's figure: a thick 50 % interval beside a thin 95 % one, in
    # faceted rows coloured by kind. Only the 50 % layer carries a thickness.
    mc = (; time=repeat(1.0:3.0, 2), q025=fill(1.0, 6), q25=fill(1.5, 6), q75=fill(2.5, 6),
            q975=fill(3.0, 6), method=repeat(["A", "B"]; inner=3), kind=fill("MCMC", 6))
    fig = data(mc) * mapping(:time, :q025, :q975; color=:kind, row=:method) * visual(Rangebars) +
          data(mc) * mapping(:time, :q25, :q75; color=:kind, row=:method) * visual(Rangebars; linewidth=3.5)
    vl = @test_logs to_vegalite(fig)
    @test sort([m isa Dict ? get(m, "thickness", 1) : 1 for m in errorbar_marks(vl)]) == [1, 3.5]
    @test !occursin("strokeWidth", JSON.json(errorbar_marks(vl)))

    # Plain marks keep `strokeWidth` and `strokeDash`.
    @test mark(data(bars) * mapping(:x, :lo) * visual(Lines; linewidth=3, linestyle=:dash)) ==
          Dict{String,Any}("type" => "line", "strokeWidth" => 3, "strokeDash" => [6, 6])

    # The static path keeps the Makie spellings, which Makie draws natively.
    static_attrs = Dict(pairs(AlgebraOfVega.extract_visual(AlgebraOfVega._fix_visual_attrs(
        ranged(linewidth=3.5, whiskerwidth=8, linestyle=:dash))).attributes))
    @test static_attrs[:linewidth] == 3.5 && static_attrs[:whiskerwidth] == 8 && static_attrs[:linestyle] == :dash
end

"""
A composite mark (`errorbar`, `boxplot`, `errorband`) carries only `color`,
`opacity` and `clip` over to the parts it draws, so a mark property it does not
read is dropped by Vega-Lite without a word, although plain marks read it. Such
an attribute is reported, as one with no Vega-Lite counterpart at all is.
"""
@testitem "a composite mark reports the visual attributes it does not read" setup=[AoVErrorbarFixtures] tags=[:translation, :regression] begin
    box = data((; g=repeat(["a", "b"], 5), v=collect(1.0:10.0))) * mapping(:g, :v)
    @test (@test_logs (:warn, r"`visual\(BoxPlot\)` sets `strokewidth` with no counterpart on the Vega-Lite `boxplot` mark") mark(
        box * visual(BoxPlot; strokewidth=2, color="teal"))) == Dict{String,Any}("type" => "boxplot", "color" => "teal")
    @test (@test_logs (:warn, r"`visual\(Rangebars\)` sets `strokecolor` with no counterpart on the Vega-Lite `errorbar` mark") mark(
        ranged(strokecolor="red", linewidth=2))) == Dict{String,Any}("type" => "errorbar", "thickness" => 2)
    # A value Vega-Lite cannot take as a fixed property (one width per bar) is reported too.
    @test (@test_logs (:warn, r"`visual\(Rangebars\)` sets `linewidth`") mark(ranged(linewidth=[1, 2, 3]))) == "errorbar"
    # An attribute with no counterpart anywhere names the composite mark as well.
    @test (@test_logs (:warn, r"`visual\(Rangebars\)` sets `rasterize` with no counterpart on the Vega-Lite `errorbar` mark") mark(
        ranged(rasterize=true, linewidth=2))) == Dict{String,Any}("type" => "errorbar", "thickness" => 2)
    # What the composites read is unchanged: colour, opacity and their own properties.
    @test (@test_logs mark(box * visual(BoxPlot; color="teal", alpha=0.5, extent="min-max"))) ==
          Dict{String,Any}("type" => "boxplot", "color" => "teal", "opacity" => 0.5, "extent" => "min-max")
    # The property sets cover exactly the composite marks AoV knows the parts of.
    @test keys(AlgebraOfVega._COMPOSITE_MARK_PROPERTIES) == AlgebraOfVega._COMPOSITE_MARKS
    @test all(issubset(Symbol.(setdiff(s, ["style"])), AlgebraOfVega._VL_MARK_PROPERTIES)
              for s in values(AlgebraOfVega._COMPOSITE_MARK_PROPERTIES))
end

@testitem "vsave draws error bars at their line width, with Makie's whiskers" setup=[AoVErrorbarFixtures] tags=[:static, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            thin = ranged() * config(width=200, height=100)
            thick = ranged(linewidth=3.5, whiskerwidth=8) * config(width=200, height=100)
            # The stroke width of each bar's line; Vega writes none for its default width.
            function bar_widths(svg)
                bars = [m.match for m in eachmatch(r"<line[^>]*aria-roledescription=\"errorbar\"[^>]*>", read(svg, String))]
                [(w = match(r"stroke-width=\"([\d.]+)\"", b); isnothing(w) ? "default" : w[1]) for b in bars]
            end
            # Each whisker is a rectangle `whiskerwidth` long and `linewidth` thick, as in Makie.
            caps(svg) = [m.match for m in eachmatch(r"h8v3\.5h-8Z\" fill=\"black\" opacity=\"1\"", read(svg, String))]
            @test bar_widths(vsave(thin, joinpath(dir, "thin.svg"))) == fill("default", 3)
            @test isempty(caps(joinpath(dir, "thin.svg")))
            svg = vsave(thick, joinpath(dir, "thick.svg"))
            @test bar_widths(svg) == fill("3.5", 3)
            @test length(caps(svg)) == 6
        end
    end
end
