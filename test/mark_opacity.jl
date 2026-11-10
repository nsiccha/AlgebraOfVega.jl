using TestItemRunner

# `fillOpacity` and `strokeOpacity` are Vega-Lite mark properties that fade one
# side of a mark; `opacity` (Makie's `alpha`) fades the whole mark, outline
# included. AoV folded `fillOpacity` into `opacity`, so
# `visual(BarPlot; fillOpacity=0, stroke="red", strokeWidth=2)` drew no frame at
# all, and a map background at `fillOpacity=0.08` drew its borders at 8 %, with
# no warning (snag `aov-fillopacity-893e8d27`).
@testsnippet AoVMarkOpacityFixtures begin
    using AlgebraOfVega, JSON

    plan = (; row=["a", "b"], start=[1.0, 2.0], stop=[3.0, 5.0])
    planned(; kw...) = data(plan) * mapping(:row, :stop; fillto=:start) *
        visual(BarPlot; direction=:x, kw...)
    mark(spec) = to_vegalite(spec; interactive=false)["mark"]
end

@testitem "fillOpacity and strokeOpacity pass as written; alpha and opacity fade the whole mark" setup=[AoVMarkOpacityFixtures] tags=[:translation, :regression] begin
    # The reporter's outline-only bar: the fill is transparent, the frame is drawn.
    m = @test_logs mark(planned(fillOpacity=0, stroke="red", strokeWidth=2))
    @test m == Dict{String,Any}("type" => "bar", "orient" => "horizontal",
        "fillOpacity" => 0, "stroke" => "red", "strokeWidth" => 2)
    m = @test_logs mark(planned(strokeOpacity=0.5, stroke="red"))
    @test m["strokeOpacity"] == 0.5 && !haskey(m, "opacity")

    # Makie's `alpha` fades a bar's outline with its fill (Makie's `poly` passes
    # it to both), as Vega-Lite's `opacity` does.
    @test mark(planned(alpha=0.3))["opacity"] == 0.3
    @test mark(planned(opacity=0.3))["opacity"] == 0.3
    # Each keeps its own meaning beside the others.
    m = mark(planned(alpha=0.5, fillOpacity=0.2, strokeOpacity=0.8, stroke="red"))
    @test (m["opacity"], m["fillOpacity"], m["strokeOpacity"]) == (0.5, 0.2, 0.8)

    # A map background in the theme ink at a faint fill, with full borders.
    geo = Dict("type" => "FeatureCollection", "features" => [Dict("type" => "Feature",
        "properties" => Dict("k" => "A"), "geometry" => Dict("type" => "Polygon",
            "coordinates" => [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]))])
    m = mark(data((; k=["A"])) * mapping(:k) * geoshape(geo) *
        visual(; color=:ink, fillOpacity=0.08, stroke="#9aa5b1", strokeWidth=0.6))
    @test m["fillOpacity"] == 0.08 && m["stroke"] == "#9aa5b1" && !haskey(m, "opacity")
end

@testitem "vsave draws an outline-only bar's frame" setup=[AoVMarkOpacityFixtures] tags=[:static, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            bars(svg) = [m.match for m in eachmatch(r"<path[^>]*aria-roledescription=\"bar\"[^>]*>", read(svg, String))]
            svg = vsave(planned(fillOpacity=0, stroke="red", strokeWidth=2) * config(width=200, height=100),
                joinpath(dir, "frame.svg"))
            drawn = bars(svg)
            @test length(drawn) == 2
            @test all(b -> occursin("stroke=\"red\"", b) && occursin("fill-opacity=\"0\"", b) &&
                           !occursin(" opacity=\"0\"", b), drawn)
        end
    end
end
