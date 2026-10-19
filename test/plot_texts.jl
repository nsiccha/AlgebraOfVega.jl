using TestItemRunner

"""
`plot_texts(locale; texts...)` builds the words of AoV's plot chrome: built-in
English and German sets, per-text overrides, and loud errors for an unknown
locale, text or placeholder (snag `algebraofvega-wi-26fe4c53`: a German
dashboard's captioned plots showed English buttons and "Show data").
"""
@testitem "plot_texts locale sets, overrides and errors" tags=[:caption, :texts] begin
    using AlgebraOfVega

    en, de = plot_texts(), plot_texts(:de)
    @test en == plot_texts(:en)
    @test en.show_data == "Show data" && de.show_data == "Daten anzeigen"
    @test de.color == "Farbe" && de.lang == "de" && en.lang == "en"
    @test en.more == "More" && de.more == "Mehr"
    # Every text has a value in every locale.
    for t in (en, de), name in fieldnames(PlotTexts)
        @test !isempty(getfield(t, name))
    end

    custom = plot_texts(:de; show_data="Kennzahlen anzeigen", image="Bild ({format})")
    @test custom.show_data == "Kennzahlen anzeigen"
    @test custom.image == "Bild ({format})"
    @test custom.share == de.share
    @test AlgebraOfVega._plot_text(custom, :image; format="PNG") == "Bild (PNG)"
    @test AlgebraOfVega._plot_text(de, :interval; point="Median", width="95%") ==
        "Median [95%-Kredibilitätsintervall]"

    @test_throws ArgumentError plot_texts(:fr)
    @test_throws ArgumentError plot_texts(:de; show_dta="x")
    @test_throws ArgumentError plot_texts(:de; image="⬇ {fromat}")
    @test_throws ArgumentError plot_texts(:de; csv="⬇ {format}")
    err = try plot_texts(:de; show_dta="x") catch e; e end
    @test occursin("show_data", sprint(showerror, err))
end

"""
The browser runtime writes some texts itself (the data preview, its summary
caption, the HTML download). Its English set must equal the Julia `:en` set
for those names: the runtime uses it whenever a plot carries no texts.
"""
@testitem "plot_texts runtime English set matches the Julia set" tags=[:caption, :texts] begin
    using AlgebraOfVega, JSON

    runtime = read(joinpath(vega_vendor_dir(), "aov-runtime.js"), String)
    m = match(r"\n\s*_TEXTS_EN: (\{[^\n]*\}),\n", runtime)
    @test !isnothing(m)
    js = JSON.parse(m[1])
    en = plot_texts()
    @test Set(keys(js)) == Set(string.(AlgebraOfVega._RUNTIME_TEXT_NAMES))
    for name in AlgebraOfVega._RUNTIME_TEXT_NAMES
        @test js[string(name)] == getfield(en, name)
    end
end

"""
`texts=` reaches every text of a captioned plot: caption buttons, Share,
the data preview, the channel picker and a standalone page's `lang`. Without
it the output keeps its English texts and carries no texts attribute.
"""
@testitem "captioned plot texts" tags=[:caption, :texts, :auto_remap] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; value=collect(1.0:24.0), model=repeat(["m1", "m2", "m3", "m4"], inner=6),
        state=repeat(["a", "b"], inner=12), group=repeat(["g1", "g2"], 12))
    spec = data(rows) * mapping(:value => "Sekunden"; y=:model => "Modell", color=:state => "Zustand") *
        pointinterval() * config(height=160)
    remap = (; dims=["state" => "Zustand", "group" => "Gruppe"], pinned=:row)
    de = plot_texts(:de; show_data="Kennzahlen anzeigen")

    german = html(with_plot_caption(spec, CaptionSpec(; title="Laufzeiten", long="Erläuterung");
        plot_id="texts-de", auto_remap=remap, share_url="/p/x?force=1", texts=de))
    for text in ("<summary>Mehr</summary>", "⬇ CSV", "⬇ PNG", "⬇ SVG", "⬇ HTML", ">Teilen<", "Kopiert!", "<summary>Kennzahlen anzeigen</summary>",
                 ">Übersicht<", ">Rohdaten<", "Farbe: ", "Zeile: ", "Spalte: ", "Ungruppiert: ")
        @test occursin(text, german)
    end
    for text in ("<summary>More</summary>", ">Share<", "Copied!", "Show data", ">Pretty<", ">Raw<", "Color: ", "Row: ", "Column: ", "Ungrouped: ")
        @test !occursin(text, german)
    end
    attr = match(r"data-aov-texts=\"([^\"]*)\"", german)
    @test !isnothing(attr)
    sent = JSON.parse(replace(attr[1], "&quot;" => "\"", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&#39;" => "'"))
    @test sent["no_data"] == de.no_data && sent["interval"] == de.interval && sent["lang"] == "de"
    @test Set(keys(sent)) == Set(string.(AlgebraOfVega._RUNTIME_TEXT_NAMES))

    # Without `texts=`: the English texts, and no attribute for the runtime.
    english = html(with_plot_caption(spec, CaptionSpec(; title="Run times", long="Notes");
        plot_id="texts-en", auto_remap=remap, share_url="/p/x"))
    for text in ("<summary>More</summary>", "⬇ CSV", ">Share<", "Copied!", "<summary>Show data</summary>", ">Pretty<", ">Raw<", "Color: ", "Ungrouped: ")
        @test occursin(text, english)
    end
    @test !occursin("data-aov-texts", english)
    @test html(with_plot_caption(spec, "Run times"; plot_id="texts-en", texts=plot_texts())) ==
        html(with_plot_caption(spec, "Run times"; plot_id="texts-en"))

    # A captioned figure without the data preview carries the texts too, for
    # the HTML download.
    bare = html(with_plot_caption(vdraw(spec; id="texts-bare"), "Laufzeiten"; plot_id="texts-bare",
        data_preview=false, texts=de))
    @test occursin("data-aov-texts", bare) && occursin("<figure class=\"captioned\"", bare)

    # The picker alone, and the share helpers.
    @test occursin("Farbe: ", html(auto_remap_node("texts-picker", spec; dims=remap.dims, texts=de)))
    @test occursin("Kopiert!", html(with_caption_share(h.div("card"), "/r"; texts=de)))
    share = html(summary_share_button("/r"; texts=de))
    @test occursin("aria-label=\"Teilbaren Link kopieren\"", share)
    @test occursin("title=\"Einen teilbaren Link zu dieser Ansicht kopieren\"", share)

    # Standalone pages declare the texts' language.
    @test occursin("<html lang=\"de\">", to_html(spec, "Laufzeiten"; plot_id="texts-page", texts=de))
    @test occursin("<html lang=\"en\">", to_html(spec, "Run times"; plot_id="texts-page"))
    @test occursin("<title>AoV-Grafik</title>", to_html(vdraw(spec; id="texts-node"); texts=de))
end

"""
In the browser the runtime writes a German card's preview texts and HTML
download in German, and an English card's in English, on the same page.
"""
@testitem "captioned plot texts in the browser" setup=[AoVBrowserServer] tags=[:caption, :texts, :browser] begin
    using AlgebraOfVega, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; value=collect(1.0:24.0), model=repeat(["m1", "m2", "m3", "m4"], inner=6),
        state=repeat(["a", "b"], inner=12))
    spec = data(rows) * mapping(:value => "Sekunden"; y=:model => "Modell", color=:state => "Zustand") *
        pointinterval() * config(height=160)
    de = plot_texts(:de)
    cards = h.div(with_plot_caption(spec, "Laufzeiten"; plot_id="texts-de", texts=de),
        with_plot_caption(spec, "Run times"; plot_id="texts-en"))
    page = to_html(cards; texts=de, source=:inline)
    expected = Dict(
        "texts-de" => (; caption="Median [95%-Kredibilitätsintervall]", no_data=de.no_data,
            no_summary=de.no_summary, lang="de"),
        "texts-en" => (; caption="Median [95% credible interval]", no_data="(no data available)",
            no_summary="(no summary data available)", lang="en"))
    payload = replace(JSON.json((; expected)), "</" => "<\\/")
    driver = read(joinpath(@__DIR__, "plot_texts.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-texts-") do dir
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "texts.html"), page[1:prevind(page, cut)] *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>" *
                page[cut:end])
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $(root * "/texts.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-texts-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] == 13
                    @test isempty(report["failures"])
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
