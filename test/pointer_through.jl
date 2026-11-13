using TestItemRunner

# `visual(...; inspectable=false)` lets the pointer through every mark of a layer
# so a text layer can leave the underlying cell's tooltip accessible.
# Vega-Lite has no mark property for Vega's
# `interactive`, so the marks carry the style `aov-passive` and the runtime sets
# `interactive: false` on them. Makie's `DataInspector` skips such a plot and
# shows the one beneath, so `sdraw` keeps the attribute as Makie's own.
@testsnippet AoVPointerThroughFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics
    const Makie = AlgebraOfVega.Makie
    ags = ["01001", "01002", "01003"]
    # Clockwise rings (see test/mark_click.jl).
    square(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 0.0], [x0, 1.0], [x0 + 1, 1.0], [x0 + 1, 0.0], [x0, 0.0]]])
    geojson = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => square(Float64(i))) for (i, a) in enumerate(ags)])
    districts = data((; AGS=ags, effect=[-0.4, 0.1, 0.7])) * mapping(:AGS; color=:effect) * geoshape(geojson)
    # A region name over district 01002, as RegionExplorer writes one: a white
    # halo under the dark ink.
    names = (; lon=[2.5], lat=[0.5], name=["Mitte"])
    label(passive) = data(names) * mapping(:lon, :lat; text=:name) * (
        visual(Makie.Text; fontsize=28, font=:bold, color="white", strokecolor="white", strokewidth=5,
            inspectable=!passive) +
        visual(Makie.Text; fontsize=28, font=:bold, color="#222", inspectable=!passive))
    name_map(passive) = (districts + label(passive)) * config(width=300, height=100)
    # Every mark of a lowered spec, with the path of keys that leads to it.
    function marks(x, path=String[], out=Pair{String,Any}[])
        if x isa AbstractDict
            haskey(x, "mark") && push!(out, join(path, "/") => x["mark"])
            for (k, v) in x
                k in ("data", "datasets", "config") || marks(v, vcat(path, k), out)
            end
        elseif x isa AbstractVector
            foreach(((i, v),) -> marks(v, vcat(path, string(i)), out), enumerate(x))
        end
        out
    end
    styles(mark) = mark isa AbstractDict ? AlgebraOfVega._style_list(get(mark, "style", String[])) : String[]
    passive(mark) = "aov-passive" in styles(mark)
    nowarn(f) = Test.@test_logs min_level=Base.CoreLogging.Warn f()
end

@testitem "inspectable=false styles every mark of its layer aov-passive" setup=[AoVPointerThroughFixtures] tags=[:translation, :interactivity] begin
    # The reporter's map: the geoshape keeps taking the pointer, both name layers
    # let it through. No warning: `inspectable` is no longer an unread attribute.
    vl = nowarn(() -> to_vegalite(name_map(true)))
    ms = [m for (_, m) in marks(vl)]
    @test length(ms) == 3
    @test count(passive, ms) == 2
    @test all(m -> passive(m) == (AlgebraOfVega._mark_type(m) == "text"), ms)
    # The style is added after the layer's own mark properties, which stay.
    ink = only(m for m in ms if passive(m) && get(m, "color", nothing) == "#222")
    @test ink["style"] == "aov-passive" && ink["fontSize"] == 28 && ink["fontWeight"] == "bold"
    # `inspectable=true` (Makie's default) changes nothing.
    @test to_vegalite(name_map(false)) == to_vegalite(districts + data(names) * mapping(:lon, :lat; text=:name) * (
        visual(Makie.Text; fontsize=28, font=:bold, color="white", strokecolor="white", strokewidth=5) +
        visual(Makie.Text; fontsize=28, font=:bold, color="#222")) * config(width=300, height=100))
    @test !any(passive, (m for (_, m) in marks(to_vegalite(name_map(false)))))

    pts = data((; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "c"]))
    # A bare mark becomes a mark object; the ink style stays and the order of
    # styles does not matter to Vega (aov-passive sets no colour).
    @test to_vegalite(pts * mapping(:x, :y) * visual(Scatter; inspectable=false))["mark"] ==
          Dict{String,Any}("type" => "point", "filled" => true, "style" => "aov-passive")
    @test to_vegalite(pts * mapping(:x, :y) * visual(Lines; color=:ink, inspectable=false))["mark"]["style"] ==
          ["aov-ink", "aov-passive"]
    # A later term sets it as any attribute (AoG's visual composition).
    @test passive(to_vegalite(pts * mapping(:x, :y) * visual(Scatter) * visual(; inspectable=false))["mark"])
    # A single passive scatter gets no nearest-point overlay: its Voronoi cells
    # would answer the pointer for the points. A plain one keeps it.
    names_of(vl) = [p["name"] for p in get(vl, "params", Any[])]
    @test "hover_nearest" in names_of(to_vegalite(pts * mapping(:x, :y) * visual(Scatter)))
    @test !("hover_nearest" in names_of(to_vegalite(pts * mapping(:x, :y) * visual(Scatter; inspectable=false))))

    # Every mark an analysis draws: the interval rules and the median point.
    draws = data((; v=randn(200), k=repeat(["a", "b"], 100)))
    vl = nowarn(() -> to_vegalite(draws * mapping(:v, y=:k) * pointinterval() * visual(; inspectable=false)))
    @test length(marks(vl)) >= 2 && all(passive, (m for (_, m) in marks(vl)))
    # A coloured ribbon over a few doses: both drawings of its switch (§8).
    bands = data((; x=repeat([1.0, 2.0, 4.0], 2), m=[1.0, 2.0, 3.0, 1.5, 2.5, 3.5],
        lo=[0.5, 1.5, 2.5, 1.0, 2.0, 3.0], hi=[1.5, 2.5, 3.5, 2.0, 3.0, 4.0], g=repeat(["a", "b"], inner=3)))
    ribbon_fig = bands * mapping(:x, :m; color=:g) * lineribbon(bands=[:lo => :hi]) * visual(; inspectable=false)
    @test ribbon_view(ribbon_fig).offered
    vl = nowarn(() -> to_vegalite(ribbon_fig))
    # The shown drawing, and the other one the switch swaps in.
    alt = delete!(copy(vl["_aov"]["ribbonView"]["alt"]), "_aov")
    @test all(passive, (m for (_, m) in marks(delete!(copy(vl), "_aov"))))
    @test length(marks(alt)) >= 2 && all(passive, (m for (_, m) in marks(alt)))
    # A composite mark's style goes onto the parts Vega-Lite draws.
    box = to_vegalite(draws * mapping(:k, :v) * visual(BoxPlot; inspectable=false))["mark"]
    @test !haskey(box, "style")
    @test all(p -> "aov-passive" in styles(box[p]), ("box", "median", "outliers", "rule"))
    # Faceted figures: the passive layer's units inside the facet's spec.
    vl = to_vegalite((pts * mapping(:x, :y; col=:g) * visual(Scatter) +
        pts * mapping(:x, :y; text=:g, col=:g) * visual(Makie.Text; inspectable=false)))
    @test count(passive, (m for (_, m) in marks(vl))) == 1
    @test count(m -> !passive(m), (m for (_, m) in marks(vl))) == 1
    # The channel picker keeps it.
    remap = (; dims=["g" => "Group"])
    vl = to_vegalite(pts * mapping(:x, :y; color=:g) * visual(Scatter) +
        pts * mapping(:x, :y; text=:g) * visual(Makie.Text; inspectable=false); auto_remap=remap)
    @test count(passive, (m for (_, m) in marks(vl))) == 1

    # A value that is not a Bool is not read, and says so.
    Test.@test_logs (:warn, r"inspectable") match_mode=:any to_vegalite(pts * mapping(:x, :y) * visual(Scatter; inspectable=1))

    # The bare `to_html(spec)` embed makes the marks non-interactive itself;
    # a spec without a passive layer embeds without that patch (a map still
    # gets the one that cuts its marks once zoomed, test/map_zoom.jl).
    @test occursin("m.interactive = false", to_html(name_map(true); id="bare"))
    plain = to_html(name_map(false); id="bare")
    @test !occursin("interactive", plain) && occursin("{actions: false, patch: function (vg) { if (vg && (vg.signals", plain)

    # Static path: Makie's own attribute reaches the Makie plot.
    fig = Makie.Figure()
    sdraw!(fig[1, 1], pts * mapping(:x, :y) * visual(Scatter; inspectable=false))
    plots = [p for ax in fig.content if ax isa Makie.Axis for p in ax.scene.plots if p isa Makie.Scatter]
    @test length(plots) == 1 && only(plots).inspectable[] === false
end

@testitem "inspectable=false: the pointer reaches the mark beneath in the browser" setup=[AoVPointerThroughFixtures] tags=[:regression, :browser, :interactivity] begin
    using JSON, HTMX, HTMXObjects
    html(x) = sprint(show, MIME"text/html"(), x)
    # A cell chart with its values written over the bars: the labels let the
    # pointer through to the bars (the runtime's own cell-chart compile).
    cell_rows = (; site=repeat([1, 2], inner=2), k=repeat(["a", "b"], 2), n=[3, 1, 2, 4])
    cells = cell_charts(data(cell_rows) * mapping(:k, :n; layout=:site) *
        (visual(BarPlot) + mapping(text=:n) * visual(Makie.Text; fontsize=9, inspectable=false)))
    scatter = (data((; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "c"])) *
        mapping(:x, :y; color=:g) * visual(Scatter) +
        data((; x=[2.0], y=[4.0], name=["B"])) * mapping(:x, :y; text=:name) *
        visual(Makie.Text; fontsize=30, inspectable=false)) * config(width=300, height=200)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-pointer-through-") do dir
            # The bare `to_html(spec)` fragment without its own script tags: the
            # page's Vega draws it, so the shim below sees its view.
            bare = replace(to_html(name_map(true); id="pt-bare"), r"<script [^>]*\bsrc=[^>]*></script>" => "")
            @test occursin("m.interactive = false", bare) && !occursin(r"<script [^>]*\bsrc=", bare)
            page = [vdraw(name_map(true) * config(link=(; group="pt", key=:AGS)); id="pt-map"),
                vdraw(name_map(false); id="pt-control"),
                vdraw(scatter; id="pt-scatter")]
            head = join(html(n) for n in vega_head(; source=:inline))
            shim = "<script>window.__ptViews = {}; (function () { var embed = window.vegaEmbed; " *
                "window.vegaEmbed = function (el, spec, opts) { var p = embed.apply(this, arguments); " *
                "p.then(function (r) { if (typeof el === 'string') window.__ptViews[el] = r.view; }); return p; }; })();</script>"
            driver = read(joinpath(@__DIR__, "pointer_through.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * shim * join(html(p) for p in page) * bare *
                "<div id='pt-svg'></div><table id='pt-cells'>" * html(HTMX.h.tr(cells[1])) * html(HTMX.h.tr(cells[2])) *
                "</table><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-pointer-through-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 25
                @test isempty(report["failures"])
                @info "pointer-through browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
