using TestItemRunner

"""
A coloured ribbon's point-interval view (`lineribbon(...; intervals=…)`).

A ribbon coloured by group over a few numeric x values (a dose ladder) is
lowered twice: as drawn, and as the vertical `pointinterval` of the same rows,
dodged by colour: around the true x on the ribbon's own (linear or log) x axis,
or on evenly spaced x slots when the x values are too unevenly spaced on that
axis to dodge readably (a dose ladder on a linear axis). The figure starts in the
point-interval view when the colour groups' outer bands overlap by more than
10% of the y range on average (in some facet panel, for some pair of groups),
and the browser runtime swaps between the two with a "Ribbons | Intervals"
switch. User request on Bruno decision `028b53f`.

The two fixtures are the user's two examples, synthesised: three groups whose
wide bands lie inside each other across the whole dose range (starts as
intervals), and three sigmoids that meet only near 0 and 1, where their bands
are thin (stays a ribbon).
"""
@testsnippet AoVRibbonViewFixtures begin
    using AlgebraOfVega, AlgebraOfGraphics
    AoV = AlgebraOfVega
    DOSES = [5, 10, 20, 40, 80, 160, 320]
    BANDS = [:q025 => :q975, :q10 => :q90, :q25 => :q75]
    function band_table(f; doses=DOSES, groups=("A", "B", "C"))
        rows = [(; dose=d, group=g, f(g, d)...) for g in groups for d in doses]
        (; (c => [getproperty(r, c) for r in rows] for c in keys(first(rows)))...)
    end
    nested_bands(m, w) = (; med=m, q025=m - w, q975=m + w, q10=m - 0.6w, q90=m + 0.6w, q25=m - 0.3w, q75=m + 0.3w)
    # Example 1: bands 50 wide around medians 5 apart.
    overlapping(; kw...) = band_table((g, d) -> nested_bands(
        20 + 5 * log2(d / 5) + Dict("A" => 0.0, "B" => 5.0, "C" => -5.0)[g], 25.0); kw...)
    # Example 2: sigmoid fractions; bands vanish at 0 and 1.
    function sigmoids(; kw...)
        band_table((g, d) -> begin
            p = 1 / (1 + exp(-3 * (log(d) - log(Dict("A" => 10, "B" => 40, "C" => 160)[g]))))
            w = 1.2 * p * (1 - p)
            b = nested_bands(p, w)
            (; (k => clamp(v, 0, 1) for (k, v) in pairs(b))...)
        end; kw...)
    end
    ribbon_fig(t; kw...) = data(t) * mapping(:dose => "Dose (mg)", :med => "Response"; color=:group) *
        lineribbon(; bands=BANDS, kw...)
    view_meta(vl) = get(get(vl, "_aov", Dict()), "ribbonView", nothing)
    other(vl) = view_meta(vl)["alt"]
    function x_encodings(vl)
        out = Dict{String,Any}[]
        AoV._each_encoded(vl) do d, _
            x = get(d["encoding"], "x", nothing)
            isnothing(x) || push!(out, x)
        end
        out
    end
    marks(vl) = let out = String[]
        AoV._each_encoded(vl) do d, _
            m = get(d, "mark", nothing)
            isnothing(m) || push!(out, m isa AbstractDict ? m["type"] : m)
        end
        out
    end
end

@testitem "a coloured ribbon starts as point-intervals when its bands overlap" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    over = to_vegalite(ribbon_fig(overlapping()))
    rv = view_meta(over)
    @test rv["view"] == "intervals" && rv["start"] == "intervals"
    @test rv["score"] ≈ 0.5 atol=0.01
    @test rv["threshold"] == 0.1
    # The shown spec is the point-interval drawing; the ribbon rides along.
    @test "rule" in marks(over) && !("area" in marks(over))
    ribbons = other(over)
    @test view_meta(ribbons)["view"] == "ribbons" && !haskey(view_meta(ribbons), "alt")
    @test "area" in marks(ribbons) && !("rule" in marks(ribbons))

    sig = to_vegalite(ribbon_fig(sigmoids()))
    @test view_meta(sig)["view"] == "ribbons" && view_meta(sig)["start"] == "ribbons"
    @test view_meta(sig)["score"] < 0.05
    @test view_meta(other(sig))["view"] == "intervals"

    # The point-interval drawing of a dose ladder on a linear axis: evenly
    # spaced dose slots in ascending order, dodged by colour, the ribbon's x
    # title, upright labels.
    slots = Any[5, 10, 20, 40, 80, 160, 320]
    for x in x_encodings(over)
        @test x["type"] == "nominal" && x["scale"] == Dict("domain" => slots)
        @test x["title"] == "Dose (mg)" && x["axis"]["labelAngle"] == 0
        @test !haskey(x["axis"], "title")
    end
    AoV._each_encoded(over) do d, _
        haskey(d["encoding"], "y") && @test d["encoding"]["xOffset"]["field"] == "group"
    end
    # The same rows in both drawings.
    @test over["data"]["values"] == ribbons["data"]["values"]
end

@testitem "intervals= overrides the starting view" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    m(t; kw...) = view_meta(to_vegalite(ribbon_fig(t; kw...)))
    @test m(overlapping(); intervals=false)["start"] == "ribbons"
    @test isnothing(m(overlapping(); intervals=false)["threshold"])
    @test m(sigmoids(); intervals=true)["start"] == "intervals"
    @test m(sigmoids(); intervals=0.0001)["start"] == "intervals"
    @test m(overlapping(); intervals=0.9)["start"] == "ribbons"
    @test m(overlapping(); intervals=0.9)["threshold"] == 0.9
    @test m(overlapping(); intervals=:auto)["start"] == "intervals"
    @test_throws ArgumentError lineribbon(bands=BANDS, intervals=1.5)
    @test_throws ArgumentError lineribbon(bands=BANDS, intervals=:always)
    @test_throws ArgumentError ribbon(intervals="yes")
    # ribbon() works the same way; its interval drawing keeps the median point.
    r = to_vegalite(data(overlapping()) * mapping(:dose, :med; color=:group) * ribbon(bands=BANDS))
    @test view_meta(r)["start"] == "intervals" && count(==("point"), marks(r)) == 1
end

@testitem "raw draws give the same overlap and the same summary" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    t = overlapping()
    n = 400
    # Draws whose 2.5/97.5% quantiles are the table's outer band.
    draws = (; dose=Int[], group=String[], y=Float64[], draw=Int[])
    for i in eachindex(t.dose), k in 1:n
        push!(draws.dose, t.dose[i]); push!(draws.group, t.group[i]); push!(draws.draw, k)
        push!(draws.y, t.q025[i] + (t.q975[i] - t.q025[i]) * (k - 1) / (n - 1))
    end
    vl = to_vegalite(data(draws) * mapping(:dose, :y; color=:group, group=:draw) * lineribbon())
    @test view_meta(vl)["start"] == "intervals"
    # The draws' 2.5/97.5% quantiles sit just inside the table's outer band.
    @test view_meta(vl)["score"] ≈ 0.5 atol=0.03
    # The interval drawing summarises the same draws: same medians and bounds.
    rib = Dict((r["dose"], r["group"]) => r for r in other(vl)["data"]["values"])
    ints = vl["data"]["values"]
    @test length(ints) == length(rib) == 21
    @test all(r -> r["__point__"] ≈ rib[(r["dose"], r["group"])]["__median__"] &&
                   r["lo_0_95_"] ≈ rib[(r["dose"], r["group"])]["lo_0_95_"], ints)
end

@testitem "only a coloured ribbon over a few numeric x values gets a point-interval view" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    using Dates
    # The plain lowering plus the last pass every figure gets.
    plain(spec) = AoV._apply_no_zero_default!(AoV._lower_vegaspec(AoV.vlspec(spec)))
    unoffered(spec) = (vl = to_vegalite(spec); isnothing(view_meta(vl)) && vl == plain(spec))
    # No colour groups.
    @test unoffered(data(overlapping()) * mapping(:dose, :med) * lineribbon(bands=BANDS))
    # A dense x grid (a time course): no switch.
    @test unoffered(ribbon_fig(overlapping(; doses=1:13)))
    @test !isnothing(view_meta(to_vegalite(ribbon_fig(overlapping(; doses=1:12)))))
    # A date x: a time axis, not doses.
    days = Date(2026, 1, 1) .+ Day.(0:3)
    t = overlapping(; doses=[5, 10, 20, 40])
    dated = merge(t, (; day=[days[findfirst(==(d), [5, 10, 20, 40])] for d in t.dose]))
    @test unoffered(data(dated) * mapping(:day, :med; color=:group) * lineribbon(bands=BANDS))
    # A layer whose x values miss the slots cannot sit on them.
    off_slot = ribbon_fig(overlapping()) + data((; dose=[7], y=[1.0])) * mapping(:dose, :y) * visual(Scatter)
    @test unoffered(off_slot)
    # On a log axis the intervals keep true positions, so it stays at 7.
    @test !isnothing(view_meta(to_vegalite(off_slot * config(scales=scales(X=(; scale=log10))))))
    # Two ribbons, or a detail split: no single set of groups to dodge.
    @test unoffered(ribbon_fig(overlapping()) + ribbon_fig(sigmoids()))
    @test unoffered(data(overlapping()) * mapping(:dose, :med; color=:group) *
        lineribbon(bands=BANDS, detail=[:group]))
end

@testitem "on a log x the intervals keep true positions, dodged around each dose" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    obs = (; dose=repeat(DOSES, 2), y=collect(1.0:14.0))
    guides = (; dose=[20, 160])
    base = ribbon_fig(overlapping()) + data(obs) * mapping(:dose, :y) * visual(Scatter; color=:ink) +
        data(guides) * mapping(:dose) * visual(VLines)
    sugar = to_vegalite(base * config(scales=scales(X=(; scale=log10))))
    raw = to_vegalite(base * config(encoding=Dict("x" => Dict("scale" => Dict("type" => "log")))))
    positional = to_vegalite(base, scales(X=(; scale=log10)))
    for vl in (sugar, raw, positional)
        @test view_meta(vl)["start"] == "intervals"
        # The interval layers draw the dodged x, quantitative on the log axis,
        # with the ribbon's x title; observations and dose lines keep theirs.
        dodged, kept = Dict{String,Any}[], Dict{String,Any}[]
        AoV._each_encoded(vl) do d, _
            x = get(d["encoding"], "x", nothing)
            isnothing(x) && return
            if x["field"] == "__aov_x"
                push!(dodged, d)
                @test x["type"] == "quantitative" && x["scale"]["type"] == "log"
                @test x["title"] == "Dose (mg)" && !haskey(d["encoding"], "xOffset")
                @test d["transform"][end]["as"] == "__aov_x"
            else
                push!(kept, x)
            end
        end
        @test length(dodged) == 4
        @test length(kept) == 2 && all(x -> x["field"] == "dose" && x["scale"]["type"] == "log", kept)
        # Three groups within 0.7 of a doubling: steps of 0.7·log(2)/3 in log space.
        dx = vl["_aov"]["dodgeX"]
        @test dx["by"] == "group" && dx["domain"] == ["A", "B", "C"] && dx["scale"] == "log"
        @test dx["span"] ≈ 0.7 * log(2)
        @test dodged[1]["transform"][end]["calculate"] ==
            AoV._ribbon_dodge_expr("dose", "group", ["A", "B", "C"], dx["span"], :log)
        # The ribbon drawing keeps its log axis and no dodge.
        @test all(x -> x["scale"]["type"] == "log", x_encodings(other(vl)))
        @test !haskey(get(other(vl), "_aov", Dict()), "dodgeX")
    end
    # The expression: the middle group stays on the dose, the others a step
    # either side (multiplied in on a log axis, added on a linear one).
    @test AoV._ribbon_dodge_expr("dose", "group", ["A", "B", "C"], 1.5, :log) ==
        "isValid(datum[\"dose\"]) ? datum[\"dose\"] * exp((indexof([\"A\",\"B\",\"C\"], datum[\"group\"]) < 0 ? 0 : " *
        "(indexof([\"A\",\"B\",\"C\"], datum[\"group\"]) - 1.0) * 0.5)) : null"
    @test occursin("datum[\"dose\"] + (", AoV._ribbon_dodge_expr("dose", "g", [1, 2], 7.0, :linear))
    @test AoV._ribbon_dodge_expr("dose", "g", ["A"], 7.0, :linear) == "isValid(datum[\"dose\"]) ? datum[\"dose\"] : null"
    # A quantitative x zooms, as in the ribbon drawing.
    zooms = String[]
    AoV._each_encoded(sugar) do d, _
        for p in get(d, "params", Any[])
            get(p, "bind", nothing) == "scales" && append!(zooms, p["select"]["encodings"])
        end
    end
    @test "x" in zooms && "y" in zooms
end

"""
The dodge moves the outermost groups past the first and last x, and the scale's
domain ends at the dodged positions. Before snag `ribbon-interval-da26aaeb`,
a `nice=false` log axis drew those groups half off the plot (1 and 1000 mg), and
the default `nice` rounded a 1–1000 mg log axis out to 0.1–10,000.
"""
@testitem "the interval drawing leaves room for the outermost groups" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    obs = (; dose=DOSES, y=collect(1.0:7.0))
    fig = ribbon_fig(overlapping()) + data(obs) * mapping(:dose, :y) * visual(Scatter)
    x_scales(vl) = [x["scale"] for x in x_encodings(vl)]
    function intervals_and_ribbons(spec)
        vl = to_vegalite(spec)
        view_meta(vl)["view"] == "intervals" ? (vl, other(vl)) : (other(vl), vl)
    end
    # Every x of the interval drawing (dodged and kept layers alike) shares one
    # scale: padded by the median point's reach (size 80: radius 5.05 + half its
    # 1.5 ring, rounded up) plus 4 px; a log axis is not rounded out.
    iv, rb = intervals_and_ribbons(fig * config(scales=scales(X=(; scale=log10))))
    @test length(x_scales(iv)) == 5 && allequal(x_scales(iv))
    @test only(unique(x_scales(iv))) == Dict("type" => "log", "padding" => 10, "nice" => false)
    # The ribbon drawing's scale is unchanged.
    @test all(s -> !haskey(s, "padding") && !haskey(s, "nice"), x_scales(rb))
    # An authored nice or padding stays as written.
    iv, _ = intervals_and_ribbons(fig * config(encoding=Dict("x" => Dict("scale" =>
        Dict("type" => "log", "nice" => true, "padding" => 25)))))
    @test all(s -> s["nice"] === true && s["padding"] == 25, x_scales(iv))
    iv, _ = intervals_and_ribbons(fig * config(encoding=Dict("x" => Dict("scale" => Dict("type" => "log", "nice" => false)))))
    @test all(s -> s["nice"] === false && s["padding"] == 10, x_scales(iv))
    # An authored domain (a tuple from `scales`, a vector from `limits`) is
    # widened by half the dodge span, on the axis's terms.
    span = 0.7 * log(2)
    iv, rb = intervals_and_ribbons(fig * config(scales=scales(X=(; scale=log10, domain=(5, 320)))))
    @test all(s -> s["domain"] ≈ [5 * exp(-span / 2), 320 * exp(span / 2)], x_scales(iv))
    @test all(s -> collect(s["domain"]) == [5, 320], x_scales(rb))
    even = to_vegalite(ribbon_fig(overlapping(; doses=[10, 20, 30, 40, 50])) *
        config(axis=(; limits=((10, 50), nothing))))
    @test even["_aov"]["dodgeX"]["scale"] == "linear"
    @test all(s -> s["domain"] ≈ [10 - 3.5, 50 + 3.5] && s["padding"] == 10 && !haskey(s, "nice"), x_scales(even))
    # A linear axis keeps Vega-Lite's nice; with no scale at all it still gets one.
    @test AoV._dodged_x_scale(nothing, Dict{String,Any}(), nothing, :linear, 7.0) == Dict("padding" => 4)
    # The slot fallback (a band scale) needs no padding.
    sq = to_vegalite(ribbon_fig(overlapping(; doses=[10, 20, 30, 40, 50])) *
        config(encoding=Dict("x" => Dict("scale" => Dict("type" => "sqrt")))))
    @test all(s -> !haskey(s, "padding"), x_scales(sq))
end

@testitem "true positions where the x values leave room, slots where they do not" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    # The closest pair needs a quarter of an even share of the axis.
    @test isnothing(AoV._ribbon_dodge_gap(DOSES, :linear))
    @test AoV._ribbon_dodge_gap(DOSES, :log) ≈ log(2)
    @test AoV._ribbon_dodge_gap([10, 20, 30, 40, 50], :linear) == 10
    @test isnothing(AoV._ribbon_dodge_gap([5], :linear)) && isnothing(AoV._ribbon_dodge_gap([0, 5, 10], :log))
    @test AoV._ribbon_dodge_kind(nothing) === :linear && AoV._ribbon_dodge_kind(Dict("zero" => false)) === :linear
    @test isnothing(AoV._ribbon_dodge_kind(Dict("type" => "sqrt")))
    # An evenly spaced ladder on a linear axis: true positions, the dodge added.
    even = to_vegalite(ribbon_fig(overlapping(; doses=[10, 20, 30, 40, 50])))
    @test even["_aov"]["dodgeX"]["scale"] == "linear" && even["_aov"]["dodgeX"]["span"] ≈ 7
    @test all(x -> x["field"] == "__aov_x" && x["type"] == "quantitative", x_encodings(even))
    # A scale the dodge cannot move along: slots.
    sq = to_vegalite(ribbon_fig(overlapping(; doses=[10, 20, 30, 40, 50])) *
        config(encoding=Dict("x" => Dict("scale" => Dict("type" => "sqrt")))))
    @test all(x -> x["type"] == "nominal", x_encodings(sq)) && !haskey(sq["_aov"], "dodgeX")
    # A sorter orders the dodge as it orders the colours.
    srt = to_vegalite(data(overlapping()) * mapping(:dose, :med; color=:group => sorter("C", "A", "B")) *
        lineribbon(bands=BANDS) * config(scales=scales(X=(; scale=log10))))
    @test srt["_aov"]["dodgeX"]["domain"] == ["C", "A", "B"]
    @test AoV._ribbon_dodge_domain(Any[3, 1, 2, 1], nothing) == [1, 2, 3]
    @test AoV._ribbon_dodge_domain(Any["b", "a", missing], ["b"]) == ["b", "a"]
end

@testitem "the y axis the overlap is measured on" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    score(spec) = view_meta(to_vegalite(spec))["score"]
    base = score(ribbon_fig(overlapping()))
    # A fixed y domain ten times wider: a tenth of the share.
    wide = score(ribbon_fig(overlapping()) * config(scales=scales(Y=(; domain=(-450, 450)))))
    @test wide ≈ base * 90 / 900 atol=0.005
    # Panels: the score is the largest over facet panels.
    t = overlapping()
    two = merge(t, (; study=fill("S1", length(t.dose))))
    sep = sigmoids()
    both = (; (k => vcat(getproperty(two, k), k === :study ? fill("S2", length(sep.dose)) : getproperty(sep, k))
        for k in keys(two))...)
    faceted = data(both) * mapping(:dose, :med; color=:group, col=:study) * lineribbon(bands=BANDS)
    @test score(faceted) ≈ base atol=0.05
    # Independent y scales measure each panel on its own range.
    indep = faceted * config(facet=(; linkyaxes=:none))
    @test score(indep) ≈ base atol=0.05
end

@testitem "a sorted colour keeps one order in both drawings" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon] begin
    spec = data(overlapping()) * mapping(:dose, :med; color=:group => sorter("C", "A", "B")) * lineribbon(bands=BANDS)
    vl = to_vegalite(spec)
    for v in (vl, other(vl))
        AoV._each_encoded(v) do d, _
            c = get(d["encoding"], "color", nothing)
            isnothing(c) || @test c["sort"] == ["C", "A", "B"]
        end
    end
    # Without a sorter no sort is written (the ribbon output is unchanged).
    AoV._each_encoded(other(to_vegalite(ribbon_fig(sigmoids())))) do d, _
        c = get(d["encoding"], "color", nothing)
        isnothing(c) || @test !haskey(c, "sort")
    end
end

@testitem "picker, embed and static paths carry both drawings" setup=[AoVRibbonViewFixtures] tags=[:translation, :ribbon, :auto_remap] begin
    obs = (; dose=repeat(DOSES, 2), y=collect(1.0:14.0))
    t = overlapping()
    t2 = merge(t, (; study=repeat(["S1"], length(t.dose))))
    spec = (data(t2) * mapping(:dose, :med; color=:group) * lineribbon(bands=BANDS) +
        data(obs) * mapping(:dose, :y) * visual(Scatter; color=:ink)) * config(height=200)
    remap = (; dims=["group" => "Group", "study" => "Study"], pinned=:row)
    vl = to_vegalite(spec; auto_remap=remap)
    @test view_meta(vl)["start"] == "intervals" && view_meta(other(vl))["view"] == "ribbons"
    @test vl == AoV._auto_remap_lowering(spec; remap...).vl
    # Sized like the shown drawing.
    emb = AoV._embed_spec(vl)
    @test emb["_aov"]["fitWidth"] && view_meta(emb)["alt"]["_aov"]["fitWidth"]
    @test !haskey(vl["_aov"], "fitWidth")   # to_node leaves its argument alone
    # vsave writes the starting drawing alone.
    st = AoV._without_ribbon_view(vl)
    @test isnothing(view_meta(st)) && "rule" in marks(st) && haskey(vl["_aov"], "ribbonView")
    # The Markdown summary reads the shown drawing only.
    @test occursin("`rule`", plot_summary_md(vl)) && !occursin("`area`", plot_summary_md(vl))
    # update_spec ships both drawings.
    js = sprint(show, MIME"text/html"(), update_spec("r", spec; auto_remap=remap))
    @test occursin("\"ribbonView\"", js) && occursin("\"alt\"", js)
end

@testitem "the Ribbons | Intervals switch" setup=[AoVRibbonViewFixtures] tags=[:ribbon, :browser, :auto_remap] begin
    using HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]
    obs = (; dose=repeat(DOSES, 2), y=collect(1.0:14.0))
    function studies(t)
        n = length(t.dose)
        (; (k => vcat(getproperty(t, k), getproperty(t, k)) for k in keys(t))..., study=vcat(fill("S1", n), fill("S2", n)))
    end
    picker_fig(t) = (data(studies(t)) * mapping(:dose => "Dose (mg)", :med => "Response"; color=:group) *
        lineribbon(bands=BANDS) + data(obs) * mapping(:dose, :y) * visual(Scatter; color=:ink)) * config(height=160)
    remap = (; dims=["group" => "Group", "study" => "Study"], pinned=:row)
    shifted = let t = overlapping()
        merge(t, (; (k => getproperty(t, k) .+ 1.0 for k in (:med, :q025, :q975, :q10, :q90, :q25, :q75))...))
    end
    updates = Dict("same" => script(update_spec("ribbon-cap", picker_fig(shifted); auto_remap=remap)))
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-ribbon-view-") do dir
            page = [
                with_plot_caption(picker_fig(overlapping()), "Dose response"; plot_id="ribbon-cap", auto_remap=remap),
                vdraw(ribbon_fig(sigmoids()) * config(height=160); id="ribbon-plain"),
                with_plot_caption(ribbon_fig(overlapping()) * config(height=160), "Dosis-Wirkung";
                    plot_id="ribbon-de", texts=plot_texts(:de)),
                vdraw(data(obs) * mapping(:dose, :y) * visual(Scatter); id="ribbon-none"),
                with_plot_caption(picker_fig(overlapping()) * config(scales=scales(X=(; scale=log10))),
                    "Log doses"; plot_id="ribbon-log", auto_remap=remap),
            ]
            runtime = join(html(n) for n in vega_head(source=:inline))
            payload = replace(JSON.json((; updates, updated_median=shifted.med[1])), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "ribbon_view.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "embed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" *
                join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-ribbon-view-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 45
                @test isempty(report["failures"])
                @info "ribbon switch browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end

# The pressed switch button's tint (15% of its text colour) took Pico's slate
# outline (HTMXObjects' `pico_bridge()`) to 4.39:1 in light mode, under WCAG
# AA's 4.5:1 for its 0.85em text; Pico's azure outline fell to 4.23:1, and on a
# dark page with no stylesheet the button's black text sat on near-black (snag
# `axe-core-4-10-3-e386d833`, axe-core 4.10.3 on ODLPlaus' report page). Now
# both buttons keep 4.5:1, at rest and focused, in light and dark.
@testitem "the Ribbons | Intervals switch keeps AA text contrast" setup=[AoVRibbonViewFixtures] tags=[:ribbon, :browser, :regression] begin
    using HTMXObjects, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-ribbon-contrast-") do dir
            copy_vendorfiles(dir; packages=(:pico,), runtime=false)
            pico = "<link rel='stylesheet' href='pico.min.css'>"
            head = join(html(n) for n in vega_head(; source=:inline)) * html(caption_style())
            body = html(with_plot_caption(ribbon_fig(overlapping()) * config(height=160), "Dose response";
                    plot_id="rc-cap")) *
                html(vdraw(ribbon_fig(sigmoids()) * config(height=160); id="rc-plain"))
            driver = read(joinpath(@__DIR__, "ribbon_view_contrast.js"), String)
            for (name, theme) in (("pico", pico), ("slate", pico * html(pico_bridge())),
                    ("plain", "<style>html[data-theme=dark] body { color: #ddd; background: #111; }</style>"))
                file = name * ".html"
                write(joinpath(dir, file), "<!doctype html><meta charset='utf-8'>" * theme * head *
                    "<body><main class='container'>" * body * "</main><script>window.AOV_CONTRAST_PAGE='" *
                    name * "';</script><script>" * driver * "</script></body>")
                output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile-" * name)) --window-size=1200,1400
                    --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, file))`,
                    stderr=joinpath(dir, name * ".log")), String)
                result = match(r"<pre id=\"aov-ribbon-contrast-results\">([^<]*)</pre>", output)
                @test !isnothing(result)
                if !isnothing(result)
                    report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                        "&gt;" => ">", "&amp;" => "&"))
                    @test report["checks"] == 20
                    @test isempty(report["failures"])
                    isempty(report["failures"]) || println(name, ": ", JSON.json(report["failures"]))
                end
            end
        end
    end
end
