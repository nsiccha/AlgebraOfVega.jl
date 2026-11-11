using TestItemRunner

# A captioned plot's downloads share one "⬇ Export ▾" menu, so they leave the
# caption's title its room.
@testsnippet AoVCaptionMenuFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects
    # HTMX escapes the quotes of an attribute value; the browser decodes them.
    html(x) = replace(sprint(show, MIME"text/html"(), x), "&#39;" => "'")
    count_of(needle, text) = length(findall(needle, text))
    rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "a"])
    spec = data(rows) * mapping(:x, :y; color=:g) * visual(Scatter) * config(width=300, height=160)
    # What a caption row's button carries; a menu row does not.
    const ROW_BUTTON = "class=\"outline caption-action\""
end

@testitem "with_plot_caption folds its downloads into one menu" setup=[AoVCaptionMenuFixtures] tags=[:caption] begin
    page = html(with_plot_caption(spec, "Errors"; plot_id="menu-a"))
    @test count_of(ROW_BUTTON, page) == 1
    @test occursin("⬇ Export", page)
    @test occursin("popovertarget=\"menu-a-download-menu\">", page)
    @test occursin("id=\"menu-a-download-menu\"", page) && occursin("popover=\"auto\"", page)
    # All four formats, each still calling the runtime, each closing the menu.
    for (word, call) in (("⬇ CSV", "AoV.downloadPlotData('menu-a'"), ("⬇ PNG", "AoV.downloadPlotImage('menu-a', 'png'"),
                         ("⬇ SVG", "AoV.downloadPlotImage('menu-a', 'svg'"), ("⬇ HTML", "AoV.downloadPlotHtml('menu-a'"))
        @test occursin(word, page)
        @test occursin(call, page)
    end
    @test count_of("popovertargetaction=\"hide\"", page) == 4

    # The node form and to_html carry it too.
    node = html(with_plot_caption(vdraw(spec; id="menu-n"), "Errors"; plot_id="menu-n"))
    @test occursin("id=\"menu-n-download-menu\"", node)
    @test occursin("id=\"menu-p-download-menu\"", to_html(spec, "Errors"; plot_id="menu-p"))

    # download_menu=false: a button each, as before, and no menu.
    plain = html(with_plot_caption(spec, "Errors"; plot_id="menu-a", download_menu=false))
    @test count_of(ROW_BUTTON, plain) == 4
    @test !occursin("popover", plain) && !occursin("⬇ Export", plain)
    @test occursin("⬇ PNG", plain) && occursin("⬇ HTML", plain)

    # A single download stays a plain button; no download shows nothing.
    one = html(with_plot_caption(spec, "Errors"; plot_id="menu-o", images=(), html_download=false))
    @test count_of(ROW_BUTTON, one) == 1 && occursin("⬇ CSV", one) && !occursin("popover", one)
    png = html(with_plot_caption(spec, "Errors"; plot_id="menu-o", images=(:png,), data_download=false, html_download=false))
    @test count_of(ROW_BUTTON, png) == 1 && occursin("⬇ PNG", png) && !occursin("popover", png)
    none = html(with_plot_caption(spec, "Errors"; plot_id="menu-o", images=nothing, data_download=false, html_download=false))
    @test count_of(ROW_BUTTON, none) == 0 && !occursin("caption-actions", none)
    # Only the enabled formats are in the menu.
    two = html(with_plot_caption(spec, "Errors"; plot_id="menu-t", images=(:svg,), html_download=false))
    @test occursin("⬇ SVG", two) && !occursin("⬇ PNG", two) && !occursin("⬇ HTML", two)
    @test count_of("popovertargetaction=\"hide\"", two) == 2

    # What is not a download stays in the row, after the menu.
    extra = html(with_plot_caption(spec, "Errors"; plot_id="menu-e", share_url="/p/x",
        extra_actions=(h.button("Mine"; type="button", class="outline caption-action"),)))
    @test count_of(ROW_BUTTON, extra) == 3
    menu = first(findfirst("id=\"menu-e-download-menu\"", extra))
    @test first(findfirst(">Mine<", extra)) > menu && first(findfirst(">Share<", extra)) > first(findfirst(">Mine<", extra))
    body = extra[menu:prevind(extra, first(findfirst(">Mine<", extra)))]
    @test occursin("⬇ CSV", body)
end

@testitem "the download menu's words come from plot_texts" setup=[AoVCaptionMenuFixtures] tags=[:caption, :texts] begin
    @test plot_texts().download == "⬇ Export" && plot_texts(:de).download == "⬇ Export"
    own = html(with_plot_caption(spec, "Fehler"; plot_id="menu-w",
        texts=plot_texts(:de; download="⬇ Herunterladen", csv="Daten als CSV")))
    @test occursin("⬇ Herunterladen", own) && occursin("Daten als CSV", own) && !occursin("⬇ Export", own)
end

# Markdown and PDF reports read the page's markdown view: the menu leaves it as
# the separate buttons do.
@testitem "the download menu stays out of the markdown view" setup=[AoVCaptionMenuFixtures] tags=[:caption] begin
    md(x) = HTMXObjects.to_markdown_string(x)
    caption = HTMXObjects.CaptionSpec(; title="Errors", short="per run", long="Notes")
    with_menu = md(with_plot_caption(spec, caption; plot_id="menu-m"))
    buttons = md(with_plot_caption(spec, caption; plot_id="menu-m", download_menu=false))
    @test with_menu == buttons
    @test !occursin("Export", with_menu) && !occursin("popover", with_menu)
    report = md(with_plot_caption(spec, caption; plot_id="menu-m", static_image="fig.png", alt="A scatter"))
    @test occursin("fig.png", report) && !occursin("Export", report)
end

"""
The menu in a real browser on a Pico page, light and dark: it opens under its
button, is not clipped by a box around the figure, keeps the page's colours,
runs each download and closes, follows the page's scroll, stays in the viewport
when its button sits at the left edge, and works in the saved HTML page.
Keyboard, mouse and touch go through the browser's own popover handling, so
they were checked with real input over CDP (decision on `0bjkegs`).
"""
@testitem "the download menu in the browser" setup=[AoVCaptionMenuFixtures] tags=[:caption, :browser] begin
    using JSON
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-caption-menu-") do dir
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            pico = only(filter(f -> occursin("pico", f) && endswith(f, ".css"),
                [relpath(joinpath(r, f), dir) for (r, _, fs) in walkdir(dir) for f in fs]))
            caption = HTMXObjects.CaptionSpec(; title="Gemessene Werte",
                short="Je Messstelle der letzte archivierte Wert. Grau: kein Wert in dieser Ebene.")
            cards = h.div(
                h.div(; id="room", style="width:645px;margin:40px 0 40px auto")(
                    with_plot_caption(spec, caption; plot_id="cm-room", texts=plot_texts(:de))),
                # A box that clips what overflows it, as a scrolling pane does.
                h.div(; style="width:645px;height:140px;overflow:hidden;margin:0 0 40px auto")(
                    with_plot_caption(spec, "Geklippt"; plot_id="cm-clip", data_preview=false)),
                # A column too narrow for the row beside the title: the button sits at the left.
                h.div(; style="width:150px;margin:0")(
                    with_plot_caption(spec, "Schmal"; plot_id="cm-left", data_preview=false)),
                h.div(; style="width:645px")(with_plot_caption(spec, "Einzeln"; plot_id="cm-plain",
                    data_preview=false, download_menu=false)),
                h.div(; style="height:2400px")())
            style = sprint(show, MIME"text/html"(), HTMXObjects.caption_style())
            page = to_html(cards; title="Menu", source=:inline,
                head_extra="<link rel=\"stylesheet\" href=\"$pico\">" * style)
            driver = read(joinpath(@__DIR__, "caption_menu.js"), String)
            cut = first(findlast("</body>", page))
            path = joinpath(dir, "menu.html")
            write(path, page[1:prevind(page, cut)] * "<script>" * driver * "</script>" * page[cut:end])
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=20000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-caption-menu-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 57
                @test isempty(report["failures"])
                @info "caption menu browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
