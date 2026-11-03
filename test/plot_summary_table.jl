using TestItemRunner

# `plot_summary_table` returns a figure's automatic summary as tables, from the
# lowered Vega-Lite alone. Item "… matches the browser" is the LOCKSTEP guard: the
# Julia computation and the runtime's "Show summary" pane must read the same.
@testsnippet AoVSummaryTableFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON, Dates

    # JSON and back: what a consumer holds when it read the spec from a payload.
    roundtrip(vl) = JSON.parse(AlgebraOfVega._vl_json(vl))

    # Long-format draws: two parameters, 25 draws each. `a` runs 10..34 and `b` runs
    # 100..340, so no quantile below sits on a rounding tie: Julia versions differ
    # in a quantile's last bit, which would decide a tie.
    draws = (; value=vcat(collect(10.0:34.0), collect(100.0:10.0:340.0)),
        parameter=vcat(fill("a", 25), fill("b", 25)),
        chain=repeat(["c1", "c2", "c3"], 17)[1:50])
    # Per-x draws of a line, x out of order, 11 draws per (x, group), away from ties too.
    function predictions()
        x, y, draw, group = Float64[], Float64[], Int[], String[]
        for g in ("g2", "g1"), xv in (40.0, 10.0, 25.0, 1234.0), d in 1:11
            push!(x, xv); push!(y, xv + (d - 6) * 1.2 + (g == "g2" ? 100 : 0)); push!(draw, d); push!(group, g)
        end
        (; x, y, draw, group)
    end
    summary = (; m=[2.0, 5.0, 8.0], lo50=[1.5, 4.5, 7.5], hi50=[2.5, 5.5, 8.5], lo95=[1.0, 4.0, 7.0],
        hi95=[3.0, 6.0, 9.0], g=["c", "a", "b"], dose=[20, 5, 10])
    ribbon_rows = (; x=[3.0, 1.0, 2.0], m=[3.0, 1.0, 2.0], lo=[2.5, 0.5, 1.5], hi=[3.5, 1.5, 2.5])
    obs = (; x=[1.0, 2.0, 3.0], y=[1.1, 1.9, 3.2])

    interval(a) = data(draws) * mapping(:value; y=:parameter) * a
    cols(t) = String.(collect(keys(t.table)))

    # The figures both items walk: every form the summary covers, and the
    # figure shapes that move its rows (several sources, facets, pads).
    function summary_figures()
        preds = predictions()
        figures = Pair{String,Any}[
            "pointinterval" => interval(pointinterval()),
            "gradient" => interval(gradient_interval()),
            "dotinterval" => interval(dotinterval()),
            "coloured" => data(draws) * mapping(:value; y=:parameter, color=:chain) * pointinterval(),
            "two-probs" => interval(pointinterval(probs=[0.5, 0.8])),
            "lineribbon" => data(preds) * mapping(:x, :y; group=:draw, color=:group) * lineribbon(),
            "ribbon" => data(preds) * mapping(:x, :y; group=:draw, color=:group) * ribbon(),
            "interval-bands" => data(summary) * mapping(:m; y=:g) * pointinterval(bands=[:lo95 => :hi95, :lo50 => :hi50]),
            "lineribbon-bands" => data(ribbon_rows) * mapping(:x, :m) * lineribbon(bands=[:lo => :hi]),
            "ribbon-bands" => data(ribbon_rows) * mapping(:x, :m) * ribbon(bands=[:lo => :hi]),
            # A layer without a summary first: its rows are source_0.
            "obs-then-ribbon" => data(obs) * mapping(:x, :y) * visual(Scatter) +
                data(preds) * mapping(:x, :y; group=:draw) * lineribbon(),
            "ribbon-then-obs" => data(preds) * mapping(:x, :y; group=:draw) * lineribbon() +
                data(obs) * mapping(:x, :y) * visual(Scatter),
            "faceted" => data(draws) * mapping(:value; y=:parameter, col=:chain) * pointinterval(),
            # A sparse row × column grid with per-column Y: `__aov_pad` rows hold its cells.
            "sparse" => data((; x=[1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0],
                    y=[1.0, 3.0, 2.0, 4.0, 5.0, 7.0, 6.0, 8.0, 9.0, 11.0, 10.0, 12.0], draw=repeat(1:2, 6),
                    r=repeat(["r1", "r2", "r1"], inner=4), c=repeat(["c1", "c1", "c2"], inner=4))) *
                mapping(:x, :y; group=:draw, row=:r, col=:c) * lineribbon() *
                config(scales=scales(Y=(; scale=Dict("c1" => log10)))),
            # A faceted figure merges its layers' rows into one `__src` dataset.
            "merged" => data(draws) * mapping(:value; y=:parameter, col=:chain) * pointinterval() +
                data((; v=[20.0])) * mapping(:v) * visual(VLines),
            # One view per column, each with its own Y scale.
            "per-column-y" => data(preds) * mapping(:x, :y; group=:draw, col=:group) * lineribbon() *
                config(scales=scales(Y=(; scale=Dict("g1" => log10)))),
            # A ribbon that starts in its interval drawing.
            "ribbon-as-intervals" => data(preds) * mapping(:x, :y; group=:draw, color=:group) * lineribbon(intervals=true),
            # A date is a string on the wire.
            "temporal" => data((; t=repeat([DateTime(2026, 3, 1), DateTime(2026, 1, 1)]; inner=11), v=collect(1.0:22.0),
                    draw=repeat(1:11, 2))) * mapping(:t, :v; group=:draw) * lineribbon(),
        ]
        figures
    end
end

@testitem "plot_summary_table returns the summary's rows and labels" setup=[AoVSummaryTableFixtures] tags=[:summary, :tidybayes] begin
    # A raw-draws interval: one row per group, in reading order, with the value
    # column named after the mapped column.
    tables = plot_summary_table(to_vegalite(interval(pointinterval())))
    @test length(tables) == 1
    t = only(tables)
    @test isnothing(t.label)
    @test t.caption == "Median [95% credible interval]"
    @test cols(t) == ["parameter", "value"]
    @test t.table.parameter == ["a", "b"]
    @test t.table.value == ["22 [11, 33]", "220 [110, 330]"]

    # A figure's forms: the spec itself, its lowered dict and that dict after JSON.
    spec = interval(gradient_interval())
    @test plot_summary_table(spec) == plot_summary_table(to_vegalite(spec)) ==
          plot_summary_table(roundtrip(to_vegalite(spec)))
    # What a route's Markdown payload carries: the spec's Vega-Lite JSON show.
    payload = sprint(show, MIME"application/vnd.vegalite.v5+json"(), spec * config(width=300))
    @test only(plot_summary_table(JSON.parse(payload))).table.parameter == ["a", "b"]
    @test only(plot_summary_table(spec)).table.value == ["22 [11, 33]", "220 [110, 330]"]
    @test only(plot_summary_table(interval(dotinterval()))).table.parameter == ["a", "b"]
    @test only(plot_summary_table(interval(pointinterval()) * config(width=300))).table.parameter == ["a", "b"]

    # A raw-draws ribbon: sorted along its key columns, categorical first, in
    # number order rather than the summary's hash order. A key rounds as the
    # browser's pane rounds it.
    preds = predictions()
    t = only(plot_summary_table(data(preds) * mapping(:x, :y; group=:draw, color=:group) * lineribbon()))
    @test cols(t) == ["group", "x", "y"]
    @test t.table.group == repeat(["g1", "g2"]; inner=4)
    @test t.table.x == repeat([10.0, 25.0, 40.0, 1200.0], 2)
    @test t.table.y[1] == "10 [4.3, 16]"
    @test only(plot_summary_table(data(preds) * mapping(:x, :y; group=:draw, color=:group) * ribbon())).table.y[1] == "10 [4.3, 16]"

    # `bands=`: the point and band columns are the table's own, named by the spec.
    bands = data(summary) * mapping(:m; y=:g) * pointinterval(bands=[:lo95 => :hi95, :lo50 => :hi50])
    for vl in (to_vegalite(bands), roundtrip(to_vegalite(bands)))
        local t = only(plot_summary_table(vl))
        @test t.caption == "Median [lo95/hi95]"
        @test cols(t) == ["g", "dose", "m"]
        @test t.table.g == ["a", "b", "c"]
        @test t.table.dose == [5, 10, 20]
        @test eltype(t.table.dose) <: Integer
        @test t.table.m == ["5 [4, 6]", "8 [7, 9]", "2 [1, 3]"]
        @test only(plot_summary_table(vl; ci=:inner)).table.m[1] == "5 [4.5, 5.5]"
        @test only(plot_summary_table(vl; ci=:inner)).caption == "Median [lo50/hi50]"
    end
    for a in (lineribbon(bands=[:lo => :hi]), ribbon(bands=[:lo => :hi]))
        local t = only(plot_summary_table(data(ribbon_rows) * mapping(:x, :m) * a))
        @test cols(t) == ["x", "m"]
        @test t.table.x == [1.0, 2.0, 3.0]
        @test t.table.m == ["1 [0.5, 1.5]", "2 [1.5, 2.5]", "3 [2.5, 3.5]"]
    end

    # An empty band value (NaN, which is `null` on the wire) leaves its place empty.
    gap = data((; m=[2.0, NaN], lo=[1.0, 1.0], hi=[NaN, 3.0], g=["x", "y"])) * mapping(:m; y=:g) * pointinterval(bands=[:lo => :hi])
    for vl in (to_vegalite(gap), roundtrip(to_vegalite(gap)))
        @test only(plot_summary_table(vl)).table.m == ["2 [1, ]", " [1, 3]"]
    end

    # A key that is empty reads as missing and sorts last.
    keyed = data((; m=[1.0, 2.0, 3.0], lo=[0.0, 1.0, 2.0], hi=[2.0, 3.0, 4.0], k=[missing, 2.0, 1.0])) *
        mapping(:m; y=:k) * pointinterval(bands=[:lo => :hi])
    t = only(plot_summary_table(roundtrip(to_vegalite(keyed))))
    @test isequal(t.table.k, [1.0, 2.0, missing])

    # A date reads as it does on the wire, lowered or decoded.
    temporal = last(only(filter(f -> first(f) == "temporal", summary_figures())))
    @test plot_summary_table(temporal) == plot_summary_table(roundtrip(to_vegalite(temporal)))
    @test only(plot_summary_table(temporal)).table.t == ["2026-01-01T00:00:00", "2026-03-01T00:00:00"]

    # The options, as on a captioned plot.
    two = interval(pointinterval(probs=[0.5, 0.8]))
    @test only(plot_summary_table(two)).caption == "Median [80% credible interval]"
    @test only(plot_summary_table(two; ci=:inner)).caption == "Median [50% credible interval]"
    @test only(plot_summary_table(two; ci=0.6)).caption == "Median [50% credible interval]"
    @test only(plot_summary_table(two; sigfigs=3)).table.value[1] == "22 [12.4, 31.6]"
    @test only(plot_summary_table(two; texts=plot_texts(:de))).caption == "Median [80%-Kredibilitätsintervall]"
    @test_throws ArgumentError plot_summary_table(two; sigfigs=0)
    @test_throws ArgumentError plot_summary_table(two; ci=:widest)

    # The summary layer is found wherever it sits, and a plain layer is left out.
    for fig in (data(obs) * mapping(:x, :y) * visual(Scatter) + data(preds) * mapping(:x, :y; group=:draw) * lineribbon(),
                data(preds) * mapping(:x, :y; group=:draw) * lineribbon() + data(obs) * mapping(:x, :y) * visual(Scatter))
        local t = only(plot_summary_table(fig))
        @test cols(t) == ["x", "y"]
        @test t.table.x[1] == 10.0
    end

    # Pad rows of a sparse facet grid are not data.
    sparse = last(only(filter(f -> first(f) == "sparse", summary_figures())))
    vl = to_vegalite(sparse)
    @test any(r -> get(r, "__aov_pad", false) === true, vl["data"]["values"])
    t = only(plot_summary_table(vl))
    @test sort(unique(zip(t.table.r, t.table.c))) == [("r1", "c1"), ("r1", "c2"), ("r2", "c1")]
    @test length(t.table.c) == 6

    # A faceted figure's merged rows: its summary source, under its name.
    merged = last(only(filter(f -> first(f) == "merged", summary_figures())))
    t = only(plot_summary_table(merged))
    @test !isnothing(t.label)
    relabelled = only(plot_summary_table(merged; labels=Dict(t.label => "Posterior")))
    @test relabelled.label == "Posterior"

    # The table is a Tables.jl source.
    t = only(plot_summary_table(interval(pointinterval())))
    @test AlgebraOfVega.Tables.istable(t.table)
    @test AlgebraOfVega.Tables.columnnames(AlgebraOfVega.Tables.columns(t.table)) == (:parameter, :value)
end

"""
A figure without such a summary gives `nothing`, never an error.
"""
@testitem "plot_summary_table is nothing for a figure without a summary" setup=[AoVSummaryTableFixtures] tags=[:summary] begin
    scatter = data(obs) * mapping(:x, :y) * visual(Scatter)
    for fig in (scatter, scatter * config(width=200),
                data(obs) * mapping(:x, :y) * visual(Lines),
                data(obs) * mapping(:x) * AlgebraOfVega.AlgebraOfGraphics.density(),
                data(obs) * mapping(:x, :y) * AlgebraOfVega.AlgebraOfGraphics.linear(),
                # No rows at all.
                data((; m=Float64[], lo=Float64[], hi=Float64[], g=String[])) * mapping(:m; y=:g) * pointinterval(bands=[:lo => :hi]))
        @test isnothing(plot_summary_table(fig))
        @test isnothing(plot_summary_table(roundtrip(to_vegalite(fig))))
    end
    # A spec not lowered by `to_vegalite`, and one by an AoV without the record.
    @test isnothing(plot_summary_table(Dict{String,Any}()))
    @test isnothing(plot_summary_table(Dict{String,Any}("data" => Dict("values" => [Dict("__point__" => 1.0, "lo_0_95_" => 0.0, "hi_0_95_" => 2.0)]))))
    # A plain-layer figure stays byte-identical: it carries no record.
    @test !haskey(to_vegalite(scatter), "_aovSummary")
end

"""
Numbers read as in the browser, including a tie (`toPrecision` goes up, Julia's
`round` to even) and JS's two notations.
"""
@testitem "plot_summary_table formats numbers as JavaScript does" tags=[:summary] begin
    using AlgebraOfVega
    round2(x, p=2) = AlgebraOfVega._js_number_string(AlgebraOfVega._js_round(x, p))
    @test round2(1.25) == "1.3"
    @test round2(-1.25) == "-1.3"
    @test round2(0.125) == "0.13"
    @test round2(12.5) == "13"
    @test round2(2.5, 1) == "3"
    @test round2(1234) == "1200"
    @test round2(99.5) == "100"
    @test round2(0.0) == "0"
    @test round2(-0.0) == "0"
    @test round2(0.15) == "0.15"
    text = AlgebraOfVega._js_number_string
    @test text(1200.0) == "1200"
    @test text(0.000001) == "0.000001"
    @test text(1.0e-7) == "1e-7"
    @test text(1.5e-7) == "1.5e-7"
    @test text(1.0e20) == "100000000000000000000"
    @test text(1.0e21) == "1e+21"
    @test text(1.5e300) == "1.5e+300"
    @test text(123.456) == "123.456"
    @test text(-0.5) == "-0.5"
    @test text(5.0e-324) == "5e-324"
end

"""
LOCKSTEP. The runtime's "Show summary" pane and `plot_summary_table` read the same
for every figure shape: heading, caption, columns and every cell, row by row. A
second fixture holds numbers against `toPrecision`/`toString` directly, ties and
both notations included, plus values spread over many magnitudes. The figure list includes the
shapes the pane got wrong before: rows in hash order, a summary whose layer is not
the first (the pane listed the other layer's rows raw) and a sparse grid (its pad
rows read as estimates for a combination without data).
"""
@testitem "plot_summary_table matches the browser's summary pane" setup=[AoVSummaryTableFixtures, AoVBrowserServer] tags=[:summary, :browser, :tidybayes] begin
    using HTMXObjects
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))

    # A cell as the page shows it.
    text(v) = ismissing(v) ? "" : AlgebraOfVega._summary_text(v)
    # The sections the browser must read for one figure, with the options passed
    # to both sides.
    sections(vl; kw...) = let tables = plot_summary_table(vl; kw...)
        isnothing(tables) ? Any[] : Any[
            Dict("label" => t.label, "caption" => t.caption, "columns" => String.(collect(keys(t.table))),
                 "rows" => [[text(t.table[c][i]) for c in keys(t.table)] for i in 1:length(first(t.table))])
            for t in tables]
    end

    de = plot_texts(:de)
    asspec(fig) = fig isa AlgebraOfVega.VegaSpec ? fig : vlspec(fig)
    cases = Any[(; id=name, spec=asspec(fig), kw=(;), cap=(;), lower=(;)) for (name, fig) in summary_figures()]
    two = vlspec(interval(pointinterval(probs=[0.5, 0.8])))
    push!(cases, (; id="inner-3-sigfigs", spec=two, kw=(; ci=:inner, sigfigs=3),
        cap=(; summary_ci=:inner, summary_sigfigs=3), lower=(;)))
    push!(cases, (; id="near-prob", spec=two, kw=(; ci=0.6), cap=(; summary_ci=0.6), lower=(;)))
    push!(cases, (; id="german", spec=vlspec(interval(pointinterval())), kw=(; texts=de), cap=(; texts=de), lower=(;)))
    # Through the channel picker, as a consumer lowers it (`to_vegalite(spec; auto_remap)`).
    picker = (; dims=["chain" => "Chain", "parameter" => "Parameter"], pinned=:row)
    push!(cases, (; id="picker", spec=vlspec(data(draws) * mapping(:value; y=:parameter, color=:chain) * pointinterval()),
        kw=(;), cap=(; auto_remap=picker), lower=(; auto_remap=picker)))
    cards = [with_plot_caption(c.spec, "Figure"; plot_id=c.id, c.cap...) for c in cases]
    expected = Dict(c.id => sections(to_vegalite(c.spec; c.lower...); c.kw...) for c in cases)
    @test all(c -> !isempty(expected[c.id]), cases)

    # Numbers: x, p, parseFloat(x.toPrecision(p)).toString(), String(x).
    magnitudes = [exp(30 * sin(1.7 * i)) for i in 1:300]
    numbers = vcat([1.25, 0.125, 2.5, 1.5, 12.5, 0.375, 99.5, 999.5, 9.95, 0.15, 1.0e21, 1.5e21, 1.0e20, 1.0e-6, 1.5e-6,
                    1.0e-7, 1.5e-7, 123456789012345680000.0, 5.0e-324, 1.7976931348623157e308, -1.25, -0.125],
                   magnitudes, -magnitudes[1:100], [round(500 + 500 * sin(2.3 * i); digits=2) for i in 1:200])
    format_cases = [(x, p, AlgebraOfVega._js_number_string(AlgebraOfVega._js_round(x, p)), AlgebraOfVega._js_number_string(x))
                    for x in numbers for p in (1, 2, 3, 6)]

    page = to_html(h.div(cards...); source=:inline)
    payload = replace(JSON.json((; expected, numbers=format_cases)), "</" => "<\\/")
    driver = read(joinpath(@__DIR__, "plot_summary_table.js"), String)

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-aov-summary-") do dir
            cut = first(findlast("</body>", page))
            write(joinpath(dir, "summary.html"), page[1:prevind(page, cut)] *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>" *
                page[cut:end])
            with_page_server(dir) do root
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                    --virtual-time-budget=60000 --dump-dom $(root * "/summary.html")`,
                    stderr=joinpath(dir, "chrome.log")), String)
                result = match(r"<pre id=\"aov-summary-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    # Every figure's sections and all the number cases were compared.
                    @test report["figures"] == length(cases)
                    @test report["numbers"] == length(format_cases)
                    @test report["checks"] == 2
                    @test isempty(report["failures"])
                    isempty(report["failures"]) || println(JSON.json(report["failures"]))
                end
            end
        end
    end
end
