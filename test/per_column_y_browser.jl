using TestItemRunner

# A per-column Y scale figure with `col=` but no `row=` embeds, through `vdraw`
# and through the channel picker, with each column's own Y scale type, and the
# picker can add and remove a row facet. Before, every hconcat child was a
# `spec` with no `facet` beside it, which Vega-Lite rejects as an invalid
# specification, so the figure never embedded.
@testitem "col-only per-column Y scales render in the browser" tags=[:regression, :browser, :translation, :auto_remap] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)

    # Two columns (P1 log-y, P2 linear) × two runs the picker may put on rows.
    pts = (; x=repeat([1.0, 2, 3], 4), y=[1.5, 2.5, 2.5, 1.0, 2.0, 3.5, 2.0, 3.0, 4.0, 1.5, 2.5, 3.0],
           g=repeat(["a", "b"], 6), p=repeat(["P1", "P2"], inner=3, outer=2), r=repeat(["R1", "R2"], inner=6))
    sc = config(height=120, scales=scales(Y=(; scale=Dict("P1" => log10))))
    single = data(pts) * mapping(:x, :y; col=:p, color=:g) * visual(Scatter) * sc
    layered = (data(pts) * mapping(:x, :y; col=:p) * visual(Lines) +
               data(pts) * mapping(:x, :y; col=:p) * visual(Scatter)) * sc
    @test all(s -> haskey(to_vegalite(s), "hconcat"), (single, layered))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-per-column-y-") do dir
            page = [vdraw(single; id="pc-single"), vdraw(layered; id="pc-layered"),
                auto_remap_node("pc-picker", layered;
                    dims=["g" => "Group", "r" => "Run"], fixed=Dict(:column => "p"), pinned=:detail)]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "per_column_y_browser.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,900
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-per-column-y-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 18
                @test isempty(report["failures"])
                @info "col-only per-column Y browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
