using TestItemRunner

# A colour legend's swatch is drawn like the first layer Vega-Lite merges into it.
# For a coloured ribbon that was the outer band at 20 % opacity: every swatch a
# pale tint of its median line, hard to tell from its neighbours and a dark dot on
# a dark page, and the legend selection dimmed backwards (snag
# `color-legend-swa-8625457a`, design `0uvo5tt`). Now a legend whose first layer
# is fainter than another is drawn like its strongest line.
@testsnippet AoVLegendSwatchFixtures begin
    using AlgebraOfVega
    t = collect(1.0:5)
    rows = (; t=repeat(t, 3), g=repeat(["a", "b", "c"], inner=5), h=repeat(["u", "v"], 8)[1:15],
        q50=collect(1.0:15), lo=collect(0.0:14), hi=collect(2.0:16), lo50=collect(0.5:14.5),
        hi50=collect(1.5:15.5))
    draws = (; t=repeat(t, 3 * 20), g=repeat(["a", "b", "c"], inner=5 * 20),
        draw=repeat(repeat(1:20, inner=5), 3), y=[x + 0.1 * d for x in 1.0:15 for d in 1:20])
    bands = [:lo => :hi, :lo50 => :hi50]
    # Every unit (a node with a mark) of a lowered spec.
    function units(s, out=Dict{String,Any}[])
        haskey(s, "mark") && push!(out, s)
        for k in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(s, k, Any[]))
        end
        haskey(s, "spec") && units(s["spec"], out)
        out
    end
    coloured(s) = [u for u in units(s) if get(get(get(u, "encoding", Dict()), "color", Dict()), "field", nothing) isa String]
    legend(u) = get(u["encoding"]["color"], "legend", Dict())
    looks_like_line(l; width=2) = get(l, "symbolType", nothing) == "stroke" &&
        get(l, "symbolOpacity", nothing) == 1 && get(l, "symbolStrokeWidth", nothing) == width
end

@testitem "a coloured ribbon's legend swatch is drawn like its median line" setup=[AoVLegendSwatchFixtures] tags=[:translation, :regression] begin
    for (name, spec) in ("bands=" => data(rows) * mapping(:t, :q50; color=:g) * lineribbon(; bands),
                         "raw draws" => data(draws) * mapping(:t, :y; color=:g, group=:draw) * lineribbon(probs=[0.95, 0.5]))
        vl = to_vegalite(spec)
        cs = coloured(vl)
        @test length(cs) == 9
        @test all(u -> looks_like_line(legend(u)), cs)
        # The runtime's picker carries the same look to the colour it moves in.
        @test all(u -> u["_aovSwatch"] == legend(u), cs)
        # Only the legend changes: the bands keep their opacity.
        @test sort(unique(get(u["mark"], "opacity", 1) for u in cs)) == [0.2, 0.6, 1]
        # The Intervals drawing already draws its swatch from a full-strength rule.
        alt = vl["_aov"]["ribbonView"]["alt"]
        @test !isempty(coloured(alt)) && all(u -> !haskey(u, "_aovSwatch") && !haskey(legend(u), "symbolOpacity"), coloured(alt))
    end
end

@testitem "the swatch follows the strongest layer of any figure, and figure keys win" setup=[AoVLegendSwatchFixtures] tags=[:translation, :regression] begin
    d = data(rows)
    # A ribbon with no line: the strongest band's opacity, the band's own symbol.
    nl = coloured(to_vegalite(d * mapping(:t, :q50; color=:g) * ribbon(; bands)))
    @test all(u -> legend(u) == Dict("symbolOpacity" => 0.6), nl)
    # A band composed under a dashed line: drawn like that line, dash and all.
    comp = d * mapping(:t, :lo, :hi; color=:g) * visual(Band; alpha=0.3) +
        d * mapping(:t, :q50; color=:g) * visual(Lines; linestyle=:dash, linewidth=3)
    cs = coloured(to_vegalite(comp))
    line = only(u for u in units(to_vegalite(comp)) if AlgebraOfVega._mark_type(u["mark"]) == "line")
    @test all(u -> looks_like_line(legend(u); width=3) && legend(u)["symbolDash"] == line["mark"]["strokeDash"] &&
        legend(u)["symbolSize"] > 100, cs)
    # A key the figure sets on the legend wins over the look.
    own = d * mapping(:t, :q50; color=:g) * lineribbon(; bands) *
        config(encoding=Dict("color" => Dict("legend" => Dict("symbolOpacity" => 0.5, "orient" => "bottom"))))
    @test all(u -> legend(u)["symbolOpacity"] == 0.5 && legend(u)["orient"] == "bottom" &&
        legend(u)["symbolType"] == "stroke", coloured(to_vegalite(own)))
    # Faceted: the look reaches the inner layers.
    fv = to_vegalite(d * mapping(:t, :q50; color=:g, col=:h) * lineribbon(; bands))
    @test haskey(fv, "facet") && all(u -> looks_like_line(legend(u)), coloured(fv))
end

@testitem "legends whose first layer is the strongest keep Vega-Lite's swatch" setup=[AoVLegendSwatchFixtures] tags=[:translation, :regression] begin
    d = data(rows) * mapping(:t, :q50; color=:g)
    untouched(s) = (vl = to_vegalite(s); all(u -> !haskey(u, "_aovSwatch") && !haskey(legend(u), "symbolType") &&
        !haskey(legend(u), "symbolOpacity"), units(vl)))
    @test untouched(d * visual(Lines))
    @test untouched(d * (visual(Lines) + visual(Scatter)))
    # A point (Vega-Lite draws it at 0.7) over a fainter line.
    @test untouched(d * (visual(Scatter) + visual(Lines; alpha=0.2)))
    @test untouched(d * linear())
end

@testitem "an uncoloured ribbon records the look a picked colour takes" setup=[AoVLegendSwatchFixtures] tags=[:translation, :regression, :auto_remap] begin
    d = data(rows) * mapping(:t, :q50)
    us = units(to_vegalite(d * lineribbon(; bands)))
    @test length(us) == 3 && all(u -> looks_like_line(u["_aovSwatch"]) && !haskey(u["encoding"], "color"), us)
    # A fixed colour is not the picker's to change.
    @test all(u -> !haskey(u, "_aovSwatch"), units(to_vegalite(d * lineribbon(; bands) * visual(; color=:ink))))
end

@testitem "coloured ribbon swatches in the browser" setup=[AoVLegendSwatchFixtures] tags=[:regression, :browser, :auto_remap] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    d = data(rows)
    sz = config(width=240, height=140)
    page = [vdraw(d * mapping(:t, :q50; color=:g) * lineribbon(; bands) * sz; id="ls-ribbon"),
        vdraw((d * mapping(:t, :lo, :hi; color=:g) * visual(Band; alpha=0.3) +
               d * mapping(:t, :q50; color=:g) * visual(Lines; linewidth=2)) * sz; id="ls-composed"),
        auto_remap_node("ls-picker", d * mapping(:t, :q50; color=:g) * lineribbon(; bands) * sz;
            dims=["g" => "Group", "h" => "Half"], pinned=:detail),
        auto_remap_node("ls-plain-picker", d * mapping(:t, :q50) * lineribbon(; bands) * sz;
            dims=["g" => "Group"], pinned=:detail)]
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-legend-swatch-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "legend_swatch.js"), String)
            # SVG, so the driver can click a legend label as a reader does.
            svg = "<script>const originalEmbed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "originalEmbed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * svg *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-legend-swatch-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 20
                @test isempty(report["failures"])
                @info "legend swatch browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
