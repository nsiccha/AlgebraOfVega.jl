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
    # A blank tier (whitespace only) is left out with its " — ", so the alt text
    # never starts or ends with a dash: a summary alone is the alt text (snag
    # `aov-caption-alt-9b2b65c1`, design decision `0no56j1`, option 1).
    alt_of(c) = md(with_plot_caption(spec, c; plot_id="radon", static_image="f.png"))
    @test occursin(img_md("f.png", "Median je Kreis, 2025"),
        alt_of(CaptionSpec(; title="", short="Median je Kreis, 2025")))
    @test occursin(img_md("f.png", "Median je Kreis, 2025"),
        alt_of(CaptionSpec(; title="  ", short="Median je Kreis, 2025")))
    @test occursin(img_md("f.png", "Radon nach Kreis"),
        alt_of(CaptionSpec(; title="Radon nach Kreis", short="  ")))
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
    # leave a PDF/UA figure undescribed (dev §1; design decision
    # 2026-10-22T23-16-21-655-1l4p2wa, option 1). `alt` without `static_image`
    # is the alt text of the image a report draws itself (next item).
    @test_throws ArgumentError with_plot_caption(spec, cap; plot_id="radon", static_image="f.png", alt=" ")
    @test_throws ArgumentError with_plot_caption(spec, CaptionSpec(; title=""); plot_id="radon", static_image="f.png")
    @test_throws ArgumentError with_plot_caption(spec, CaptionSpec(; title=" ", short=" "); plot_id="radon",
        static_image="f.png")
end

"""
A report's markdown draws a captioned figure itself, with no per-figure wiring
(snag `plot-markdown-st-242cdfc9`, design decision
`AlgebraOfVega:snag.plot-markdown-st-242cdfc9/decisions/2026-11-15T09-54-40-583-0wwdtwg`,
option 1). These are the parts that need no vl-convert: an ordinary markdown
read (`?plain`) and the browser are exactly what they were, nothing is rendered
outside a report, and the keywords that cannot mean anything are refused.
Before, a report showed the figure's `PlotSummary` table unless the caller
rendered an image with `vsave` and passed it as `static_image`.
"""
@testitem "captioned figure: a report draws it, an ordinary read keeps its summary" tags=[:caption, :markdown, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    md(x) = HTMXObjects.to_markdown_string(x)
    report_md(x) = HTMXObjects.to_markdown_string(x; report=true)
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[2.0, 3.0, 1.0, 4.0], g=["a", "a", "b", "b"])
    spec = data(rows) * mapping(:x => "X", :y => "Y"; color=:g => "Group") * visual(Scatter) *
        config(height=160)
    cap = CaptionSpec(; title="Radon nach Kreis", short="Median je Kreis, 2025", long="Quelle: BfS.")
    remap = (; dims=["g" => "Group"], pinned=:row)

    # `static_image=false` is the figure as it was before reports drew it: the
    # default must read and look the same everywhere but in a report.
    figures = [
        (with_plot_caption(spec, cap; plot_id="radon"),
         with_plot_caption(spec, cap; plot_id="radon", static_image=false)),
        (with_plot_caption(spec, cap; plot_id="pick", auto_remap=remap),
         with_plot_caption(spec, cap; plot_id="pick", auto_remap=remap, static_image=false)),
        (with_plot_caption(vdraw(spec; id="node"), cap; plot_id="node"),
         with_plot_caption(vdraw(spec; id="node"), cap; plot_id="node", static_image=false)),
    ]
    # Nothing is rendered outside a report: with no vl-convert to render with,
    # the ordinary read still works.
    withenv("AOV_VL_CONVERT" => joinpath(tempdir(), "no-such-vl-convert")) do
        for (fig, before) in figures
            @test html(fig) == html(before)
            @test md(fig) == md(before)
            @test occursin("**Vega-Lite figure**", md(fig))
            @test !occursin("data:image/svg+xml", md(fig))
        end
        # The picker stays in an ordinary read, as before.
        @test occursin("Assign dimensions", md(first(figures[2])))
        # A report does render, so it needs the tool, and says which.
        err = try report_md(first(figures[1])); nothing catch e; e end
        @test err isa ErrorException && occursin("AOV_VL_CONVERT", sprint(showerror, err))
    end
    # `static_image=false` keeps the summary table in a report too.
    m = report_md(last(figures[1]))
    @test occursin("**Vega-Lite figure**", m) && !occursin("data:image/svg+xml", m)
    # An image the caller names wins in a report.
    m = report_md(with_plot_caption(spec, cap; plot_id="radon", static_image="figs/radon.png"))
    @test occursin("figs/radon.png", m) && !occursin("data:image/svg+xml", m)

    # A node with no AlgebraOfVega plot in it reads the same in a report.
    other = h.div(h.p("Eine Tabelle statt einer Grafik."))
    @test report_md(with_plot_caption(other, cap; plot_id="other")) ==
        md(with_plot_caption(other, cap; plot_id="other"))

    # refused: `static_image=true` names no image; `alt` with
    # `static_image=false`, or for a node AoV cannot draw, describes an image
    # that no view shows (dev §1). A caption with neither a title nor a summary
    # (blank: empty or whitespace only) gives the drawn figure no alt text,
    # which a PDF/UA report needs: refused when the report is written, so a page
    # that never becomes one still renders.
    @test_throws ArgumentError with_plot_caption(spec, cap; plot_id="radon", static_image=true)
    @test_throws ArgumentError with_plot_caption(spec, cap; plot_id="radon", static_image=false, alt="Karte")
    @test_throws ArgumentError with_plot_caption(other, cap; plot_id="other", alt="Karte")
    for blank in (CaptionSpec(; title=""), CaptionSpec(; title=" ", short=" "))
        untitled = with_plot_caption(spec, blank; plot_id="radon")
        @test occursin("**Vega-Lite figure**", md(untitled))
        err = try report_md(untitled); nothing catch e; e end
        @test err isa ArgumentError && occursin("`alt`", sprint(showerror, err))
    end
end

"""
The figure a report draws is the one `vsave` writes, as an SVG `data:` URI with
the caption's alt text, in place of the figure's `PlotSummary` and channel
picker (snag `plot-markdown-st-242cdfc9`, design decision `0wwdtwg`, option 1).
Needs the vl-convert tool.
"""
@testitem "captioned figure: a report draws the figure vsave writes" tags=[:caption, :markdown, :vsave, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    using Base64: base64encode
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
        return
    end
    report_md(x) = HTMXObjects.to_markdown_string(x; report=true)
    img_md(src, alt) = strip(sprint(show, MIME"text/markdown"(), h.img(; src, alt)))
    svg_uri(spec; kw...) = mktempdir() do dir
        "data:image/svg+xml;base64," * base64encode(read(vsave(spec, joinpath(dir, "f.svg"); kw...)))
    end
    count_svgs(m) = count("data:image/svg+xml;base64,", m)

    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[2.0, 3.0, 1.0, 4.0], g=["a", "a", "b", "b"])
    spec = data(rows) * mapping(:x => "X", :y => "Y"; color=:g => "Group") * visual(Scatter) *
        config(height=160)
    cap = CaptionSpec(; title="Radon nach Kreis", short="Median je Kreis, 2025", long="Quelle: BfS.")
    alt = "Radon nach Kreis — Median je Kreis, 2025"
    uri = svg_uri(spec)

    m = report_md(with_plot_caption(spec, cap; plot_id="radon"))
    @test occursin(img_md(uri, alt), m) && count_svgs(m) == 1
    @test !occursin("**Vega-Lite figure**", m)
    @test occursin("**Radon nach Kreis** — Median je Kreis, 2025 — Quelle: BfS.", m)
    # An explicit alt text, with no image of the caller's.
    described = "Streudiagramm: Y gegen X, zwei Gruppen."
    @test occursin(img_md(uri, described), report_md(with_plot_caption(spec, cap; plot_id="radon", alt=described)))
    # ...which a caption with neither a title nor a summary needs.
    @test occursin(img_md(uri, described),
        report_md(with_plot_caption(spec, CaptionSpec(; title=""); plot_id="radon", alt=described)))
    # A caption of a summary alone gives that summary, with no leading dash
    # (snag `aov-caption-alt-9b2b65c1`, design decision `0no56j1`, option 1).
    m = report_md(with_plot_caption(spec, CaptionSpec(; title="", short="Median je Kreis, 2025"); plot_id="radon"))
    @test occursin(img_md(uri, "Median je Kreis, 2025"), m) && !occursin("alt=\" —", m)

    # A picker figure draws what it first shows, as `vsave(...; auto_remap)`
    # writes it, and leaves its controls out.
    remap = (; dims=["g" => "Group"], pinned=:row)
    m = report_md(with_plot_caption(spec, cap; plot_id="pick", auto_remap=remap))
    @test occursin(img_md(svg_uri(spec; auto_remap=remap), alt), m) && count_svgs(m) == 1
    @test !occursin("Assign dimensions", m) && !occursin("**Vega-Lite figure**", m)

    # The node form, and a node holding two plots, which draws both.
    @test occursin(img_md(uri, alt), report_md(with_plot_caption(vdraw(spec; id="n"), cap; plot_id="n")))
    other = data(rows) * mapping(:x => "X", :y => "Y") * visual(Lines) * config(height=160)
    m = report_md(with_plot_caption(h.div(vdraw(spec; id="a"), vdraw(other; id="b")), cap; plot_id="ab"))
    @test occursin(img_md(uri, alt), m) && occursin(img_md(svg_uri(other), alt), m)
    @test count_svgs(m) == 2 && !occursin("**Vega-Lite figure**", m)
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
    import AlgebraOfGraphics   # with Makie, loads the static path (AlgebraOfVegaMakieExt)
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
