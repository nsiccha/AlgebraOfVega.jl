using TestItemRunner

"""
The caption share buttons in a real browser, on a served page whose address
the inputs have changed: `caption_share_button`, `with_plot_caption(...;
share_url=...)`, `with_caption_share` and `summary_share_button` each copy
their URL resolved against the current address (an empty URL copies the
address itself, query included), and raise no error. Before, the inline
handler of `caption_share_button` read a bare `URL` as `document.URL` and
threw "URL is not a constructor" (snag `caption-share-ur-6256f7c2`).
"""
@testitem "caption share buttons in the browser" setup=[AoVBrowserServer] tags=[:caption, :browser] begin
    using AlgebraOfVega, HTMXObjects, JSON
    import AlgebraOfGraphics
    rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0])
    spec = data(rows) * mapping(:x, :y) * visual(Scatter) * config(width=300, height=160)
    cards = h.div(
        h.div(; id="cs-row")(caption_share_button(""; texts=plot_texts(:en; share="Copy link"))),
        h.div(; id="cs-rel")(caption_share_button("other.html?a=1&force=1"; label="Relative")),
        with_plot_caption(spec, "Shared"; plot_id="cs-plot", share_url="/p/Slug/analysis?force=1&plot_height=300"),
        with_caption_share(with_plot_caption(spec, "Injected"; plot_id="cs-inj"), "/q?x=1&force=1";
            label="Injected share"),
        h.details(; id="cs-summary")(h.summary("Lazy", summary_share_button("/s?force=1")), h.div("body")))
    page = to_html(cards; source=:inline)
    driver = read(joinpath(@__DIR__, "caption_share.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-caption-share-") do dir
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "share.html"), page[1:prevind(page, cut)] * "<script>" * driver * "</script>" *
                page[cut:end])
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $(root * "/share.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-caption-share-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] == 12
                    @test isempty(report["failures"])
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
