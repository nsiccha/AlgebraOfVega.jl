using TestItemRunner

# A plot's tooltip reads as one surface in the page's own colours. Before, AoV left it
# in vega-tooltip's light look while Pico painted every cell in the page's
# background: on a dark page a white frame around dark cells, with a white band
# wherever a key wrapped onto a second line, and a dark page without Pico got a
# white box.
@testitem "tooltips in the browser: one surface in the page's colours" tags=[:regression, :browser, :interactivity] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)

    rows = (; k=["a", "b", "c"], v=[1.0, 2.0, 4.0], title=["first", "second", "third"])
    # The long name wraps in the tooltip's key column, as in the report.
    long_name = "A long name that wraps onto a second line of the tooltip"
    figure = data(rows) * mapping(:k, :v => long_name) * visual(BarPlot) * config(width=240, height=120)
    titled = figure * config(encoding=Dict(:tooltip => [Dict("field" => "title"), Dict("field" => "k")]))
    site_rows = (; site=repeat([1, 2], inner=2), f=repeat(["a", "b"], 2), n=[3, 1, 2, 4])
    cells = cell_charts(data(site_rows) * mapping(:f, :n; layout=:site) * visual(BarPlot); id="tt-cells")
    host(fig=figure; id="tt-host") = html(vdraw(fig; id))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-tooltip-theme-") do dir
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            pico = "<link rel='stylesheet' href='pico.min.css'>"
            driver = read(joinpath(@__DIR__, "tooltip_theme.js"), String)
            head = join(html(n) for n in vega_head(; source=:inline))
            box(style, inner) = "<div style='$style'>$inner</div>"
            bare_spec = JSON.json(to_vegalite(figure))
            pages = Dict(
                "pico" => (pico, join([
                    "<table><tbody><tr>" * html(cells[1]) * "</tr><tr>" * html(cells[2]) * "</tr></tbody></table>",
                    host(),
                    host(titled; id="tt-title"),
                    host(figure * config(theme=:none); id="tt-none"),
                    box("background-color:rgb(250,240,220);color:rgb(60,40,20)", host(; id="tt-card")),
                    box("background-image:linear-gradient(rgb(10,20,30),rgb(20,40,60));color:rgb(240,240,240)", host(; id="tt-hero")),
                    box("background-color:rgba(255,255,255,.06)", host(; id="tt-translucent")),
                    box("background-color:rgba(0,0,0,.04)", host(; id="tt-shade"))]), 144),
                "plain" => ("<style>body{color:rgb(30,40,50);background:rgb(250,250,250)}" *
                        "html[data-theme=dark] body{color:rgb(200,210,220);background:rgb(20,24,31)}" *
                        "html[data-paper] body{background:rgb(250,240,220)}</style>",
                    host() * "<div id='tt-opts'></div><script>AoV.embed('tt-opts', $bare_spec, {tooltip: {theme: 'dark'}});</script>", 40),
                "bare" => ("", host(), 10),
                "scheme" => ("<style>:root{color-scheme:dark}</style>", host(), 9),
                "own" => ("<style>body{color:rgb(240,240,240);background:rgb(40,40,40)}#vg-tooltip-element{background-color:rgb(1,2,3)}</style>", host(), 2))
            for (name, (style, body, expected)) in pages
                file = "$name.html"
                write(joinpath(dir, file), "<!doctype html><meta charset='utf-8'>" * style * head *
                    "<body><main>" * body * "</main><script>window.AOV_TOOLTIP_PAGE='$name';</script><script>" * driver * "</script></body>")
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile-" * name)) --window-size=1200,3000
                    --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, file))`,
                    stderr=joinpath(dir, file * ".log")), String)
                result = match(r"<pre id=\"aov-tooltip-theme-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                isnothing(result) && continue
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] == expected
                @test isempty(report["failures"])
                @info "tooltip theme browser checks" name checks=report["checks"]
                isempty(report["failures"]) || println(name, ": ", JSON.json(report["failures"]))
            end
        end
    end
end
