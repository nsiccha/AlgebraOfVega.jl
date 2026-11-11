using TestItemRunner

@testitem "axis remaps release and restore authored domains" tags=[:auto_remap, :browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        rows = (; category=["A", "B", "A", "B"], other=["C", "D", "C", "D"],
            value=[1., 2., 1., 2.], larger=[100., 200., 100., 200.],
            panel=["P", "P", "Q", "Q"])
        categories = ["B", "spacer", "A"]
        base = data(rows) * mapping(:value, :category)
        cfg = config(width=240, height=150,
            scales=scales(X=(; domain=[0., 3.], nice=false), Y=(; categories)))
        categorical = base * visual(Scatter) * cfg
        faceted = data(rows) * mapping(:value, :category; col=:panel) * visual(Scatter) * cfg
        concat = data(rows) * mapping(:category, :value; col=:panel) * visual(Scatter) *
            config(width=240, height=150, scales=scales(X=(; categories),
                Y=(; scale=Dict("P" => log10))),
                encoding=Dict("y" => Dict("scale" => Dict("domain" => [1., 3.], "nice" => false))))
        @test haskey(to_vegalite(concat), "hconcat")
        plots = [auto_remap_node("domain-picker", categorical;
                dims=["other" => "Other", "larger" => "Larger"], axes=true, pinned=:detail),
            vdraw(base * (visual(Scatter) + visual(Lines)) * cfg; id="domain-layered"),
            vdraw(faceted; id="domain-faceted"), vdraw(concat; id="domain-concat")]
        mktempdir(prefix="kb-remap-domain-") do dir
            html(x) = sprint(show, MIME"text/html"(), x)
            head = join(html(n) for n in vega_head(source=:inline))
            driver = read(joinpath(@__DIR__, "remap_axis_domain.js"), String)
            path = joinpath(dir, "test.html")
            write(path, "<!doctype html><meta charset='utf-8'>" * head *
                join(html(p) for p in plots) * "<script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1100
                --virtual-time-budget=20000 --dump-dom $("file://" * path)`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-remap-domain-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 80
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
                @test isempty(report["failures"])
                @info "axis domain browser checks" checks=report["checks"]
            end
        end
    end
end
