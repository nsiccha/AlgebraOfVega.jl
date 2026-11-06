using TestItemRunner

# A wide data preview scrolls in a frame of its own (snag `show-data-table-6b2e6950`,
# reporter ODLPlaus:review:ux: opening "Daten anzeigen" in a 561 px map pane widened
# the whole page by 1,006 px and laid the table over the column beside the pane).
@testitem "a data table scrolls in its own frame and leaves the page its width" tags=[:regression, :browser, :caption, :texts] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    # Long words set a column's narrowest width, so many of them outgrow any pane.
    columns = (Symbol("column_with_a_rather_long_name_", i) => ["value_of_some_length_$(i)_$(j)" for j in 1:60] for i in 1:14)
    wide = (; x=collect(1.0:60.0), y=collect(1.0:60.0), f=repeat(["a", "b"], 30), columns...)
    points(rows; kw...) = data(rows) * mapping(:x, :y) * visual(Scatter) * config(; width=200, height=80, kw...)
    roomy = (; x=[1.0, 2.0], y=[1.0, 2.0], f=["a", "b"])
    # A faceted figure merges its layers' rows into one dataset, listed per layer.
    two_sources = (data(wide) * mapping(:x, :y; col=:f) * visual(Scatter) +
        data(roomy) * mapping(:x, :y; col=:f) * visual(Lines)) * config(width=120, height=80)
    summary = data((; value=collect(1.0:40.0), group=repeat(["a_rather_long_group_name", "another_long_group_name"], 20))) *
        mapping(:value; y=:group) * pointinterval() * config(width=200, height=80)
    own_table = h.table(h.tr((h.td("a_long_cell_of_a_table_the_caller_wrote_$i") for i in 1:14)...))
    de = plot_texts(:de)

    # The accessible name lives in the words the runtime writes.
    @test plot_texts().scrollable_table == "Scrollable table" && de.scrollable_table == "Scrollbare Tabelle"
    @test plot_texts(:de; scrollable_table="Verschiebbar").scrollable_table == "Verschiebbar"
    css = read(joinpath(vega_vendor_dir(), "aov.css"), String)
    # A printout shows the whole table, not the height of a window.
    @test occursin("@media print { .aov-table-frame { max-height: none; overflow: visible; contain: none; } }", css)
    # The runtime builds the frames when a preview opens; the page's bytes stay plain.
    @test !occursin("aov-table-frame", html(with_plot_caption(points(wide), "Bytes"; plot_id="tf-bytes")))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-table-frame-") do dir
            caption(id, title; kw...) = with_plot_caption(points(wide), title; plot_id=id, kw...)
            cards = h.div(
                # A narrow pane in plain block flow, as a map pane holds the figure.
                h.div(; id="tf-pane", style="width:560px")(caption("tf-raw", "Messwerte")),
                h.div(; id="tf-pane-de", style="width:560px")(caption("tf-de", "Felder"; texts=de)),
                # Columns that take a minimum width from their content.
                h.div(; id="tf-grid", style="display:grid;grid-template-columns:1fr 1fr;width:1000px")(
                    h.div(caption("tf-in-grid", "In a grid")), h.div(; id="tf-grid-right")("Beside")),
                h.div(; id="tf-flex", style="display:flex;width:1000px")(
                    h.div(; style="flex:1")(caption("tf-in-flex", "In a row")), h.div(; id="tf-flex-right", style="flex:1")("Beside")),
                # Room for the table: no scrolling, no tab stop.
                h.div(; style="width:560px")(with_plot_caption(points(roomy), "Fits"; plot_id="tf-fits")),
                # Summary and raw rows, with the toggle between them.
                h.div(; id="tf-both-pane", style="width:220px")(with_plot_caption(summary, "Summary"; plot_id="tf-both")),
                # Two sources: two tables, each under its heading.
                h.div(; style="width:560px")(with_plot_caption(two_sources, "Two"; plot_id="tf-two")),
                # A summary the caller wrote, with and without the raw rows beside it.
                h.div(; style="width:560px")(caption("tf-own", "Own"; summary_table=own_table, data_preview=false)),
                h.div(; style="width:560px")(caption("tf-own-raw", "Own and raw"; summary_table=own_table)),
                # The public entry point, into a container of the app's.
                h.div(; style="width:560px")(vdraw(points(wide); id="tf-app"), h.div(; id="tf-app-box")),
            )
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            style = sprint(show, MIME"text/html"(), HTMXObjects.caption_style())
            page = to_html(cards; title="Frames", source=:inline, head_extra="<link rel=\"stylesheet\" href=\"pico.min.css\">" * style)
            driver = read(joinpath(@__DIR__, "table_frame.js"), String)
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "page.html"), page[1:prevind(page, cut)] * "<script>" * driver * "</script>" * page[cut:end])
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-table-frame-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 100
                @test isempty(report["failures"])
                @info "table frame browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
