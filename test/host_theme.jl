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
                vdraw(ink; id="theme-ink")]
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
