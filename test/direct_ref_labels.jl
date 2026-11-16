using TestItemRunner

# The caesium page supplies only the moving threshold from its browser model.
# The constant label belongs to the mapping, and must survive replacement of
# that whole dataset, including an empty dataset when the threshold is off.
@testitem "direct scalars are data and reference labels survive reports" tags=[:reflabels] begin
    using AlgebraOfVega, HTMXObjects, Base64, Dates
    rows = (; lower=[2.0, 3.0], upper=[2.5, 3.5])
    label = "Detection 'limit' \"quoted\" \\ μ"
    for (mark, positions) in ((VLines, (:lower,)), (HLines, (:lower,)),
                              (VSpan, (:lower, :upper)), (HSpan, (:lower, :upper)))
        fig = data(rows) * mapping(positions...; text=direct(label)) * visual(mark; color=:ink)
        vl = to_vegalite(fig)
        @test length(vl["layer"]) == 2
        @test vl["layer"][2]["encoding"]["text"] == Dict("datum" => label, "type" => "nominal")
        @test !haskey(vl["layer"][1]["encoding"], "text")
        @test all(r -> Set(keys(r)) == Set(["lower", "upper"]), vl["data"]["values"])
        @test rows == (; lower=[2.0, 3.0], upper=[2.5, 3.5])
        if !isnothing(Sys.which("vl-convert")) || haskey(ENV, "AOV_VL_CONVERT")
            md = HTMXObjects.to_markdown_string(with_plot_caption(fig, "Threshold"; plot_id="direct-report"); report=true)
            m = match(r"data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)", md)
            @test !isnothing(m)
            svg = String(base64decode(m[1]))
            @test occursin("Detection", svg) && occursin("quoted", svg) && occursin("μ", svg)
        end
    end
    # Data constants participate in scales, unlike a Vega pixel/mark value.
    vl = to_vegalite(data(rows) * mapping(direct(4.0) => "Constant", :lower;
        color=direct("Group")) * visual(Scatter))
    @test vl["encoding"]["x"]["datum"] == 4.0
    @test vl["encoding"]["x"]["type"] == "quantitative"
    @test vl["encoding"]["x"]["title"] == "Constant"
    @test vl["encoding"]["color"] == Dict("datum" => "Group", "type" => "nominal")
    for (constant, kind) in ((:group, "nominal"), (Date(2026, 1, 2), "temporal"), (2, "quantitative"))
        scalar_vl = to_vegalite(data(rows) * mapping(:lower, :upper; color=direct(constant)) * visual(Scatter))
        @test isequal(scalar_vl["encoding"]["color"]["datum"], constant)
        @test scalar_vl["encoding"]["color"]["type"] == kind
        @test to_json(data(rows) * mapping(:lower, :upper; color=direct(constant)) * visual(Scatter)) isa String
    end
end

@testitem "constant reference labels follow bound rows and standalone downloads" setup=[AoVBoundFixtures] tags=[:reflabels, :browser] begin
    using AlgebraOfVega, HTMXObjects, JSON
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        obj = BoundLines()
        line = data((; x=[0.0, 10.0], y=[0.0, 10.0])) * mapping(:x, :y) * visual(Lines)
        fig = (line + data(obj.rule) * mapping(:mid; text=direct("Detection limit")) *
            visual(VLines; color=:ink, linestyle=:dot)) * config(width=500, height=180)
        node = with_plot_caption(fig, "Threshold"; plot_id="direct-bound")
        html = to_html(node; source=:inline)
        @test occursin("data-htmxo-bound-columns", html)
        driver = read(joinpath(@__DIR__, "direct_ref_labels.js"), String)
        page = replace(html, r"</body>\s*</html>\s*$" => "<script>" * driver * "</script></body></html>")
        @test page != html
        mktempdir(prefix="kb-aov-direct-labels-") do dir
            write(joinpath(dir, "page.html"), page)
            # Optional retained page for inspecting the same fixture in real time.
            if haskey(ENV, "AOV_REF_LABEL_ARTIFACTS")
                mkpath(ENV["AOV_REF_LABEL_ARTIFACTS"])
                write(joinpath(ENV["AOV_REF_LABEL_ARTIFACTS"], "page.html"), html)
            end
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,800
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"direct-label-result\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                r = JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">"))
                @info "constant reference labels" r
                @test isempty(r["errors"])
                @test length(r["checks"]) >= 30
                @test all(c -> c["ok"], r["checks"])
            end
        end
    end
end
