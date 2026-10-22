using TestItemRunner

"""
A page restyles its host-themed plots from CSS: the plot element's font, and an
optional look of `--aov-*` custom properties (default categorical palette, axis,
grid, tick, view-frame, legend and facet-header colours) on the element or any
ancestor.

Feature (todo `1f3r6ad`, user decision `1s5lxgn`): a page-level look that
switches live (an attribute on `<html>` plus `AoV.refreshTheme()`) restyles
every plot on the page, including ones its app draws outside its own wrappers.
Plots follow a font the page sets by default (decision `0cyx8fb`); a page on
the browser's default font keeps Vega's sans-serif (`host_theme.js`).
"""
@testitem "host look follows page CSS" setup=[AoVBrowserServer] tags=[:theme, :browser] begin
    using AlgebraOfVega, HTMXObjects, JSON, Base64
    import Makie
    html(x) = sprint(show, MIME"text/html"(), x)

    cats = ["c1", "c2", "c3", "c4"]
    scatter = data((; x=collect(1.0:8.0), y=[3.0, 1, 4, 1, 5, 9, 2, 6], cat=repeat(cats, 2))) *
        mapping(:x => "Ex", :y => "Why"; color=:cat => "Cat") * visual(Scatter) * config(height=140)
    states = ["passed", "failed"]
    semantic = data((; x=[1.0, 2.0, 3.0, 4.0], y=[1.0, 2.0, 3.0, 4.0], state=repeat(states, 2))) *
        mapping(:x, :y; color=:state) * visual(Scatter) *
        config(height=120, scales=scales(Color=(; categories=states, palette=["#16826b", "#d94848"])))
    facet = data((; x=collect(1.0:6.0), y=collect(1.0:6.0), panel=repeat(["p1", "p2"], 3))) *
        mapping(:x, :y; col=:panel => "Panel") * visual(Scatter) * config(height=100)
    authored = data((; x=[1.0, 2.0], y=[2.0, 1.0])) * mapping(:x, :y) * visual(Scatter) *
        config(height=100, config=Dict("axis" => Dict("labelColor" => "#ff0000")))
    ink = data((; x=[1.0, 2.0, 3.0], y=[1.0, 3.0, 2.0])) * mapping(:x, :y) *
        visual(Lines; color=:ink) * config(height=100)
    plain = data((; x=[1.0, 2.0], y=[2.0, 1.0])) * mapping(:x, :y) * visual(Scatter) * config(height=100)
    captioned = data((; x=collect(1.0:4.0), y=[2.0, 4.0, 1.0, 3.0], cat=cats)) *
        mapping(:x, :y; color=:cat) * visual(Scatter) * config(height=120)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-host-look-") do dir
            # A web font the page declares but nothing has used yet: the embed
            # waits for its faces instead of measuring and drawing a fallback.
            # (A data: URL, since a file:// page may not fetch a font file.)
            face = base64encode(read(Makie.assetpath("fonts", "DejaVuSansMono.ttf")))
            page = ["<div class='look'>", html(vdraw(scatter; id="look-scatter")),
                html(vdraw(semantic; id="look-semantic")), html(vdraw(facet; id="look-facet")),
                html(vdraw(authored; id="look-authored")), html(vdraw(ink; id="look-ink")),
                html(vdraw(plain * config(theme=:none); id="look-none")), "</div>",
                "<div style='--aov-font: \"AoV Test Face\"'>", html(vdraw(plain; id="look-face")), "</div>",
                "<div id='look-invalid-host' style='--aov-grid-color: notacolor; --aov-category: red, nocolor; " *
                    "--aov-tick-color: rgb(1,2,3); --aov-view-color: rgb(4, 5, 7)'>", html(vdraw(plain; id="look-invalid")), "</div>",
                html(with_plot_caption(captioned, "Captioned"; plot_id="look-card"))]
            style = """<style>
                @font-face { font-family: "AoV Test Face"; src: url(data:font/ttf;base64,$face); }
                html { --test-accent: rgb(200, 100, 0); }
                body { color: rgb(30, 40, 50); background: rgb(250, 250, 250);
                       font-family: "Test Grotesk", monospace; }
                html[data-look=alt] {
                    --aov-category: rgb(10, 20, 30), #c0ffee, light-dark(rgb(1, 2, 3), rgb(4, 5, 6)), var(--test-accent);
                    --aov-axis-label-color: rgb(90, 0, 0);
                    --aov-axis-title-color: rgb(0, 90, 0);
                    --aov-grid-color: rgb(0, 0, 90);
                    --aov-tick-color: NONE;
                    --aov-domain-color: none;
                    --aov-view-color: none;
                    --aov-legend-label-color: rgb(91, 0, 0);
                    --aov-legend-title-color: rgb(0, 91, 0);
                    --aov-header-label-color: rgb(92, 0, 0);
                    --aov-header-title-color: rgb(0, 92, 0);
                    --aov-font: "Alt Serif", serif;
                }
                </style><script>window.AOV_FACE_BEFORE = document.fonts.check('10px "AoV Test Face"');</script>"""
            driver = read(joinpath(@__DIR__, "host_look.js"), String)
            body = "<body>" * join(page) * "<script>" * driver * "</script></body>"
            # Inline runtime (a file:// page) and the linked runtime a static
            # export loads from a served `vega_vendor_dir()`.
            for (source, runtime) in ((:inline, :inline), (:vendor, :linked))
                head = join(html(n) for n in vega_head(; source, runtime, base="/vendor"))
                write(joinpath(dir, "$source.html"), "<!doctype html><meta charset='utf-8'>" * style * head * body)
            end
            function run_page(url, source)
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile-$source")) --window-size=1200,3000
                    --virtual-time-budget=20000 --dump-dom $url`,
                    stderr=joinpath(dir, "chrome-$source.log")), String)
                result = match(r"<pre id=\"aov-host-look-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                isnothing(result) && return
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 50
                @test isempty(report["failures"])
                @info "host look browser checks" source checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
            run_page("file://" * joinpath(dir, "inline.html"), :inline)
            with_page_server(dir) do root
                run_page(root * "/vendor.html", :vendor)
            end
        end
    end
end
