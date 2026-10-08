using TestItemRunner

"""
Keyed partial replacement of a plot's rows, and ribbon groups that data
changes bring.

Snag `keyed-replace-da-dbb90827`: one plot holds several scenarios' posterior
bands, and the scenario being computed is refined in stages. `update_data`
replaces the whole dataset (every scenario re-sent at every stage) and
`append_data` cannot drop the provisional rows. `replace_data(id, table; key)`
removes the rows whose key values `table` carries and inserts `table`, in one
changeset, leaving the other groups' rows (and tuples) untouched.

A coloured `lineribbon`/`ribbon` draws each colour group as its own layers (z
order, `87465a0`), built from the groups present at the first render: rows of a
group sent later were kept but never drawn, and an empty first render had no
dataset at all (`Unrecognized data set: source_0`). The group layers are now
tagged `_lr_group` (an empty render emits `_lr_proto` template layers), and a
data change that brings a new group re-embeds once with that group's layers.
"""
@testitem "keyed replacement and removal keep other groups mounted" tags=[:incremental, :browser, :regression] begin
    using AlgebraOfVega, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]

    function rows(s; off=0.0, n=5, panels=nothing)
        ps = isnothing(panels) ? [nothing] : panels
        r = [(; x=Float64(i), y=off + i / 10, lower=off - 1, upper=off + 1, scenario=s, panel=p)
            for p in ps for i in 1:n]
        cols = isnothing(panels) ? (:x, :y, :lower, :upper, :scenario) : (:x, :y, :lower, :upper, :scenario, :panel)
        (; (c => [getproperty(q, c) for q in r] for c in cols)...)
    end
    cat(ts...) = (; (k => vcat((getproperty(t, k) for t in ts)...) for k in keys(ts[1]))...)
    typed_empty = (; x=Float64[], y=Float64[], lower=Float64[], upper=Float64[], scenario=String[])

    # Server side: the fragment, the key, and refusal of a key the table lacks.
    t = rows("B"; off=10)
    @test occursin(r"^AoV\.replaceData\('rk', \{\"n\":5,.*\}, \[\"scenario\"\], 'source_0'\);$"s,
        script(replace_data("rk", t; key=:scenario)))
    @test occursin("}, [\"scenario\",\"panel\"], 'source_0');",
        script(replace_data("rk", rows("B"; panels=["p1"]); key=[:scenario, "panel"])))
    @test occursin("'other');", script(replace_data("rk", t; key="scenario", name="other")))
    payload(f) = JSON.parse(replace(script(f), r"^AoV\.\w+\('rk', " => "",
        r"(, \[\"scenario\"\])?, 'source_0'\);$" => ""))
    @test payload(replace_data("rk", t; key=:scenario)) == payload(update_data("rk", t))
    # refused: a key that names no column of the table could never match a row
    @test_throws ArgumentError replace_data("rk", t; key=:panel)
    # refused: an empty key would select every row (that is update_data)
    @test_throws ArgumentError replace_data("rk", t; key=Symbol[])

    @test script(remove_data("rk", "B"; key=:scenario)) ==
        "AoV.removeData('rk', [\"B\"], [\"scenario\"], 'source_0');"
    @test script(remove_data("rk", ("B", "p1"); key=[:scenario, :panel])) ==
        "AoV.removeData('rk', [\"B\",\"p1\"], [\"scenario\",\"panel\"], 'source_0');"
    @test occursin("'other');", script(remove_data("rk", "B"; key=:scenario, name="other")))
    @test_throws ArgumentError remove_data("rk", "B"; key=Symbol[])
    @test_throws ArgumentError remove_data("rk", ("B",); key=:scenario)
    @test_throws ArgumentError remove_data("rk", "B"; key=[:scenario, :panel])
    @test_throws ArgumentError remove_data("rk", ("B",); key=[:scenario, :panel])

    # Lowering: group layers carry `_lr_group`; an empty coloured ribbon emits
    # its template layers instead of none.
    ribbon(tbl; kw...) = data(tbl) * mapping(:x, :y; color=:scenario, kw...) * lineribbon(bands=[:lower => :upper])
    vl = to_vegalite(ribbon(cat(rows("A"), rows("B"; off=3))))
    groups = [l for l in vl["layer"] if get(l, "_lr_layer", false)]
    @test [l["_lr_group"] for l in groups] == ["A", "A", "B", "B"]
    @test all(l -> l["transform"][end]["filter"] == "datum[\"scenario\"] === \"$(l["_lr_group"])\"", groups)
    ev = to_vegalite(ribbon(typed_empty))
    @test length(ev["layer"]) == 2 && all(l -> get(l, "_lr_proto", false), ev["layer"])
    @test all(l -> l["encoding"]["color"]["field"] == "scenario" && !haskey(l, "transform"), ev["layer"])
    @test !any(l -> haskey(l, "_lr_group") || haskey(l, "_lr_proto"),
        to_vegalite(data(rows("A")) * mapping(:x, :y) * lineribbon(bands=[:lower => :upper]))["layer"])

    band_lines(tbl) = data(tbl) * (mapping(:x, :lower, :upper; color=:scenario) * visual(Band) +
        mapping(:x, :y; color=:scenario) * visual(Lines)) * config(height=150)
    pinned = band_lines(cat(rows("A"), rows("B"; off=3))) *
        config(scales=scales(Color=(; categories=["A", "B"], palette=["#cc0000", "#0066cc"])))
    draws = (; v=randn(60), g=repeat(["a", "b", "c"], 20))
    updates = Dict(
        "plain_B" => script(replace_data("rk-plain", rows("B"; off=10); key=:scenario)),
        "plain_remove_B" => script(remove_data("rk-plain", "B"; key=:scenario)),
        "plain_missing_key" => script(remove_data("rk-plain", "B"; key=:unknown)),
        "ribbon_C1" => script(replace_data("rk-ribbon", rows("C"; off=6, panels=["p1", "p2"]); key=:scenario)),
        "ribbon_C2" => script(replace_data("rk-ribbon", rows("C"; off=7, panels=["p1", "p2"]); key=:scenario)),
        "ribbon_Cp1" => script(replace_data("rk-ribbon", rows("C"; off=8, panels=["p1"]); key=[:scenario, :panel])),
        "ribbon_remove_Cp1" => script(remove_data("rk-ribbon", ("C", "p1"); key=[:scenario, :panel])),
        "ribbon_remove_C" => script(remove_data("rk-ribbon", "C"; key=:scenario)),
        "pinned_remove_A" => script(remove_data("rk-pinned", "A"; key=:scenario)),
        "empty_A" => script(replace_data("rk-empty", rows("A"); key=:scenario)),
        "empty_B" => script(replace_data("rk-empty", rows("B"; off=3); key=:scenario)),
        "empty_A2" => script(replace_data("rk-empty", rows("A"; off=1); key=:scenario)),
        "empty_append_C" => script(append_data("rk-empty", rows("C"; off=6))),
        "interval_raw" => script(replace_data("rk-interval", draws; key=:g)),
        "layered_C" => script(replace_data("rk-layered", rows("C"; off=6); key=:scenario)))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-replace-data-") do dir
            page = [vdraw(band_lines(cat(rows("A"), rows("B"; off=3))); id="rk-plain"),
                vdraw(pinned; id="rk-pinned"),
                vdraw(ribbon(cat(rows("A"; panels=["p1", "p2"]), rows("B"; off=3, panels=["p1", "p2"]));
                    col=:panel) * config(height=150); id="rk-ribbon"),
                vdraw(ribbon(typed_empty) * config(height=150); id="rk-empty"),
                vdraw(data(draws) * mapping(:v; y=:g) * pointinterval() * config(height=150); id="rk-interval"),
                # A ribbon layered with other layers cannot grow groups: warned.
                vdraw((ribbon(cat(rows("A"), rows("B"; off=3))) + data((; x=[1.0], y=[0.0], scenario=["A"])) *
                    mapping(:x, :y; color=:scenario) * visual(Scatter)) * config(height=150); id="rk-layered"),
                vdraw(data(cat(rows("A"), rows("B"; off=3))) * mapping(:x, :y; color=:scenario) *
                    visual(Lines) * config(height=150); id="rk-queued"),
                # Sent before the plot above has embedded: queued until it is ready.
                replace_data("rk-queued", rows("B"; off=10); key=:scenario)]
            runtime = join(html(n) for n in vega_head(source=:inline))
            payload = replace(JSON.json((; updates)), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "replace_data.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "embed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" *
                join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1100
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-replace-data-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "replace_data browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
