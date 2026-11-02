# A layer's rows read by the browser from an address: `data(by_url(rows, url))`
# (snag `odl-s-framed-reg-a3e457ca`, design decision `0wiwrsc`). Before it, a
# table layer's rows were always written into the plot. ODL's static export
# repeated the nationwide station table (318 MB over 3,754 region fragments)
# although its fragments drew only 13 different tables.

@testsnippet AoVByURLFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON, Tables, Dates

    district(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    ags = ["01001", "01002", "01003"]
    geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("AGS" => a),
            "geometry" => district(9.0 + i)) for (i, a) in enumerate(ags)])
    regions = (; AGS=ags, v=[1.0, 2.0, 3.0])
    sites = (; name=["A", "B", "C", "D"], kenn=["k1", "k2", "k3", "k4"], AGS=["01001", "01002", "01002", "01003"],
        lon=[10.5, 11.2, 11.8, 12.6], lat=[54.5, 54.2, 54.9, 54.4], nsv=[80.0, 101.0, 95.5, 120.0])
    selected = "01002"
    in_selected = config(transform=[Dict("calculate" => "datum.AGS === '$selected'", "as" => "in_selected")])
    region_map = data(regions) * mapping(:AGS; color=:v) * geoshape(geo)
    station_map(src) = region_map + data(src) * mapping(:lon, :lat; color=:nsv) * visual(Scatter) * in_selected
end

@testitem "by_url: the layer names its address, the rest is the inline figure's" setup=[AoVByURLFixtures] tags=[:by_url, :geoshape] begin
    url = "/stationen?zeit=letzte"
    inline = to_vegalite(station_map(sites))
    addressed = to_vegalite(station_map(by_url(sites, url)))
    @test addressed["layer"][2]["data"] == Dict("url" => url, "format" => Dict("type" => "json"))
    # Only the data differs: marks, encodings, tooltips, the calculate, the projection.
    strip(spec) = (s = deepcopy(spec); delete!(s["layer"][2], "data"); s)
    @test strip(inline) == strip(addressed)
    @test haskey(inline["layer"][2]["data"], "values")

    # The address serves exactly the rows the inline figure carries.
    @test JSON.parse(rows_json(sites)) == JSON.parse(AlgebraOfVega._vl_json(inline["layer"][2]["data"]["values"]))
    @test rows_json(by_url(sites, url)) == rows_json(sites)
    nan_rows = (; x=[1.0, NaN], when=[Date(2024, 1, 1), Date(2024, 1, 2)])
    @test JSON.parse(rows_json(nan_rows)) == [Dict("when" => "2024-01-01", "x" => 1.0),
        Dict("when" => "2024-01-02", "x" => nothing)]

    # Julia keeps the rows: AoG reads them as any table.
    layer = data(by_url(sites, url))
    @test Tables.columntable(AlgebraOfVega.extract_data(layer)) == sites
    @test Tables.columnnames(AlgebraOfVega.extract_data(layer)) == propertynames(sites)
    # Encodings are typed from the rows: a numeric colour is quantitative.
    @test addressed["layer"][2]["encoding"]["color"]["type"] == "quantitative"

    # Layers drawing one `by_url` table share it at the top.
    shared = to_vegalite(data(by_url(sites, url)) * mapping(:lon, :nsv) * (visual(Scatter) + linear()))
    @test shared["data"] == Dict("url" => url, "format" => Dict("type" => "json"))
    @test all(l -> !haskey(l, "data"), shared["layer"])

    # A faceted figure whose layers all draw it partitions the address's rows.
    faceted = to_vegalite(data(by_url(sites, url)) * mapping(:lon, :lat; col=:AGS) *
        (visual(Scatter) + visual(Lines)))
    @test faceted["data"] == Dict("url" => url, "format" => Dict("type" => "json"))
    @test haskey(faceted, "facet")
    @test all(l -> !haskey(l, "data") && !occursin("__src", JSON.json(l)), faceted["spec"]["layer"])
    # One faceted layer reads it from its own data, as an encoding facet.
    single = to_vegalite(data(by_url(sites, url)) * mapping(:lon, :lat; col=:AGS) * visual(Scatter))
    @test single["data"]["url"] == url

    # Choropleth tables and Vega-Lite transform analyses read it too.
    choro = to_vegalite(data(by_url(regions, "/regionen")) * mapping(:AGS; color=:v) * geoshape(geo))
    @test choro["data"] == Dict("url" => "/regionen", "format" => Dict("type" => "json"))
    @test occursin("lookup", JSON.json(choro["transform"]))
    for analysis in (density(), histogram())
        @test to_vegalite(data(by_url(sites, url)) * mapping(:nsv) * analysis)["data"]["url"] == url
    end

    # The embedded node names the address and carries none of the rows.
    node = sprint(show, MIME"text/html"(), vdraw(station_map(by_url(sites, url)); id="by-url-node"))
    @test occursin(url, node)
    @test !occursin("\"k2\"", node)
    @test occursin("\"k2\"", sprint(show, MIME"text/html"(), vdraw(station_map(sites); id="inline-node")))

    # vsave's lowering writes the rows themselves; a plain lowering after it names the address again.
    lowered = AlgebraOfVega._with_rows_inline(() -> to_vegalite(station_map(by_url(sites, url))))
    @test lowered == inline
    @test to_vegalite(station_map(by_url(sites, url)))["layer"][2]["data"]["url"] == url

    # Misuse names the fix.
    @test_throws ArgumentError by_url(sites, "")
    @test_throws ArgumentError by_url(sites, :stations)
    @test_throws ArgumentError by_url(by_url(sites, url), "/other")
end

@testitem "by_url: figures whose rows AoV computes in Julia are refused" setup=[AoVByURLFixtures] tags=[:by_url] begin
    using HTMXObjects   # cell_charts' table cells
    url = "/d"
    draws = (; g=["a", "a", "b", "b"], value=[1.0, 2.0, 3.0, 4.0], x=[1.0, 2.0, 1.0, 2.0], draw=[1, 1, 2, 2])
    bands = (; x=[1.0, 2.0], m=[1.0, 2.0], lo=[0.0, 1.0], hi=[2.0, 3.0], g=["a", "b"])
    refused(spec) = try
        to_vegalite(spec); nothing
    catch e
        e isa ArgumentError ? e.msg : rethrow()
    end
    for (name, spec) in [
            "pointinterval()" => data(by_url(draws, url)) * mapping(:value, y=:g) * pointinterval(),
            "gradient_interval()" => data(by_url(draws, url)) * mapping(:value, y=:g) * gradient_interval(),
            "dotinterval()" => data(by_url(draws, url)) * mapping(:value, y=:g) * dotinterval(),
            "pointinterval(bands=…)" => data(by_url(bands, url)) * mapping(:m, y=:g) * pointinterval(bands=[:lo => :hi]),
            "lineribbon()" => data(by_url(draws, url)) * mapping(:x, :value; group=:draw) * lineribbon(),
            "ribbon(bands=…)" => data(by_url(bands, url)) * mapping(:x, :m) * ribbon(bands=[:lo => :hi]),
            "A faceted density()" => data(by_url(draws, url)) * mapping(:value; col=:g) * density(),
            "density() with `y=`" => data(by_url(draws, url)) * mapping(:value; y=:g) * density()]
        msg = refused(spec)
        @test !isnothing(msg) && startswith(msg, name)
        @test !isnothing(msg) && occursin("\"$url\"", msg) && occursin("without `by_url`", msg)
    end
    # Faceted beside another table: the facet merges rows in Julia.
    msg = refused(data(by_url(sites, url)) * mapping(:lon, :lat; col=:AGS) * visual(Scatter) +
        data(sites) * mapping(:lon, :lat; col=:AGS) * visual(Lines))
    @test !isnothing(msg) && occursin("faceted", msg) && occursin("\"$url\"", msg)
    msg = refused(data(by_url(sites, url)) * mapping(:lon, :lat; col=:AGS) * visual(Scatter) +
        data(by_url(sites, "/other")) * mapping(:lon, :lat; col=:AGS) * visual(Lines))
    @test !isnothing(msg) && occursin("\"/other\"", msg)

    # The picker rebuilds every layer's rows.
    remap = (; dims=["AGS" => "Kreis"])
    spec = data(by_url(sites, url)) * mapping(:lon, :lat; color=:AGS) * visual(Scatter)
    err = try
        to_vegalite(spec; auto_remap=remap); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("auto_remap", sprint(showerror, err))
    @test_throws ArgumentError auto_remap_node("by-url-picker", spec; dims=remap.dims)

    # cell_charts splits rows per key.
    classes = (; id=["s1", "s1", "s2"], klasse=["a", "b", "a"], n=[1, 2, 3])
    err = try
        cell_charts(data(by_url(classes, url)) * mapping(:klasse, :n; layout=:id) * visual(BarPlot)); nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("cell_charts", sprint(showerror, err))
end

@testitem "vsave: a by_url table's rows are written into the file" setup=[AoVByURLFixtures] tags=[:by_url, :vsave, :static] begin
    if isnothing(Sys.which("vl-convert")) && isempty(get(ENV, "AOV_VL_CONVERT", ""))
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            cd(dir) do
                # No server answers the address; the file still draws every station.
                vsave(station_map(by_url(sites, "http://127.0.0.1:9/never")), "addressed.svg")
                vsave(station_map(sites), "inline.svg")
                @test read("addressed.svg") == read("inline.svg")
                @test count("aria-roledescription=\"point\"", read("addressed.svg", String)) == length(sites.name)
            end
        end
    end
end

@testitem "by_url in the browser: fetched rows draw as inline ones, framed, and from a saved card's preload" setup=[AoVByURLFixtures, AoVBrowserServer] tags=[:by_url, :browser, :geoshape, :frame] begin
    using HTMXObjects
    html(x) = sprint(show, MIME"text/html"(), x)
    frame_sites = merge(map(c -> repeat(c, 2), sites), (; zeit=repeat(["t1", "t2"], inner=4)))
    frame_rows = (; (k => v[[1, 2, 7]] for (k, v) in pairs(frame_sites))...)   # t1: A, B; t2: C
    sized = config(width=300, height=120)
    page = [vdraw(station_map(sites) * sized; id="bu-inline"),
        vdraw(station_map(by_url(sites, "stationen.json")) * sized; id="bu-url"),
        vdraw(station_map(by_url(sites, "nowhere.json")) * sized; id="bu-preload"),
        vdraw((region_map + data(by_url(frame_rows, "frames.json")) * mapping(:lon, :lat) * visual(Scatter)) *
            sized * config(frame=:zeit); id="bu-frame")]
    fixture = (; names=sites.name, selected, url="stationen.json", rows_json=rows_json(sites),
        frames=[(; zeit="t1", names=["A", "B"]), (; zeit="t2", names=["C"])])

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-by-url-") do dir
            write(joinpath(dir, "stationen.json"), rows_json(sites))
            write(joinpath(dir, "frames.json"), rows_json(frame_rows))
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "by_url.js"), String)
            # What a saved "⬇ HTML" card carries: its data URLs' text, before the plots embed.
            preload = "<script>AoV._preload(" * replace(JSON.json(Dict("nowhere.json" => rows_json(sites))),
                "</" => "<\\/") * ");</script>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" *
                preload * join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * replace(JSON.json(fixture), "</" => "<\\/") * ";</script>" *
                "<script>" * driver * "</script></body>")
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                    --virtual-time-budget=20000 --dump-dom $(root * "/page.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-by-url-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] == 2 + 4 * length(sites.name) + 1 + 4 + 1 + 2
                    @test isempty(report["failures"])
                    @info "by_url browser checks" checks=report["checks"]
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
