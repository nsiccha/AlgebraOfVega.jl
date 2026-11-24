using TestItemRunner

# The "Show intervals" switch (todo `0no7hcn`, Bruno decision `0whc4na`): every
# figure that draws interval marks beside other marks gets a pressed button that
# hides and shows them, shown by default; while they are hidden an axis whose
# range they set refits to the marks still drawn.
@testsnippet AoVIntervalSwitchFixtures begin
    using AlgebraOfVega
    # xgx-like summaries: a median, a thin 95 % and a thick 50 % interval per
    # time, group and panel. The 95 % intervals are far wider than the medians'
    # spread, so hiding them refits the y axis.
    rows = [(; t=Float64(t), g, k, m=t + (g == "b") + (k == "Q"), lo=t - 30.0, hi=t + 30.0,
                lo50=t - 3.0, hi50=t + 3.0)
            for t in 1:6 for g in ("a", "b") for k in ("P", "Q")]
    draws = [(; t=Float64(t), g, y=t + (g == "b") + 4 * sin(13d + t), d)
             for t in 1:6 for g in ("a", "b") for d in 1:40]
    d = data(rows)
    rangebars(; kw...) = d * mapping(:t, :lo, :hi; color=:g, kw...) * visual(Rangebars; linewidth=1) +
        d * mapping(:t, :lo50, :hi50; color=:g, kw...) * visual(Rangebars; linewidth=4) +
        d * mapping(:t, :m; color=:g, kw...) * visual(Scatter)
    function units(s, out=Dict{String,Any}[])
        s isa AbstractDict || return out
        haskey(s, "mark") && push!(out, s)
        for k in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(s, k, Any[]))
        end
        haskey(s, "spec") && units(s["spec"], out)
        out
    end
    marktype(u) = (m = u["mark"]; m isa AbstractDict ? m["type"] : m)
    tagged(u) = get(u, "_aovInterval", false) === true
    offers(vl) = get(get(vl, "_aov", Dict()), "intervals", false) === true
end

@testitem "interval marks are tagged where they are made" setup=[AoVIntervalSwitchFixtures] tags=[:translation, :intervals] begin
    # Plain layers: every unit of Rangebars, Errorbars and Band; nothing else.
    vl = to_vegalite(rangebars())
    @test sort([(marktype(u), tagged(u)) for u in units(vl)]) ==
        [("errorbar", true), ("errorbar", true), ("point", false)]
    @test offers(vl)
    eb = to_vegalite(d * mapping(:t, :m, :lo50; color=:g) * visual(Errorbars) + d * mapping(:t, :m) * visual(Lines))
    @test count(tagged, units(eb)) == 1 && offers(eb)
    band = to_vegalite(d * mapping(:t, :lo, :hi) * visual(Band) + d * mapping(:t, :m) * visual(Lines))
    @test [(marktype(u), tagged(u)) for u in units(band)] == [("area", true), ("line", false)]
    # Analyses: the rules, never the median point.
    pi = to_vegalite(data(draws) * mapping(:y, :g) * pointinterval())
    @test count(u -> marktype(u) == "rule", units(pi)) >= 2 && all(u -> tagged(u) == (marktype(u) == "rule"), units(pi))
    @test offers(pi)
    gi = to_vegalite(data(draws) * mapping(:y, :g) * gradient_interval())
    @test any(tagged, units(gi)) && all(u -> marktype(u) == "rule", filter(tagged, units(gi))) && offers(gi)
    di = to_vegalite(data(draws) * mapping(:y, :g) * dotinterval())
    @test any(tagged, units(di)) && all(u -> marktype(u) == "rule", filter(tagged, units(di))) && offers(di)
    # A ribbon: its bands, not its line; its Intervals drawing: the rules.
    lr = to_vegalite(data(draws) * mapping(:t, :y; color=:g) * lineribbon(intervals=false))
    @test all(u -> tagged(u) == (marktype(u) == "area"), units(lr)) && count(tagged, units(lr)) > 0 && offers(lr)
    alt = lr["_aov"]["ribbonView"]["alt"]
    @test all(u -> tagged(u) == (marktype(u) == "rule"), units(alt)) && count(tagged, units(alt)) > 0 && offers(alt)
    # linear()/smooth(): the interval band.
    for a in (linear(interval=:confidence), smooth(interval=:confidence))
        fit = to_vegalite(d * mapping(:t, :m) * a)
        @test [(marktype(u), tagged(u)) for u in units(fit)] == [("area", true), ("line", false)]
        @test offers(fit)
    end
    # Faceted: the inner units.
    @test count(tagged, units(to_vegalite(rangebars(; col=:k)))) == 2
end

@testitem "intervals_switch says whether a figure offers the switch" setup=[AoVIntervalSwitchFixtures] tags=[:translation, :intervals, :auto_remap] begin
    @test intervals_switch(rangebars()) == (; offered=true, why_not=nothing)
    @test intervals_switch(rangebars(; col=:k)).offered
    # Nothing would be left to show, or nothing to hide.
    @test intervals_switch(d * mapping(:t, :lo, :hi; color=:g) * visual(Rangebars)) == (; offered=false, why_not=:only_intervals)
    @test intervals_switch(d * mapping(:t, :m) * visual(Scatter)) == (; offered=false, why_not=:no_intervals)
    @test intervals_switch(d * mapping(:t, :m) * linear()) == (; offered=false, why_not=:no_intervals)
    @test !offers(to_vegalite(d * mapping(:t, :m) * visual(Scatter)))
    # The picker's lowering and the positional scales form.
    @test intervals_switch(rangebars(); auto_remap=(; dims=["g" => "Group", "k" => "Kind"], pinned=:detail)).offered
    @test intervals_switch(rangebars(), scales(Color=(; palette=["#111", "#999"]))).offered
end

@testitem "vsave draws the intervals as before" setup=[AoVIntervalSwitchFixtures] tags=[:static, :intervals] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        # The tags are metadata: the file is the one the spec without them draws.
        strip!(x) = x
        strip!(v::AbstractVector) = (foreach(strip!, v); v)
        function strip!(x::AbstractDict)
            delete!(x, "_aovInterval")
            haskey(x, "_aov") && x["_aov"] isa AbstractDict && delete!(x["_aov"], "intervals")
            foreach(strip!, values(x))
            x
        end
        for fig in (rangebars(; col=:k), data(draws) * mapping(:t, :y; color=:g) * lineribbon())
            mktempdir() do dir
                a, b = joinpath(dir, "a.svg"), joinpath(dir, "b.svg")
                vsave(fig, a)
                vl = AlgebraOfVega._with_rows_inline(() -> to_vegalite(fig; interactive=false))
                @test offers(vl) || offers(get(get(vl["_aov"], "ribbonView", Dict()), "alt", Dict()))
                AlgebraOfVega._vsave_render(strip!(vl), b, AlgebraOfVega._vsave_command(b))
                @test read(a, String) == read(b, String)
            end
        end
    end
end

@testitem "the Show intervals switch in the browser" setup=[AoVIntervalSwitchFixtures] tags=[:regression, :browser, :intervals, :auto_remap] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    sz = config(width=260, height=160)
    page = [vdraw(rangebars(; col=:k) * sz; id="iv-range"),
        with_plot_caption(rangebars() * sz, "Concentration over time"; plot_id="iv-caption"),
        with_plot_caption(rangebars() * sz, "Konzentration"; plot_id="iv-de", texts=plot_texts(:de)),
        vdraw(data(draws) * mapping(:t, :y; color=:g) * lineribbon(intervals=true) * sz; id="iv-ribbon"),
        vdraw(data(draws) * mapping(:y, :g) * pointinterval() * sz; id="iv-point"),
        vdraw(rangebars() * sz * config(axis=(; limits=(nothing, (-40, 50)))); id="iv-limits"),
        auto_remap_node("iv-picker", rangebars() * sz; dims=["g" => "Group", "k" => "Kind"], pinned=:detail),
        vdraw(d * mapping(:t, :m; color=:g) * visual(Scatter) * sz; id="iv-none")]
    standalone = to_html(rangebars() * sz, "Standalone"; plot_id="iv-standalone")
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-interval-switch-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = read(joinpath(@__DIR__, "interval_switch.js"), String)
            # The standalone page goes into an iframe (srcdoc keeps it same-origin).
            data_script = "<script>window.IV_STANDALONE = " *
                replace(JSON.json(standalone), "</" => "<\\/") * ";</script>"
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body>" * join(html(p) for p in page) * data_script * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,2600
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-interval-switch-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "intervals switch browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
