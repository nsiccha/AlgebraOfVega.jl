using TestItemRunner

"""
A captioned plot in an HTMXObjects `numbered(…)` document can be cited by its
number: `with_plot_caption(…; id)` gives the figure the id `ref(id)` cites (snag
`cite-an-algebrao-ebaff96a`). Before, the caption was numbered ("Figure 1:")
but carried no id, so `ref` threw `ArgumentError: ref: nothing numbered in this
document has the id …`. The figure and the link are written by HTMXObjects and
HTMX, so the Markdown checks compare against `with_caption`'s output for the
same id rather than pinning HTMX's spelling.
"""
@testitem "with_plot_caption id: ref cites a captioned plot by its number" tags=[:caption, :markdown, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    md(x) = sprint(show, MIME"text/markdown"(), x)
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[2.0, 3.0, 1.0, 4.0], g=["a", "a", "b", "b"])
    spec = data(rows) * mapping(:x => "X", :y => "Y"; color=:g => "Group") * visual(Scatter) *
        config(height=160)

    # The reporter's case: a plot cited before it, in a numbered section.
    doc = numbered(SemanticSection("Results",
        h.p("See ", ref("fig-posterior"), "."),
        with_plot_caption(spec, "Posterior"; plot_id="posterior", id="fig-posterior")))
    x, m = html(doc), md(doc)
    @test occursin("""See <a href="#fig-posterior" class="htmxo-ref">Figure 1</a>.""", x)
    @test occursin("See [Figure 1](#fig-posterior).", m)
    @test occursin("""<figure class="captioned" id="fig-posterior">""", x)
    @test occursin("""<span class="htmxo-caption-number">Figure 1:</span>""", x)
    # The plot keeps its own id inside the figure.
    @test occursin("id=\"posterior\"", x)
    # The figure's Markdown carries the id as the link target, as
    # `with_caption`'s does for the same id.
    target = only(match(r"(::: \{#fig-posterior[^}]*\})", md(numbered(h.p(ref("fig-posterior")),
        with_caption("Posterior", h.p("PLOT"); id="fig-posterior")))).captures)
    @test occursin(target, m)

    # Figures are counted with `with_caption` figures, straight through, and
    # every form cites the same number.
    mixed = numbered(
        h.p(ref("fig-b"), " follows ", ref("fig-a"), "."),
        with_caption("A", h.p("a"); id="fig-a"),
        with_plot_caption(spec, CaptionSpec(; title="B", short="draws"); plot_id="plot-b", id="fig-b"))
    @test occursin("[Figure 2](#fig-b) follows [Figure 1](#fig-a).", md(mixed))
    @test occursin("Figure 2 follows Figure 1.", HTMXObjects._plain_string(mixed))

    # The node form and a picker figure take `id` too; the picker stays outside
    # the figure that carries it.
    node = vdraw(spec; id="plot-node")
    @test occursin("[Figure 1](#fig-node)", md(numbered(h.p(ref("fig-node")),
        with_plot_caption(node, "Node"; plot_id="plot-node", id="fig-node"))))
    picker = with_plot_caption(spec, "Picker"; plot_id="plot-pick", id="fig-pick",
        auto_remap=(; dims=["g" => "Group"], pinned=:row))
    p = html(numbered(h.p(ref("fig-pick")), picker))
    @test occursin("""<a href="#fig-pick" class="htmxo-ref">Figure 1</a>""", p)
    @test occursin(r"<div data-aov-fragment=\"plot-pick\">.*<figure class=\"captioned\" id=\"fig-pick\">"s, p)

    # A report's Markdown (`pdf_report`) keeps the reference and the figure's id
    # with the figure's image in place of the plot.
    r = HTMXObjects.to_markdown_string(numbered(h.p(ref("fig-posterior")),
        with_plot_caption(spec, "Posterior"; plot_id="posterior", id="fig-posterior",
            static_image="figs/posterior.png")); report=true)
    @test occursin("[Figure 1](#fig-posterior)", r) && occursin(target, r) &&
        occursin("figs/posterior.png", r)

    # Without `id` nothing changes: the figure has no id attribute and a `ref`
    # to it still fails, naming the id.
    @test occursin("""<figure class="captioned">""", html(with_plot_caption(spec, "Posterior"; plot_id="posterior")))
    @test html(with_plot_caption(spec, "Posterior"; plot_id="posterior", id=nothing)) ==
        html(with_plot_caption(spec, "Posterior"; plot_id="posterior"))
    err = try md(numbered(h.p(ref("fig-posterior")),
        with_plot_caption(spec, "Posterior"; plot_id="posterior"))); nothing catch e; e end
    @test err isa ArgumentError && occursin("\"fig-posterior\"", err.msg)
    # Outside a numbered document `id` only names the figure.
    plain = html(with_plot_caption(spec, "Posterior"; plot_id="posterior", id="fig-posterior"))
    @test occursin("""<figure class="captioned" id="fig-posterior">""", plain) &&
        !occursin("htmxo-caption-number", plain)

    # refused: the figure encloses the plot, so a figure id equal to `plot_id`
    # is the element the runtime finds for the plot's downloads and data preview
    # (dev §1: surface the failure rather than a broken figure).
    @test_throws ArgumentError with_plot_caption(spec, "Posterior"; plot_id="posterior", id="posterior")
    @test_throws ArgumentError with_plot_caption(node, "Node"; plot_id="plot-node", id="plot-node")
end

"""
A captioned plot can stay unnumbered in an HTMXObjects `numbered(…)` document:
`with_plot_caption(…; kind=nothing)` forwards `kind` to `render_caption`, as
`with_caption(…; kind)` takes it (snag `give-one-with-pl-086d49f0`). Before,
`with_plot_caption` took no `kind`, so `kind=nothing` threw a `MethodError`
and the only unnumbered figure was a `with_caption` one, without the plot's
report image and alt text. The numbers are HTMXObjects', so the checks compare
the captions' numbers and `with_caption`'s behaviour for the same `kind`.
"""
@testitem "with_plot_caption kind: a figure a numbered document leaves unnumbered" tags=[:caption, :markdown, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using HTMX: h
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    md(x; kw...) = HTMXObjects.to_markdown_string(x; kw...)
    html(x) = sprint(show, MIME"text/html"(), x)
    captions(text) = [m.match for m in eachmatch(r"(Figure|Table) \d+:", text)]

    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[2.0, 3.0, 1.0, 4.0], g=["a", "a", "b", "b"])
    spec = data(rows) * mapping(:x => "X", :y => "Y"; color=:g => "Group") * visual(Scatter) *
        config(height=160)

    # The reporter's case: the first figure keeps its plain title and is not
    # counted, so the next one is still "Figure 1".
    doc = numbered(with_plot_caption(spec, "A"; plot_id="a", kind=nothing),
                   with_plot_caption(spec, "B"; plot_id="b"))
    x, m = html(doc), md(doc)
    @test captions(x) == ["Figure 1:"] && captions(m) == ["Figure 1:"]
    # The one number is B's: it follows A's caption.
    @test findfirst("Figure 1:", x).start > findfirst(">A<", x).start
    @test findfirst("Figure 1:", m).start > findfirst("A", m).start
    # `with_caption` numbers the same document the same way.
    @test captions(md(numbered(with_caption("A", h.p("a"); kind=nothing), with_caption("B", h.p("b"))))) ==
        captions(m)
    # Counted with other figures, straight through: a `with_caption` figure
    # after the unnumbered plot is Figure 1, and the next plot Figure 2.
    mixed = numbered(h.p(ref("fig-c")),
        with_plot_caption(spec, "A"; plot_id="a", kind=nothing),
        with_caption("B", h.p("b"); id="fig-b"),
        with_plot_caption(spec, "C"; plot_id="c", id="fig-c"))
    @test captions(md(mixed)) == ["Figure 1:", "Figure 2:"]
    @test occursin("[Figure 2](#fig-c)", md(mixed))

    # The node form and a picker figure take it too.
    node = vdraw(spec; id="plot-node")
    @test isempty(captions(md(numbered(with_plot_caption(node, "Node"; plot_id="plot-node", kind=nothing)))))
    picker = with_plot_caption(spec, "Picker"; plot_id="plot-pick", kind=nothing,
        auto_remap=(; dims=["g" => "Group"], pinned=:row))
    @test isempty(captions(html(numbered(picker))))
    # `kind=:table` counts the caption as a table, as `with_caption` does.
    @test captions(md(numbered(with_plot_caption(spec, "T"; plot_id="t", kind=:table)))) == ["Table 1:"]

    # A report's Markdown (`pdf_report`) keeps the figure's image and its alt
    # text, with no number on its caption.
    r = md(numbered(
        with_plot_caption(spec, "A"; plot_id="a", kind=nothing, static_image="figs/a.png", alt="Scatter of y over x"),
        with_plot_caption(spec, "B"; plot_id="b", static_image="figs/b.png")); report=true)
    @test captions(r) == ["Figure 1:"]
    @test occursin("figs/a.png", r) && occursin("Scatter of y over x", r) && occursin("figs/b.png", r)

    # The default is `kind=:figure`: passing it changes nothing.
    @test html(with_plot_caption(spec, "B"; plot_id="b", kind=:figure)) == html(with_plot_caption(spec, "B"; plot_id="b"))
    @test md(numbered(with_plot_caption(spec, "B"; plot_id="b", kind=:figure))) ==
        md(numbered(with_plot_caption(spec, "B"; plot_id="b")))
    # Outside a numbered document `kind` changes nothing, as for `with_caption`,
    # and the standalone page takes it as `id` is taken.
    @test html(with_plot_caption(spec, "B"; plot_id="b", kind=nothing)) == html(with_plot_caption(spec, "B"; plot_id="b"))
    @test to_html(spec, "B"; plot_id="b", kind=nothing) == to_html(spec, "B"; plot_id="b")
    @test to_html(node, "Node"; plot_id="plot-node", kind=nothing) == to_html(node, "Node"; plot_id="plot-node")

    # An unnumbered figure has no number to cite, as with `with_caption`: a `ref`
    # to its id fails, naming the id.
    for fig in (with_plot_caption(spec, "A"; plot_id="a", id="fig-a", kind=nothing),
                with_caption("A", h.p("a"); id="fig-a", kind=nothing))
        err = try md(numbered(h.p(ref("fig-a")), fig)); nothing catch e; e end
        @test err isa ArgumentError && occursin("\"fig-a\"", err.msg)
    end
    # refused by HTMXObjects: a caption is counted as a figure or a table, or not at all.
    @test_throws ArgumentError with_plot_caption(spec, "A"; plot_id="a", kind=:listing)
end
