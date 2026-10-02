using TestItemRunner

@testsnippet AoVLegendFixtures begin
    using AlgebraOfVega, JSON, HTMX
    rows = (; x=repeat([1., 2., 3.], 4), y=collect(1.:12.),
        group=repeat(["A", "B"], inner=3, outer=2),
        panel=repeat(["P", "Q"], inner=6),
        row=repeat(["R", "S"], inner=3, outer=2),
        other=repeat(["C", "D"], inner=3, outer=2))
    base = data(rows) * mapping(:x, :y; color=:group)
    fixtures = Dict(
        "single" => base * visual(Scatter),
        "layered" => base * (visual(Scatter) + visual(Lines)),
        "translucent" => base * (visual(Scatter) + visual(Lines; opacity=0.2)),
        "facet" => data(rows) * mapping(:x, :y; color=:group, col=:panel) *
            (visual(Scatter) + visual(Lines)),
        "encoding_facet" => data(rows) * mapping(:x, :y; color=:group, col=:panel) * visual(Scatter),
        "ribbon" => data(rows) * mapping(:x, :y; color=:group) * lineribbon(probs=[0.5]),
        "interval" => data(rows) * mapping(:y; y=:panel, color=:group) * pointinterval(probs=[0.5]),
        "hconcat" => data(rows) * mapping(:x, :y; color=:group, col=:panel, row=:row) *
            (visual(Scatter) + visual(Lines)) *
            config(scales=scales(Y=(; scale=Dict("Q" => log10)))))
    default_specs = Dict(k => to_vegalite(v * config(width=180, height=120)) for (k, v) in fixtures)
    specs = deepcopy(default_specs)
    foreach(s -> AlgebraOfVega._add_auto_legend_interactivity!(s; mode=:highlight), values(specs))
    units(s) = AlgebraOfVega._legend_units!(Any[], s)
    legend_params(s) = [p for info in units(s) for p in get(info.unit, "params", [])
        if get(p, "bind", nothing) == "legend"]
end

@testitem "legend default matches the selected response" setup=[AoVLegendFixtures] tags=[:translation, :regression] begin
    for spec in values(default_specs)
        @test spec["_aov"]["legendInteraction"] == string(AlgebraOfVega._AUTO_LEGEND_MODE)
        @test length(legend_params(spec)) == 1
    end
end

@testitem "legend selection has one unit owner across compositions" setup=[AoVLegendFixtures] tags=[:translation, :regression] begin
    for (name, spec) in specs
        ps = legend_params(spec)
        @test length(ps) == 1
        @test ps[1]["select"]["fields"] == ["group"]
        @test get(spec, "_aov", Dict())["legendInteraction"] == "highlight"
        before = deepcopy(spec)
        AlgebraOfVega._add_auto_legend_interactivity!(spec; mode=:highlight)
        @test spec == before  # re-lowering must not accumulate params or opacity
        quiet = to_vegalite(fixtures[name] * config(); interactive=false)
        @test isempty(legend_params(quiet))
        @test !haskey(get(quiet, "_aov", Dict()), "legendInteraction")
    end
    line = only(info.unit for info in units(specs["translucent"])
        if AlgebraOfVega._mark_type(info.unit["mark"]) == "line")
    @test line["encoding"]["opacity"]["condition"]["value"] == 0.2
    @test line["encoding"]["opacity"]["value"] ≈ 0.03

    # Explicit opacity conditions and explicit interaction remain authoritative.
    opacity = Dict("condition" => Dict("test" => "datum.x > 1", "value" => 0.4), "value" => 0.2)
    override = to_vegalite(fixtures["single"] * config(encoding=Dict("opacity" => opacity)))
    @test override["encoding"]["opacity"] == opacity
    explicit = to_vegalite(fixtures["facet"] * config(params=[Dict("name" => "chosen", "value" => 1)]))
    @test isempty(legend_params(explicit))
    @test explicit["params"] == [Dict("name" => "chosen", "value" => 1)]
    continuous = to_vegalite(data(rows) * mapping(:x, :y; color=:y) * visual(Scatter) * config())
    @test isempty(legend_params(continuous))
    hidden = to_vegalite(fixtures["single"] * config(encoding=Dict("color" => Dict("legend" => nothing))))
    @test isempty(legend_params(hidden))
    no_scale = to_vegalite(fixtures["single"] * config(encoding=Dict("color" => Dict("scale" => nothing))))
    @test isempty(legend_params(no_scale))
    composite = to_vegalite(data(rows) * mapping(:group, :y; color=:group) * visual(BoxPlot) * config())
    @test isempty(legend_params(composite))

    # Separate categorical fields get distinct selection stores, and field-less
    # reference rows retain their visibility when a group is selected.
    raw = Dict{String,Any}("data" => Dict("values" => [Dict("x" => 1, "g" => "A", "h" => "C")]),
        "layer" => [Dict{String,Any}("mark" => "point", "encoding" => Dict{String,Any}("color" =>
            Dict("field" => f, "type" => "nominal"))) for f in ["g", "h"]])
    AlgebraOfVega._add_auto_legend_interactivity!(raw)
    @test [p["name"] for p in legend_params(raw)] == ["legend_selection", "legend_selection_2"]
    @test [p["select"]["fields"] for p in legend_params(raw)] == [["g"], ["h"]]
    AlgebraOfVega._add_auto_legend_interactivity!(raw; mode=:filter)
    @test all(info -> info.encoding["color"]["scale"]["domain"] isa Dict, units(raw))
    filter_spec = deepcopy(specs["layered"])
    AlgebraOfVega._add_auto_legend_interactivity!(filter_spec; mode=:filter)
    @test filter_spec["_aov"]["legendInteraction"] == "filter"
    @test all(info -> last(info.unit["transform"])["filter"] isa Dict, units(filter_spec))
    @test all(info -> !haskey(info.unit["encoding"], "opacity"), units(filter_spec))
    original = deepcopy(filter_spec)
    AlgebraOfVega._add_auto_legend_interactivity!(filter_spec; mode=:filter)
    @test filter_spec == original
end

@testitem "legend clicks render and remap with the vendored runtime" setup=[AoVLegendFixtures] tags=[:translation, :browser, :regression] begin
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-legend-test-") do dir
            profile = joinpath(dir, "profile")
            filter_specs = Dict(k => deepcopy(v) for (k, v) in specs)
            foreach(s -> AlgebraOfVega._add_auto_legend_interactivity!(s; mode=:filter), values(filter_specs))
            runtime = join(sprint(show, MIME"text/html"(), n) for n in vega_head(source=:inline))
            driver = read(joinpath(@__DIR__, "legend_interaction.js"), String)
            html = "<!doctype html><meta charset='utf-8'>" * runtime * "<body><script>" *
                "const fixtures=" * JSON.json(specs) * ";const filterFixtures=" * JSON.json(filter_specs) *
                ";" * driver * "</script></body>"
            path = joinpath(dir, "test.html")
            write(path, html)
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu --user-data-dir=$profile --virtual-time-budget=15000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-legend-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                body = replace(result[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&")
                report = JSON.parse(body)
                @test report["checks"] >= 100
                @test isempty(report["failures"])
                @info "legend browser checks" checks=report["checks"]
                isempty(report["failures"]) || @info "browser failures" report["failures"]
            end
        end
    end
end
