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
    # Layers colouring by DIFFERENT fields share Vega-Lite's one colour scale,
    # so their legends merge into one (snag `legend-selection-0bea9abd`). Each
    # entry is `(drawable, point colour field)`; the lines colour by `group`.
    line_rows = (; x=repeat([1., 2., 3.], 4), y=collect(1.:12.),
        group=repeat(["A", "B"], inner=3, outer=2), panel=repeat(["P", "Q"], inner=6))
    point_rows = (; x=repeat([1.5, 2.5], 4), y=collect(1.:8.),
        kind=repeat(["C", "D"], inner=2, outer=2), panel=repeat(["P", "Q"], inner=4))
    palette = config(scales=scales(Color=(; categories=["A", "B", "C", "D"],
        palette=["black", "#d55e00", "#0072b2", "#e69f00"])))
    merged_fixtures = Dict(
        "merged" => (data(line_rows) * mapping(:x, :y; color=:group) * visual(Lines) +
            data(point_rows) * mapping(:x, :y; color=:kind) * visual(Scatter), "kind"),
        "merged_facet" => ((data(line_rows) * mapping(:x, :y; color=:group, col=:panel) * visual(Lines) +
            data(point_rows) * mapping(:x, :y; color=:kind, col=:panel) * visual(Scatter)) * palette, "kind"),
        # Every row carries both fields: each layer answers to its own colour.
        "merged_rows" => (base * visual(Lines) +
            data(rows) * mapping(:x, :y; color=:other) * visual(Scatter), "other"))
    # An explicit independent colour scale keeps one legend, listing only its
    # own field's entries, and one selection per layer.
    independent = merged_fixtures["merged"][1] *
        config(resolve=Dict("scale" => Dict("color" => "independent")))
    embed(v) = AlgebraOfVega._embed_spec(v; width=180, height=120, fit_width=false)
    merged_specs = Dict(k => embed(v) for (k, (v, _)) in merged_fixtures)
    default_specs = Dict(k => embed(v) for (k, v) in fixtures)
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

@testitem "bare drawables retain legend interaction through public renderers" setup=[AoVLegendFixtures] tags=[:translation, :regression] begin
    using HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    for (name, drawable) in fixtures
        bare = to_vegalite(drawable)
        @test bare == to_vegalite(drawable * config())
        @test length(legend_params(bare)) == 1
        quiet = to_vegalite(drawable; interactive=false)
        @test isempty(legend_params(quiet))
        @test !haskey(get(quiet, "_aov", Dict()), "legendInteraction")
        @test length(legend_params(AlgebraOfVega._embed_spec(drawable))) == 1
        @test occursin("legend_selection", to_html(drawable; source=:vendor))
        node = vdraw(drawable; id="bare-" * name)
        card = with_plot_caption(node, "Series"; plot_id="bare-" * name)
        @test occursin("legend_selection", sprint(show, MIME"text/html"(), card))
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

    # Categorical fields sharing a colour scale share Vega-Lite's merged legend,
    # hence one selection bound to its first field (snag
    # `legend-selection-0bea9abd`: a second selection had no legend to bind).
    # An independent colour legend gets its own selection store.
    raw = Dict{String,Any}("data" => Dict("values" => [Dict("x" => 1, "g" => "A", "h" => "C")]),
        "layer" => [Dict{String,Any}("mark" => "point", "encoding" => Dict{String,Any}("color" =>
            Dict("field" => f, "type" => "nominal"))) for f in ["g", "h"]])
    AlgebraOfVega._add_auto_legend_interactivity!(raw)
    @test [p["name"] for p in legend_params(raw)] == ["legend_selection"]
    @test [p["select"]["fields"] for p in legend_params(raw)] == [["g"]]
    split = deepcopy(raw)
    split["resolve"] = Dict("legend" => Dict("color" => "independent"))
    AlgebraOfVega._add_auto_legend_interactivity!(split)
    @test [p["name"] for p in legend_params(split)] == ["legend_selection", "legend_selection_2"]
    @test [p["select"]["fields"] for p in legend_params(split)] == [["g"], ["h"]]
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

@testitem "fields sharing one colour legend share one selection" setup=[AoVLegendFixtures] tags=[:translation, :regression] begin
    # Regression (snag `legend-selection-0bea9abd`): two layers colouring by
    # different fields got one legend-bound selection per field, but Vega-Lite
    # merges their legends and binds only the first field's selection, so the
    # other field's entries highlighted nothing.
    for (name, spec) in merged_specs
        pfield = merged_fixtures[name][2]
        ps = legend_params(spec)
        @test length(ps) == 1
        @test only(ps)["name"] == "legend_selection"
        @test only(ps)["select"]["fields"] == ["group"]
        for info in units(spec)
            field = info.encoding["color"]["field"]
            @test field in ("group", pfield)
            # Each layer answers to its own colour field, also when its rows
            # carry the other one (`merged_rows`).
            test = only(info.unit["encoding"]["opacity"]["condition"]["test"]["and"])
            @test test["or"][1] == "!isValid(datum[\"$field\"])"
            @test length(test["or"]) == 2
            @test test["or"][2] == (field == "group" ?
                Dict("param" => "legend_selection", "empty" => true) :
                "!length(data(\"legend_selection_store\")) || (legend_selection[\"group\"] && " *
                    "indexof(legend_selection[\"group\"], datum[\"$pfield\"]) >= 0)")
        end
        before = deepcopy(spec)
        AlgebraOfVega._add_auto_legend_interactivity!(spec)
        @test spec == before
    end
    spec = embed(independent)
    @test spec["resolve"]["scale"]["color"] == "independent"
    @test [p["name"] for p in legend_params(spec)] == ["legend_selection", "legend_selection_2"]
    @test [p["select"]["fields"] for p in legend_params(spec)] == [["group"], ["kind"]]
end

@testitem "legend clicks render and remap with the vendored runtime" setup=[AoVLegendFixtures] tags=[:translation, :browser, :regression] begin
    using HTMXObjects
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
            card(prefix, k, v) = sprint(show, MIME"text/html"(), with_plot_caption(
                vdraw(v; id=prefix * "-" * k * "-caption", width=180, height=120, fit_width=false),
                "Series"; plot_id=prefix * "-" * k * "-caption"))
            cards = join(card("highlight", k, v) for (k, v) in fixtures) *
                join(card("merged", k, v) for (k, (v, _)) in merged_fixtures)
            merged = Dict(k => Dict("spec" => merged_specs[k], "pointField" => f)
                for (k, (_, f)) in merged_fixtures)
            html = "<!doctype html><meta charset='utf-8'>" * runtime *
                "<body><script>const originalEmbed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "originalEmbed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" * cards * "<script>" *
                "const fixtures=" * JSON.json(specs) * ";const filterFixtures=" * JSON.json(filter_specs) *
                ";const mergedFixtures=" * JSON.json(merged) *
                ";const independentFixture=" * JSON.json(embed(independent)) *
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
