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
