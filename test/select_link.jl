# A click on a map item chooses which key's rows other charts draw, in the
# browser with no request (snag `click-a-map-key-a85f71a9`, design decision
# `0n1b5vy`): the map's `config(link=(; group, key, on=:click))` selects, a
# chart's `config(select=(; field, group, initial))` follows, and a
# `by_url(rows, "…/{field}.json")` address serves each key's rows. Before it a
# static page needed one fragment per key, or page script calling the
# runtime's undocumented `AoV.updateData`.

@testsnippet AoVSelectFixtures begin
    using AlgebraOfVega, JSON, Tables

    cellbox(x0) = Dict{String,Any}("type" => "Polygon", "coordinates" =>
        [[[x0, 54.0], [x0, 55.0], [x0 + 1, 55.0], [x0 + 1, 54.0], [x0, 54.0]]])
    keys3 = ["A", "B", "C"]
    geo = Dict{String,Any}("type" => "FeatureCollection", "features" => [
        Dict{String,Any}("type" => "Feature", "properties" => Dict{String,Any}("cell" => k),
            "geometry" => cellbox(9.0 + i)) for (i, k) in enumerate(keys3)])
    cells = (; cell=keys3, v=[1.0, 2.0, 3.0])
    base = Dict("A" => 10.0, "B" => 40.0, "C" => 70.0)
    curves = let cell = repeat(keys3, inner=12), month = repeat(1:12, 3)
        share = [base[c] + m for (c, m) in zip(cell, month)]
        (; cell, month, share, low=share .- 5, high=share .+ 5, observed=share .+ 1, checklists=fill(20, 36))
    end
    rows_of(k) = (; (n => v[curves.cell .== k] for (n, v) in pairs(curves))...)
    sized(h) = config(width=300, height=h)
    cell_map = data(cells) * mapping(:cell; color=:v, strokecolor=:v) * geoshape(geo; key=:cell) *
        visual(; strokeWidth=0.6) * config(link=(; group="cells", key=:cell, on=:click)) * sized(200)
    follow(initial) = config(select=(; field=:cell, group="cells", initial))
    # The reporter's month chart: a median line with its band, and the observed share as dots.
    month_chart = (data(curves) * mapping(:month, :share) * lineribbon(bands=[:low => :high]) +
        data(curves) * mapping(:month, :observed) * visual(Scatter)) * follow("A") * sized(150)
    # The same, with each key's rows at its own address, and nothing selected at first.
    keyed_chart = data(by_url(curves, "cells/{cell}.json")) *
        (mapping(:month, :low, :high) * visual(Band; alpha=0.3) + mapping(:month, :share) * visual(Lines) +
         mapping(:month, :observed) * visual(Scatter)) *
        config(select=(; field=:cell, group="cells")) * sized(150)
    units(vl) = (out = Any[]; AlgebraOfVega._each_frame_unit(u -> push!(out, u), vl); out)
    select_param(vl) = only(p for p in vl["params"] if p["name"] == "aov_select")
end

@testitem "select: config(link=(; on=:click)) and config(select=(; field, group, initial)) lower to metadata, a parameter and a filter" setup=[AoVSelectFixtures] tags=[:select, :link] begin
    vl = to_vegalite(cell_map)
    @test vl["_aov"]["link"] == Dict("group" => "cells", "key" => "cell", "on" => "click")
    @test to_vegalite(cell_map * config(link=(; group="cells", key=:cell, on=:click, address=false)))["_aov"]["link"]["address"] == false
    # A hover link is unchanged.
    @test to_vegalite(cell_map * config(link=(; group="cells", key=:cell)))["_aov"]["link"] == Dict("group" => "cells", "key" => "cell")
    @test_throws ArgumentError config(link=(; group="cells", key=:cell, on=:press))
    @test_throws ArgumentError config(link=(; group="cells", key=:cell, address=false))

    vl = to_vegalite(month_chart)
    @test select_param(vl)["value"] == ["A"]
    @test vl["_aov"]["select"] == Dict("field" => "cell", "group" => "cells", "initial" => ["A"], "param" => "aov_select")
    us = units(vl)
    @test length(us) >= 3   # band, line, dots
    @test all(u -> first(u["transform"])["filter"] ==
        "!isValid(datum[\"cell\"]) || indexof(aov_select, toString(datum[\"cell\"])) >= 0", us)
    # The selection parameter does not switch AoV's own interactivity off.
    @test any(p -> p["name"] == "aov_select", vl["params"])
    @test any(u -> any(AlgebraOfVega._is_auto_zoom, something(get(u, "params", nothing), Any[])), us)
    # Integer keys and several initial keys, as text.
    @test AlgebraOfVega._select_option((; field=:id, group="g", initial=[3, 4])).initial == ["3", "4"]
    @test AlgebraOfVega._select_option((; field=:id, group="g")).initial == String[]
    # `select=:field` keeps its dropdown.
    dd = to_vegalite(data(curves) * mapping(:month, :share) * visual(Lines) * config(select=:cell))
    @test any(p -> get(p, "bind", nothing) isa AbstractDict, dd["params"])
    @test !haskey(get(dd, "_aov", Dict()), "select")
end

@testitem "select: figures whose rows cannot be selected by key are refused" setup=[AoVSelectFixtures] tags=[:select] begin
    line = data(curves) * mapping(:month, :share) * visual(Lines)
    @test_throws ArgumentError to_vegalite(line * config(select=(; field=:nope, group="cells")))
    @test_throws ArgumentError config(select=(; field=:cell))
    @test_throws ArgumentError config(select=(; field=:cell, group="cells", colour=1))
    @test_throws ArgumentError config(select=(; field=:cell, group="cells", initial=1.5))
    # A summary AoV computes from raw draws has no key in its rows.
    draws = (; cell=repeat(["A", "B"], inner=40), month=repeat(1:4, 20), y=randn(80))
    err = try
        to_vegalite(data(draws) * mapping(:month, :y) * lineribbon() * config(select=(; field=:cell, group="cells")))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("bands=", sprint(showerror, err))
    # A float key.
    @test_throws ArgumentError to_vegalite(data((; k=[1.5, 2.5], y=[1, 2])) * mapping(:k, :y) * visual(Scatter) *
        config(select=(; field=:k, group="g")))
    # Two ways of choosing rows.
    @test_throws ArgumentError to_vegalite(line * config(select=(; field=:cell, group="cells"), frame=:month))
    # A stack panel and a cell column follow no selection.
    @test_throws ArgumentError to_vegalite(vconcat(line * follow("A"), line))
    @test_throws ArgumentError AlgebraOfVega._cell_column(data(curves) * mapping(:month, :share; layout=:cell) *
        visual(Lines) * follow("A"))
end

@testitem "select: a by_url address with {field} carries only the initial keys' rows" setup=[AoVSelectFixtures] tags=[:select, :by_url] begin
    vl = to_vegalite(keyed_chart * follow("B"))
    keyed = vl["_aov"]["select"]["keyed"]
    @test keyed == [Dict("dataset" => "aov_keyed_1", "url" => "cells/{cell}.json")]
    datas = Any[]
    walk(x) = x isa AbstractDict ? (haskey(x, "name") && haskey(x, "values") && push!(datas, x); foreach(walk, values(x))) :
        x isa AbstractVector ? foreach(walk, x) : nothing
    walk(vl)
    @test length(datas) == 1 && datas[1]["name"] == "aov_keyed_1"
    @test length(datas[1]["values"]) == 12 && all(r -> r["cell"] == "B", datas[1]["values"])
    @test !occursin("{cell}.json\"", JSON.json(filter(p -> first(p) != "_aov", vl)))
    # Nothing selected at first: an empty dataset.
    empty!(datas)
    walk(to_vegalite(keyed_chart))
    @test length(datas) == 1 && datas[1]["name"] == "aov_keyed_1" && isempty(datas[1]["values"])
    # A file has every row, which the parameter filters.
    inline = AlgebraOfVega._with_rows_inline(() -> to_vegalite(keyed_chart * follow("B"); interactive=false))
    @test !haskey(inline["_aov"]["select"], "keyed")
    @test occursin("\"C\"", JSON.json(inline))
    # The address names a column but the figure follows no selection on it.
    @test_throws ArgumentError to_vegalite(data(by_url(curves, "cells/{cell}.json")) * mapping(:month, :share) * visual(Lines))
    @test_throws ArgumentError to_vegalite(data(by_url(curves, "cells/{cell}.json")) * mapping(:month, :share) * visual(Lines) *
        config(select=(; field=:month, group="g")))
    # A brace that names no column is left alone.
    @test haskey(to_vegalite(data(by_url(curves, "cells/{v}.json")) * mapping(:month, :share) * visual(Lines))["data"], "url")
    @test plot_texts(:de).select_hint == "Ein Element anklicken, um es hier zu zeigen"
end

@testitem "select in the browser: a map click picks the rows two charts draw, by click, Shift-click, long press, script and address" setup=[AoVSelectFixtures, AoVBrowserServer] tags=[:select, :link, :by_url, :browser, :geoshape] begin
    using HTMXObjects
    html(x) = sprint(show, MIME"text/html"(), x)
    page = [vdraw(cell_map; id="sl-map"), vdraw(month_chart; id="sl-month"), vdraw(keyed_chart; id="sl-keyed")]
    late = to_vegalite(month_chart)
    fixture = (; base, late)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-select-") do dir
            mkpath(joinpath(dir, "cells"))
            for k in keys3
                write(joinpath(dir, "cells", "$k.json"), rows_json(rows_of(k)))
            end
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "select_link.js"), String)
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'><link rel='icon' href='data:,'>" *
                head * "<body>" * join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * replace(JSON.json(fixture), "</" => "<\\/") * ";</script>" *
                "<script>" * driver * "</script></body>")
            with_page_server(dir) do root
                for (mode, query, expected) in (("clicks", "", 37), ("address", "?cells=C&mode=address", 6))
                    output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                        --user-data-dir=$(joinpath(dir, "profile-" * mode)) --window-size=1200,1400
                        --virtual-time-budget=30000 --dump-dom $(root * "/page.html" * query)`,
                        stderr=joinpath(dir, "chrome-$mode.log")), String)
                    result = match(r"<pre id=\"aov-select-results\">([^<]*)</pre>", output)
                    @test !isnothing(result)
                    if !isnothing(result)
                        report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                            "&gt;" => ">", "&amp;" => "&"))
                        @test report["mode"] == mode
                        @test report["checks"] == expected
                        @test isempty(report["failures"])
                        @info "select browser checks" mode checks=report["checks"]
                        isempty(report["failures"]) || println(JSON.json(report["failures"]))
                    end
                end
            end
        end
    end
end
