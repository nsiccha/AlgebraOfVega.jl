using TestItemRunner

# Interval and ribbon tooltips show the estimate with its widest interval as one
# row, `139.2 (134.8–144.4)`, rounded at the second significant digit of the
# interval's width in the plot's number locale (`__aov_estimate`, a calculate on
# each layer showing the tooltip), titled with the value label and what the
# numbers are: `Level (cm): median (95% interval)`, or the columns,
# `Level (cm): q50 (q025–q975)`. A temporal tooltip keeps its time of day when
# the rows have one. User decision 0qrccve, prong `tooltips`. Before, these
# tooltips listed `median`, `q025`, `q975` (or `95% lo`/`95% hi`) unrounded
# (`125.057600736`), and an hourly time read `Mar 15, 2026`.
@testitem "interval and ribbon tooltips: one rounded estimate row; temporal tooltips keep the time" tags=[:tooltips] begin
    using AlgebraOfVega, AlgebraOfGraphics, Dates
    estimate_rows(vl) = begin
        out = Any[]
        walk(n) = n isa Dict ? (begin
            enc = get(n, "encoding", nothing)
            tt = enc isa Dict ? get(enc, "tooltip", nothing) : nothing
            if tt isa AbstractVector && any(e -> get(e, "field", nothing) == "__aov_estimate", tt)
                calc = [t for t in get(n, "transform", Any[]) if get(t, "as", nothing) == "__aov_estimate"]
                push!(out, (; titles=[get(e, "title", get(e, "field", "")) for e in tt], calc=length(calc)))
            end
            foreach(walk, values(n))
        end) : n isa AbstractVector ? foreach(walk, n) : nothing
        walk(vl)
        out
    end
    draws = (; site=repeat(["a", "b"], inner=200), v=[randn(200); randn(200) .+ 2])
    pi = to_vegalite(data(draws) * mapping(:v => "Change", y=:site => "Site") * pointinterval())
    rows = estimate_rows(pi)
    @test !isempty(rows) && all(r -> r.calc == 1, rows)
    @test all(r -> r.titles == ["Site", "Change: median (95% interval)"], rows)

    summ = (; site=["a", "b"], q50=[0.1, 1.0], q025=[-0.9, 0.4], q975=[0.4, 1.7], q25=[-0.3, 0.8], q75=[0.3, 1.2])
    pib = to_vegalite(data(summ) * mapping(:q50 => "Change"; y=:site) * pointinterval(bands=[:q025 => :q975, :q25 => :q75]))
    @test all(r -> last(r.titles) == "Change: q50 (q025–q975)" && r.calc == 1, estimate_rows(pib))
    # What a `bands=` figure states (`probs=`, `point=`) names the point and width.
    pis = to_vegalite(data(summ) * mapping(:q50 => "Change"; y=:site) *
        pointinterval(bands=[:q025 => :q975, :q25 => :q75], probs=[0.95, 0.5], point=:mean))
    @test all(r -> last(r.titles) == "Change: mean (95% interval)" && r.calc == 1, estimate_rows(pis))
    pip = to_vegalite(data(summ) * mapping(:q50 => "Change"; y=:site) *
        pointinterval(bands=[:q025 => :q975, :q25 => :q75], point=:median))
    @test all(r -> last(r.titles) == "Change: median (q025–q975)", estimate_rows(pip))

    t = DateTime(2026, 3, 15) .+ Hour.(0:3)
    rib = (; t, q50=[10.0, 11, 12, 13], q025=[8.0, 9, 10, 11], q975=[12.0, 13, 14, 15])
    vrib = to_vegalite(data(rib) * mapping(:t => "Time", :q50 => "Level (cm)") * lineribbon(bands=[:q025 => :q975]))
    rr = estimate_rows(vrib)
    @test !isempty(rr) && all(r -> r.titles == ["Time", "Level (cm): q50 (q025–q975)"] && r.calc == 1, rr)
    rs = estimate_rows(to_vegalite(data(rib) * mapping(:t => "Time", :q50 => "Level (cm)") *
        lineribbon(bands=[:q025 => :q975], probs=[0.95], point=:mean)))
    @test !isempty(rs) && all(r -> r.titles == ["Time", "Level (cm): mean (95% interval)"], rs)
    raw = (; x=repeat(1.0:4, inner=100), y=randn(400))
    @test all(r -> last(r.titles) == "y: median (95% interval)", estimate_rows(to_vegalite(data(raw) * mapping(:x, :y) * lineribbon())))

    # A coloured ribbon over a few x values: both drawings carry the estimate.
    dose = (; d=repeat([1.0, 2, 4], 2), g=repeat(["A", "B"], inner=3), q50=[1.0, 2, 3, 1.5, 2.5, 3.5],
        q025=[0.5, 1.5, 2.5, 1.0, 2.0, 3.0], q975=[1.5, 2.5, 3.5, 2.0, 3.0, 4.0])
    vd = to_vegalite(data(dose) * mapping(:d, :q50; color=:g) * lineribbon(bands=[:q025 => :q975]))
    for drawing in (vd, vd["_aov"]["ribbonView"]["alt"])
        er = estimate_rows(drawing)
        @test !isempty(er) && all(r -> r.calc == 1, er)
    end

    # Temporal tooltips: the time of day when the rows have one.
    tfmt(vl) = [e["format"] for e in vl["encoding"]["tooltip"] if get(e, "type", nothing) == "temporal" && haskey(e, "format")]
    hourly = data((; t, v=[1.0, 2, 3, 4])) * mapping(:t, :v) * visual(Scatter)
    @test tfmt(to_vegalite(hourly)) == ["%b %d, %Y %H:%M"]
    @test tfmt(to_vegalite(hourly * config(config=Dict("timeFormat" => "%d.%m.%Y")))) == ["%d.%m.%Y %H:%M"]
    secs = data((; t=DateTime(2026, 3, 15) .+ Second.(0:3), v=[1.0, 2, 3, 4])) * mapping(:t, :v) * visual(Scatter)
    @test tfmt(to_vegalite(secs)) == ["%b %d, %Y %H:%M:%S"]
    @test isempty(tfmt(to_vegalite(data((; t=Date(2026, 3, 1) .+ Day.(0:3), v=[1.0, 2, 3, 4])) * mapping(:t, :v) * visual(Scatter))))
    midnight = data((; t=DateTime(2026, 3, 1) .+ Day.(0:3), v=[1.0, 2, 3, 4])) * mapping(:t, :v) * visual(Scatter)
    @test isempty(tfmt(to_vegalite(midnight)))
    authored = hourly * config(encoding=Dict(:tooltip => [Dict("field" => "t", "type" => "temporal", "format" => "%H")]))
    @test tfmt(to_vegalite(authored)) == ["%H"]
end

@testitem "the estimate row's text in the browser" tags=[:tooltips, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-tooltip-estimates-") do dir
            summ = (; site=["wide", "neg", "flat", "small"], q50=[139.2, -0.2, 2.0, 0.0512],
                q025=[134.8, -0.9, 2.0, 0.0301], q975=[144.4, 0.4, 2.0, 0.0789])
            spec = data(summ) * mapping(:q50 => "Value"; y=:site) * pointinterval(bands=[:q025 => :q975]) *
                config(width=300, height=160)
            dose = (; d=repeat([1.0, 2, 4], 2), g=repeat(["A", "B"], inner=3), q50=[1.0, 2, 3, 1.5, 2.5, 3.5],
                q025=[0.5, 1.5, 2.5, 1.0, 2.0, 3.0], q975=[1.5, 2.5, 3.5, 2.0, 3.0, 4.0])
            ribbon = data(dose) * mapping(:d, :q50; color=:g) * lineribbon(bands=[:q025 => :q975]) * config(width=300, height=160)
            page = [vdraw(spec; id="te-en"), vdraw(spec * locale_config(:de); id="te-de"), vdraw(ribbon; id="te-rib")]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = """
            (async function () {
                const out = {};
                const estimates = id => {
                    const got = {};
                    (function walk(it) {
                        const d = it.datum;
                        if (d && d.__aov_estimate !== undefined && (d.site !== undefined || d.g !== undefined))
                            got[(d.site || d.g) + (d.d !== undefined ? '@' + d.d : '')] = d.__aov_estimate;
                        (it.items || []).forEach(walk);
                    })(AoV.views[id].scenegraph().root);
                    return got;
                };
                for (const id of ['te-en', 'te-de', 'te-rib']) {
                    for (let i = 0; i < 500 && !(AoV.views[id] && !AoV._inFlight[id]); i++) await new Promise(r => setTimeout(r, 10));
                    out[id] = estimates(id);
                }
                AoV.setRibbonView('te-rib', AoV._ribbonViews['te-rib'] && AoV._ribbonViews['te-rib'].view === 'ribbons' ? 'intervals' : 'ribbons');
                for (let i = 0; i < 300; i++) { await new Promise(r => setTimeout(r, 10)); if (!AoV._inFlight['te-rib']) break; }
                await new Promise(r => setTimeout(r, 200));
                out['te-rib-other'] = estimates('te-rib');
                const pre = document.createElement('pre'); pre.id = 'aov-tooltip-estimates';
                pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
            })();
            """
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,1200
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-tooltip-estimates\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                r = JSON.parse(replace(result[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "estimate texts" r
                @test r["te-en"]["wide"] == "139.2 (134.8–144.4)"
                @test r["te-en"]["neg"] == "−0.2 (−0.9 – 0.4)"
                @test r["te-en"]["flat"] == "2.00 (2.00–2.00)"
                @test r["te-en"]["small"] == "0.051 (0.030–0.079)"
                @test r["te-de"]["wide"] == "139,2 (134,8–144,4)"
                @test r["te-rib"]["A@1"] == "1.0 (0.5–1.5)" || r["te-rib"]["A@1.0"] == "1.0 (0.5–1.5)"
                @test any(==("2.5 (2.0–3.0)"), values(r["te-rib-other"]))
            end
        end
    end
end
