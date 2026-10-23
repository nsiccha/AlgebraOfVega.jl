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

# Runs `driver` (a `test/*.js` file) after `body` on an inline-head page in
# headless Chrome, opened with the URL `query`, and checks the
# `{checks, failures}` report it writes to `<pre id=result_id>`.
@testsnippet AoVFitWidthBrowser begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    rows = (; x=repeat([1.0, 2.0, 3.0], 4), y=collect(1.0:12.0),
        group=repeat(["A", "B"], inner=3, outer=2), panel=repeat(["P", "Q"], inner=6))
    layered = data(rows) * mapping(:x, :y; color=:group) * (visual(Scatter) + visual(Lines))
    function browser_checks(body, driver, result_id; min_checks, query="")
        chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
        if isempty(chrome)
            @test_skip "headless Chrome is not installed"
            return
        end
        mktempdir(prefix="kb-fit-width-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * body * "<script>" * read(driver, String) * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=15000 --dump-dom $("file://" * joinpath(dir, "page.html") * query)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(Regex("<pre id=\"$result_id\">([^<]*)</pre>"), output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= min_checks
                @test isempty(report["failures"])
                @info "$(basename(driver)) browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

@testitem "fixed and responsive widths in the browser" setup=[AoVFitWidthBrowser] tags=[:regression, :browser] begin
    encoding_facet = data(rows) * mapping(:x, :y; color=:group, col=:panel) * visual(Scatter)
    plots = ["fw-fixed-layered" => vdraw(layered; id="fw-fixed-layered", width=180, height=120, fit_width=false),
        "fw-fixed-encfacet" => vdraw(encoding_facet; id="fw-fixed-encfacet", width=180, height=120, fit_width=false),
        "fw-fixed-remap" => vdraw(layered; id="fw-fixed-remap", width=180, height=120, fit_width=false),
        "fw-fit-layered" => vdraw(layered; id="fw-fit-layered", height=120),
        "fw-fit-remap" => vdraw(layered; id="fw-fit-remap", height=120)]
    body = join("<div id='wrap-$id' style='width:640px'>" * html(n) * "</div>" for (id, n) in plots)
    browser_checks(body, joinpath(@__DIR__, "fit_width.js"), "aov-fit-width-results"; min_checks=21)
end

# A fitted plot in a container that grows with its content: SQKM's master/detail
# row, where a lazily swapped-in `<td colspan>` holds a two-plot grid and a
# full-width plot (snag rendered-layered-13357461), and a 600px auto-layout table
# whose plot overshoots within the correction tolerance.
@testitem "fitted plots settle in content-sized containers" setup=[AoVFitWidthBrowser] tags=[:regression, :browser] begin
    unlabelled = data(rows) * mapping(:x, :y) * (visual(Lines) + visual(Scatter))
    detail = "<div style='display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:24px'>" *
        html(vdraw(layered; id="sw-half-a", height=120)) * html(vdraw(unlabelled; id="sw-half-b", height=120)) *
        "</div>" * html(vdraw(unlabelled; id="sw-full", height=120))
    # Without axes, 16px padding on each side is 32px of chrome against the 30px
    # the runtime reserves: a 2px overshoot that `_fitCorrection` leaves alone.
    points = [Dict("x" => "Q$i", "y" => i) for i in 1:8]
    unit(mark) = Dict("data" => Dict("values" => points), "mark" => mark,
        "encoding" => Dict("x" => Dict("field" => "x", "type" => "nominal", "axis" => nothing),
            "y" => Dict("field" => "y", "type" => "quantitative", "axis" => nothing)))
    tolerance = Dict("height" => 60, "padding" => 16, "layer" => [unit("line"), unit("point")])
    cells = join("<td>row $i</td>" for i in 1:5)
    body = "<div style='width:900px'><table id='sw-table' style='width:100%;border-collapse:collapse'>" *
        "<thead><tr>" * join("<th>column $i</th>" for i in 1:5) * "</tr></thead><tbody><tr>" * cells *
        "</tr><tr><td id='sw-cell' colspan='5' style='padding:8px 16px'></td></tr></tbody></table></div>" *
        "<table style='width:600px;border-collapse:collapse'><tr><td id='sw-tol-cell' style='padding:0'></td></tr></table>" *
        "<template id='sw-detail'>" * detail * "</template>" *
        "<template id='sw-tol-plot'>" * html(vdraw(tolerance; id="sw-tol")) * "</template>"
    browser_checks(body, joinpath(@__DIR__, "fit_width_shrinkwrap.js"), "aov-fit-width-shrinkwrap-results"; min_checks=20)
end

# A tabset panel hidden while its plots embed (`display: none`) offers them no
# width. A page opened with `?tab=<name>` shows that panel only after its plots
# embedded, from the restore script the tabset renders as its last child. They
# now fill the panel as soon as it shows, instead of first painting at the 400px
# fallback for the 200ms resize debounce (captured by a screenshot taken at load).
# A plain single view, which no ResizeObserver watched, stayed 0px wide for good;
# a plot re-embedded while hidden stayed at its fallback when the panel came back
# at its old width (snag a-page-with-an-h-eb58645a).
@testitem "plots in a hidden tab panel fill it once it is shown" setup=[AoVFitWidthBrowser] tags=[:regression, :browser] begin
    using HTMXObjects
    using HTMX: h
    plain = data(rows) * mapping(:x, :y) * visual(Scatter)
    # No colour legend, so no `_aov`: the single view no observer watched.
    @test !haskey(AlgebraOfVega._embed_spec(plain), "_aov")
    tabs = tabset("Shown" => vdraw(layered; id="hp-shown", height=120),
        "Hidden" => h.div(vdraw(layered; id="hp-layered", height=120), vdraw(plain; id="hp-single", height=120),
            h.div(; style="display:inline-block")(vdraw(layered; id="hp-wrap", height=120)));
        names=["shown", "hidden"])
    body = html(htmxo_utility_styles()) * html(tabset_script()) * "<div style='width:900px'>" * html(tabs) * "</div>"
    browser_checks(body, joinpath(@__DIR__, "fit_width_hidden.js"), "aov-fit-width-hidden-results";
        min_checks=22, query="?tab=hidden")
end
