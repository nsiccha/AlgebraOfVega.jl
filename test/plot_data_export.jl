using TestItemRunner

# Which rows a figure's ⬇ CSV button and "Show data" pane give: one group per
# dataset that draws values, for a figure with or without facets. Before, a figure
# without facets gave only its first layer's rows and omitted later layers.
@testitem "a figure's CSV and data preview in the browser" tags=[:caption, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    Text = AlgebraOfVega.Makie.Text
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        square(key, x, y) = Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("SN_L" => key),
            "geometry" => Dict{String,Any}("type" => "Polygon",
                "coordinates" => [[[x, y], [x + 1, y], [x + 1, y + 1], [x, y + 1], [x, y]]]))
        geo = Dict{String,Any}("type" => "FeatureCollection",
            "features" => [square("01", 8.0, 50.0), square("02", 9.0, 50.0), square("03", 10.0, 50.0)])
        regions = (; SN_L=["01", "02", "03"], name=["Eins", "Zwei", "Drei"])
        names = (; SN_L=["01"], label_lon=[8.5], label_lat=[50.5], label_text=["Eins"])
        points = (; point_key=["a", "b", "c", "d"], lon=[8.2, 8.8, 9.5, 10.5], lat=[50.2, 50.8, 50.5, 50.5],
            value=[1.5, 2.5, 3.5, 4.5])
        cells = (; SN_L=["01", "02"], value=[1.5, 2.5])

        shapes(rows) = data(rows) * mapping(:SN_L) * geoshape(geo; key=:SN_L)
        labels = data(names) * mapping(:label_lon, :label_lat; text=:label_text)
        halo = labels * visual(Text; color="#ffffff") + labels * visual(Text; color="#111111")
        # The reported shape: uncoloured regions, an outline, a name in dark type over
        # a white halo, and the values last, in a table of their own.
        reported_map = shapes(regions) * visual(; color="#d9d9d9") + shapes(regions) * visual(; fill=nothing, stroke="#333333") +
            halo + data(points) * mapping(:lon, :lat; color=:value) * visual(Scatter)
        # The values colour the first layer, and the regions come later as context.
        coloured_map = data(cells) * mapping(:SN_L; color=:value) * geoshape(geo; key=:SN_L) +
            shapes(regions) * visual(; fill=nothing, stroke="#333333") + halo
        outline_only = shapes(regions) * visual(; fill=nothing, stroke="#333333") + halo

        obs = (; x=[1.0, 2.0, 3.0], y=[1.1, 1.9, 3.2])
        model = (; x=[1.0, 2.0, 3.0, 4.0], m=[1.0, 2.0, 3.0, 4.0])
        two_layers = data(obs) * mapping(:x, :y) * visual(Scatter) + data(model) * mapping(:x, :m) * visual(Lines)
        one_layer = data(obs) * mapping(:x, :y) * visual(Scatter)

        panel(g, x, y) = (; x, y, g)
        facet_obs = panel(["a", "b", "a"], [1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
        facet_model = panel(["a", "b"], [1.0, 2.0], [3.0, 4.0])
        facet_note = (; g=["a"], x=[2.0], y=[2.0], note=["hier"])
        faceted = data(facet_obs) * mapping(:x, :y; col=:g) * visual(Scatter) +
            data(facet_model) * mapping(:x, :y; col=:g) * visual(Lines) +
            data(facet_note) * mapping(:x, :y; text=:note, col=:g) * visual(Text)
        # A sparse row × column grid with per-column Y: `__aov_pad` rows hold its cells.
        sparse = data((; x=[1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0],
                y=[1.0, 3.0, 2.0, 4.0, 5.0, 7.0, 6.0, 8.0, 9.0, 11.0, 10.0, 12.0], draw=repeat(1:2, 6),
                r=repeat(["r1", "r2", "r1"], inner=4), c=repeat(["c1", "c1", "c2"], inner=4))) *
            mapping(:x, :y; group=:draw, row=:r, col=:c) * lineribbon() *
            config(scales=scales(Y=(; scale=Dict("c1" => log10))))

        card(id, spec; kw...) = with_plot_caption(spec * config(width=300, height=200), id; plot_id=id, kw...)
        mktempdir(prefix="kb-aov-plot-data-export-") do dir
            cards = h.div(
                card("x-map", reported_map),
                card("x-coloured", coloured_map),
                card("x-outline", outline_only),
                card("x-two", two_layers),
                card("x-labelled", two_layers; layer_labels=Dict("_s2" => "Modell")),
                card("x-one", one_layer),
                card("x-facet", faceted),
                card("x-sparse", sparse))
            style = sprint(show, MIME"text/html"(), HTMXObjects.caption_style())
            page = to_html(cards; title="Export", source=:inline, head_extra=style)
            driver = read(joinpath(@__DIR__, "plot_data_export.js"), String)
            cut = first(findlast("</body>", page))
            path = joinpath(dir, "export.html")
            write(path, page[1:prevind(page, cut)] * "<script>" * driver * "</script>" * page[cut:end])
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=20000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-plot-data-export-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 35
                @test isempty(report["failures"])
                @info "plot data export browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
