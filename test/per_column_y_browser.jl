using TestItemRunner

# Per-column Y scale figures embed, through `vdraw` and through the channel
# picker, with each column's own Y scale type.
# - `col=` but no `row=`: the picker can add and remove a row facet. Before,
#   every hconcat child was a `spec` with no `facet` beside it, which Vega-Lite
#   rejects as an invalid specification, so the figure never embedded.
# - `row=` and `col=`: a reference layer without the column field reaches every
#   cell, and the picker can clear and restore the row facet. Before, the
#   row×col children faceted only by row, so the cross-source broadcast never
#   replicated the reference rows across columns (0 hlines drawn), and a
#   row-clear left `facet: {}` beside `spec` (a TypeError, no re-embed).
@testitem "per-column Y scales render in the browser" tags=[:regression, :browser, :translation, :auto_remap] begin
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
    # Row × column, with a reference line that has neither facet field.
    ref = data((; y0=[2.0])) * mapping(:y0) * visual(HLines)
    rowcol_ref = (data(pts) * mapping(:x, :y; col=:p, row=:r) * visual(Scatter) + ref) * sc
    colonly_ref = (data(pts) * mapping(:x, :y; col=:p) * visual(Scatter) + ref) * sc
    rowcol = (data(pts) * mapping(:x, :y; col=:p, row=:r) * visual(Lines) +
              data(pts) * mapping(:x, :y; col=:p, row=:r) * visual(Scatter)) * sc
    @test all(s -> haskey(to_vegalite(s), "hconcat"), (single, layered, rowcol_ref, colonly_ref, rowcol))
    # The second-positional Scales form of the single-layer figure (its legend
    # pass runs twice; see the items.jl parity item).
    positional = to_vegalite(data(pts) * mapping(:x, :y; col=:p, color=:g) * visual(Scatter) *
                             config(height=120), scales(Y=(; scale=Dict("P1" => log10))))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-per-column-y-") do dir
            page = [vdraw(single; id="pc-single"), vdraw(layered; id="pc-layered"),
                vdraw(positional; id="pc-positional"),
                auto_remap_node("pc-picker", layered;
                    dims=["g" => "Group", "r" => "Run"], fixed=Dict(:column => "p"), pinned=:detail),
                vdraw(rowcol_ref; id="pc-rowcol-ref"), vdraw(colonly_ref; id="pc-colonly-ref"),
                auto_remap_node("pc-rowcol-picker", rowcol;
                    dims=["g" => "Group", "r" => "Run"], fixed=Dict(:column => "p"), pinned=:detail, row="r")]
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
                @test report["checks"] >= 41
                @test isempty(report["failures"])
                @info "per-column Y browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
