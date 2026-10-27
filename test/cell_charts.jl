using TestItemRunner

# A table cell that holds a breakdown shows it as a small chart on a scale the
# column shares, plus its total (user principle `distributions-as-charts`,
# `VerkehrsStrukturdaten:ux/decisions/2026-10-26T14-22-29-072-06zfdtk`). Before
# `cell_charts`, an app drew one full `vdraw` per cell (one Vega view, compile
# and resize observer each: about 0.3–0.55 s and 13 MB per 60 cells), hid the
# axes and legend through raw `config(...)`, passed the shared maximum by hand
# and built the Markdown text itself (snag `aov-in-cell-brea-2051993f`, design
# decision `AlgebraOfVega:snag.aov-in-cell-brea-2051993f/decisions/2026-10-26T18-24-16-240-15i6kwf`).

@testsnippet AoVCellFixtures begin
    cell_classes = ["200–499", "500–999", "1000–2499"]
    # Site 11002 has the largest bar (9); site 11003 has no firm at all.
    cell_rows = (; site=repeat([11001, 11002, 11003], inner=3), klasse=repeat(cell_classes, 3),
        n=[3, 0, 1, 9, 2, 0, 0, 0, 0])
    cell_spec(rows=cell_rows) = data(rows) *
        mapping(:klasse => sorter(cell_classes) => "Größenklasse", :n => "Betriebe"; layout=:site) * visual(BarPlot)
    cell_html(x) = sprint(show, MIME"text/html"(), x)
    cell_md(x) = sprint(show, MIME"text/markdown"(), x)
end

@testitem "cell charts: one lowered column, a <td> per key, Markdown text" setup=[AoVCellFixtures] tags=[:cells] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, HTMX, JSON

    cells = cell_charts(cell_spec(); texts=table_texts(:de))
    col = cells.column
    vl = col.vl
    # The figure without its facet, one frame per key, nothing around the bars.
    @test !haskey(vl, "facet") && !haskey(vl["encoding"], "facet") && !haskey(vl, "columns")
    @test vl["_aov"]["frame"]["field"] == "site"
    @test vl["_aov"]["frame"]["values"] == [11001, 11002, 11003]
    @test any(p -> p["name"] == "aov_frame", vl["params"])
    @test (vl["width"], vl["height"], vl["padding"]) == (120, 24, 0)
    @test vl["config"]["axis"]["disable"] === true && vl["config"]["legend"]["disable"] === true
    @test vl["config"]["view"]["stroke"] === nothing
    # Bars start at zero, so lengths compare across cells; no zoom or legend params.
    @test vl["encoding"]["y"]["scale"]["zero"] === true
    @test all(p -> p["name"] == "aov_frame", vl["params"])
    @test vl["_aov"]["cells"]["own"] == String[]

    @test collect(keys(cells)) == [11001, 11002, 11003] && haskey(cells, 11002) && !haskey(cells, 1)
    @test col.totals == Dict(11001 => 4.0, 11002 => 11.0, 11003 => 0.0)
    @test col.parts[11002] == ["200–499" => 9.0, "500–999" => 2.0, "1000–2499" => 0.0]

    first_td, second_td = cell_html(cells[11002]), cell_html(cells[11001])
    # The column's figure travels in the first cell built, every cell finds it by id.
    @test occursin("AoV.cellColumn(\"$(col.id)\"", first_td) && occursin("AoV.cell(", first_td)
    @test !occursin("cellColumn", second_td) && occursin("AoV.cell(", second_td)
    @test occursin("data-aov-cells=\"$(col.id)\"", second_td)
    @test occursin("data-sort-value=\"11\"", first_td) && occursin("data-htmxo-number=\"11\"", first_td)
    @test occursin("class=\"aov-cells\"", first_td)
    @test occursin("<span class=\"aov-cell-total\">11</span>", first_td)
    @test occursin("aria-label=\"200–499: 9; 500–999: 2\"", first_td)
    @test occursin("width:120px;height:24px", first_td)
    # The Markdown view: the total and the breakdown as text, no chart.
    md = cell_md(h.tr(cells[11001]))
    @test occursin("4 (200–499: 3; 1000–2499: 1)", md)
    @test !occursin("cellColumn", md) && !occursin("aov-cell", md)
    # A key with no rows: total 0, empty chart, no text.
    @test occursin("data-sort-value=\"0\"", cell_html(cells[99999]))
    @test strip(cell_md(h.tr(cells[11003]))) |> s -> occursin("0", s) && !occursin("(", s)

    # German digits, a custom total, label and text.
    area = cell_charts(data((; site=[1, 1, 2, 2], f=["a", "b", "a", "b"], t=[50.44, 3.0, 1.24, 0.0])) *
        mapping(:f, :t; layout=:site) * visual(BarPlot) * config(width=150, height=34);
        texts=table_texts(:de), sigdigits=2, label=x -> "$(round(Int, x)) Tsd. m²")
    @test (area.column.width, area.column.height) == (150, 34)
    a = cell_html(area[1])
    @test occursin(">53 Tsd. m²<", a) && occursin("data-sort-value=\"53.44\"", a)
    @test occursin("a: 50; b: 3", cell_md(h.tr(area[1])))
    @test occursin("a: 1,2", cell_md(h.tr(area[2])))
    custom = cell_charts(cell_spec(); total=rows -> count(r -> r.n > 0, rows), text=rows -> "custom")
    @test occursin("data-sort-value=\"2\"", cell_html(custom[11002])) && occursin("(custom)", cell_md(h.tr(custom[11002])))

    # Counting rows: one positional and frequency().
    firms = (; site=[1, 1, 1, 2], klasse=["x", "y", "x", "y"])
    counted = cell_charts(data(firms) * mapping(:klasse; layout=:site) * frequency())
    @test counted.column.totals == Dict(1 => 3.0, 2 => 1.0)
    @test counted.column.parts[1] == ["x" => 2.0, "y" => 1.0]

    # An authored zero, unlinked axes, and a stable id for the same figure.
    @test cell_charts(cell_spec() * config(scales=scales(Y=(; zero=false)))).column.vl["encoding"]["y"]["scale"]["zero"] === false
    own = cell_charts(cell_spec() * config(facet=(; linkyaxes=:none))).column.vl
    @test own["_aov"]["cells"]["own"] == ["y"] && !haskey(own, "resolve")
    @test cell_charts(cell_spec()).column.id == col.id
    @test cell_charts(cell_spec(); id="firms.col").column.id == "firms-col"
end

@testitem "cell charts refuse what has no cell" setup=[AoVCellFixtures] tags=[:cells] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects

    msg(f) = try f(); "" catch e; e isa ArgumentError ? e.msg : rethrow() end
    @test occursin("layout=", msg(() -> cell_charts(data(cell_rows) * mapping(:klasse, :n) * visual(BarPlot))))
    @test occursin("row=", msg(() -> cell_charts(data(cell_rows) *
        mapping(:klasse, :n; layout=:site, row=:klasse) * visual(BarPlot))))
    @test occursin("frame", msg(() -> cell_charts(cell_spec() * config(frame=:site))))
    draws = (; site=repeat([1, 2], inner=4), g=repeat(["a", "b"], 4), v=collect(1.0:8.0))
    @test occursin("bands=", msg(() -> cell_charts(data(draws) * mapping(:v, y=:g; layout=:site) * pointinterval())))
end

@testitem "cell charts in the browser: shared scales, drawn near the viewport, released" setup=[AoVCellFixtures] tags=[:cells, :browser, :regression] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, HTMX, JSON

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        firms = cell_charts(cell_spec(); texts=table_texts(:de))
        own = cell_charts(cell_spec() * config(facet=(; linkyaxes=:none)); id="own")
        late = cell_charts(cell_spec(); id="late")
        table(cells, n) = sortable_table(["Zelle", "Betriebe"],
            [h.tr(; id="row-$(s)-$(n)")(h.td(string(s)), cells[s]) for s in (11001, 11002, 11003)])
        # `#far-table` shows the first column again (its scales are known by
        # then), `#late-table` a column of its own; both start far below.
        page = [h.div(; id="near")(table(firms, 1)), h.div(; id="own-table")(table(own, 2)),
            h.div(; style="height:6000px"), h.div(; id="far-table")(table(firms, 3)),
            h.div(; style="height:6000px"), h.div(; id="late-table")(table(late, 4))]
        mktempdir(prefix="kb-aov-cells-") do dir
            head = join(cell_html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(cell_html(p) for p in page) *
                "<script>" * read(joinpath(@__DIR__, "cell_charts.js"), String) * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1000
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"aov-cells-results\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                report = JSON.parse(replace(m[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 14
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
