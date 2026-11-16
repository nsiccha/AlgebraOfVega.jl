using TestItemRunner

@testitem "captioned layers use the spec path without config" tags=[:caption, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using AlgebraOfGraphics: Layer, Layers

    rows = (; x=[0.0, 1.0], y=[0.0, 1.0], group=["a", "b"])
    layer = data(rows) * mapping(:x, :y) * visual(Lines)
    layers = layer + data(rows) * mapping(:x, :y) * visual(Scatter)
    @test layer isa Layer
    @test layers isa Layers
    html(x) = repr(MIME"text/html"(), x)
    md(x) = HTMXObjects.to_markdown_string(x)
    cap = CaptionSpec(; title="Numbering control")
    caption_forms = (
        s -> with_plot_caption(s, "Numbering control"; plot_id="control"),
        s -> with_plot_caption(s, cap; plot_id="control"),
        s -> with_plot_caption(s; title="Numbering control", plot_id="control"),
    )
    for spec in (layer, layers), caption in caption_forms
        figure = caption(spec)
        configured = caption(spec * config())
        @test html(figure) == html(configured)
        @test md(figure) == md(configured)
        @test occursin("**Vega-Lite figure**", md(figure))
        @test !occursin("data:image/svg+xml", md(figure))
    end

    # Spec keywords work on the unconfigured algebra too, through both the
    # caption helper and its standalone HTML convenience form.
    remap = (; dims=["group" => "Group"], pinned=:row)
    for spec in (layer, layers)
        figure = with_plot_caption(spec, cap; plot_id="pick", auto_remap=remap)
        configured = with_plot_caption(spec * config(), cap; plot_id="pick", auto_remap=remap)
        @test html(figure) == html(configured)
        @test to_html(spec, cap; plot_id="pick", auto_remap=remap) ==
            to_html(spec * config(), cap; plot_id="pick", auto_remap=remap)
    end

    # The automatic interval summary used to disappear through the same
    # node fallback (owner todo 091fvn4).
    interval = data(rows) * mapping(:y; y=:group) * pointinterval()
    for spec in (interval, interval + interval)
        figure = with_plot_caption(spec, cap; plot_id="interval")
        @test occursin("aov-data-pretty-body", html(figure))
        @test html(figure) == html(with_plot_caption(spec * config(), cap; plot_id="interval"))
    end
end

@testitem "captioned layers retain report images and numbering without config" tags=[:caption, :markdown, :vsave, :regression] begin
    using AlgebraOfVega, HTMXObjects
    using Base64: base64encode
    using HTMX: h
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
        return
    end
    report_md(x) = HTMXObjects.to_markdown_string(x; report=true)
    img_md(src, alt) = strip(sprint(show, MIME"text/markdown"(), h.img(; src, alt)))
    rows = (; x=[0.0, 1.0], y=[0.0, 1.0])
    layer = data(rows) * mapping(:x, :y) * visual(Lines)
    layers = layer + data(rows) * mapping(:x, :y) * visual(Scatter)
    for spec in (layer, layers)
        uri = mktempdir() do dir
            "data:image/svg+xml;base64," * base64encode(read(vsave(spec, joinpath(dir, "figure.svg"))))
        end
        figures = (
            with_plot_caption(spec, "Numbering control"; plot_id="string"),
            with_plot_caption(spec, CaptionSpec(; title="Numbering control"); plot_id="caption"),
            with_plot_caption(spec; title="Numbering control", plot_id="keyword"),
        )
        for figure in figures
            markdown = report_md(numbered(figure))
            @test count("data:image/svg+xml;base64,", markdown) == 1
            @test occursin(img_md(uri, "Numbering control"), markdown)
            @test occursin("Figure 1:", markdown)
            @test !occursin("**Vega-Lite figure**", markdown)
        end
        markdown = report_md(numbered(
            with_plot_caption(spec, "Plain title"; plot_id="plain", kind=nothing, alt="Two observations"),
            first(figures)))
        @test count("data:image/svg+xml;base64,", markdown) == 2
        @test occursin(img_md(uri, "Two observations"), markdown)
        @test count(r"Figure\s+\d+:", markdown) == 1
        @test occursin("Figure 1:", markdown)

        markdown = report_md(with_plot_caption(spec, "Summary"; plot_id="summary", static_image=false))
        @test occursin("**Vega-Lite figure**", markdown)
        @test !occursin("data:image/svg+xml", markdown)
    end
end
