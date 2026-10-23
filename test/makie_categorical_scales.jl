# `scales(LineStyle=…)` and `scales(Marker=…)`: the categorical scales whose palette AoG
# spells in Makie attribute values (snag `a-map-layer-with-db3ce798`). Before the fix a
# `LineStyle` scale was dropped without a word, so Vega gave the solid pattern to the
# alphabetically first category ("Prüfung empfohlen" < "ohne Hinweis") and a map drew
# the flagged sides solid and the unflagged ones dashed; a `Marker` palette passed Makie
# symbols through as strings Vega has no shape for (`:rect` → "rect").

@testsnippet AoVLineStyleRows begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # Four two-point segments along one latitude; odd segments carry the flag.
    rows = [(; lon=13.0 + i / 100, lat=52.0, g=string(i ÷ 2),
               chk=isodd(i ÷ 2) ? "Prüfung empfohlen" : "ohne Hinweis") for i in 0:7]
    flagged = data(rows) * mapping(:lon, :lat; group=:g, linestyle=:chk => "Hinweis") * visual(Lines)
    flag_scale = scales(LineStyle=(; categories=["ohne Hinweis", "Prüfung empfohlen"], palette=[:solid, :dash]))
end

@testitem "LineStyle scale: categories fix the order, palette the dash pattern of each" setup=[AoVLineStyleRows] tags=[:translation] begin
    enc = to_vegalite(flagged * config(scales=flag_scale))["encoding"]["strokeDash"]
    @test enc["field"] == "chk" && enc["title"] == "Hinweis"
    @test enc["scale"] == Dict{String,Any}("domain" => ["ohne Hinweis", "Prüfung empfohlen"],
                                           "range" => Any[[1, 0], [6, 6]])
    # The positional `scales(...)` form lowers the same.
    @test to_vegalite(flagged, flag_scale)["encoding"]["strokeDash"] == enc

    # Every Makie linestyle symbol converts as the fixed `visual(Lines; linestyle=…)` does;
    # `nothing` (Makie's default first entry) is solid and a numeric array passes through.
    palette = [nothing, :dash, :dot, :dashdot, :dashdotdot, [4, 2]]
    got = to_vegalite(flagged * config(scales=scales(LineStyle=(; palette))))["encoding"]["strokeDash"]
    @test got["scale"] == Dict{String,Any}("range" => Any[[1, 0], [6, 6], [2, 4], [6, 6, 2, 6], [6, 6, 2, 4, 2, 6], [4, 2]])
    # `value => label` categories contribute their value, as for `Color`.
    got = to_vegalite(flagged * config(scales=scales(LineStyle=(; categories=["ohne Hinweis" => "ok", "Prüfung empfohlen" => "prüfen"]))))
    @test got["encoding"]["strokeDash"]["scale"] == Dict{String,Any}("domain" => ["ohne Hinweis", "Prüfung empfohlen"])

    # The emitted arrays are fresh: editing the spec does not reach the fixed-attribute table.
    out = to_vegalite(flagged * config(scales=flag_scale))
    push!(out["encoding"]["strokeDash"]["scale"]["range"][2], 99)
    @test AlgebraOfVega._LINESTYLE_DASH[:dash] == [6, 6]

    # Only field-bearing strokeDash encodings take the scale; a layer without one is untouched.
    pts = data(rows) * mapping(:lon, :lat) * visual(Scatter)
    vl = to_vegalite((flagged + pts) * config(scales=flag_scale))
    @test vl["layer"][1]["encoding"]["strokeDash"]["scale"]["range"] == Any[[1, 0], [6, 6]]
    @test !haskey(vl["layer"][2]["encoding"], "strokeDash")
    # A figure with no linestyle mapping is left alone.
    @test !haskey(to_vegalite(pts * config(scales=flag_scale))["encoding"], "strokeDash")
end

@testitem "LineStyle scale: the map-series flag beside a numeric colour scale" setup=[AoVGeoshapeMapFixtures] tags=[:translation, :geoshape] begin
    # The consumer shape of the snag: polygons plus segment lines coloured by a measure and
    # dashed by a flag, with one `scales(...)` carrying both the colour and the line style.
    segs = (; seg=["a", "a", "b", "b"], lon=[10.2, 10.8, 11.2, 11.8], lat=[54.5, 54.5, 54.4, 54.6],
            demand=[3.0, 3.0, 8.0, 8.0], check=["ohne Hinweis", "ohne Hinweis", "Prüfung empfohlen", "Prüfung empfohlen"])
    lines = data(segs) * mapping(:lon, :lat; group=:seg, color=:demand => "Demand",
                                 linestyle=:check => "Hinweis") * visual(Lines; linewidth=2.5)
    sc = scales(Color=(; colormap=:viridis, colorrange=(0, 10)),
                LineStyle=(; categories=["ohne Hinweis", "Prüfung empfohlen"], palette=[:solid, :dash]))
    geo, ln = to_vegalite(kreis_map + lines, sc)["layer"]
    @test haskey(ln["encoding"], "longitude")
    @test ln["encoding"]["strokeDash"]["scale"] == Dict{String,Any}(
        "domain" => ["ohne Hinweis", "Prüfung empfohlen"], "range" => Any[[1, 0], [6, 6]])
    @test ln["encoding"]["color"]["scale"]["domain"] == [0, 10]
    @test !haskey(geo["encoding"], "strokeDash")
end

@testitem "Marker scale: a palette of Makie marker symbols becomes Vega shapes" setup=[AoVLineStyleRows] tags=[:translation] begin
    pts = data(rows) * mapping(:lon, :lat; marker=:chk) * visual(Scatter)
    sc = scales(Marker=(; categories=["ohne Hinweis", "Prüfung empfohlen"], palette=[:rect, :utriangle]))
    @test to_vegalite(pts, sc)["encoding"]["shape"]["scale"] == Dict{String,Any}(
        "domain" => ["ohne Hinweis", "Prüfung empfohlen"], "range" => Any["square", "triangle-up"])
    # Vega shape names (the documented spelling) pass through unchanged.
    sc = scales(Marker=(; palette=["circle", "diamond"]))
    @test to_vegalite(pts, sc)["encoding"]["shape"]["scale"] == Dict{String,Any}("range" => Any["circle", "diamond"])
end

@testitem "Marker/LineStyle scale keys: AoG's unknown keys refused, guide keys warn" setup=[AoVLineStyleRows] tags=[:translation] begin
    pts = data(rows) * mapping(:lon, :lat; marker=:chk) * visual(Scatter)
    # refused: AlgebraOfGraphics rejects an attribute its categorical scale does not have
    # (`Unknown scale attribute :colormap for categorical scale`), so `sdraw` fails on it too.
    err = try to_vegalite(flagged, scales(LineStyle=(; colormap=:viridis))); nothing catch e; e end
    @test err isa ArgumentError && occursin("`LineStyle` scale attribute `colormap`", err.msg)
    @test_throws ArgumentError to_vegalite(pts, scales(Marker=(; colormap=:viridis)))
    # AoG's guide keys are valid there but not lowered yet: a warning, and the rest applies.
    got = @test_logs (:warn, r"`LineStyle` scale attribute `legend` is not lowered") to_vegalite(
        flagged, scales(LineStyle=(; legend=false, palette=[:dash])))
    @test got["encoding"]["strokeDash"]["scale"] == Dict{String,Any}("range" => Any[[6, 6]])
end

@testitem "LineStyle scale: a palette entry Makie has no line style for is refused" setup=[AoVLineStyleRows] tags=[:translation] begin
    # refused: Makie itself rejects an unknown linestyle symbol (`Unknown line style: dashed`),
    # so the entry has no meaning to lower; Vega would draw it solid without a word.
    err = try to_vegalite(flagged, scales(LineStyle=(; palette=[:solid, :dashed]))); nothing catch e; e end
    @test err isa ArgumentError && occursin(":dashed", err.msg)
end

@testitem "LineStyle scale: vsave draws each category in its palette pattern" setup=[AoVLineStyleRows] tags=[:static, :vsave] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        # Vega's own SVG: one path per segment, left to right; segments 0 and 2 carry
        # "ohne Hinweis" (solid), 1 and 3 "Prüfung empfohlen" (dashed).
        dashes(svg) = [m[2] for m in sort!(collect(eachmatch(
            r"d=\"M([0-9.]+),[0-9.]+L[^\"]*\"[^>]*stroke-dasharray=\"([^\"]*)\"", svg)); by=m -> parse(Float64, m[1]))]
        mktempdir() do dir
            path = vsave(flagged * config(scales=flag_scale), joinpath(dir, "flags.svg"))
            @test dashes(read(path, String)) == ["1,0", "6,6", "1,0", "6,6"]
            # Fewer palette entries than categories repeat from the start, as in AoG.
            rows3 = [(; x=i, y=0.0, g=string(i ÷ 2), c=("a", "b", "c")[i ÷ 2 + 1]) for i in 0:5]
            three = data(rows3) * mapping(:x, :y; group=:g, linestyle=:c) * visual(Lines)
            path = vsave(three, scales(LineStyle=(; categories=["a", "b", "c"], palette=[:dash, :dot])),
                         joinpath(dir, "three.svg"))
            @test dashes(read(path, String)) == ["6,6", "2,4", "6,6"]
        end
    end
end
