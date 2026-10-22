using TestItemRunner

# Hover linking between a plot and the other elements that show the same items
# (snag `aov-hover-event-2eb5b89e`, design decision `0u45lzm`; the shared link
# contract is HTMXObjects' design `0e39vjf`). A plot reports hovers as
# `aov:hover`/`aov:hoverend` DOM events, page script highlights marks by key
# with `AoV.highlight(id, match)`, and `config(link=(; group, key))` joins a
# named link group whose members announce hovered keys as `htmxo:link` events.
# Before it, the only route was a hand-attached Vega listener on
# `AoV.views[id]`, which every re-embed drops.
@testitem "config(link=…) lowers to _aov.link and refuses malformed links" tags=[:interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics
    rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], kenn=["a", "b", "c"])
    scatter = data(rows) * mapping(:x, :y) * visual(Scatter)

    vl = to_vegalite(scatter * config(link=(; group="probes", key=:kenn)))
    @test vl["_aov"]["link"] == Dict("group" => "probes", "key" => "kenn")
    # The link is runtime metadata: no Vega-Lite property, no extra parameter.
    @test !haskey(vl, "link")
    @test to_vegalite(scatter)["params"] == vl["params"]
    # Symbols and strings spell the same link.
    @test to_vegalite(scatter * config(link=(; group=:probes, key="kenn")))["_aov"]["link"] == vl["_aov"]["link"]

    # A layer without the key column (a base map) is fine as long as one has it.
    ags = ["01001", "01002"]
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => Dict{String,Any}("type" => "Polygon",
                "coordinates" => [[[i, 0.0], [i, 1.0], [i + 1.0, 1.0], [i + 1.0, 0.0], [i, 0.0]]]))
        for (i, a) in enumerate(ags)])
    pts = (; lon=[1.5, 2.5], lat=[0.5, 0.5], kenn=["a", "b"])
    map_spec = (data((; AGS=ags, v=[1.0, 2.0])) * mapping(:AGS; color=:v) * geoshape(geojson) +
        data(pts) * mapping(:lon, :lat) * visual(Scatter)) * config(link=(; group="probes", key=:kenn))
    @test to_vegalite(map_spec)["_aov"]["link"]["key"] == "kenn"

    # Faceted and picker figures carry it too.
    faceted = data((; rows..., g=["p", "p", "q"])) * mapping(:x, :y; col=:g) * visual(Scatter) *
        config(link=(; group="probes", key=:kenn))
    @test to_vegalite(faceted)["_aov"]["link"]["group"] == "probes"
    picked = to_vegalite(faceted; auto_remap=(; dims=["g" => "Group"]))
    @test picked["_aov"]["link"]["group"] == "probes"

    @test_throws ArgumentError config(link=:probes)
    @test_throws ArgumentError config(link=(; group="probes"))
    @test_throws ArgumentError config(link=(; group="", key=:kenn))
    @test_throws ArgumentError config(link=(; group="probes", key=:kenn, colour=:red))
    # A key column no layer has would link nothing, silently.
    err = try
        to_vegalite(scatter * config(link=(; group="probes", key=:id)))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("`id` column", sprint(showerror, err))
end

@testitem "hover events, keyed highlight and link groups in the browser" tags=[:regression, :browser, :interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    link = config(link=(; group="probes", key=:kenn))
    size = config(width=240, height=160)

    rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], kenn=["a", "b", "c"], g=["p", "q", "q"])
    # Clockwise rings: d3-geo reads a counter-clockwise ring as the whole
    # globe minus the square (see test/mark_click.jl).
    ags = ["01001", "01002", "01003"]
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0, 1.0], [x0 + 1, 1.0], [x0 + 1, 0.0], [x0, 0.0]]])
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => square(Float64(i))) for (i, a) in enumerate(ags)])
    probes = (; lon=[1.5, 2.5, 3.5], lat=[0.5, 0.5, 0.5], kenn=["a", "b", "c"])
    series = (; t=repeat([1.0, 2.0, 3.0], 3), v=[1.0, 2.0, 3.0, 2.0, 3.0, 4.0, 3.0, 4.0, 5.0],
        kenn=repeat(["a", "b", "c"], inner=3))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-hover-highlight-") do dir
            page = [
                # Linked, coloured (legend selection), nearest-point hover.
                vdraw(data(rows) * mapping(:x, :y; color=:g) * visual(Scatter) * size * link; id="hh-scatter"),
                # Linked map: districts without the key column, probes with it.
                vdraw((data((; AGS=ags, effect=[-0.4, 0.1, 0.7])) * mapping(:AGS; color=:effect) *
                    geoshape(geojson) + data(probes) * mapping(:lon, :lat) * visual(Scatter)) *
                    config(width=300, height=100) * link; id="hh-map"),
                # Linked lines, one per probe.
                vdraw(data(series) * mapping(:t, :v; color=:kenn) * visual(Lines) * size * link; id="hh-lines"),
                # Unlinked, uncoloured: VL's own 0.7 point opacity.
                vdraw(data(rows) * mapping(:x, :y) * visual(Scatter) * size; id="hh-plain"),
                # Unlinked bars: no nearest-point overlay, so space above a bar is no mark.
                vdraw(data((; k=["a", "b", "c"], v=[1.0, 2.0, 4.0])) * mapping(:k, :v) * visual(BarPlot) *
                    config(scales=scales(Y=(; zero=true))) * size; id="hh-bars"),
                # Another group: ignores "probes" announcements.
                vdraw(data(rows) * mapping(:x, :y) * visual(Scatter) * size *
                    config(link=(; group="other", key=:kenn)); id="hh-other")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "hover_highlight.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-hover-highlight-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "hover/highlight browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
