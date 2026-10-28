using TestItemRunner

"""
Plots follow the host page's light/dark choice.

Regression (snag `live-figure-host-15b6fe37`): Vega's canvas renderer paints a
`currentColor` config value black, so a consumer that set axis/legend colours to
`currentColor` got dark-on-dark text in a dark Pico page, and inverted the whole
canvas with a CSS filter instead — which recoloured its semantic palette. The
runtime now resolves the plot element's inherited CSS `color` itself and embeds
with a Vega-Lite config for the chrome on a transparent background (theme
`:host`, the default), and re-embeds when the page's theme changes.
"""
@testitem "host theme lowering and options" tags=[:theme, :regression] begin
    using AlgebraOfVega, JSON
    import Makie
    html(x) = sprint(show, MIME"text/html"(), x)
    head(; kw...) = join(html(n) for n in vega_head(; kw...))

    rows = (; value=collect(1.0:20.0))
    # Page default: :host is the runtime default and emits no setting.
    @test !occursin("\"theme\"", head())
    @test occursin("\"theme\":\"none\"", head(theme=:none))
    @test_throws ArgumentError vega_head(theme=:dark)
    @test_throws ArgumentError vega_head(theme="none")
    # Per plot: config(theme=...) rides the spec's `_aov` hint.
    spec = data(rows) * mapping(:value) * visual(Scatter)
    @test to_vegalite(spec * config(theme=:none))["_aov"]["theme"] == "none"
    @test to_vegalite(spec * config(theme=:host))["_aov"]["theme"] == "host"
    @test !haskey(get(to_vegalite(spec), "_aov", Dict()), "theme")
    @test_throws ArgumentError to_vegalite(spec * config(theme=:dark))

    # AoV's neutral ink is a named style defaulting to the old literal colour.
    dots = to_vegalite(data(rows) * mapping(:value) * dotinterval())
    @test dots["config"]["style"]["aov-ink"] == Dict("color" => "#333")
    rule_marks = [l["mark"] for l in dots["layer"][2]["layer"] if get(l["mark"], "type", nothing) == "rule"]
    @test !isempty(rule_marks) && all(m -> m["style"] == "aov-ink" && !haskey(m, "color"), rule_marks)
    @test !haskey(get(to_vegalite(spec), "config", Dict()), "style")
    own = to_vegalite(data(rows) * mapping(:value) * dotinterval() *
        config(config=Dict("style" => Dict("aov-ink" => Dict("color" => "red")))))
    @test own["config"]["style"]["aov-ink"]["color"] == "red"

    # Public fixed-mark ink uses the same theme style as AoV's interval rules.
    line = data((; x=[1, 2], y=[2, 3])) * mapping(:x, :y) * visual(Lines; color=:ink)
    vl = to_vegalite(line)
    @test vl["mark"]["style"] == "aov-ink"
    @test !haskey(vl["mark"], "color")
    @test vl["config"]["style"]["aov-ink"]["color"] == "#333"
    @test to_vegalite(data((; x=[1, 2], y=[2, 3])) * mapping(:x, :y) *
        visual(Lines; color="black"))["mark"]["color"] == "black"
    styled = to_vegalite(data((; x=[1, 2], y=[2, 3])) * mapping(:x, :y) *
        visual(Lines; color=:ink, style="other"))
    @test styled["mark"]["style"] == ["other", "aov-ink"]
    @test styled["config"]["style"]["aov-ink"]["color"] == "#333"
    @test AlgebraOfVega.extract_visual(line).attributes[:color] === :ink
    Makie.with_theme(Makie.theme_black()) do
        fixed = AlgebraOfVega._fix_visual_attrs(line)
        @test AlgebraOfVega.extract_visual(fixed).attributes[:color] == :white
    end
end

"""
`:ink` on one side of a mark: `stroke`, `strokecolor` and `fill`.

Regression (snag `visual-stroke-in-91baea43`): only `color=:ink` lowered to the
theme ink; `visual(; stroke=:ink)` reached the mark as the colour name `"ink"`,
which is no CSS colour, so the stroke was invalid paint (dropped by Vega's SVG
renderer, left at the previous stroke on canvas), with no warning. Each side has
its own style, and its colour is also written onto the mark: Vega-Lite leaves a
style's `stroke`/`fill` below the colour it gives that side itself.
"""
@testitem "stroke and fill ink paint one side of the mark" tags=[:theme, :regression] begin
    using AlgebraOfVega
    import Makie
    xy = data((; x=[1.0, 2.0], y=[2.0, 3.0])) * mapping(:x, :y)
    vl(spec) = to_vegalite(spec)

    # The reported shape: a geoshape outline with no fill.
    geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [Dict{String,Any}(
        "type" => "Feature", "properties" => Dict{String,Any}("ags" => "a"),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]))])
    outline = vl(data((; ags=["a"])) * mapping(:ags) * geoshape(geo; key=:ags) *
        visual(; fill=nothing, stroke=:ink, strokeWidth=2))
    @test outline["mark"] == Dict("type" => "geoshape", "fill" => nothing, "stroke" => "#333",
        "strokeWidth" => 2, "style" => "aov-ink-stroke")
    @test outline["config"]["style"]["aov-ink-stroke"] == Dict("stroke" => "#333")
    @test !haskey(outline["config"]["style"], "aov-ink")

    # Makie's `strokecolor` and Vega-Lite's `stroke` are one side; `fill` the other.
    for spelling in (:stroke, :strokecolor)
        m = vl(xy * visual(Lines; NamedTuple{(spelling,)}((:ink,))...))["mark"]
        @test m["style"] == "aov-ink-stroke" && m["stroke"] == "#333" && !haskey(m, "color")
    end
    dot = vl(xy * visual(Scatter; fill=:ink, strokecolor="red", strokewidth=2))
    @test dot["mark"]["fill"] == "#333" && dot["mark"]["stroke"] == "red" && dot["mark"]["style"] == "aov-ink-fill"
    @test dot["config"]["style"] == Dict("aov-ink-fill" => Dict("fill" => "#333"))
    # Several sides: one style each, after the caller's own; `color=:ink` stays a style only.
    both = vl(xy * visual(Scatter; color=:ink, strokecolor=:ink, stroke=:ink, style="mine"))
    @test both["mark"]["style"] == ["mine", "aov-ink", "aov-ink-stroke"]
    @test both["mark"]["stroke"] == "#333" && !haskey(both["mark"], "color") && !haskey(both["mark"], "fill")
    @test both["config"]["style"]["aov-ink"] == Dict("color" => "#333")
    # A spec's own style colour reaches the marks; a literal on the other spelling wins.
    own = vl(xy * visual(Lines; stroke=:ink) *
        config(config=Dict("style" => Dict("aov-ink-stroke" => Dict("stroke" => "teal")))))
    @test own["mark"]["stroke"] == "teal"
    @test vl(xy * visual(Lines; stroke=:ink, strokecolor="red"))["mark"]["stroke"] == "red"
    # Literal paint is unchanged.
    @test vl(xy * visual(Lines; stroke="black"))["mark"] == Dict("type" => "line", "stroke" => "black")
    @test vl(xy * visual(Lines; strokecolor=:black))["mark"] == Dict("type" => "line", "stroke" => "black")
    # A composite mark's parts carry the style and the paint.
    bars = data((; x=[1.0, 2.0], lo=[0.5, 1.5], hi=[1.5, 2.5])) * mapping(:x, :lo, :hi)
    @test vl(bars * visual(Rangebars; stroke=:ink))["mark"] == Dict("type" => "errorbar",
        "rule" => Dict("style" => ["errorbar-rule", "aov-ink-stroke"], "stroke" => "#333"))
    # A picker figure and a layered sum are finished the same way.
    summed = vl(xy * visual(Lines; stroke=:ink) + xy * visual(Scatter))
    @test only(l["mark"]["stroke"] for l in summed["layer"] if l["mark"]["type"] == "line") == "#333"
    picked = to_vegalite(data((; x=[1.0, 2.0], y=[2.0, 3.0], g=["a", "b"])) * mapping(:x, :y; color=:g) *
        visual(Lines; stroke=:ink); auto_remap=(; dims=["g" => "G"]))
    @test picked["mark"]["stroke"] == "#333"

    # Static output: Makie's `strokecolor` takes the theme's text colour.
    Makie.with_theme(Makie.theme_black()) do
        fixed = AlgebraOfVega._fix_visual_attrs(xy * visual(Scatter; strokecolor=:ink))
        @test AlgebraOfVega.extract_visual(fixed).attributes[:strokecolor] == :white
    end
end

"""
Composite marks take fixed ink on the parts they draw.

Regression (snag `rangebars-ink-er-e2c73e9e`): Vega-Lite drops a composite
mark's own `style` (each part gets `"<mark>-<part>"`), so
`visual(Rangebars; color=:ink)` emitted `{"type":"errorbar","style":"aov-ink"}`
and its rule rendered Vega-Lite's default black in both themes.
"""
@testitem "composite marks carry fixed ink on their drawn parts" tags=[:theme, :regression] begin
    using AlgebraOfVega
    bars = (; x=[1.0, 2.0], lo=[0.5, 1.5], hi=[1.5, 2.5])
    mark(spec) = to_vegalite(spec)["mark"]
    ranged(; kw...) = data(bars) * mapping(:x, :lo, :hi) * visual(Rangebars; kw...)
    part(m, p) = m[p]["style"]

    vl = to_vegalite(ranged(color=:ink))
    @test vl["mark"] == Dict("type" => "errorbar", "rule" => Dict("style" => ["errorbar-rule", "aov-ink"]))
    @test vl["config"]["style"]["aov-ink"] == Dict("color" => "#333")
    errs = data((; x=[1.0, 2.0], y=[1.0, 2.0], e=[0.2, 0.3])) * mapping(:x, :y, :e) * visual(Errorbars; color=:ink)
    @test part(mark(errs), "rule") == ["errorbar-rule", "aov-ink"]
    # A part the caller switches on is styled too; one switched off stays off.
    @test part(mark(ranged(color=:ink, ticks=true)), "ticks") == ["errorbar-ticks", "aov-ink"]
    @test mark(ranged(color=:ink, ticks=false))["ticks"] === false
    # The caller's part properties and style are kept (ink last), and not mutated.
    own = Dict("strokeWidth" => 3, "style" => "mine")
    @test mark(ranged(color=:ink, rule=own))["rule"] == Dict("strokeWidth" => 3, "style" => ["mine", "aov-ink"])
    @test own == Dict("strokeWidth" => 3, "style" => "mine")
    @test mark(ranged(color=:ink, rule=(; strokeWidth=3)))["rule"] ==
        Dict("strokeWidth" => 3, "style" => ["errorbar-rule", "aov-ink"])
    # Any composite style reaches the parts, not only ink.
    @test mark(ranged(style="other")) == Dict("type" => "errorbar", "rule" => Dict("style" => ["errorbar-rule", "other"]))
    # Literal colours already reach every part through the composite's `color`.
    @test mark(ranged(color="black")) == Dict("type" => "errorbar", "color" => "black")

    box = mark(data((; g=repeat(["a", "b"], 5), v=collect(1.0:10.0))) * mapping(:g, :v) * visual(BoxPlot; color=:ink))
    @test !haskey(box, "style") && !haskey(box, "ticks")
    @test all(p -> part(box, p) == ["boxplot-$p", "aov-ink"], ("box", "median", "outliers", "rule"))
    # Plain marks keep the style on the mark itself.
    @test AlgebraOfVega._style_composite_parts(Dict{String,Any}("type" => "rule", "style" => "aov-ink")) ==
        Dict("type" => "rule", "style" => "aov-ink")
end

@testitem "host theme follows the page in the browser" setup=[AoVBrowserServer] tags=[:theme, :browser, :regression, :auto_remap, :incremental] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]

    states = ["passed", "failed"]
    palette = ["#16826b", "#d94848"]
    function figure(scale)
        rows = (; value=[scale * i for i in 1:24], model=repeat(["m1", "m2", "m3", "m4"], inner=6),
            state=repeat(states, inner=12), group=repeat(["g1", "g2"], 12))
        data(rows) * mapping(:value => "Seconds"; y=:model => "Model", color=:state => "Outcome") *
            pointinterval(probs=[0.5]) *
            config(height=160, scales=scales(Color=(; categories=states, palette)))
    end
    remap = (; dims=["state" => "Outcome", "group" => "Group"], pinned=:row)
    live = data((; x=Float64[], y=Float64[])) * mapping(:x, :y) * visual(Scatter) * config(height=120)
    plain = data((; x=[1.0, 2.0, 3.0], y=[3.0, 1.0, 2.0])) * mapping(:x, :y) * visual(Scatter) *
        config(height=120)
    ink = data((; value=collect(1.0:30.0))) * mapping(:value) * dotinterval() * config(height=120)
    line_rows = (; x=[1.0, 2.0, 3.0], y=[1.0, 3.0, 2.0])
    ink_line = data(line_rows) * mapping(:x, :y) * visual(Lines; color=:ink, linewidth=3) * config(height=120)
    ink_point = data(line_rows) * mapping(:x, :y) * visual(Scatter; color=:ink, filled=true) * config(height=120)
    black_line = data(line_rows) * mapping(:x, :y) * visual(Lines; color="black", linewidth=3) * config(height=120)
    bar_rows = (; x=[1.0, 2.0, 3.0], lo=[0.5, 1.5, 1.0], hi=[1.5, 2.5, 3.0])
    ink_bars = data(bar_rows) * mapping(:x, :lo, :hi) * visual(Rangebars; color=:ink) * config(height=120)
    black_bars = data(bar_rows) * mapping(:x, :lo, :hi) * visual(Rangebars; color="black") * config(height=120)
    ink_box = data((; g=repeat(["a", "b"], 6), v=collect(1.0:12.0))) * mapping(:g, :v) *
        visual(BoxPlot; color=:ink) * config(height=120)
    # One side of a mark in the ink (snag `visual-stroke-in-91baea43`).
    square = Dict{String,Any}("type" => "FeatureCollection", "features" => [Dict{String,Any}(
        "type" => "Feature", "properties" => Dict{String,Any}("ags" => "a"),
        "geometry" => Dict{String,Any}("type" => "Polygon",
            "coordinates" => [[[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]]))])
    ink_outline = data((; ags=["a"])) * mapping(:ags) * geoshape(square; key=:ags) *
        visual(; fill=nothing, stroke=:ink, strokeWidth=2) * config(height=120)
    ink_stroke_line = data(line_rows) * mapping(:x, :y) * visual(Lines; strokecolor=:ink, linewidth=3) * config(height=120)
    ink_fill_point = data(line_rows) * mapping(:x, :y) *
        visual(Scatter; fill=:ink, strokecolor="red", strokewidth=2) * config(height=120)

    updates = Dict(
        "append" => script(append_data("theme-live", (; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0]))),
        "spec" => script(update_spec("theme-picker", figure(2.0); auto_remap=remap)))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-host-theme-") do dir
            page = [with_plot_caption(figure(1.0), "Outcomes"; plot_id="theme-picker", auto_remap=remap),
                vdraw(live; id="theme-live"),
                vdraw(plain * config(theme=:none); id="theme-none"),
                vdraw(plain * config(config=Dict("axis" => Dict("labelColor" => "#ff0000"))); id="theme-authored"),
                vdraw(ink; id="theme-ink"),
                vdraw(ink_line; id="theme-line-ink"),
                vdraw(ink_point; id="theme-point-ink"),
                vdraw(black_line; id="theme-line-black"),
                vdraw(ink_bars; id="theme-bars-ink"),
                vdraw(ink_box; id="theme-box-ink"),
                vdraw(ink_outline; id="theme-geo-stroke-ink"),
                vdraw(ink_stroke_line; id="theme-line-stroke-ink"),
                vdraw(ink_fill_point; id="theme-point-fill-ink"),
                vdraw(black_bars; id="theme-bars-black")]
            style = "<style>body{color:rgb(30,40,50);background:rgb(250,250,250)}" *
                "html[data-theme=dark] body{color:rgb(200,210,220);background:rgb(20,24,31)}</style>"
            payload = replace(JSON.json((; updates, palette)), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "host_theme.js"), String)
            body = "<body>" * join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script></body>"
            # The same page with the runtime inlined (a file:// page) and loaded
            # by URL from a served `vega_vendor_dir()` (snag
            # `cacheable-aov-ru-114438c0`): the runtime behaves identically.
            for (source, runtime) in ((:inline, :inline), (:vendor, :linked))
                head = join(html(n) for n in vega_head(; source, runtime, base="/vendor"))
                write(joinpath(dir, "$source.html"), "<!doctype html><meta charset='utf-8'>" * style * head * body)
            end
            function run_page(url, source)
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile-$source")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $url`,
                    stderr=joinpath(dir, "chrome-$source.log")), String)
                result = match(r"<pre id=\"aov-host-theme-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                isnothing(result) && return
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "host theme browser checks" source checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
            run_page("file://" * joinpath(dir, "inline.html"), :inline)
            with_page_server(dir) do root
                run_page(root * "/vendor.html", :vendor)
            end
        end
    end
end
