using TestItemRunner

# config(legend_zoom=true): selecting colour legend entries zooms each panel's
# axes to the selected entries' marks; clearing the selection brings back the
# full view (todo `0b9v7xy`, Bruno decision `0ji9x5d`: an ARV-393 client wants
# to drop a 15 mg ALT outlier from a pred/observed scatter by toggling the dose
# group). Off by default: a selection only dims, and the spec is unchanged.
@testsnippet AoVLegendZoomFixtures begin
    using AlgebraOfVega
    # Three groups on x 1..5. Group B has one far-out reading (y = 60); C is
    # drawn in panel P only, so a panel can lack the selected group.
    function zoom_rows(; scale_q=10.0)
        rows = NamedTuple[]
        for (g, off) in (("A", 0.0), ("B", 1.0), ("C", 2.0)), kind in ("P", "Q"), x in 1:5
            g == "C" && kind == "Q" && continue
            k = kind == "Q" ? scale_q : 1.0
            push!(rows, (; x=k * x, y=k * (x + off), g, h=isodd(x) ? "u" : "v", kind))
        end
        push!(rows, (; x=3.0, y=60.0, g="B", h="u", kind="P"))
        rows
    end
    # The dashed identity line spans the global range and has no colour field.
    ident = [(; x=0.0, y=0.0), (; x=60.0, y=60.0)]
    identity_layer = data(ident) * mapping(:x, :y) * visual(Lines; color=:gray, linestyle=:dash)
    scatter(rows; kw...) = data(rows) * mapping(:x, :y; color=:g, kw...) * visual(Scatter)
    sz = config(width=240, height=160)
    zoom = config(legend_zoom=true)
end

@testitem "config(legend_zoom=…) lowers to runtime metadata only" setup=[AoVLegendZoomFixtures] tags=[:translation, :legend] begin
    using JSON
    rows = zoom_rows()
    plain = scatter(rows) + identity_layer
    vl = to_vegalite(plain * zoom)
    @test vl["_aov"]["legendZoom"] === true
    @test vl["_aov"]["legendInteraction"] == "highlight"
    # Nothing else changes, and the default (or `false`) writes nothing.
    @test JSON.json(delete!(deepcopy(vl["_aov"]), "legendZoom")) == JSON.json(to_vegalite(plain)["_aov"])
    without = delete!(deepcopy(vl), "_aov")
    @test JSON.json(without) == JSON.json(delete!(to_vegalite(plain), "_aov"))
    @test JSON.json(to_vegalite(plain * config(legend_zoom=false))) == JSON.json(to_vegalite(plain))
    @test !haskey(to_vegalite(plain)["_aov"], "legendZoom")
    # Faceted, per-panel scales and the picker keep it on the figure.
    facet = to_vegalite((scatter(rows; col=:kind) + identity_layer) * zoom *
        config(facet=(; linkxaxes=:none, linkyaxes=:none)))
    @test facet["_aov"]["legendZoom"] === true
    @test haskey(facet, "facet")
    stack = to_vegalite(vconcat(scatter(rows) * zoom, scatter(rows)))
    @test stack["_aov"]["legendZoom"] === true
    picked = to_vegalite(scatter(rows) * zoom; auto_remap=(; dims=["g" => "Group", "h" => "Half"], pinned=:detail))
    @test picked["_aov"]["legendZoom"] === true
    # Only a Bool.
    @test_throws ArgumentError config(legend_zoom=:on)
    @test_throws ArgumentError config(legend_zoom=1)
    # The static path has no legend interaction and ignores it.
    kw = AlgebraOfVega._draw_kwargs(AlgebraOfVega.Config(Dict{Symbol,Any}(:legend_zoom => true)))
    @test isempty(kw.figure) && isempty(kw.facet) && isempty(kw.axis)
end

@testitem "vsave draws a legend-zoom figure exactly as without it" setup=[AoVLegendZoomFixtures] tags=[:static, :legend] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        rows = zoom_rows()
        fig = (scatter(rows; col=:kind) + identity_layer) * sz
        mktempdir() do dir
            a, b = joinpath(dir, "a.svg"), joinpath(dir, "b.svg")
            vsave(fig, a)
            vsave(fig * zoom, b)
            @test read(a, String) == read(b, String)
        end
    end
end

@testitem "legend selections zoom each panel's axes in the browser" setup=[AoVLegendZoomFixtures] tags=[:regression, :browser, :legend, :auto_remap] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    rows = zoom_rows()
    # One view draws panel P's rows; the facets draw both panels.
    prow = filter(r -> r.kind == "P", rows)
    plain = (scatter(prow) + identity_layer) * sz
    independent = config(facet=(; linkxaxes=:none, linkyaxes=:none))
    faceted = (scatter(rows; col=:kind) + identity_layer) * sz
    page = [vdraw(plain * zoom; id="lz-plain"),
        vdraw(plain * zoom; id="lz-canvas"),
        vdraw(plain; id="lz-off"),
        vdraw(plain * zoom * config(axis=(; limits=(nothing, (-5, 70)))); id="lz-limits"),
        vdraw(faceted * zoom * independent; id="lz-facet"),
        vdraw(faceted * zoom; id="lz-shared"),
        auto_remap_node("lz-picker", (scatter(prow) + identity_layer) * sz * zoom;
            dims=["g" => "Group", "h" => "Half"], pinned=:detail),
        with_plot_caption(faceted * zoom * independent, "Predicted against observed"; plot_id="lz-caption"),
        # Canvas, for clicks at a position inside the plot area: the
        # reporter's facet panels, a tooltip scatter (its nearest-point
        # overlay covers the plot area) and facet panels without the setting.
        vdraw(faceted * zoom * independent; id="lz-facet-canvas"),
        vdraw(scatter(prow) * sz * zoom; id="lz-scatter-canvas"),
        vdraw(faceted * independent; id="lz-off-facet-canvas")]
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-legend-zoom-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "legend_zoom.js"), String)
            # SVG, so the driver can click a legend label as a reader does;
            # `lz-canvas` keeps the canvas, for a pan as `mark_click.js` drags.
            svg = "<script>const originalEmbed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "originalEmbed(el,spec,Object.assign({},opts,{renderer:/canvas/.test(String(el))?'canvas':'svg'}));</script>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * svg *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,2400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-legend-zoom-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "legend zoom browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
