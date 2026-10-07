using TestItemRunner

"""
The caption row's "⬇ HTML" export saves a self-contained card from pages that
load the Vega trio and AoV's runtime inline or by URL.

Regression (snag `cacheable-aov-ru-114438c0`): `vega_head(source=:vendor,
runtime=:linked)` loads AoV's runtime and stylesheet by URL, and
`AoV.downloadPlotHtml` used to collect only inline AoV scripts and `vega@` CDN
tags — so a saved card from a `:vendor` or `:inline` page carried no Vega at
all. Same-origin vendored files are now fetched and inlined, and inline
vendored scripts copied, so the saved file renders with neither the server nor
a CDN.
"""
@testitem "standalone html export from inline and vendored pages" setup=[AoVBrowserServer] tags=[:standalone, :browser, :regression, :caption] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))

    states = ["passed", "failed"]
    rows = (; value=collect(1.0:24.0), model=repeat(["m1", "m2", "m3", "m4"], inner=6),
        state=repeat(states, inner=12), group=repeat(["g1", "g2"], 12))
    spec = data(rows) * mapping(:value => "Seconds"; y=:model => "Model", color=:state => "Outcome") *
        pointinterval(probs=[0.5]) * config(height=160)
    remap = (; dims=["state" => "Outcome", "group" => "Group"], pinned=:row)
    versions = [AlgebraOfVega.VEGA_VERSION, AlgebraOfVega.VEGALITE_VERSION, AlgebraOfVega.VEGA_EMBED_VERSION]
    driver = read(joinpath(@__DIR__, "standalone_export.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-export-") do dir
            # (source, runtime, assets loaded by URL, vendored assets in the
            # saved file): an inline trio is copied; vendored URLs — the trio,
            # plus AoV's runtime + stylesheet when linked — are fetched.
            cases = ((:inline, :inline, 0, 3), (:vendor, :inline, 3, 3), (:vendor, :linked, 5, 5))
            for (source, runtime, by_url, saved_marked) in cases
                page = to_html(spec, "Outcomes"; plot_id="export-plot", auto_remap=remap,
                    source, runtime, base="/vendor")
                payload = replace(JSON.json((; id="export-plot", byUrl=by_url, savedMarked=saved_marked,
                    linked=runtime === :linked, versions)), "</" => "<\\/")
                # The page's own closing tag: inlined vega-embed spells
                # `</body>` inside a string, so only the last one is the page's.
                cut = first(findlast("</body>", page))
                write(joinpath(dir, "$source-$runtime.html"), page[1:prevind(page, cut)] *
                    "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>" *
                    page[cut:end])
            end
            with_page_server(dir) do root
                for (source, runtime, by_url, _) in cases
                    name = "$source-$runtime"
                    output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                        --user-data-dir=$(joinpath(dir, "profile-$name")) --window-size=1200,1400
                        --virtual-time-budget=20000 --dump-dom $(root * "/$name.html")`,
                        stderr=joinpath(dir, "chrome-$name.log")), String)
                    result = match(r"<pre id=\"aov-export-results\">([^<]*)</pre>", output)
                    @test !isnothing(result)
                    isnothing(result) && continue
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] >= 16 + 2by_url
                    @test isempty(report["failures"])
                    @info "standalone export browser checks" source runtime checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
