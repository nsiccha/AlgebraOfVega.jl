@testitem "background paint lowers without changing authored colours" tags=[:theme, :regression] begin
    using JSON
    import Makie
    xy = data((; x=[1, 2], y=[2, 1])) * mapping(:x, :y)
    for (attr, prop, style) in ((:color, "color", "aov-background"),
            (:strokecolor, "stroke", "aov-background-stroke"),
            (:stroke, "stroke", "aov-background-stroke"), (:fill, "fill", "aov-background-fill"))
        attrs = Dict(attr => :background)
        spec = xy * visual(Scatter; attrs...)
        vl = to_vegalite(spec)
        @test vl["mark"]["style"] == style
        @test Makie.to_color(vl["config"]["style"][style][prop]) == Makie.to_color(:white)
        prop == "color" || @test vl["mark"][prop] == vl["config"]["style"][style][prop]
        @test attrs[attr] === :background
        own = to_vegalite(spec * config(config=Dict("background" => "#182025")))
        @test Makie.to_color(own["config"]["style"][style][prop]) == Makie.to_color("#182025")
    end
    spec = xy * visual(Scatter; color="#1f6fb5", strokecolor=:background, strokewidth=1.5)
    vl = to_vegalite(spec)
    @test vl["mark"]["color"] == "#1f6fb5"
    @test vl["mark"]["strokeWidth"] == 1.5
    own = to_vegalite(spec * config(config=Dict("style" => Dict("aov-background-stroke" => Dict("stroke" => "red")))))
    @test own["mark"]["stroke"] == "red"
    @test to_vegalite(xy * visual(Scatter; color=:ink))["mark"]["style"] == "aov-ink"
    @test to_vegalite(xy * visual(Scatter; color="white"))["mark"]["color"] == "white"
    alpha = to_vegalite(spec * config(config=Dict("background" => "rgba(0,0,0,0.5)")))
    @test alpha["mark"]["stroke"] == "rgba(127.5, 127.5, 127.5, 1.0)"
    panel = to_vegalite(spec * config(config=Dict("background" => "black", "view" => Dict("fill" => "rgba(255,255,255,0.5)"))))
    @test panel["mark"]["stroke"] == "rgba(127.5, 127.5, 127.5, 1.0)"
    @test JSON.json(to_vegalite(spec)) == JSON.json(vl)
end

@testitem "background paint uses the Makie destination axis" tags=[:theme, :static, :regression] begin
    import AlgebraOfGraphics   # with Makie, loads the static path (AlgebraOfVegaMakieExt)
    import Makie
    spec = data((; x=[1, 2], y=[2, 1])) * mapping(:x, :y) *
        visual(Scatter; color="#1f6fb5", strokecolor=:background, strokewidth=1.5)
    original = to_json(spec)
    for color in (:white, "#181c25")
        fig = Makie.Figure()
        ax = Makie.Axis(fig[1, 1]; backgroundcolor=color)
        sdraw!(ax, spec)
        pts = filter(p -> p isa Makie.Scatter, ax.scene.plots)
        @test length(pts) == 1
        @test Makie.to_value(only(pts).strokecolor) == Makie.to_color(color)
        @test Makie.to_value(only(pts).color) == Makie.to_color("#1f6fb5")
    end
    fig = Makie.Figure(backgroundcolor=:black)
    sdraw!(fig[1, 1], spec * config(axis=(; backgroundcolor=(:white, 0.5))))
    ax = only(filter(x -> x isa Makie.Axis, fig.content))
    pts = only(filter(p -> p isa Makie.Scatter, ax.scene.plots))
    @test Makie.to_value(pts.strokecolor) == Makie.RGBAf(0.5, 0.5, 0.5, 1)
    Makie.with_theme(Makie.theme_dark()) do
        fig = Makie.Figure()
        sdraw!(fig, spec + spec)
        ax = only(filter(x -> x isa Makie.Axis, fig.content))
        @test all(p -> Makie.to_value(p.strokecolor) == Makie.to_color(:gray10), ax.scene.plots)
    end
    @test to_json(spec) == original
end

@testitem "background paint survives vsave" tags=[:theme, :vsave, :regression] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        spec = data((; x=[1, 2], y=[2, 1])) * mapping(:x, :y) *
            visual(Scatter; color="#1f6fb5", strokecolor=:background, strokewidth=1.5)
        mktempdir() do dir
            for (name, cfg) in (("white", config()), ("dark", config(config=Dict("background" => "#181c25"))))
                path = joinpath(dir, name * ".svg")
                vsave(spec * cfg, path)
                svg = read(path, String)
                points = collect(eachmatch(r"<path[^>]*aria-roledescription=\"point\"[^>]*>", svg))
                @test length(points) == 2
                stroke = to_vegalite(spec * cfg)["mark"]["stroke"]
                @test all(m -> occursin("stroke=\"$stroke\"", m.match), points)
                @test all(m -> occursin("fill=\"#1f6fb5\"", m.match), points)
            end
        end
    end
end

@testitem "background paint follows browser surfaces and downloads" tags=[:theme, :browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    using HTMX: h
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    xy = data((; x=collect(1:24), y=sin.(1:24))) * mapping(:x, :y)
    points = xy * visual(Scatter; color="#1f6fb5", size=64, alpha=1,
        strokecolor=:background, strokewidth=1.5) * config(width=440, height=180)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-background-") do tmp
            dir = get(ENV, "AOV_BACKGROUND_ARTIFACTS", tmp)
            mkpath(dir)
            page = [with_plot_caption(points, "Caesium point outlines"; plot_id="bg-points"),
                h.div(id="panel", style="background:rgba(255,255,255,.25)")(
                    vdraw(points; id="bg-panel")),
                vdraw(points * config(config=Dict("background" => "#456789")); id="bg-own"),
                vdraw(points * config(config=Dict("background" => "#445566", "view" => Dict("fill" => "#aabbcc"))); id="bg-view"),
                vdraw(points * config(theme=:none); id="bg-none"),
                vdraw(xy * visual(Scatter; fill=:background, strokecolor=:ink, strokewidth=2) * config(height=100); id="bg-fill"),
                vdraw(xy * visual(Scatter; color=:background) * config(height=100); id="bg-color")]
            css = "<style>body{color:rgb(30,40,50);background:white;margin:24px}" *
                "html[data-theme=dark] body{color:rgb(200,210,220);background:rgb(24,28,37)}" *
                "html[data-theme=changed] body{color:rgb(200,210,220);background:rgb(40,50,60)}</style>"
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "background_color.js"), String)
            body = "<button id='theme-toggle' onclick=\"document.documentElement.dataset.theme='dark';AoV.refreshTheme()\">Dark theme</button>" * join(html(p) for p in page)
            file = joinpath(dir, "background.html")
            write(file, "<!doctype html><meta charset='utf-8'>" * css * head * "<body>" * body * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(tmp, "profile")) --window-size=1200,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * file)`, stderr=joinpath(dir, "chrome.log")), String)
            write(joinpath(dir, "result.html"), output)
            result = match(r"<pre id=\"background-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
                write(joinpath(dir, "receipt.json"), JSON.json(report))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
