using TestItemRunner

# A data preview of more than 1,000 rows shows them a page at a time: opening
# "Show data" on a 120,802-row map built every row and took the tab from
# 0.4 to 7.1 GiB and 20 s (snag large-captioned-ce633d40, design decision
# 2026-11-17T00-15-59-118-05b00qc, option 1).
@testitem "a long data preview shows a page at a time, sorts and reaches every row" tags=[:regression, :browser, :caption, :texts] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    # The words: English and German defaults, an override, and the placeholders
    # each text takes.
    en, de = plot_texts(), plot_texts(:de)
    @test en.table_rows == "Rows {from}–{to} of {total}" && de.table_rows == "Zeilen {from}–{to} von {total}"
    @test (en.previous_page, en.next_page, de.previous_page, de.next_page) == ("Previous", "Next", "Zurück", "Weiter")
    @test AlgebraOfVega._plot_text(de, :table_page; page="2") == "Seite 2"
    @test plot_texts(:de; next_page="Vor").next_page == "Vor"
    @test_throws ArgumentError plot_texts(; table_rows="{form}–{to} of {total}")
    @test_throws ArgumentError plot_texts(; table_csv="{total}")

    # Rows in a known, unsorted order. `score` is a number, `label` a text whose
    # natural order differs from its code-point order, `code` a text that starts
    # with a number (HTMXObjects' sort reads it as that number), and `note` is
    # sometimes empty.
    rows(n) = (; x=[Float64(mod(37i, n)) for i in 1:n], y=[Float64(i % 50) for i in 1:n],
        score=[round(mod(7919i, 1013) / 10 - 50; digits=1) for i in 1:n],
        label=["item $(mod(31i, 97))" for i in 1:n], code=["$(mod(13i, 40)):$(i % 7)" for i in 1:n],
        note=[i % 5 == 0 ? "" : "n$(i % 3)" for i in 1:n])
    points(n) = data(rows(n)) * mapping(:x, :y) * visual(Scatter) * config(; width=200, height=80)
    # The runtime builds the pages when a preview opens; the page's bytes are as before.
    @test !occursin("aov-table-pager", html(with_plot_caption(points(1001), "Bytes"; plot_id="dp-bytes")))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-data-pages-") do dir
            cards = h.div(
                h.div(; style="width:700px")(with_plot_caption(points(1000), "Whole"; plot_id="dp-whole")),
                h.div(; style="width:700px")(with_plot_caption(points(2500), "Pages"; plot_id="dp-pages")),
                h.div(; style="width:700px")(with_plot_caption(points(2500), "Seiten"; plot_id="dp-de", texts=de)),
                h.div(; style="width:700px")(with_plot_caption(points(1001), "No CSV"; plot_id="dp-nocsv", data_download=false)),
                # The public entry point, into a container of the app's.
                h.div(; style="width:700px")(vdraw(points(2500); id="dp-app"), h.div(; id="dp-app-box")),
            )
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            head = html(HTMXObjects.caption_style()) * html(HTMXObjects.sortable_table_js())
            page = to_html(cards; title="Pages", source=:inline, head_extra="<link rel=\"stylesheet\" href=\"pico.min.css\">" * head)
            driver = read(joinpath(@__DIR__, "data_preview_pages.js"), String)
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "page.html"), page[1:prevind(page, cut)] * "<script>" * driver * "</script>" * page[cut:end])
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=60000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-data-pages-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 80
                @test isempty(report["failures"])
                @info "data preview pages browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
