using TestItemRunner

@testitem "remapping preserves cell sizing and streamed rows" tags=[:auto_remap, :browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        rows = (; value=[2., 3., 2., 2., 4., 5.],
            category=repeat(["A", "B", "C"], inner=2),
            family=repeat(["F1", "F2", "F3"], inner=2),
            group=repeat(["G1", "G2", "G3"], inner=2),
            metric=repeat(["P", "Q"], 3))
        base = data(rows) * mapping(:value, :category; color=:family)
        faceted = data(rows) * mapping(:value, :category; color=:family, col=:metric)
        cfg = config(height=140, scales=scales(X=(; scale=log10)),
            facet=(; linkxaxes=:none, linkyaxes=:none))
        picker = auto_remap_node("sizing-picker", faceted * visual(Scatter) * cfg;
            dims=["family" => "Family", "group" => "Group"],
            off=["family", "group"], pinned=:row, fixed=Dict(:column => "metric"))
        plots = [picker,
            vdraw(base * visual(Scatter) * cfg; id="sizing-single"),
            vdraw(base * (visual(Scatter) + visual(Lines)) * cfg; id="sizing-layered"),
            vdraw(faceted * (visual(Scatter) + visual(Lines)) * cfg; id="sizing-faceted-layered")]
        mktempdir(prefix="kb-remap-sizing-") do dir
            runtime = join(sprint(show, MIME"text/html"(), n) for n in vega_head(source=:inline))
            driver = read(joinpath(@__DIR__, "remap_sizing.js"), String)
            html = "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "embed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" *
                join(sprint(show, MIME"text/html"(), p) for p in plots) *
                "<script>" * driver * "</script>"
            path = joinpath(dir, "test.html")
            write(path, html)
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1100
                --virtual-time-budget=15000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-remap-sizing-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 25
                @test isempty(report["failures"])
                @info "remap sizing browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
