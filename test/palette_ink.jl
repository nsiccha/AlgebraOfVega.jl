using TestItemRunner

"""
`:ink` as an entry of a categorical `Color` palette.

Regression (snag `give-one-categor-f6fa34be`): `scales(Color=(; categories, palette=[:ink,
"#e03131"]))` emitted `"range": ["ink", "#e03131"]`. "ink" is no CSS colour, so the
reference series was not drawn in the page's text colour, and the only legible choices
were a palette colour that happens to read in both themes or a separate `color=:ink`
layer, which leaves the colour legend. A palette entry `:ink` is now the theme ink, as
`visual(; color=:ink)` is: `#333` in the spec (what `vsave` and a bare export draw), its
position recorded in `_aov.inkPalette`, and the runtime's host theme swaps it for the
page's text colour in every scale with that range, so marks and legend symbol follow.
"""
@testsnippet AoVPaletteInkFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    series = ["reference", "other"]
    rows = (; x=[1.0, 2.0, 1.0, 2.0], y=[1.0, 2.0, 2.0, 3.0], s=repeat(series; inner=2),
              g=["a", "b", "a", "b"])
    ink_scale = scales(Color=(; categories=series, palette=[:ink, "#e03131"]))
    lines(sc) = data(rows) * mapping(:x, :y; color=:s => "") * visual(Lines) * config(scales=sc)
    record(vl) = get(get(vl, "_aov", Dict()), "inkPalette", nothing)
    # Every colour/stroke/fill scale range of a lowered spec, in every view.
    function ranges(vl)
        out = Any[]
        AlgebraOfVega._foreach_colour_range(sc -> push!(out, sc["range"]), vl)
        out
    end
    # The colour name "ink" as a JSON string value (not the record's `"ink":` key).
    ink_value(json) = occursin(r"[\[,:]\"ink\"[\],}]", json)
end

@testitem "a palette entry :ink lowers to the theme ink" setup=[AoVPaletteInkFixtures] tags=[:theme, :regression, :translation] begin
    using JSON
    recorded = Dict{String,Any}("range" => Any["#333", "#e03131"], "ink" => [0])

    # The reported figure, inline and in the positional form.
    for vl in (to_vegalite(lines(ink_scale)),
               to_vegalite(data(rows) * mapping(:x, :y; color=:s) * visual(Lines), ink_scale))
        @test vl["encoding"]["color"]["scale"] == Dict("domain" => series, "range" => ["#333", "#e03131"])
        @test record(vl) == recorded
        @test vl["config"]["style"]["aov-ink"] == Dict("color" => "#333")
        @test !ink_value(JSON.json(vl))
    end
    # Control for that check: the base emitted the colour name.
    @test ink_value("{\"range\":[\"ink\",\"#e03131\"]}") && !ink_value("{\"ink\":[0]}")

    # A palette without ink is written as before: no record, no ink style.
    plain = to_vegalite(lines(scales(Color=(; categories=series, palette=["#212529", "#e03131"]))))
    @test plain["encoding"]["color"]["scale"]["range"] == ["#212529", "#e03131"]
    @test isnothing(record(plain))
    @test !haskey(get(plain, "config", Dict()), "style")

    # Several ink entries, a shorter palette, Makie colours beside the ink.
    many = to_vegalite(data(rows) * mapping(:x, :y; color=:g) * visual(Scatter) *
        config(scales=scales(Color=(; palette=[:red, :ink, (:blue, 0.5), :ink]))))
    @test many["encoding"]["color"]["scale"]["range"][[1, 2, 4]] == ["red", "#333", "#333"]
    @test record(many)["ink"] == [1, 3]

    # Every layer and a mapped stroke get the same range; one record per view.
    layered = to_vegalite(data(rows) * mapping(:x, :y; color=:s, strokecolor=:s) *
        (visual(Lines) + visual(Scatter)) * config(scales=ink_scale))
    lranges = [l["encoding"][ch]["scale"]["range"] for l in layered["layer"] for ch in ("color", "stroke")]
    @test length(lranges) == 4 && all(==(["#333", "#e03131"]), lranges)
    @test record(layered) == recorded

    # Facets (encoding and operator form) and the per-column Y scale concatenation keep
    # the record at the top, and every view's scale has the range.
    prows = merge(rows, (; p=["u", "u", "v", "v"]))
    faceted = to_vegalite(data(prows) * mapping(:x, :y; color=:s, col=:p) * visual(Lines) * config(scales=ink_scale))
    opfacet = to_vegalite(data(prows) * mapping(:x, :y; color=:s, col=:p) * (visual(Lines) + visual(Scatter)) *
        config(scales=ink_scale))
    percol = to_vegalite(data(prows) * mapping(:x, :y; color=:s, col=:p) * visual(Lines) *
        config(scales=scales(Color=(; categories=series, palette=[:ink, "#e03131"]),
                             Y=(; scale=Dict("u" => log10)))))
    @test haskey(opfacet, "spec") && haskey(percol, "hconcat")
    for vl in (faceted, opfacet, percol)
        @test record(vl) == recorded
        @test !isempty(ranges(vl)) && all(==(["#333", "#e03131"]), ranges(vl))
    end

    # The picker's lowering keeps it.
    picked = to_vegalite(lines(ink_scale); auto_remap=(; dims=["s" => "Series", "g" => "G"], pinned=:row))
    @test record(picked) == recorded

    # A caller who set the `aov-ink` colour gets it on the palette too, as on ink marks.
    pinned = to_vegalite(lines(ink_scale) * config(config=Dict("style" => Dict("aov-ink" => Dict("color" => "#123456")))))
    @test pinned["encoding"]["color"]["scale"]["range"] == ["#123456", "#e03131"]
    @test record(pinned)["range"] == ["#123456", "#e03131"]

    # A coloured ribbon: both drawings (ribbons and point-intervals) carry the palette.
    doses = [5.0, 10.0, 20.0, 40.0]
    rib = (; dose=repeat(doses, 2), q50=[1.0, 2.0, 3.0, 4.0, 1.5, 2.5, 3.5, 4.5],
             lo=[0.0, 1.0, 2.0, 3.0, 0.5, 1.5, 2.5, 3.5], hi=[2.0, 3.0, 4.0, 5.0, 2.5, 3.5, 4.5, 5.5],
             s=repeat(series; inner=4))
    rvl = to_vegalite(data(rib) * mapping(:dose, :q50; color=:s) * lineribbon(bands=[:lo => :hi]) *
        config(scales=ink_scale))
    alt = rvl["_aov"]["ribbonView"]["alt"]
    @test record(rvl) == recorded && record(alt) == recorded
    @test occursin("[\"#333\",\"#e03131\"]", JSON.json(alt))

    # The continuous colour keys take one literal colour: `:ink` there is refused, not
    # written as the colour name "ink".
    num = data((; x=[1.0, 2.0], y=[1.0, 2.0], v=[0.0, 1.0])) * mapping(:x, :y; color=:v) * visual(Scatter)
    for key in (:lowclip, :highclip, :nan_color)
        sc = scales(Color=(; colormap=:viridis, colorrange=(0.0, 1.0), NamedTuple{(key,)}((:ink,))...))
        @test_throws ArgumentError to_vegalite(num * config(scales=sc))
    end
end

@testitem "a palette entry :ink takes the Makie text colour on the static path" setup=[AoVPaletteInkFixtures] tags=[:theme, :regression, :static] begin
    import Makie
    pal(sc) = AlgebraOfVega._static_ink_palette(sc).dict[:Color][:palette]
    @test pal(ink_scale) == Any[Makie.to_value(Makie.theme(:textcolor; default=:black)), "#e03131"]
    Makie.with_theme(Makie.theme_black()) do
        @test pal(ink_scale)[1] == :white
    end
    # Other scales and palettes pass through untouched.
    other = scales(Color=(; palette=["red", "blue"]), X=(; scale=log10))
    @test AlgebraOfVega._static_ink_palette(other) === other
    @test isnothing(AlgebraOfVega._static_ink_palette(nothing))
    kept = AlgebraOfVega._static_ink_palette(scales(Color=(; categories=series, palette=[:ink, "red"]), X=(; scale=log10)))
    @test kept.dict[:X][:scale] === log10 && kept.dict[:Color][:categories] == series
end

@testitem "vsave draws a palette's ink in dark grey" setup=[AoVPaletteInkFixtures] tags=[:theme, :regression, :static] begin
    tool = something(get(ENV, "AOV_VL_CONVERT", nothing), Sys.which("vl-convert"), "")
    if isempty(tool)
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            path = vsave(lines(ink_scale) * config(width=200, height=100), joinpath(dir, "ink.svg"))
            svg = read(path, String)
            @test occursin("stroke=\"#333\"", svg) && occursin("stroke=\"#e03131\"", svg)
            @test !occursin("\"ink\"", svg)
        end
    end
end

@testitem "a palette's ink follows the page in the browser" setup=[AoVBrowserServer, AoVPaletteInkFixtures] tags=[:theme, :browser, :regression, :auto_remap] begin
    using HTMXObjects, JSON
    using HTMX: h
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)

    tall(x) = x * config(height=120)
    remap = (; dims=["s" => "Series", "g" => "G"], pinned=:row)
    doses = [5.0, 10.0, 20.0, 40.0]
    rib = (; dose=repeat(doses, 2), q50=[1.0, 2.0, 3.0, 4.0, 1.5, 2.5, 3.5, 4.5],
             lo=[0.0, 1.0, 2.0, 3.0, 0.5, 1.5, 2.5, 3.5], hi=[2.0, 3.0, 4.0, 5.0, 2.5, 3.5, 4.5, 5.5],
             s=repeat(series; inner=4))
    ribbon = data(rib) * mapping(:dose, :q50; color=:s) * lineribbon(bands=[:lo => :hi]; intervals=false) *
        config(scales=ink_scale, height=120)
    page = [vdraw(tall(lines(ink_scale)); id="ink-lines"),
        vdraw(tall(lines(scales(Color=(; categories=series, palette=["#333", "#e03131"])))); id="ink-literal"),
        vdraw(tall(lines(ink_scale) * config(config=Dict("style" => Dict("aov-ink" => Dict("color" => "#123456"))))); id="ink-pinned"),
        vdraw(tall(data(rows) * mapping(:x, :y; color=:s => "") * (visual(Lines) + visual(Scatter)) *
            config(scales=ink_scale)); id="ink-layered"),
        with_plot_caption(tall(lines(ink_scale)), "Series"; plot_id="ink-picker", auto_remap=remap),
        vdraw(ribbon; id="ink-ribbon")]
    style = "<style>body{color:rgb(30,40,50);background:rgb(250,250,250)}" *
        "html[data-theme=dark] body{color:rgb(200,210,220);background:rgb(20,24,31)}</style>"

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-palette-ink-") do dir
            driver = read(joinpath(@__DIR__, "palette_ink.js"), String)
            body = "<body>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>"
            for (source, runtime) in ((:inline, :inline), (:vendor, :linked))
                head = join(html(n) for n in vega_head(; source, runtime, base="/vendor"))
                write(joinpath(dir, "$source.html"), "<!doctype html><meta charset='utf-8'>" * style * head * body)
            end
            function run_page(url, source)
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile-$source")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $url`,
                    stderr=joinpath(dir, "chrome-$source.log")), String)
                result = match(r"<pre id=\"aov-palette-ink-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                isnothing(result) && return
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "palette ink browser checks" source checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
            run_page("file://" * joinpath(dir, "inline.html"), :inline)
            with_page_server(dir) do root
                run_page(root * "/vendor.html", :vendor)
            end
        end
    end
end
