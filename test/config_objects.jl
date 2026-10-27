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
    @test !haskey(x["scale"], "zero")           # a log scale takes no zero default (snag `log-scale-zero-w-7b997a94`)
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

# Successive config terms merge their object-valued properties instead of the
# later term replacing the earlier one wholesale: a chart composed as
# `spec * config(config=…legend/mark…) * config(config=…locale/axisX…)` kept only
# the second raw config, so the legend moved back to the right and the pointer
# cursor disappeared (snag `composed-a-chart-b50ca220`). The same held for the
# AoG-mirror `facet`, `axis` and `scales` properties; only `encoding` merged.
@testitem "successive config(config=…) terms deep-merge" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :regression] begin
    styled = config(config = Dict("legend" => Dict("orient" => "bottom", "titleLimit" => 0),
                                  "mark" => Dict("cursor" => "pointer")))
    shared = config(config = Dict("locale" => Dict("number" => Dict("decimal" => ",")),
                                  "axisX" => Dict("labelAngle" => 0)))
    vl = to_vegalite(base * styled * shared)
    @test vl["config"]["legend"]["orient"] == "bottom"
    @test vl["config"]["legend"]["titleLimit"] == 0
    @test vl["config"]["mark"]["cursor"] == "pointer"
    @test vl["config"]["locale"]["number"]["decimal"] == ","
    @test vl["config"]["axisX"]["labelAngle"] == 0
    for guide in ("legend", "axis", "header")   # AoV's no-truncate defaults survive
        @test vl["config"][guide]["labelLimit"] == 0
    end
    # Exactly one config term carrying both objects.
    @test vl == to_vegalite(base * config(config = Dict(
        "legend" => Dict("orient" => "bottom", "titleLimit" => 0),
        "mark" => Dict("cursor" => "pointer"),
        "locale" => Dict("number" => Dict("decimal" => ",")),
        "axisX" => Dict("labelAngle" => 0))))
    # The later term wins a conflicting key; sibling keys of the earlier term stay.
    later = to_vegalite(base * styled * config(config = (; legend = (; orient = "top"))))
    @test later["config"]["legend"]["orient"] == "top"
    @test later["config"]["legend"]["titleLimit"] == 0
    # `config(…) * spec`: the spec's own config comes later, so it wins.
    left = to_vegalite(config(config = (; legend = (; orient = "top"))) * (base * styled))
    @test left["config"]["legend"]["orient"] == "bottom"
    # A `+` sum merges its summands' raw configs the same way.
    lines = data(rows) * mapping(:x, :y) * visual(Lines)
    summed = to_vegalite((base * styled) + (lines * shared))
    @test summed["config"]["mark"]["cursor"] == "pointer"
    @test summed["config"]["axisX"]["labelAngle"] == 0
    # Merging leaves both terms as they were: each still lowers alone.
    @test to_vegalite(base * styled)["config"]["legend"] ==
        Dict("orient" => "bottom", "titleLimit" => 0, "labelLimit" => 0)
    @test !haskey(to_vegalite(base * shared)["config"], "mark")
end

@testitem "successive facet, axis and scales terms merge" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :regression] begin
    faceted = data(rows) * mapping(:x, :y; col=:group) * visual(Scatter)
    linked = to_vegalite(faceted * config(facet = (; linkxaxes = :none)) *
        config(facet = (; linkyaxes = :none)))
    @test linked["resolve"]["scale"] == Dict("x" => "independent", "y" => "independent")
    limited = to_vegalite(base * config(axis = (; limits = ((1, 100), nothing))) *
        config(axis = (; clamp = true)))
    @test limited["encoding"]["x"]["scale"]["domain"] == [1, 100]
    @test limited["encoding"]["x"]["scale"]["clamp"] == true
    coloured = data(rows) * mapping(:x, :y; color=:group) * visual(Scatter)
    palette = config(scales = scales(Color = (; palette = ["red", "blue"], categories = ["a", "b"])))
    vl = to_vegalite(coloured * config(scales = scales(Y = (; scale = log10))) * palette *
        config(scales = scales(Y = (; nice = false))))
    @test vl["encoding"]["y"]["scale"]["type"] == "log"
    @test vl["encoding"]["y"]["scale"]["nice"] == false
    @test vl["encoding"]["color"]["scale"]["range"] == ["red", "blue"]
    @test vl["encoding"]["color"]["scale"]["domain"] == ["a", "b"]
    # Exactly one `scales(...)` carrying every setting.
    @test vl == to_vegalite(coloured * config(scales = scales(Y = (; scale = log10, nice = false),
        Color = (; palette = ["red", "blue"], categories = ["a", "b"]))))
    # The later term wins a conflicting key.
    relinear = to_vegalite(coloured * config(scales = scales(Y = (; scale = log10))) *
        config(scales = scales(Y = (; scale = identity))))
    @test get(relinear["encoding"]["y"]["scale"], "type", "linear") == "linear"
    # The static path reads the merged settings too.
    kw = AlgebraOfVega._draw_kwargs((faceted * config(facet = (; linkxaxes = :none)) *
        config(facet = (; linkyaxes = :none), scales = scales(Y = (; scale = log10)))).config; faceted=true)
    @test kw.facet == (; linkxaxes = :none, linkyaxes = :none)
    @test kw.scales isa AlgebraOfGraphics.Scales
    @test kw.scales.dict[:Y][:scale] === log10
end

@testitem "non-object config properties take the later term's value" setup=[AoVConfigObjectFixtures] tags=[:translation, :config] begin
    vl = to_vegalite(base * config(width = 100, title = "first", transform = [Dict("filter" => "datum.x > 1")]) *
        config(width = 200, title = "second", transform = [Dict("filter" => "datum.x > 2")]))
    @test vl["width"] == 200
    @test vl["title"] == "second"
    @test vl["transform"] == [Dict("filter" => "datum.x > 2")]
end

# Two configs compose into one, so an app can extend a shared config with its own
# settings and use the result at every `spec * SHARED` call site. Before,
# `SHARED * config(...)` threw `MethodError: no method matching
# *(::AlgebraOfVega.Config, ::AlgebraOfVega.Config)`, so the app copied the shared
# config whole (snag `extend-a-shared-a232bbae`).
@testitem "two configs compose into the config spec * a * b applies" setup=[AoVConfigObjectFixtures] tags=[:translation, :config, :regression] begin
    shared = config(config = Dict("locale" => Dict("number" => Dict("decimal" => ",", "thousands" => ".")),
                                  "axisX" => Dict("labelAngle" => 0)))
    extra = config(config = Dict("axisTemporal" => Dict("format" => "%a %d.%m. %H:%M"),
                                 "legend" => Dict("orient" => "top")))
    extended = shared * extra
    @test extended isa AlgebraOfVega.Config
    vl = to_vegalite(base * extended)
    @test vl == to_vegalite(base * shared * extra)
    @test vl["config"]["locale"]["number"]["decimal"] == ","
    @test vl["config"]["axisX"]["labelAngle"] == 0
    @test vl["config"]["axisTemporal"]["format"] == "%a %d.%m. %H:%M"
    @test vl["config"]["legend"]["orient"] == "top"
    @test vl["config"]["legend"]["labelLimit"] == 0   # AoV's defaults survive
    # Every merged property, and the replaced ones, compose as they do on a spec.
    faceted = data(rows) * mapping(:x, :y; col=:group, color=:group) * visual(Scatter)
    a = config(facet = (; linkxaxes = :none), axis = (; limits = ((1, 100), nothing)),
        scales = scales(Y = (; scale = log10)), encoding = (; tooltip = [(; field=:group)]),
        width = 100, title = "first")
    b = config(facet = (; linkyaxes = :none), axis = (; clamp = true),
        scales = scales(Y = (; nice = false)), encoding = (; y = (; sort = "descending")),
        width = 200)
    @test to_vegalite(faceted * (a * b)) == to_vegalite(faceted * a * b)
    @test to_vegalite((a * b) * faceted) == to_vegalite(faceted * a * b)
    # Grouping does not matter.
    @test to_vegalite(base * ((shared * extra) * a)) == to_vegalite(base * (shared * (extra * a)))
    @test to_vegalite(base * shared * extra * a) == to_vegalite(base * (shared * extra * a))
    # The right one wins a conflicting key; the left one's sibling keys stay.
    tilted = to_vegalite(base * (shared * config(config = (; axisX = (; labelAngle = 45)))))
    @test tilted["config"]["axisX"]["labelAngle"] == 45
    @test tilted["config"]["locale"]["number"]["thousands"] == "."
    # On one summand of a sum it behaves as the two terms would.
    lines = data(rows) * mapping(:x, :y) * visual(Lines)
    @test to_vegalite(base * extended + lines) == to_vegalite(base * shared * extra + lines)
    # Composing leaves both operands as they were.
    @test !haskey(to_vegalite(base * shared)["config"], "axisTemporal")
    @test !haskey(to_vegalite(base * extra)["config"], "locale")
end
