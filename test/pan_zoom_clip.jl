using TestItemRunner

# AoV's automatic pan/zoom (the `grid` selection bound to the scales) made
# Vega-Lite clip every mark of the view to its frame, so `vdraw` drew less than
# the `vsave` file: text placed outside the frame — labels above a schedule's
# meeting lines, a direct label past the right edge — was cut, and Vega reserved
# no room for it, so an authored `padding` stayed blank (snag
# `text-marks-above-6e3d5a0b`, design decision `1jxmoil`). The runtime now draws
# such marks whole until the reader zooms or pans, and then cuts them at the
# frame only along the zoomed axes. A layer that authors `clip=true` keeps it.
@testsnippet AoVPanZoomClipFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    const Mk = AlgebraOfVega.Makie
    rows = ["a", "b", "c"]
    bars = data((; row=rows, s=[0.0, 1, 2], e=[2.0, 3, 4])) *
        mapping(:row => sorter(rows) => "", :e; fillto=:s) * visual(BarPlot; direction=:x)
    M = (; at=[1.0, 3.0], label=["M 1", "M 2"], row=["a", "a"])
    lines = data(M) * mapping(:at) * visual(VLines; linestyle=:dash)
    label_layer(; kw...) = data(M) * mapping(:at, :row => sorter(rows) => ""; text=:label) *
        visual(Mk.Text; align=(:center, :bottom), offset=(0, 12), fontsize=11, inspectable=false, kw...)
    # The reporter's figure, verbatim.
    gantt = (bars + lines + label_layer()) * config(height=60)
    own = (bars + lines + label_layer(; clip=true)) * config(height=60)
    # Both axes zoom: a label above the top point.
    scatter = (data((; x=[1.0, 2, 3], y=[1.0, 2, 3])) * mapping(:x, :y) * visual(Scatter) +
        data((; x=[3.0], y=[3.0], t=["top"])) * mapping(:x, :y; text=:t) *
        visual(Mk.Text; align=(:center, :bottom), offset=(0, 12), fontsize=11)) * config(height=80)
    panels = (; row=["a", "b", "a", "b"], s=[0.0, 1, 0, 1], e=[2.0, 3, 2, 3], panel=["P", "P", "Q", "Q"])
    F = (; at=[1.0, 1.0], label=["F 1", "F 2"], row=["a", "a"], panel=["P", "Q"])
    facet = (data(panels) * mapping(:row => sorter(["a", "b"]) => "", :e; fillto=:s, col=:panel) *
        visual(BarPlot; direction=:x) +
        data(F) * mapping(:at, :row => sorter(["a", "b"]) => ""; text=:label, col=:panel) *
        visual(Mk.Text; align=(:center, :bottom), offset=(0, 12), fontsize=11)) * config(height=40)
    marks_of(vl) = haskey(vl, "layer") ? [l["mark"] for l in vl["layer"]] :
        haskey(vl, "spec") ? marks_of(vl["spec"]) : [vl["mark"]]
    styles(mark) = mark isa AbstractDict ? (s = get(mark, "style", String[]); s isa AbstractVector ? s : [s]) : String[]
end

@testitem "pan/zoom leaves the marks' clip to the runtime, except a clip the layer authors" setup=[AoVPanZoomClipFixtures] tags=[:regression, :translation, :interactivity] begin
    vl = to_vegalite(gantt)
    @test any(l -> any(p -> p["name"] == "grid" && p["bind"] == "scales", get(l, "params", [])), vl["layer"])
    # Nothing is written onto the marks: the runtime's compiled-spec patch
    # replaces Vega-Lite's own pan/zoom clip.
    @test all(m -> !("aov-own-clip" in styles(m)) && !(m isa AbstractDict && haskey(m, "clip")), marks_of(vl))

    # An authored `clip=true` is kept: its marks carry the style the patch skips.
    own_marks = marks_of(to_vegalite(own))
    @test count(m -> "aov-own-clip" in styles(m), own_marks) == 1
    text_mark = only(filter(m -> m isa AbstractDict && m["type"] == "text", own_marks))
    @test text_mark["clip"] === true
    @test "aov-passive" in styles(text_mark)   # the other style stays
    # An authored `clip=false` needs no marker: the patch rewrites only `true`.
    @test !any(m -> "aov-own-clip" in styles(m), marks_of(to_vegalite((bars + label_layer(; clip=false)))))
    # Without pan/zoom there is no runtime clip to keep a layer's own from.
    @test !any(m -> "aov-own-clip" in styles(m), marks_of(to_vegalite(own; interactive=false)))
    # A facet's cells carry the selection and the marker alike.
    facet_own = (data(panels) * mapping(:row => sorter(["a", "b"]) => "", :e; fillto=:s, col=:panel) *
        visual(BarPlot; direction=:x) * visual(; clip=true)) * config(height=40)
    @test any(m -> "aov-own-clip" in styles(m), marks_of(to_vegalite(facet_own)))

    # The bare `to_html(spec)` embed carries the same patch, only with pan/zoom.
    @test occursin("grid_tuple_fields", to_html(gantt; id="bare"))
    @test occursin("m.interactive = false", to_html(gantt; id="bare"))  # still passive
    no_zoom = data((; k=["a", "b"], v=["x", "y"])) * mapping(:k, :v) * visual(Scatter)
    @test !occursin("grid_tuple_fields", to_html(no_zoom; id="bare"))
end

@testitem "pan/zoom clip in the browser: marks drawn whole until the reader zooms" setup=[AoVPanZoomClipFixtures] tags=[:regression, :browser, :interactivity] begin
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-pan-zoom-clip-") do dir
            # The bare embed draws through vega-embed directly; the page hands
            # its view to the driver (`window.aovBareViews`).
            capture = "<script>(function () { var embed = window.vegaEmbed; window.aovBareViews = {}; " *
                "window.vegaEmbed = function (el, spec, opts) { return embed(el, spec, opts).then(function (r) { " *
                "window.aovBareViews[String(el).replace('#', '')] = r.view; return r; }); }; })();</script>"
            bare = replace(to_html(gantt; id="pz-bare"), r"<script [^>]*\bsrc=[^>]*></script>" => "")
            page = join(html(p) for p in (vdraw(gantt; id="pz-gantt"),
                vdraw(gantt * config(padding=Dict("top" => 24, "left" => 5, "right" => 5, "bottom" => 5)); id="pz-padded"),
                vdraw(scatter; id="pz-scatter"), vdraw(own; id="pz-own"), vdraw(facet; id="pz-facet")))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "pan_zoom_clip.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='margin:0'><div style='width:800px'>" * page * capture * bare *
                "</div><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,1400
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-pan-zoom-clip-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "pan/zoom clip browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
