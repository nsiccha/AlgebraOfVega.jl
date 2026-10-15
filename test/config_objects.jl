using TestItemRunner

# `config(encoding=…)` and `config(config=…)` deep-merge into the Vega-Lite
# object AoV generated. Both take a Dict or the equivalent NamedTuple spelling
# (the FAQ's `encoding = (; x = (; scale = (; type = "log")))`). Before, only a
# Dict was merged: a NamedTuple encoding replaced the generated encoding and a
# later pass threw a `MethodError` on it, and a NamedTuple `config` replaced
# AoV's default Vega-Lite config, silently dropping its `labelLimit=0` defaults
# (todo `0wqszhg`, decision `1a16qo7`).
@testsnippet AoVConfigObjectFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    rows = (; x=[1.0, 10.0, 100.0], y=[1.0, 2.0, 3.0], group=["a", "b", "b"])
    base = data(rows) * mapping(:x, :y) * visual(Scatter)
    tooltip_fields(enc) = [t["field"] for t in enc["tooltip"]]
end

@testitem "NamedTuple config(encoding=…) deep-merges like the Dict spelling" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :regression] begin
    # The FAQ example, verbatim apart from the data.
    nt = config(encoding = (;
        x = (; scale = (; type = "log")),
        tooltip = [(; field=:x), (; field=:y), (; field=:group)],
    ))
    vl = to_vegalite(base * nt)
    x = vl["encoding"]["x"]
    @test x["field"] == "x"                     # generated channel kept
    @test x["scale"]["type"] == "log"           # override merged into it
    @test x["scale"]["zero"] == false           # AoV's default survives the merge
    @test tooltip_fields(vl["encoding"]) == ["x", "y", "group"]
    # Exactly what the Dict spelling produces.
    dict = config(encoding = Dict(
        "x" => Dict("scale" => Dict("type" => "log")),
        "tooltip" => [Dict("field" => "x"), Dict("field" => "y"), Dict("field" => "group")],
    ))
    @test vl == to_vegalite(base * dict)
    @test to_json(base * nt) == to_json(base * dict)
end

@testitem "NamedTuple encodings merge across terms and scope to their summand" setup=[AoVConfigObjectFixtures] tags=[:translation, :config] begin
    # Successive terms merge channel by channel, as with Dicts.
    vl = to_vegalite(base * config(encoding = (; tooltip = [(; field=:group)])) *
        config(encoding = (; y = (; sort = "descending"))))
    @test tooltip_fields(vl["encoding"]) == ["group"]
    @test vl["encoding"]["y"]["sort"] == "descending"
    # A summand's override stays on that summand's layer.
    lines = data(rows) * mapping(:x, :y) * visual(Lines)
    layered = to_vegalite(base * config(encoding = (; tooltip = [(; field=:group)])) + lines)
    a, b = layered["layer"]
    @test tooltip_fields(a["encoding"]) == ["group"]
    @test tooltip_fields(b["encoding"]) == ["x", "y"]   # AoV's automatic tooltip
end

@testitem "a NamedTuple log scale reaches the static axis" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :static] begin
    # `sdraw` reads `scale.type == "log"`; a Symbol value lowers to that string.
    cfg = config(encoding = (; y = (; scale = (; type = :log))))
    @test AlgebraOfVega._draw_kwargs(cfg).axis.yscale === log10
    @test to_vegalite(base * cfg)["encoding"]["y"]["scale"]["type"] == "log"
end

@testitem "NamedTuple config(config=…) merges into AoV's defaults" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :regression] begin
    vl = to_vegalite(base * config(config = (; legend = (; orient = "top"))))
    @test vl["config"]["legend"]["orient"] == "top"
    # The no-truncate defaults are still there.
    for guide in ("legend", "axis", "header")
        @test vl["config"][guide]["labelLimit"] == 0
    end
    @test vl == to_vegalite(base * config(config = Dict("legend" => Dict("orient" => "top"))))
end

@testitem "config rejects an encoding or config that is not an object" setup=[AoVConfigObjectFixtures] tags=[:config] begin
    # refused: a non-object value would replace the generated Vega-Lite object
    # wholesale and fail later or silently (dev §1; decision `1a16qo7`).
    @test_throws ArgumentError config(encoding = "x")
    @test_throws ArgumentError config(encoding = nothing)
    @test_throws ArgumentError config(config = [1, 2])
    @test_throws ArgumentError vlspec(base; encoding = :x)
end

@testitem "rendering never aliases the caller's or the config's values" setup=[AoVConfigObjectFixtures] tags=[:config] begin
    caller = Dict("tooltip" => Any[Dict("field" => "x")])
    raw = Dict("legend" => Dict("symbolType" => Any["circle"]))
    spec = base * config(encoding = caller, config = raw)
    vl = to_vegalite(spec)
    push!(vl["encoding"]["tooltip"], Dict("field" => "y"))
    push!(vl["config"]["legend"]["symbolType"], "square")
    @test caller == Dict("tooltip" => Any[Dict("field" => "x")])
    @test raw == Dict("legend" => Dict("symbolType" => Any["circle"]))
    again = to_vegalite(spec)
    @test tooltip_fields(again["encoding"]) == ["x"]
    @test again["config"]["legend"]["symbolType"] == ["circle"]
end
