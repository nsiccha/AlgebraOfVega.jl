using TestItemRunner

"""
A captioned figure's static image reaches the markdown view with alt text, for
reports built from it such as an accessible (PDF/UA) PDF (snag
`looked-for-the-a-b231b3da`, design decision
`AlgebraOfVega:snag.looked-for-the-a-b231b3da/decisions/2026-10-22T23-16-21-655-1l4p2wa`,
option 1). Before, the markdown view of a captioned plot held only its
`PlotSummary`, and Typst's `pdf-standard: ua-1` refuses an image without alt
text. The image is written by HTMX's own markdown writer, so these tests compare
against that writer's output rather than pinning its spelling.
"""
@testitem "captioned figure static image for reports" tags=[:caption, :markdown, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    md(x) = sprint(show, MIME"text/markdown"(), x)
    html(x) = sprint(show, MIME"text/html"(), x)
    img_md(src, alt) = strip(md(h.img(; src, alt)))

    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[2.0, 3.0, 1.0, 4.0], g=["a", "a", "b", "b"])
    spec = data(rows) * mapping(:x => "X", :y => "Y"; color=:g => "Group") * visual(Scatter) *
        config(height=160)
    cap = CaptionSpec(; title="Radon nach Kreis", short="Median je Kreis, 2025", long="Quelle: BfS.")

    plain = with_plot_caption(spec, cap; plot_id="radon")
    report = with_plot_caption(spec, cap; plot_id="radon", static_image="figs/radon.png")

    # The browser view is byte-identical; only the markdown view changes.
    @test html(report) == html(plain)
    @test occursin("**Vega-Lite figure**", md(plain))
    m = md(report)
    @test occursin(img_md("figs/radon.png", "Radon nach Kreis — Median je Kreis, 2025"), m)
    @test !occursin("**Vega-Lite figure**", m)
    # The caption, long tier included, stays.
    @test occursin("**Radon nach Kreis** — Median je Kreis, 2025 — Quelle: BfS.", m)

    # An explicit alt text replaces the caption-derived one.
    described = "Karte: Radon-Median je Kreis, höchste Werte im Süden."
    m = md(with_plot_caption(spec, cap; plot_id="radon", static_image="figs/radon.png", alt=described))
    @test occursin(img_md("figs/radon.png", described), m)
    @test !occursin("Radon nach Kreis — Median", m)
    # Without a short summary the alt text is the title.
    @test occursin(img_md("f.png", "Radon nach Kreis"),
        md(with_plot_caption(spec, "Radon nach Kreis"; plot_id="radon", static_image="f.png")))
    # A data: URI is used as given.
    uri = "data:image/png;base64,iVBORw0KGgo="
    @test occursin(img_md(uri, "Radon nach Kreis — Median je Kreis, 2025"),
        md(with_plot_caption(spec, cap; plot_id="radon", static_image=uri)))

    # The node form takes the same keywords.
    node = vdraw(spec; id="radon-node")
    @test html(with_plot_caption(node, cap; plot_id="radon-node", static_image="n.png")) ==
        html(with_plot_caption(node, cap; plot_id="radon-node"))
    @test occursin(img_md("n.png", "Radon nach Kreis — Median je Kreis, 2025"),
        md(with_plot_caption(node, cap; plot_id="radon-node", static_image="n.png")))

    # The channel picker is left out of the markdown view, and stays in the browser.
    remap = (; dims=["g" => "Group"], pinned=:row)
    picker = with_plot_caption(spec, cap; plot_id="radon-pick", auto_remap=remap)
    picker_report = with_plot_caption(spec, cap; plot_id="radon-pick", auto_remap=remap, static_image="p.png")
    @test html(picker_report) == html(picker)
    @test occursin("Assign dimensions", md(picker))
    m = md(picker_report)
    @test !occursin("Assign dimensions", m) && !occursin("**Vega-Lite figure**", m)
    @test occursin(img_md("p.png", "Radon nach Kreis — Median je Kreis, 2025"), m)

    # refused: a report figure is never decorative, so empty alt text would
    # leave a PDF/UA figure undescribed, and `alt` alone would do nothing
    # (dev §1; design decision 2026-10-22T23-16-21-655-1l4p2wa, option 1)
    @test_throws ArgumentError with_plot_caption(spec, cap; plot_id="radon", alt="Karte")
    @test_throws ArgumentError with_plot_caption(spec, cap; plot_id="radon", static_image="f.png", alt=" ")
    @test_throws ArgumentError with_plot_caption(spec, CaptionSpec(; title=""); plot_id="radon", static_image="f.png")
end

"""
The data preview's Pretty/Raw toggle stays out of the markdown view (snag
`accessible-pdf-u-e569daa4`). Its `aria-pressed` state is browser-only: the
markdown view has no raw pane to switch to. Before, HTMXObjects' markdown read
(`to_markdown_string`, which `?plain` and `pdf_report` use) projected the
pressed button as a stray `Übersicht (pressed)` line in every captioned figure
with a summary, including a report figure's PDF.
"""
@testitem "data preview toggle stays out of the markdown view" tags=[:caption, :markdown, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    md(x) = HTMXObjects.to_markdown_string(x)
    html(x) = sprint(show, MIME"text/html"(), x)
    img_md(src, alt) = strip(sprint(show, MIME"text/markdown"(), h.img(; src, alt)))

    rows = (; k=["a", "b", "c"], v=[1.0, 2.0, 3.0], q05=[0.5, 1.5, 2.5], q95=[1.5, 2.5, 3.5])
    spec = data(rows) * mapping(:k => "Kreis", :v => "Wert") *
        pointinterval(bands=[:q05 => :q95], orientation=:vertical) * config(height=160)
    cap = CaptionSpec(; title="Realisierung", short="Median und 90%-Intervall")
    de = plot_texts(:de)

    report = with_plot_caption(spec, cap; plot_id="abb", texts=de, static_image="abb.png", alt="Punkte")
    # The browser keeps the toggle, with its pressed state.
    @test occursin("aria-pressed=\"true\"", html(report)) && occursin(">Übersicht</button>", html(report))
    m = md(report)
    @test occursin(img_md("abb.png", "Punkte"), m)
    @test occursin("**Realisierung** — Median und 90%-Intervall", m)
    @test !occursin("Übersicht", m) && !occursin("Rohdaten", m) && !occursin("pressed", m)

    # A page read (`?plain`) of the same figure without a static image.
    m = md(with_plot_caption(spec, cap; plot_id="abb", texts=de))
    @test occursin("**Vega-Lite figure**", m)
    @test !occursin("Übersicht", m) && !occursin("pressed", m)

    # An explicit summary table stays in the markdown view; its toggle does not.
    m = md(with_plot_caption(spec, cap; plot_id="abb", static_image="abb.png",
        summary_table=h.table(h.tr(h.td("Kreis a"), h.td("1.0")))))
    @test occursin("| Kreis a | 1.0 |", m)
    @test !occursin("Pretty", m) && !occursin("Raw", m) && !occursin("pressed", m)
end

"""
`sdraw(spec, path; alt)` returns `<img src alt>`; before, `alt` went on to
`Makie.save`, which ignores unknown keywords, so the image had no alt text and
nothing said so. The test env loads no Makie backend, so this pins the image
`sdraw` returns (`_static_img`) and that `alt` is `sdraw`'s own keyword.
"""
@testitem "sdraw image alt text" tags=[:static, :markdown, :regression] begin
    using AlgebraOfVega
    html(x) = sprint(show, MIME"text/html"(), x)
    @test html(AlgebraOfVega._static_img("fig.png", "Karte der Kreise.")) ==
        "<img src=\"fig.png\" alt=\"Karte der Kreise.\">"
    @test html(AlgebraOfVega._static_img("fig.png", nothing)) == "<img src=\"fig.png\">"
    @test :alt in Base.kwarg_decl(only(methods(AlgebraOfVega.sdraw, (Any, AbstractString))))
end
