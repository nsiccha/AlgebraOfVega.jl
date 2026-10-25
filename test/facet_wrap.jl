using TestItemRunner

# A `layout=` facet is AlgebraOfGraphics' wrap facet. Vega-Lite wraps one only when
# the spec carries `columns`, and AoV used to write none, so every panel went in one
# row: ODLPlaus' 17 regional panels at 170px rendered 3,350px wide (snag
# `aov-layout-facet-e1179109`). The lowering now writes AoG's near-square count
# (`_aov.autoColumns`), and the browser runtime puts as many panels in a row as fit
# the plot's width (user pick on
# `AlgebraOfVega:snag.aov-layout-facet-e1179109/decisions/2026-10-25T09-18-44-857-1r4o8ot`).
@testsnippet AoVFacetWrapFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics
    const AoG = AlgebraOfGraphics
    regions = ["Region " * lpad(g, 2, '0') for g in 1:17]
    rows = [(; region, year, q50=g + 0.1 * (year - 2000), lo=g - 1.0, hi=g + 1.0)
            for (g, region) in enumerate(regions) for year in 2000:2004]
    ribbon = data(rows) * mapping(:year, :q50; layout=:region) * lineribbon(bands=[:lo => :hi])
    sized = ribbon * config(width=170, height=120)
    plain = data(rows) * mapping(:year, :q50; layout=:region) * visual(Lines)
    layered = data(rows) * mapping(:year, :q50; layout=:region) * (visual(Lines) + visual(Scatter))
    columns(vl) = get(vl, "columns", nothing)
    auto(vl) = get(get(vl, "_aov", Dict()), "autoColumns", false)
end

@testitem "a layout= facet wraps into AoG's near-square grid" setup=[AoVFacetWrapFixtures] tags=[:translation, :facet, :regression] begin
    # Every path that emits a wrap facet gets the count: the analysis operator, the
    # layered operator, and a single plain mark's `encoding.facet`.
    for spec in (ribbon, sized, layered, plain)
        vl = to_vegalite(spec)
        @test columns(vl) == 4
        @test auto(vl) === true
    end
    @test haskey(to_vegalite(plain)["encoding"], "facet")
    # The count is AoG's own rule: 2→2, 9→3, 10→4, and the panel aspect from an
    # authored width/height moves it (wide panels get fewer columns).
    @test AlgebraOfVega._aog_wrap_columns(2, 1.0) == 2
    @test AlgebraOfVega._aog_wrap_columns(9, 1.0) == 3
    @test AlgebraOfVega._aog_wrap_columns(16, 2.0) == 3
    @test AlgebraOfVega._aog_wrap_columns(3, 0.1) == 3    # never more columns than panels
    if isdefined(AoG, :resolve_lazy_wrap)
        for n in 1:40, aspect in (0.3, 0.5, 1.0, 170 / 120, 2.0, 3.0)
            @test AlgebraOfVega._aog_wrap_columns(n, aspect) ==
                  min(n, maximum(last, AoG.resolve_lazy_wrap(1:n, n, aspect)))
        end
    end
    wide = to_vegalite(ribbon * config(width=400, height=100))
    @test columns(wide) == AlgebraOfVega._aog_wrap_columns(17, 4.0)
    # A grid facet does not wrap and gets no count.
    vc = to_vegalite(data(rows) * mapping(:year, :q50; col=:region) * visual(Lines))
    @test isnothing(columns(vc)) && !auto(vc)
end

@testitem "an authored layout= column count is kept" setup=[AoVFacetWrapFixtures] tags=[:translation, :facet, :regression] begin
    # The raw Vega-Lite key and AoG's `wrapped(...)` palette are authored counts:
    # no `autoColumns` marker, so the browser runtime never re-wraps them.
    vl = to_vegalite(sized * config(columns=6))
    @test columns(vl) == 6 && !auto(vl)
    vl = to_vegalite(plain * config(columns=6))
    @test columns(vl) == 6 && !auto(vl)
    vl = to_vegalite(sized * config(scales=scales(Layout=(; palette=wrapped(cols=3)))))
    @test columns(vl) == 3 && !auto(vl)
    vl = to_vegalite(sized * config(scales=scales(Layout=(; palette=wrapped(rows=3)))))
    @test columns(vl) == 6 && !auto(vl)                  # 17 panels in 3 rows
    vl = to_vegalite(ribbon, scales(Layout=(; palette=wrapped(cols=2))))
    @test columns(vl) == 2 && !auto(vl)
    # `wrapped()` without a count leaves AoG's default rule in charge, as in AoG.
    vl = to_vegalite(sized * config(scales=scales(Layout=(; palette=wrapped()))))
    @test columns(vl) == 4 && auto(vl)
    # refused: Vega-Lite fills a wrap facet row by row, so a column-first fill or
    # explicit positions would place the panels unlike `sdraw` (decision `1r4o8ot`).
    @test_throws ArgumentError to_vegalite(sized * config(scales=scales(Layout=(; palette=wrapped(cols=3, by_col=true)))))
    @test_throws ArgumentError to_vegalite(sized * config(scales=scales(Layout=(; palette=[(1, 1), (1, 2)]))))
end

@testitem "a single-layer layout= facet is sized and ordered like the others" setup=[AoVFacetWrapFixtures] tags=[:translation, :facet, :regression] begin
    # One plain mark lowers to `encoding.facet`. `to_node` used to take it for a
    # single view (`width: "container"`, which Vega-Lite ignores on a facet with a
    # warning), `scales(Layout=(; categories))` never reached it, and `plot_size`
    # measured one panel (todo `q1u0pj`).
    order = reverse(regions)
    vl = to_vegalite(plain * config(scales=scales(Layout=(; categories=order))))
    @test vl["encoding"]["facet"]["sort"] == order
    emb = AlgebraOfVega._embed_spec(plain)
    @test emb["width"] != "container" && !haskey(emb, "autosize")
    @test emb["_aov"]["fitWidth"] === true
    @test emb["_aov"]["nFacetCols"] == 4                  # the wrap's columns, not 17 levels
    @test AlgebraOfVega._embed_spec(plain * config(columns=6))["_aov"]["nFacetCols"] == 6
    # plot_size measures the wrapped grid: 4 columns × 5 rows, like the operator form.
    one_row = plot_size(to_vegalite(plain * config(columns=17)))
    grid = plot_size(to_vegalite(plain))
    @test grid.width < one_row.width / 3
    @test grid.height > 4 * one_row.height / 2
    @test plot_size(to_vegalite(sized)) == plot_size(to_vegalite(sized * config(columns=4)))
    # The operator path's sizing hint divides by the wrap's columns too.
    @test AlgebraOfVega._embed_spec(ribbon)["_aov"]["nFacetCols"] == 4
end

@testitem "sdraw wraps a layout= facet into the spec's columns" setup=[AoVFacetWrapFixtures] tags=[:translation, :facet, :regression] begin
    # The static path drops width/height on a faceted figure, so AoG alone would wrap
    # with aspect 1; AoV hands it the spec's count as the Layout palette instead.
    palette(sc) = sc.dict[:Layout][:palette]
    cols(w) = w.size_restriction.n
    for spec in (sized, sized * config(width=400, height=100), sized * config(columns=6))
        sc = AlgebraOfVega._sdraw_scales(nothing, spec.drawable, spec.config)
        @test palette(sc) isa AoG.Wrap && !palette(sc).by_col
        @test cols(palette(sc)) == columns(to_vegalite(spec))
    end
    # Other scales survive; an authored Layout palette is AoG's own and wins; a
    # figure without `layout=` is left alone.
    user = scales(Color=(; palette=[:red, :blue]))
    sc = AlgebraOfVega._sdraw_scales(user, ribbon, nothing)
    @test haskey(sc.dict, :Color) && cols(palette(sc)) == 4
    authored = scales(Layout=(; palette=wrapped(cols=2)))
    @test AlgebraOfVega._sdraw_scales(authored, ribbon, nothing) === authored
    @test isnothing(AlgebraOfVega._sdraw_scales(nothing, data(rows) * mapping(:year, :q50) * visual(Lines), nothing))
end

# The runtime half: an auto-wrapped facet takes as many panels per row as fit its
# container; an authored count is never re-wrapped.
@testitem "auto-wrapped layout= facets fill the plot's width in the browser" setup=[AoVFitWidthBrowser] tags=[:regression, :browser, :facet] begin
    regions = ["Region " * lpad(g, 2, '0') for g in 1:17]
    rows17 = [(; region, year, q50=g + 0.1 * (year - 2000), lo=g - 1.0, hi=g + 1.0)
              for (g, region) in enumerate(regions) for year in 2000:2004]
    ribbon = data(rows17) * mapping(:year, :q50; layout=:region) * lineribbon(bands=[:lo => :hi])
    plain = data(rows17) * mapping(:year, :q50; layout=:region) * visual(Lines)
    plots = ["fwr-sized" => vdraw(ribbon * config(width=170, height=120); id="fwr-sized"),
        "fwr-fit" => vdraw(ribbon * config(height=120); id="fwr-fit"),
        "fwr-plain" => vdraw(plain * config(width=170, height=120); id="fwr-plain"),
        "fwr-explicit" => vdraw(ribbon * config(width=170, height=120, columns=3); id="fwr-explicit"),
        "fwr-indep" => vdraw(ribbon * config(width=170, height=120, facet=(; linkyaxes=:none)); id="fwr-indep")]
    body = join("<div id='wrap-$id' style='width:1450px'>" * html(n) * "</div>" for (id, n) in plots)
    browser_checks(body, joinpath(@__DIR__, "facet_wrap.js"), "aov-facet-wrap-results"; min_checks=20)
end
