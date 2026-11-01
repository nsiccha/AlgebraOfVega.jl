using TestItemRunner

# `a * config(transform=T) + b` runs `T` on `a`'s rows only: `*` binds tighter than
# `+`, exactly as `a * config(encoding=E) + b` scopes `E`. Before, a summand's
# transform went into the one spec-level config, so the later summand's replaced
# the earlier one's, and the survivor was written onto the top of the spec, where
# Vega-Lite runs it only on data a layer inherits. A figure whose layers each carry
# their own data (every layer of a map) therefore lost every transform, without a
# word, and `config(transform=T)` on a lone geoshape or `density()` replaced the
# transform AoV had generated, so the map painted nothing
# (snag `gave-two-layers-0c054233`).
@testsnippet AoVLayerTransformFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    const Makie = AlgebraOfVega.Makie

    # Every Vega-Lite unit (a dict with a `mark`), in emission order.
    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            for child in get(node, key, Any[])
                units(child, out)
            end
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    drop(cond) = Any[Dict("filter" => cond)]
    filters(node) = [t["filter"] for t in get(node, "transform", Any[]) if haskey(t, "filter")]

    rows = (; a=[1.0, 2.0, 3.0], b=[4.0, 5.0, 6.0], x=[1, 2, 3], t=["p", "q", "r"])
    other_rows = (; a=[1.5, 2.5], b=[4.5, 5.5], x=[1, 3], t=["u", "v"])
    points(table=rows) = data(table) * mapping(:a, :b) * visual(Scatter)
    line(table=rows) = data(table) * mapping(:a, :b) * visual(Lines)
    labels(table=rows) = data(table) * mapping(:a, :b; text=:t) * visual(Makie.Text)

    region = Dict{String,Any}("type" => "FeatureCollection", "features" => [Dict{String,Any}(
        "type" => "Feature", "properties" => Dict{String,Any}("k" => "A"),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[0.0, 0.0], [0.0, 8.0], [8.0, 8.0], [8.0, 0.0], [0.0, 0.0]]]))])
    base_map = data((; k=["A"], v=[1.0])) * mapping(:k; color=:v) * geoshape(region)
end

@testitem "each summand keeps its own transform" setup=[AoVLayerTransformFixtures] tags=[:translation, :config] begin
    # The figure of the report: labels with their own filter on a map, where every
    # layer carries its own data.
    vl = to_vegalite(base_map + labels() * config(transform=drop("datum.x > 1")) +
        labels() * config(transform=drop("datum.x > 2")))
    @test !haskey(vl, "transform")
    geo, first_labels, second_labels = vl["layer"]
    @test filters(geo) == String[]
    @test filters(first_labels) == ["datum.x > 1"]
    @test filters(second_labels) == ["datum.x > 2"]

    # A table the layers share: the top-level data stays shared, and the layer
    # without a transform draws every row.
    shared = to_vegalite(points() * config(transform=drop("datum.x > 1")) + line())
    @test haskey(shared, "data") && !haskey(shared, "transform")
    @test filters(shared["layer"][1]) == ["datum.x > 1"]
    @test !haskey(shared["layer"][2], "transform")

    # A summand of several Vega-Lite units covers all of them, as an encoding does.
    bands = data((; g=["A", "B"], m=[0.2, 0.5], lo=[0.1, 0.3], hi=[0.4, 0.7])) *
        mapping(:g, :m) * pointinterval(bands=[:lo => :hi], orientation=:vertical) *
        config(transform=drop("datum.m > 0.3"))
    with_marks = to_vegalite(bands + data((; g=["A"], m=[0.3])) * mapping(:g, :m) * visual(Scatter))
    us = units(with_marks)
    @test length(us) >= 3
    @test all(u -> filters(u) == ["datum.m > 0.3"], us[1:end-1])
    @test filters(us[end]) == String[]
end

@testitem "a whole-figure transform reaches every layer and runs first" setup=[AoVLayerTransformFixtures] tags=[:translation, :config] begin
    # Every layer of a map carries its own data, so a top-level transform reaches none.
    map_vl = to_vegalite((base_map + labels()) * config(transform=drop("datum.x > 1")))
    @test !haskey(map_vl, "transform")
    @test all(u -> filters(u) == ["datum.x > 1"], map_vl["layer"])
    @test haskey(first(map_vl["layer"][1]["transform"]), "filter")
    @test haskey(last(map_vl["layer"][1]["transform"]), "lookup")

    # Shared data stays at the top, and a layer with its own table gets its own copy.
    mixed = to_vegalite((points() + line(other_rows)) * config(transform=drop("datum.x > 1")))
    @test filters(mixed) == ["datum.x > 1"]
    @test !haskey(mixed["layer"][1], "transform")
    @test filters(mixed["layer"][2]) == ["datum.x > 1"]
    @test mixed["transform"][1] !== mixed["layer"][2]["transform"][1]

    # A figure's transform runs before a layer's.
    both = to_vegalite((base_map + labels() * config(transform=drop("datum.x > 2"))) *
        config(transform=drop("datum.x > 1")))
    @test filters(both["layer"][2]) == ["datum.x > 1", "datum.x > 2"]
end

@testitem "a transform keeps what AoV generated" setup=[AoVLayerTransformFixtures] tags=[:translation, :config] begin
    geo = to_vegalite(base_map * config(transform=drop("datum.v > 0")))
    @test filters(geo) == ["datum.v > 0"]
    @test haskey(geo["transform"][2], "lookup")

    dens = to_vegalite(data(rows) * mapping(:a) * AlgebraOfGraphics.density() *
        config(transform=drop("datum.x > 1")))
    @test filters(dens) == ["datum.x > 1"]
    @test haskey(dens["transform"][2], "density")

    # A faceted geoshape keeps its lookup inside the facet, behind the transform.
    years = (; k=["A", "A"], v=[1.0, 2.0], y=["2020", "2021"])
    by_year = data(years) * mapping(:k; color=:v, col=:y) * geoshape(region)
    faceted = to_vegalite(by_year * config(transform=drop("datum.v > 1")))
    @test filters(faceted) == ["datum.v > 1"]
    @test haskey(only(faceted["spec"]["transform"]), "lookup")

    # A faceted map of several layers runs the lookup on the merged rows, and a
    # figure's transform runs ahead of it there too.
    sites = (; k=["A"], v=[2.0], y=["2021"], lon=[4.0], lat=[4.0])
    merged = to_vegalite((by_year + data(sites) * mapping(:lon, :lat; col=:y) * visual(Scatter)) *
        config(transform=drop("datum.v > 1")))
    @test filters(merged) == ["datum.v > 1"]
    @test haskey(merged["transform"][2], "lookup")
end

@testitem "a layer's filter stays behind the facet's row filter" setup=[AoVLayerTransformFixtures] tags=[:translation, :config, :facet] begin
    with_panel(table) = merge(table, (; p=fill("P", length(table.a))))
    vl = to_vegalite(data(with_panel(rows)) * mapping(:a, :b; col=:p) * visual(Scatter) *
        config(transform=drop("datum.x > 1")) +
        data(with_panel(other_rows)) * mapping(:a, :b; col=:p) * visual(Lines))
    a, b = vl["spec"]["layer"]
    @test !haskey(vl, "transform")
    @test occursin("__src", first(filters(a)))
    @test filters(a)[2] == "datum.x > 1"
    @test length(filters(b)) == 1 && occursin("__src", only(filters(b)))
end

@testitem "nested sums and further terms keep transforms on their layers" setup=[AoVLayerTransformFixtures] tags=[:translation, :config] begin
    # A summand's own sum: the transform covers both of its layers, first.
    nested = to_vegalite((points() * config(transform=drop("datum.x > 2")) + line()) *
        config(transform=drop("datum.x > 1")) + labels())
    @test !haskey(nested, "transform")
    a, b, c = nested["layer"]
    @test filters(a) == ["datum.x > 1", "datum.x > 2"]
    @test filters(b) == ["datum.x > 1"]
    @test !haskey(c, "transform")

    # A further term reaches each layer, which keeps its transform.
    further = to_vegalite((data(rows) * mapping(:a, :b) * config(transform=drop("datum.x > 1")) +
        data(rows) * mapping(:a, :b)) * visual(Scatter; color=:red))
    @test filters(further["layer"][1]) == ["datum.x > 1"]
    @test !haskey(further["layer"][2], "transform")

    # A right factor with overrides of its own: as in the expanded expression, its
    # transform comes later and takes the place of the left factor's.
    left = data(rows) * config(transform=drop("left"))
    right = mapping(:a, :b) * visual(Scatter) * config(transform=drop("right")) +
        mapping(:a, :b) * visual(Lines)
    product = to_vegalite(left * right)
    @test [filters(u) for u in product["layer"]] == [["right"], ["left"]]

    # Successive terms on one view keep the later transform, as documented.
    @test filters(to_vegalite(points() * config(transform=drop("first")) *
        config(transform=drop("second")))) == ["second"]
end

@testitem "config(transform=…) is a list AoV owns" setup=[AoVLayerTransformFixtures] tags=[:translation, :config] begin
    # One transform may stand alone, NamedTuple spelling included.
    @test filters(to_vegalite(points() * config(transform=Dict("filter" => "datum.x > 1")))) == ["datum.x > 1"]
    @test filters(to_vegalite(points() * config(transform=(; filter="datum.x > 1")))) == ["datum.x > 1"]
    @test !haskey(to_vegalite(points() * config(transform=nothing)), "transform")
    @test !haskey(to_vegalite(points() * config(transform=Any[]) + line()), "transform")
    @test_throws ArgumentError config(transform="datum.x > 1")

    # A dropdown extends AoV's copy, so the same spec lowers alike every time and
    # the caller's list stays as written.
    list = drop("datum.x > 1")
    spec = data(rows) * mapping(:a, :b) * visual(Scatter) * config(transform=list, select=:t)
    once = to_vegalite(spec)
    twice = to_vegalite(spec)
    @test once["transform"] == twice["transform"]
    @test length(once["transform"]) == 2
    @test length(list) == 1
    @test first(filters(once)) == "datum.x > 1"

    summed = (labels() * config(transform=list) + line()) * config(width=200)
    @test to_vegalite(summed)["layer"][1]["transform"] == to_vegalite(summed)["layer"][1]["transform"]
    @test length(list) == 1
end

@testitem "transforms survive the channel picker, update_spec, cell charts and sdraw" setup=[AoVLayerTransformFixtures] tags=[:translation, :config, :remap] begin
    using HTMXObjects
    table = merge(rows, (; arm=["x", "y", "x"]))
    spec = (data(table) * mapping(:a, :b; color=:arm) * visual(Scatter) *
        config(transform=drop("datum.x > 1")) +
        data(table) * mapping(:a, :b; color=:arm) * visual(Lines)) * config(height=250)
    remap = (; dims=["arm" => "Arm"])

    (; vl) = AlgebraOfVega._auto_remap_lowering(spec; remap...)
    us = units(vl)
    @test count(u -> "datum.x > 1" in filters(u), us) == 1
    html = repr(MIME"text/html"(), update_spec("fig", spec; auto_remap=remap))
    @test occursin("datum.x > 1", html)

    cells = (; site=[1, 1, 2, 2], klasse=["a", "b", "a", "b"], n=[3, 0, 9, 2])
    bars = data(cells) * mapping(:klasse, :n; layout=:site) * visual(BarPlot) *
        config(transform=drop("datum.n > 0"))
    dots = data(cells) * mapping(:klasse, :n; layout=:site) * visual(Scatter)
    column = cell_charts(bars + dots).column
    @test count(u -> "datum.n > 0" in filters(u), units(column.vl)) == 1

    # The static path has no Vega-Lite transforms; it draws every row, as before.
    fig = Makie.Figure()
    @test !isnothing(sdraw!(fig[1, 1], points() * config(transform=drop("datum.x > 1")) + line()))
end

@testitem "per-layer and whole-figure transforms draw the right rows in the browser" tags=[:regression, :browser, :config] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    const Makie = AlgebraOfVega.Makie
    html(x) = sprint(show, MIME"text/html"(), x)
    drop(cond) = Any[Dict("filter" => cond)]
    rows = (; a=[1.0, 2.0, 3.0], b=[4.0, 5.0, 6.0], x=[1, 2, 3], t=["p", "q", "r"])
    other = (; a=[1.5, 2.5], b=[4.5, 5.5], x=[1, 3], t=["u", "v"])
    labels = data(rows) * mapping(:a, :b; text=:t) * visual(Makie.Text)
    points = data(rows) * mapping(:a, :b) * visual(Scatter)
    region = Dict{String,Any}("type" => "FeatureCollection", "features" => [Dict{String,Any}(
        "type" => "Feature", "properties" => Dict{String,Any}("k" => "A"),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[0.0, 0.0], [0.0, 8.0], [8.0, 8.0], [8.0, 0.0], [0.0, 0.0]]]))])
    base = data((; k=["A"], v=[1.0])) * mapping(:k; color=:v) * geoshape(region)
    # Two tables, as in a timeline with event rules: the calculate names columns
    # only the first has, and the rules still draw.
    timeline = (; time=[1.0, 2.0, 3.0], cost=[2.0, 4.0, 8.0])
    events = (; time=[1.5, 2.5])
    size = config(width=240, height=120)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-layer-transform-") do dir
            page = [vdraw(spec * size; id) for (id, spec) in [
                "lt-map" => base + labels * config(transform=drop("datum.x > 1")) +
                    labels * config(transform=drop("datum.x > 2")),
                "lt-shared" => points * config(transform=drop("datum.x > 1")) +
                    data(rows) * mapping(:a, :b; text=:t) * visual(Makie.Text),
                "lt-whole" => (points + data(other) * mapping(:a, :b) * visual(Scatter; color=:red)) *
                    config(transform=drop("datum.x > 1")),
                "lt-calculate" => (data(timeline) * mapping(:time, :value) * visual(Scatter) +
                    data(events) * mapping(:time) * visual(VLines)) *
                    config(transform=[Dict("calculate" => "datum.cost * 2", "as" => "value")]),
                "lt-geoshape" => base * config(transform=drop("datum.v > 0")),
                "lt-facet" => data(merge(rows, (; p=["L", "L", "R"]))) * mapping(:a, :b; col=:p) *
                    visual(Scatter) * config(transform=drop("datum.x > 1")) +
                    data(merge(rows, (; p=["L", "L", "R"]))) * mapping(:a, :b; col=:p) * visual(Lines),
            ]]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "layer_transform.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-layer-transform-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] == 6
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
