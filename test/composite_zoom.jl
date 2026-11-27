using TestItemRunner

# A composite mark (Vega-Lite's `errorbar`, `errorband`, `boxplot`) holds no
# selection. AoV put a faceted figure's zoom/pan on its first layer that encodes
# x and y, so on a `Rangebars` drawn first Vega-Lite logged "Selection not
# supported for errorbar yet." and dropped it: the figure had no pan or zoom.
# An unfaceted figure with any composite layer got none either, since AoV left
# all interactivity off for it (snag `drew-a-faceted-f-c1afd58d`).
@testsnippet AoVCompositeZoomFixtures begin
    using AlgebraOfVega, JSON

    est = (; window=[1.0, 2.0, 3.0, 1.0, 2.0, 3.0], class=["a", "a", "a", "b", "b", "b"],
        q025=[0.5, 1.0, 1.5, 2.0, 2.5, 3.0], q975=[3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
        q25=[1.0, 1.8, 2.5, 3.0, 4.0, 5.0], q75=[2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
        q50=[1.5, 2.4, 3.2, 4.0, 5.0, 6.0])
    obs = (; window=[1.0, 2.0, 3.0, 1.0, 2.0, 3.0], class=["a", "a", "a", "b", "b", "b"],
        video=[1.6, 2.2, 3.5, 4.5, 4.8, 6.5])
    # The reporter's figure: two Rangebars layers, then the medians and the observations.
    figure(; facet=(; row=:class)) =
        data(est) * mapping(:window, :q025, :q975; facet...) * visual(Rangebars; color="#1f6fb5", alpha=0.55) +
        data(est) * mapping(:window, :q25, :q75; facet...) * visual(Rangebars; linewidth=3.5) +
        data(est) * mapping(:window, :q50; facet...) * visual(Scatter; color="#1f6fb5") +
        data(obs) * mapping(:window, :video; facet...) * visual(Scatter; marker=:diamond)
    reported = figure() * config(height=150, readout=false, facet=(; linkyaxes=:none))

    # Every automatic zoom selection: (its unit's mark type, name, encodings).
    function zooms(d, out=Any[])
        d isa AbstractDict || return out
        for p in something(get(d, "params", nothing), Any[])
            p isa AbstractDict && AlgebraOfVega._is_auto_zoom_name(get(p, "name", nothing)) &&
                push!(out, (AlgebraOfVega._mark_type(get(d, "mark", nothing)), p["name"], p["select"]["encodings"]))
        end
        for k in ("layer", "spec", "vconcat", "hconcat", "concat")
            v = get(d, k, nothing)
            v isa AbstractVector ? foreach(x -> zooms(x, out), v) : zooms(v, out)
        end
        out
    end
end

@testitem "the zoom goes on a layer that can hold it, never on a composite mark" setup=[AoVCompositeZoomFixtures] tags=[:translation, :interactive, :regression] begin
    # The reporter's faceted figure: on the median Scatter (third layer), on x and y.
    vl = to_vegalite(reported)
    @test zooms(vl) == [("point", "grid", ["x", "y"])]
    @test vl["spec"]["layer"][3]["params"][1]["name"] == "grid"
    @test !any(l -> haskey(l, "params"), vl["spec"]["layer"][1:2])
    # Linked y, an unfaceted figure, a wrap and a per-row Y stack alike.
    @test zooms(to_vegalite(figure() * config(height=150))) == [("point", "grid", ["x", "y"])]
    @test zooms(to_vegalite(figure(facet=(;)))) == [("point", "grid", ["x", "y"])]
    @test zooms(to_vegalite(figure(facet=(; layout=:class)))) == [("point", "grid", ["x", "y"])]
    stack = to_vegalite(figure() * config(scales=scales(Y=(; scale=Dict("a" => log10)))))
    @test sort(zooms(stack)) == sort([("point", "grid", ["x"]), ("point", "grid_p0", ["y"]),
        ("point", "grid", ["x"]), ("point", "grid_p1", ["y"])])
    # A box plot under points: the points hold the y zoom (x is nominal).
    box = data((; g=["a", "a", "b", "b"], v=[1.0, 2.0, 3.0, 4.0])) * mapping(:g, :v)
    @test zooms(to_vegalite(box * (visual(BoxPlot) + visual(Scatter)))) == [("point", "grid", ["y"])]
    # With no other layer on y, the rule holds x alone: a selection on a channel
    # its unit does not encode is a Vega-Lite warning too.
    rule = data((; t=[2.0])) * mapping(:t) * visual(VLines)
    @test zooms(to_vegalite(data(est) * mapping(:window, :q025, :q975) * visual(Rangebars) + rule)) ==
        [("rule", "grid", ["x"])]
    # Composite marks alone: no unit can hold a zoom, so there is none.
    bars = data(est) * mapping(:window, :q025, :q975) * visual(Rangebars)
    @test isempty(zooms(to_vegalite(bars)))
    @test isempty(zooms(to_vegalite(bars + data(est) * mapping(:window, :q25, :q75) * visual(Rangebars))))
    @test isempty(zooms(to_vegalite(data(est) * mapping(:window, :q025, :q975; row=:class) * visual(Rangebars))))
    # Figures without a composite layer keep their zoom where it was.
    pts = data(est) * mapping(:window, :q50) * visual(Scatter)
    @test zooms(to_vegalite(pts + bars)) == [("point", "grid", ["x", "y"])]
    @test zooms(to_vegalite(pts)) == [("point", "grid", ["x", "y"])]
    @test zooms(to_vegalite(rule + pts)) == [("point", "grid", ["x", "y"])]
end

@testitem "a figure with a composite layer zooms in the browser with an empty console" setup=[AoVCompositeZoomFixtures] tags=[:regression, :browser, :interactive] begin
    using HTMX, HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-composite-zoom-") do dir
            capture = "<script>window.AOV_ERRORS = []; ['error', 'warn'].forEach(k => { const o = console[k]; " *
                "console[k] = function () { window.AOV_ERRORS.push(k + ': ' + [...arguments].map(String).join(' ')); " *
                "return o.apply(console, arguments); }; });</script>"
            page = "<div style='width:800px'>" *
                html(with_plot_caption(reported, CaptionSpec(; title="Fibre volume"); plot_id="cz-facet")) *
                "</div><div style='width:600px'>" * html(vdraw(figure(facet=(;)) * config(height=150); id="cz-plain")) *
                "</div>"
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "composite_zoom.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * capture * head * "<body>" *
                page * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1200
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-composite-zoom-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 10
                @test isempty(report["failures"])
                @info "composite zoom browser checks" checks=report["checks"] samples=JSON.json(get(report, "samples", nothing))
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
