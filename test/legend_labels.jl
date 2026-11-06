using TestItemRunner

# A label of a continuous colour's legend lies within its gradient, so the canvas
# never cuts it. A horizontal gradient centres each label on its value unless the
# value is exactly an end of the domain, and Vega's legend layout makes no room for
# what hangs past the start. So a lowest tick just inside the domain lost its first
# characters at the canvas's left edge, and the legend stated a false number:
# `−3,35` read `3,35`, `−102,5 Tsd.` read `2,5 Tsd.`, with no error. A highest tick
# did the same at the right edge of a fitted figure whose authored `gradientLength`
# filled it (snag `horizontal-gradi-806cacbf`).
@testsnippet AoVLegendLabelFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    region(i) = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("k" => "k$i"),
        "geometry" => Dict{String,Any}("type" => "Polygon", "coordinates" =>
            [[[Float64(i), 51.0], [i + 1.0, 51.0], [i + 1.0, 50.0], [Float64(i), 50.0], [Float64(i), 51.0]]]))
    geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [region(i) for i in 0:4])
    rows(lo, hi) = (; k=["k$i" for i in 0:4], v=[lo + (hi - lo) * i / 4 for i in 0:4],
        g=["a", "b", "a", "b", "a"])

    # RegionExplorer's compact thousands: a long label on a short gradient position.
    compact = "abs(datum.value) >= 9999.5 ? format(datum.value / 1e3, ',.4~r') + ' Tsd.' : datum.label"
    # What a figure draws without the fit: an authored `dx` of 0 is kept as written.
    unfitted = Dict{String,Any}("encoding" => Dict{String,Any}("labels" =>
        Dict{String,Any}("dx" => Dict{String,Any}("value" => 0))))
    # `legend` keys go on the encoding, `guide` keys in the shared `config.legend`,
    # as RegionExplorer's choropleth and hand-written app configs spell them.
    function legend_map(lo, hi; legend=Dict{String,Any}(), width=420, table=rows(lo, hi), guide...)
        cfg = Dict{String,Any}("orient" => "bottom", "titleLimit" => 0, "labelOverlap" => "greedy",
            "labelSeparation" => 8)
        for (k, v) in guide
            cfg[string(k)] = v
        end
        size = isnothing(width) ? (; height=70) : (; width, height=70)
        data(table) * mapping(:k; color=:v => "Wert") * geoshape(geo) *
            config(; size..., config=Dict{String,Any}("legend" => cfg),
                encoding=Dict{String,Any}("color" => Dict{String,Any}("legend" => legend)))
    end
    dx_of(def) = def["legend"]["encoding"]["labels"]["dx"]
    fit = Dict{String,Any}("value" => Dict{String,Any}("expr" => AlgebraOfVega._GRADIENT_LABEL_DX))
end

@testitem "a continuous colour's legend fits its labels; every other legend is left alone" setup=[AoVLegendLabelFixtures] tags=[:regression, :translation, :geoshape] begin
    plain = data(rows(1.0, 2.0)) * mapping(:k; color=:v) * geoshape(geo)
    @test dx_of(to_vegalite(plain)["encoding"]["color"]) == fit

    # Every shape: a layer's own colour, an encoding facet, the facet operator.
    xy = (; x=[1.0, 2.0, 3.0], v=[1.0, 2.0, 3.0], p=["P", "Q", "P"])
    layered = to_vegalite(data(xy) * mapping(:x, :x; color=:v) * (visual(Scatter) + visual(Lines)))
    @test all(l -> dx_of(l["encoding"]["color"]) == fit, layered["layer"])
    @test dx_of(to_vegalite(data(xy) * mapping(:x, :x; color=:v, col=:p) * visual(Scatter))["encoding"]["color"]) == fit
    facet = to_vegalite(data(xy) * mapping(:x, :x; color=:v, col=:p) * (visual(Scatter) + visual(Lines)))
    @test all(l -> dx_of(l["encoding"]["color"]) == fit, facet["spec"]["layer"])

    # A figure drawn through the picker, and the positional scales form.
    remap = (; dims=["g" => "Gruppe"], pinned=:detail)
    @test dx_of(to_vegalite(plain; auto_remap=remap)["encoding"]["color"]) == fit
    @test dx_of(to_vegalite(plain, scales(Color=(; colormap=:viridis)))["encoding"]["color"]) == fit

    # A categorical colour has a symbol legend, and no legend key appears on it.
    @test !haskey(to_vegalite(data(rows(1.0, 2.0)) * mapping(:k; color=:g) * geoshape(geo))["encoding"]["color"], "legend")

    # One colour bar: the stroke that paints the fill keeps `legend: null`.
    both = to_vegalite(data(rows(1.0, 2.0)) * mapping(:k; color=:v, strokecolor=:v) * geoshape(geo))
    @test dx_of(both["encoding"]["color"]) == fit
    @test isnothing(both["encoding"]["stroke"]["legend"])

    # A raw Vega-Lite Dict is the caller's spec.
    raw = Dict{String,Any}("mark" => "rect", "encoding" => Dict{String,Any}(
        "color" => Dict{String,Any}("field" => "v", "type" => "quantitative")))
    @test !haskey(to_vegalite(raw)["encoding"]["color"], "legend")
end

@testitem "an authored legend keeps its keys, its dx and its off switch, and is not written into" setup=[AoVLegendLabelFixtures] tags=[:regression, :translation, :geoshape] begin
    authored = Dict{String,Any}("title" => "T", "labelExpr" => compact,
        "encoding" => Dict{String,Any}("labels" => Dict{String,Any}("fontWeight" => Dict{String,Any}("value" => "bold"))))
    snapshot = deepcopy(authored)
    def = to_vegalite(legend_map(1.0, 2.0; legend=authored))["encoding"]["color"]
    @test def["legend"]["title"] == "T" && def["legend"]["labelExpr"] == compact
    @test def["legend"]["encoding"]["labels"]["fontWeight"] == Dict{String,Any}("value" => "bold")
    @test dx_of(def) == fit
    @test authored == snapshot      # the caller's Dict, used again for the next figure

    @test dx_of(to_vegalite(legend_map(1.0, 2.0; legend=unfitted))["encoding"]["color"]) ==
        Dict{String,Any}("value" => 0)
    off = data(rows(1.0, 2.0)) * mapping(:k; color=:v) * geoshape(geo) *
        config(encoding=Dict{String,Any}("color" => Dict{String,Any}("legend" => nothing)))
    @test isnothing(to_vegalite(off)["encoding"]["color"]["legend"])
end

@testitem "legend labels are drawn whole in the browser" setup=[AoVLegendLabelFixtures] tags=[:regression, :browser, :geoshape] begin
    using HTMX, JSON, Dates
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-legend-labels-") do dir
            labelled = Dict{String,Any}("labelExpr" => compact)
            compact_unfitted = merge(labelled, unfitted)
            gl = (; gradientLength=260)
            framed = (; k=repeat(rows(0, 1).k, 2), v=[-3.3502 + 0.2002 * i / 4 for i in [0:4; 4:-1:0]],
                year=[fill(2020, 5); fill(2021, 5)])
            dated = (; k=rows(0, 1).k, v=DateTime(2024, 1, 20) .+ Day.(0:40:160))
            figures = Dict(
                # The reported cases at the start of the domain, each with its control.
                "low" => legend_map(-3.3502, -3.15; gl...),
                "low-control" => legend_map(-3.3502, -3.15; legend=unfitted, gl...),
                "compact" => legend_map(-102510, -100100; legend=labelled, gl...),
                "compact-control" => legend_map(-102510, -100100; legend=compact_unfitted, gl...),
                "top" => legend_map(-102510, -100100; legend=labelled, orient="top", gl...),
                # Vega-Lite's default length is the signal `clamp(width, 100, 200)`.
                "default-length" => legend_map(-102510, -100100; legend=labelled),
                "font" => legend_map(-3.3502, -3.15; labelFontSize=16, gl...),
                "log" => data(rows(3.1, 912.0)) * mapping(:k; color=:v) * geoshape(geo) *
                    config(width=420, height=70, scales=scales(Color=(; scale=log10)),
                        config=Dict("legend" => Dict("orient" => "bottom"))),
                "dated" => data(dated) * mapping(:k; color=:v) * geoshape(geo) *
                    config(width=420, height=70, config=Dict("legend" => Dict("orient" => "bottom"))),
                "stroke" => data(rows(-102510, -100100)) * mapping(:k; color=:v, strokecolor=:v) * geoshape(geo) *
                    config(width=420, height=70, config=Dict("legend" => Dict("orient" => "bottom", "gradientLength" => 260))),
                "facet" => data(rows(-102510, -100100)) * mapping(:k; color=:v, col=:g) * geoshape(geo) *
                    config(width=180, height=70, config=Dict("legend" => Dict("orient" => "bottom", "gradientLength" => 260)),
                        encoding=Dict("color" => Dict("legend" => labelled))),
                "frame" => data(framed) * mapping(:k; color=:v) * geoshape(geo) *
                    config(width=420, height=70, frame=:year, config=Dict("legend" => Dict("orient" => "bottom", "gradientLength" => 260))),
                # A label that comes out empty leaves the others drawn.
                "null-label" => legend_map(-3.3502, -3.15;
                    legend=Dict{String,Any}("labelExpr" => "datum.value > -3.28 ? null : datum.label"), gl...),
                # Nothing to move: the pixels equal the control's.
                "fits" => legend_map(-1502000, -500000; legend=labelled, gl...),
                "fits-control" => legend_map(-1502000, -500000; legend=compact_unfitted, gl...),
                "exact" => legend_map(-3.35, -3.15; gl...),
                "exact-control" => legend_map(-3.35, -3.15; legend=unfitted, gl...),
                "vertical" => legend_map(-3.3502, -3.15; direction="vertical", gradientDirection="vertical"),
                "vertical-control" => legend_map(-3.3502, -3.15; legend=unfitted, direction="vertical", gradientDirection="vertical"),
                # Rows that arrive later get the same fit.
                "update" => legend_map(1.0, 2.0; legend=labelled, gl...))
            # The far end: a figure fitted to a 277 px column with a 260 px gradient.
            narrow = Dict(
                "high" => legend_map(2_000_000, 8_020_000; width=nothing, gl...),
                "high-control" => legend_map(2_000_000, 8_020_000; width=nothing, legend=unfitted, gl...),
                "picker" => legend_map(-3.3502, -3.15; width=nothing, gl...))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "legend_labels.js"), String)
            plots = join(html(vdraw(figures[id]; id)) for id in keys(figures))
            columns = join("<div style='width:277px'>" * html(id == "picker" ?
                auto_remap_node(id, narrow[id]; dims=["g" => "Gruppe"], pinned=:detail) :
                vdraw(narrow[id]; id)) * "</div>" for id in keys(narrow))
            update_rows = JSON.json([(; k="k$i", v=-102510 + 2410 * i / 4, g="a") for i in 0:4])
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='font-family:Arial,sans-serif'>" * plots * columns *
                "<script>window.AOV_UPDATE_ROWS=" * update_rows * "</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,2400
                --virtual-time-budget=40000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-legend-labels-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "legend label browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

@testitem "vsave writes the fitted legend labels" setup=[AoVLegendLabelFixtures] tags=[:regression, :static, :vsave] begin
    tool = get(ENV, "AOV_VL_CONVERT", something(Sys.which("vl-convert"), ""))
    if isempty(tool)
        @test_skip "the vl-convert CLI is not installed"
    else
        mktempdir(prefix="kb-legend-labels-") do dir
            # The first label's x in the file, against half its width at 10 px.
            first_x(path) = parse(Float64, match(r"translate\(([-\d.]+),[-\d.]+\)\"[^>]*>−3\.35<", read(path, String))[1])
            fitted = vsave(legend_map(-3.3502, -3.15; gradientLength=260), joinpath(dir, "fitted.svg"))
            control = vsave(legend_map(-3.3502, -3.15; legend=unfitted, gradientLength=260), joinpath(dir, "control.svg"))
            @test first_x(control) < 1          # the tick's own place, 0.3 px along the gradient
            @test first_x(fitted) >= 12         # 0.27 * 10 px * 5 characters = 13.5
        end
    end
end
