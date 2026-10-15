using TestItemRunner

# Only a container-sized plot is sized by the runtime. `_embed_spec` marks one
# with `_aov.fitWidth`; an authored width (`width=`, `fit_width=false`) carries no
# marker and the runtime leaves it alone. Before, the runtime sized every spec
# that had any `_aov` key — and legend interactivity puts `legendInteraction`
# there on every colour-mapped plot — so an explicit `width=180` rendered at the
# container's width (2× it for an encoding facet), and a container resize
# re-embedded the plot, replacing its view and dropping the legend selection
# (todo `0dp0do2`: the flaky `legend_interaction` caption fixture).
@testsnippet AoVFitWidthFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics
    rows = (; x=repeat([1.0, 2.0, 3.0], 4), y=collect(1.0:12.0),
        group=repeat(["A", "B"], inner=3, outer=2), panel=repeat(["P", "Q"], inner=6),
        row=repeat(["R", "S"], inner=3, outer=2))
    layered = data(rows) * mapping(:x, :y; color=:group) * (visual(Scatter) + visual(Lines))
    single = data(rows) * mapping(:x, :y; color=:group) * visual(Scatter)
    encoding_facet = data(rows) * mapping(:x, :y; color=:group, col=:panel) * visual(Scatter)
    facet = data(rows) * mapping(:x, :y; color=:group, col=:panel) * (visual(Scatter) + visual(Lines))
    per_column = data(rows) * mapping(:x, :y; color=:group, col=:panel, row=:row) * visual(Scatter) *
        config(scales=scales(Y=(; scale=Dict("Q" => log10))))
    aov(vl) = get(vl, "_aov", Dict{String,Any}())
end

@testitem "responsive specs carry the fitWidth marker" setup=[AoVFitWidthFixtures] tags=[:regression, :translation] begin
    for spec in (layered, encoding_facet, facet, per_column)
        vl = AlgebraOfVega._embed_spec(spec)
        @test aov(vl)["fitWidth"] === true
        @test haskey(aov(vl), "legendInteraction")
    end
    @test aov(AlgebraOfVega._embed_spec(encoding_facet))["nFacetCols"] == 2
    @test aov(AlgebraOfVega._embed_spec(facet))["nFacetCols"] == 2
    @test aov(AlgebraOfVega._embed_spec(per_column))["nFacetCols"] == 2
    # A single view stays VL-native: `width: "container"`, no runtime marker.
    sv = AlgebraOfVega._embed_spec(single)
    @test sv["width"] == "container"
    @test !haskey(aov(sv), "fitWidth")
end

@testitem "an authored width carries no fitWidth marker" setup=[AoVFitWidthFixtures] tags=[:regression, :translation] begin
    for spec in (layered, single, encoding_facet, facet, per_column),
            kw in ((; width=180), (; fit_width=false), (; width=180, fit_width=false))
        vl = AlgebraOfVega._embed_spec(spec; kw...)
        @test !haskey(aov(vl), "fitWidth")
        # Legend metadata still rides `_aov` — it is not a sizing marker.
        @test haskey(aov(vl), "legendInteraction")
    end
    @test AlgebraOfVega._embed_spec(layered; width=180)["width"] == 180
    @test AlgebraOfVega._embed_spec(layered * config(width=240))["width"] == 240
    @test !haskey(aov(AlgebraOfVega._embed_spec(layered * config(width=240))), "fitWidth")
end

@testitem "fixed and responsive widths in the browser" tags=[:regression, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    rows = (; x=repeat([1.0, 2.0, 3.0], 4), y=collect(1.0:12.0),
        group=repeat(["A", "B"], inner=3, outer=2), panel=repeat(["P", "Q"], inner=6))
    layered = data(rows) * mapping(:x, :y; color=:group) * (visual(Scatter) + visual(Lines))
    encoding_facet = data(rows) * mapping(:x, :y; color=:group, col=:panel) * visual(Scatter)
    plots = ["fw-fixed-layered" => vdraw(layered; id="fw-fixed-layered", width=180, height=120, fit_width=false),
        "fw-fixed-encfacet" => vdraw(encoding_facet; id="fw-fixed-encfacet", width=180, height=120, fit_width=false),
        "fw-fixed-remap" => vdraw(layered; id="fw-fixed-remap", width=180, height=120, fit_width=false),
        "fw-fit-layered" => vdraw(layered; id="fw-fit-layered", height=120),
        "fw-fit-remap" => vdraw(layered; id="fw-fit-remap", height=120)]

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-fit-width-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            body = join("<div id='wrap-$id' style='width:640px'>" * html(n) * "</div>" for (id, n) in plots)
            driver = read(joinpath(@__DIR__, "fit_width.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * body * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=15000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-fit-width-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 21
                @test isempty(report["failures"])
                @info "fit-width browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
