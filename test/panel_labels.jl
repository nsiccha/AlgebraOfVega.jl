using TestItemRunner

# Per-panel axis titles, `config(facet=(; ylabels=:col, xlabels=:col))` (snag
# `facet-panels-can-13c4e53c`, design decision
# `AlgebraOfVega:snag.facet-panels-can-13c4e53c/decisions/2026-11-19T13-20-11-057-08wsvrj`).
# Before AoV 0.2.67 every panel of a facet showed the mapping's one y label, so
# Bruno web-sim's dose views titled each panel "Median, 50 % and 95 % intervals"
# and the tooltip's estimate row read the same: a facet panel had no axis title of
# its own.
@testsnippet AoVPanelLabelFixtures begin
    using AlgebraOfVega, JSON, Tables
    import Makie

    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    # The axis title of every `ch` encoding that has one written.
    axis_titles(vl, ch="y") = [u["encoding"][ch]["axis"]["title"] for u in units(vl)
        if haskey(get(u, "encoding", Dict()), ch) && get(u["encoding"][ch], "axis", nothing) isa Dict &&
           haskey(u["encoding"][ch]["axis"], "title")]
    title_exprs(vl, ch="y") = unique([t["expr"] for t in axis_titles(vl, ch) if t isa Dict])
    rows(vl) = AlgebraOfVega._inline_row_sets!(Any[], vl)

    # Bruno web-sim's dose figure (`dose_figure`, web-sim/src/views.jl): one panel
    # per output and quantity over a log dose axis, its median and intervals
    # (`bands=`), each population percentile as a dashed line, the Time course's
    # dose as a dashed rule and the fit's doses as a bar along the top.
    PANELS = ["Plasma ARV-102 — Cmax", "PBMC LRRK2 — Maximal decrease"]
    QUANTITY = Dict(PANELS[1] => "Cmax (ng/mL)", PANELS[2] => "Maximal decrease from baseline (%)")
    DOSES = [1.0, 3.0, 10.0, 30.0, 100.0]
    median_of(p, d) = p == PANELS[1] ? 10 * d^0.8 : 80 * d / (d + 10)
    bands = let p = repeat(PANELS, inner=length(DOSES)), d = repeat(DOSES, length(PANELS))
        m = median_of.(p, d)
        (; panel=p, quantity=[QUANTITY[x] for x in p], dose=d, q50=m,
           q2_5=0.6 .* m, q97_5=1.5 .* m, q25=0.85 .* m, q75=1.15 .* m)
    end
    # The population lines carry no quantity column: their rows get it.
    lines = let p = repeat(PANELS, inner=2 * length(DOSES)), d = repeat(DOSES, 2 * length(PANELS))
        l = repeat(repeat(["5th", "95th"], inner=length(DOSES)), length(PANELS))
        (; panel=p, dose=d, line=l, q50=median_of.(p, d) .* ifelse.(l .== "5th", 0.7, 1.3))
    end
    marks = (; panel=PANELS, dose=fill(30.0, 2))
    span = (; panel=PANELS, from=fill(3.0, 2), to=fill(30.0, 2))
    facet(; label="") = (; layout=:panel => sorter(PANELS) => label)
    dose_figure(labels; extra=config()) = (
        data(bands) * mapping(:dose => "Dose (mg)", :q50 => "Median"; facet()...) *
            lineribbon(bands=[:q2_5 => :q97_5, :q25 => :q75], probs=[0.95, 0.5]) * visual(; color=:ink) +
        data(lines) * mapping(:dose => "Dose (mg)", :q50 => "Median"; group=:line, facet()...) *
            visual(Lines; linestyle=:dash, linewidth=1, color=:ink) +
        data(marks) * mapping(:dose => "Dose (mg)"; facet()...) * visual(VLines; linestyle=:dash, color=:ink) +
        data(span) * mapping(:from => "Dose (mg)", :to => "Dose (mg)"; facet()...) *
            visual(VSpan; color=:ink, alpha=0.45, ymin=0.975, ymax=1.0)) *
        config(scales=scales(X=(; scale=log10, nice=false)), facet=(; linkyaxes=:none, ylabels=labels)) * extra

    # Raw draws: a summary computed in Julia keeps only its key columns.
    draws = let n = 40, p = repeat(PANELS, inner=length(DOSES) * n), d = repeat(repeat(DOSES, inner=n), length(PANELS))
        (; panel=p, quantity=[QUANTITY[x] for x in p], dose=d, draw=repeat(1:n, length(PANELS) * length(DOSES)),
           value=median_of.(p, d) .* (0.8 .+ 0.4 .* (repeat(1:n, length(PANELS) * length(DOSES)) ./ n)))
    end

    # The y axis titles a rendered SVG states (Vega's axis aria-label), and how
    # often a text is drawn.
    svg_y_titles(svg) = sort!([m[1] for m in eachmatch(r"aria-label=\"Y-axis titled '([^']*)'", svg)])
    svg_x_titles(svg) = sort!([m[1] for m in eachmatch(r"aria-label=\"X-axis titled '([^']*)'", svg)])
    drawn(svg, text) = count(m -> m[1] == text, eachmatch(r"<text[^>]*>([^<]*)</text>", svg))
    have_vl_convert() = !isnothing(get(ENV, "AOV_VL_CONVERT", nothing)) || !isnothing(Sys.which("vl-convert"))
end

@testitem "Each panel's y axis takes its facet value; the repeated header is left out" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(dose_figure(:panel))
    exprs = title_exprs(vl)
    # One expression on every layer with a y axis: the panel's own value, else the layers' title.
    @test exprs == ["isValid(parent[\"panel\"]) && parent[\"panel\"] !== '' ? '' + parent[\"panel\"] : \"Median\""]
    @test vl["resolve"]["axis"]["y"] == "independent"
    @test vl["resolve"]["scale"]["y"] == "independent"
    # The wrap facet's labels are its cells' titles: emptied, taking no room.
    @test vl["facet"]["header"] == Dict("labelExpr" => "''", "labelFontSize" => 0, "labelPadding" => 0, "title" => nothing)
    meta = vl["_aov"]["panelLabels"]["y"]
    @test meta["field"] == "panel" && meta["facet"] == ["panel"] && meta["titles"] == ["Median"]
    @test "q50" in meta["fields"] && "q2_5" in meta["fields"]
    # A single-view facet (encoding.facet) takes it the same way.
    one = to_vegalite(data(bands) * mapping(:dose, :q50 => "Median"; facet()...) * visual(Scatter) *
        config(facet=(; ylabels=:panel)))
    @test title_exprs(one) == ["isValid(parent[\"panel\"]) && parent[\"panel\"] !== '' ? '' + parent[\"panel\"] : \"Median\""]
    @test one["encoding"]["facet"]["header"]["labelExpr"] == "''"
    @test one["resolve"]["axis"]["y"] == "independent"
    # A row/column grid hides that channel's labels.
    grid = to_vegalite(data(bands) * mapping(:dose, :q50 => "Median"; row=:panel) * visual(Scatter) *
        config(facet=(; linkyaxes=:none, ylabels=:panel)))
    @test grid["encoding"]["row"]["header"] == Dict("labels" => false, "title" => nothing)
end

@testitem "Another column titles the axes and the header keeps the facet value" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(dose_figure(:quantity))
    pick = "extent(pluck(data(\"facet\"), \"quantity\"))[0]"
    @test title_exprs(vl) == ["isValid($pick) && $pick !== '' ? '' + $pick : \"Median\""]
    @test !haskey(vl["facet"], "header") || vl["facet"]["header"] != Dict("labelExpr" => "''", "labelFontSize" => 0, "labelPadding" => 0, "title" => nothing)
    # The population lines' and the reference rows' panels state their quantity too.
    filled = [r for set in rows(vl) for r in set if r isa Dict && haskey(r, "panel")]
    @test !isempty(filled) && all(r -> get(r, "quantity", nothing) == QUANTITY[r["panel"]], filled)
    @test vl["_aov"]["panelLabels"]["y"]["field"] == "quantity"

    # A summary computed from raw draws keeps only its key columns: its rows get the panel's quantity.
    raw = to_vegalite(data(draws) * mapping(:dose => "Dose (mg)", :value => "Median"; facet()...) *
        lineribbon() * config(facet=(; linkyaxes=:none, ylabels=:quantity)))
    summary = [r for set in rows(raw) for r in set if r isa Dict && haskey(r, "panel")]
    @test !isempty(summary) && all(r -> get(r, "quantity", nothing) == QUANTITY[r["panel"]], summary)
end

@testitem "Both drawings of the Ribbons | Intervals switch carry the panel titles" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    vl = to_vegalite(dose_figure(:quantity))
    rv = vl["_aov"]["ribbonView"]
    @test rv["view"] == "ribbons"
    alt = rv["alt"]
    @test alt["_aov"]["panelLabels"]["y"]["field"] == "quantity"
    @test length(title_exprs(alt)) == 1 && occursin("pluck(data(\"facet\"), \"quantity\")", only(title_exprs(alt)))
    @test alt["resolve"]["axis"]["y"] == "independent"
    @test ribbon_view(dose_figure(:quantity)).offered
end

@testitem "Per-column Y scales title each child's panels from its own rows" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    fig = data(bands) * mapping(:dose, :q50 => "Median"; col=:panel) * visual(Scatter) *
        config(facet=(; ylabels=:quantity), scales=scales(Y=(; scale=Dict(PANELS[2] => log10))))
    vl = to_vegalite(fig)
    @test haskey(vl, "hconcat")
    for (k, child) in enumerate(vl["hconcat"])
        @test only(title_exprs(child)) == "isValid(extent(pluck(data(\"concat_$(k - 1)_facet\"), \"quantity\"))[0]) && " *
            "extent(pluck(data(\"concat_$(k - 1)_facet\"), \"quantity\"))[0] !== '' ? '' + " *
            "extent(pluck(data(\"concat_$(k - 1)_facet\"), \"quantity\"))[0] : \"Median\""
    end
    # The positional `scales(...)` form lowers the same.
    @test to_vegalite(data(bands) * mapping(:dose, :q50 => "Median"; col=:panel) * visual(Scatter) *
        config(facet=(; ylabels=:quantity)), scales(Y=(; scale=Dict(PANELS[2] => log10))))["hconcat"][2] |> title_exprs ==
        title_exprs(vl["hconcat"][2])
end

@testitem "x labels, unfaceted figures and authored titles" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    xs = to_vegalite(data(bands) * mapping(:q50 => "Median", :dose => "Dose (mg)"; facet()...) * visual(Scatter) *
        config(facet=(; linkxaxes=:none, xlabels=:quantity)))
    @test length(title_exprs(xs, "x")) == 1 && isempty(title_exprs(xs, "y"))
    @test xs["resolve"]["axis"]["x"] == "independent"
    @test xs["_aov"]["panelLabels"]["x"]["field"] == "quantity"
    # An unfaceted figure has one panel: the setting does nothing there, as `linkyaxes` does.
    flat = data(bands) * mapping(:dose, :q50 => "Median") * visual(Scatter)
    @test to_vegalite(flat * config(facet=(; ylabels=:quantity))) == to_vegalite(flat)
    # An authored axis title is kept.
    own = to_vegalite(data(bands) * mapping(:dose, :q50; facet()...) * visual(Scatter) *
        config(facet=(; ylabels=:quantity), encoding=(; y=(; axis=(; title="Mine")))))
    @test unique(axis_titles(own)) == ["Mine"] && !haskey(get(own, "_aov", Dict()), "panelLabels")
end

@testitem "A label column that cannot title a panel is refused, naming it" setup=[AoVPanelLabelFixtures] tags=[:translation, :regression] begin
    mixed = merge(bands, (; quantity=[i == 2 ? "Other" : q for (i, q) in enumerate(bands.quantity)]))
    err = try
        to_vegalite(data(mixed) * mapping(:dose, :q50; facet()...) * visual(Scatter) * config(facet=(; ylabels=:quantity)))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("panel = \"$(PANELS[1])\"", err.msg) && occursin("\"Other\"", err.msg) && occursin("one value per panel", err.msg)
    @test_throws "names no column of the figure's tables" to_vegalite(data(bands) * mapping(:dose, :q50; facet()...) *
        visual(Scatter) * config(facet=(; ylabels=:unit)))
    @test_throws "as a Symbol or String" to_vegalite(data(bands) * mapping(:dose, :q50; facet()...) *
        visual(Scatter) * config(facet=(; ylabels=1)))
end

@testitem "vsave draws each panel's own axis title" setup=[AoVPanelLabelFixtures] tags=[:static, :regression] begin
    if !have_vl_convert()
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            # The facet value: each axis states its panel, and the header does not repeat it.
            svg = read(vsave(dose_figure(:panel), joinpath(dir, "panel.svg")), String)
            @test svg_y_titles(svg) == sort(PANELS)
            @test all(p -> drawn(svg, p) == 1, PANELS)
            # Another column: the header names the output, the axis the quantity, in
            # each panel's own rows (`data('facet')`), whatever layer a row came from.
            svg = read(vsave(dose_figure(:quantity), joinpath(dir, "quantity.svg")), String)
            @test svg_y_titles(svg) == sort(collect(values(QUANTITY)))
            @test all(p -> drawn(svg, p) == 1, PANELS)
            @test drawn(svg, "Median") == 0
            # Each per-column-Y child reads its own rows.
            fig = data(bands) * mapping(:dose, :q50 => "Median"; col=:panel) * visual(Scatter) *
                config(facet=(; ylabels=:quantity), scales=scales(Y=(; scale=Dict(PANELS[2] => log10))))
            @test svg_y_titles(read(vsave(fig, joinpath(dir, "columns.svg")), String)) == sort(collect(values(QUANTITY)))
            # x labels.
            xs = data(bands) * mapping(:q50 => "Median", :dose => "Dose (mg)"; facet()...) * visual(Scatter) *
                config(facet=(; linkxaxes=:none, xlabels=:quantity))
            @test svg_x_titles(read(vsave(xs, joinpath(dir, "x.svg")), String)) == sort(collect(values(QUANTITY)))
        end
    end
end

@testitem "sdraw labels each Makie axis with its panel's title" setup=[AoVPanelLabelFixtures] tags=[:static, :regression] begin
    plain(labels) = (data(bands) * mapping(:dose => "Dose (mg)", :q50 => "Median"; layout=:panel) * visual(Scatter) +
        data(lines) * mapping(:dose => "Dose (mg)", :q50 => "Median"; group=:line, layout=:panel) * visual(Lines)) *
        config(facet=(; linkyaxes=:none, ylabels=labels))
    for (labels, expected, header) in ((:quantity, QUANTITY, true), (:panel, Dict(p => p for p in PANELS), false))
        fig = Makie.Figure()
        grid = sdraw!(fig[1, 1], plain(labels))
        drawn_axes = [ae.axis for ae in grid if !isempty(ae.entries)]
        @test sort([string(ax.ylabel[]) for ax in drawn_axes]) == sort(collect(values(expected)))
        @test all(ax -> ax.ylabelvisible[], drawn_axes)
        texts = [string(c.text[]) for c in fig.content if c isa Makie.Label]
        @test !("Median" in texts)                         # no spanned label over the grid
        @test all(p -> (p in texts) == header, PANELS)     # facet labels only where the axes do not repeat them
    end
end

@testitem "The tooltip, the readout and both drawings name each panel's title in the browser" setup=[AoVPanelLabelFixtures] tags=[:regression, :browser] begin
    using HTMX
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-panel-labels-") do dir
            obs = (; panel=PANELS, quantity=[QUANTITY[p] for p in PANELS], dose=[10.0, 10.0], obs=[60.0, 40.0])
            tip = (data(bands) * mapping(:dose => "Dose (mg)", :q50 => "Median"; facet()...) *
                    lineribbon(bands=[:q2_5 => :q97_5, :q25 => :q75], probs=[0.95, 0.5], intervals=true) +
                data(obs) * mapping(:dose => "Dose (mg)", :obs => "Observed"; facet()...) * visual(Scatter; color=:ink)) *
                config(facet=(; linkyaxes=:none, ylabels=:quantity), readout=false, width=260, height=180)
            figures = Dict(
                "pl-readout" => dose_figure(:quantity; extra=config(width=260, height=180)),
                "pl-tip" => tip)
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "panel_labels.js"), String)
            plots = join(html(vdraw(figures[id]; id)) for id in sort!(collect(keys(figures))))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head * "<body>" * plots *
                "<script>window.AOV_PANELS = " * JSON.json(QUANTITY) * ";</script><script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1000
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-panel-labels-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 14
                @test isempty(report["failures"])
                @info "panel label browser checks" checks=report["checks"] samples=JSON.json(get(report, "samples", nothing))
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
