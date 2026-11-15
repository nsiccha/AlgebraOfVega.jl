# Three result views drawn with AlgebraOfVega's public API, on synthetic data:
#
#   1. an interval table: one estimate with its 50 % and 95 % intervals per item,
#      a known true value and a reference, as small charts in the rows of a
#      grouped table on one shared scale, and as a forest plot linked to a table;
#   2. a forecast over time: observations, forecast medians with their bands per
#      scenario, the forecast window and the issue time, a precipitation panel,
#      and a table of the same times linked to the chart;
#   3. a faceted comparison: two methods over a sample-size axis in three noise
#      settings, with single runs and a reference curve, and a grouped table.
#
# Every number is generated here from fixed seeds. The page is written as one
# static HTML file (the figures load AoV's runtime from the vendored files next
# to it), and each figure is also written with `vsave` (the static export path).
#
#   julia --project=. examples/results-views/build.jl [outdir]

using AlgebraOfVega, HTMXObjects, Dates, Random, Statistics
using HTMXObjects: h
const Makie = AlgebraOfVega.Makie

const OUT = abspath(get(ARGS, 1, joinpath(@__DIR__, "build")))
mkpath(OUT)

const Z95 = 1.959963984540054   # standard normal 97.5 % quantile
const Z50 = 0.6744897501960817  # standard normal 75 % quantile

# Median with its 50 % and 95 % central intervals for a normal posterior.
normal_bands(m, s) = (; q025=m - Z95 * s, q25=m - Z50 * s, q50=m, q75=m + Z50 * s, q975=m + Z95 * s)

const BANDS = [:q025 => :q975, :q25 => :q75]

# ---------------------------------------------------------------------------
# 1. Interval table: change per site, three regions, a synthetic study whose
#    true values are known.
# ---------------------------------------------------------------------------
function interval_rows()
    rng = Xoshiro(11)
    rows = NamedTuple[]
    for (region, base) in (("North", 0.0), ("Central", 0.6), ("South", 1.5)), i in 1:6
        truth = round(base + 0.25 * randn(rng); digits=2)
        s = 0.12 + 0.3 * rand(rng)
        m = truth + s * randn(rng)
        push!(rows, (; site="$(region[1])-$(lpad(i, 2, '0'))", region, truth, s, normal_bands(m, s)...))
    end
    [merge(r, (; excludes_zero=(r.q025 > 0 || r.q975 < 0) ? "yes" : "no",
               what="Median with 50 % and 95 % intervals")) for r in rows]
end

# ---------------------------------------------------------------------------
# 2. Forecast: an hourly level, observed for 48 h, forecast for 12 h from the
#    issue time under two scenarios, with hourly precipitation.
# ---------------------------------------------------------------------------
function forecast_rows()
    rng = Xoshiro(22)
    t0 = DateTime(2026, 3, 14, 0)
    nh, issue = 49, 37                 # hours 0..48; the forecast is issued at hour 36 (index 37)
    rain = [h in 30:41 ? max(0.0, 2.6 * sin(pi * (h - 29) / 13) + 0.25 * randn(rng)) : max(0.0, 0.04 * randn(rng))
            for h in 0:nh-1]
    inflow(r, k) = sum(r[max(1, k - 6):max(1, k - 2)]; init=0.0) / 5   # mean rain 2 to 6 hours earlier
    step(l, k, r, g, e) = 0.9 * l + 0.1 * 118 + g * inflow(r, k) + e
    level = zeros(nh)
    l = 118.0
    for k in 1:nh
        l = step(l, k, rain, 2.4, 0.5 * randn(rng))
        level[k] = round(l; digits=1)
    end
    obs = [(; t=t0 + Hour(k - 1), level=level[k]) for k in 1:nh]
    precip = [(; t=t0 + Hour(k - 1), mm=round(rain[k]; digits=1)) for k in 1:nh]
    # The forecast knows the rain up to the issue time; after it, either no rain or the
    # rain of the issue hour continues. 400 simulations with an uncertain response.
    fc = NamedTuple[]
    for (scenario, future) in (("No further rain", 0.0), ("Rain persists", rain[issue]))
        sims = zeros(400, nh - issue)
        for s in 1:400
            g = 2.4 * exp(0.15 * randn(rng))
            r = [k <= issue ? rain[k] : future for k in 1:nh]
            l = level[issue]
            for (j, k) in enumerate(issue+1:nh)
                l = step(l, k, r, g, 0.5 * randn(rng))
                sims[s, j] = l
            end
        end
        for (j, k) in enumerate(issue+1:nh)
            q = quantile(sims[:, j], [0.025, 0.25, 0.5, 0.75, 0.975])
            push!(fc, (; t=t0 + Hour(k - 1), scenario, q025=q[1], q25=q[2], q50=q[3], q75=q[4], q975=q[5]))
        end
    end
    (; obs, precip, fc, start=t0, issue=t0 + Hour(issue - 1), stop=t0 + Hour(nh - 1))
end

# ---------------------------------------------------------------------------
# 3. Faceted comparison: estimation error of two methods over sample size in
#    three noise settings; ten simulated runs per cell.
# ---------------------------------------------------------------------------
function comparison_rows()
    rng = Xoshiro(33)
    runs = NamedTuple[]
    summary = NamedTuple[]
    reference = NamedTuple[]
    for (noise, sigma) in (("Low noise", 0.5), ("Medium noise", 1.0), ("High noise", 2.0))
        for n in (25, 50, 100, 200, 400)
            push!(reference, (; noise, n, bound=sigma / sqrt(n)))
            for (method, eff) in (("Method A", 1.15), ("Method B", 1.0 + 0.6 / sqrt(n / 25)))
                errs = [eff * sigma / sqrt(n) * sqrt(sum(abs2, randn(rng, 4)) / 4) for _ in 1:10]
                for e in errs
                    push!(runs, (; noise, n, method, rmse=e))
                end
                q = quantile(errs, [0.025, 0.25, 0.5, 0.75, 0.975])
                push!(summary, (; noise, n, method, cell="$noise|$n", q025=q[1], q25=q[2], q50=q[3], q75=q[4], q975=q[5]))
            end
        end
    end
    (; runs, summary, reference)
end

const IR = interval_rows()
const FR = forecast_rows()
const CR = comparison_rows()

# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------
const LEGEND_TOP = config(config=Dict("legend" => Dict("orient" => "top", "title" => nothing)))
# A y axis of fixed minimum width, so figures stacked on one page put their plot
# areas at the same x; facet titles bold at the left. Tick counts, type sizes and
# log-axis labels are AoV's defaults.
const AXES = config(config=Dict("axisY" => Dict("minExtent" => 44)))
const TYPE = config(config=Dict("legend" => Dict("symbolSize" => 120),
    "header" => Dict("labelFontSize" => 13, "labelFontWeight" => "bold", "labelAnchor" => "start")))
const LOOK = LEGEND_TOP * AXES * TYPE
# A single series coloured by a constant column: it takes the page's first
# category colour (light or dark) and gets one legend entry that names it.
const EST = "Median with 50 % and 95 % intervals"

# 1a. The chart column of the interval table: one small chart per site on the
#     scale every row shares; the truth as a tick, zero as a dashed line.
interval_cells() = cell_charts(
    (data(IR) * mapping(:q50 => "Change (%/yr)"; color=:what, layout=:site) * pointinterval(bands=BANDS) +
     data(IR) * mapping(:truth; layout=:site) * visual(VLines; color=:ink, linewidth=2) +
     data([(; zero=0.0)]) * mapping(:zero) * visual(VLines; color="#8a8a85", linestyle=:dash)) *
    config(width=300, height=20);
    total=rs -> first(rs).q50, label=_ -> "", id="site-cells")

# 1b. The same estimates as a forest plot, hover-linked to a table.
const REGIONS = ["North", "Central", "South"]
forest() = (
    data([(; zero=0.0)]) * mapping(:zero) * visual(VLines; color="#8a8a85", linestyle=:dash) +
    data(IR) * mapping(:q50 => "Change (%/yr)"; y=:site => "Site", color=:what => "", row=:region => sorter(REGIONS) => "") *
        pointinterval(bands=BANDS) +
    data(IR) * mapping(:truth => "True value", :site => "Site"; row=:region => sorter(REGIONS) => "") *
        visual(Scatter; color=:ink, shape="M0,-1L0,1", strokeWidth=2, filled=false, markersize=14)
) * LOOK * config(height=110, facet=(; linkyaxes=:none), link=(; group="sites", key=:site))

# 2. The forecast figure and its precipitation panel.
const TIME_X = config(axis=(; limits=((FR.start, FR.stop), nothing)))
forecast() = (
    data([(; from=FR.issue, to=FR.stop)]) * mapping(:from, :to) * visual(VSpan; color=:ink, alpha=0.06) +
    data([(; t=FR.issue)]) * mapping(:t) * visual(VLines; color=:ink, linestyle=:dash) +
    data([(; t=FR.issue, y=maximum(r.q975 for r in FR.fc), text="Forecast issued")]) * mapping(:t, :y; text=:text) *
        visual(Makie.Text; align=(:left, :bottom), offset=(4, 0), fontsize=11, color=:ink) +
    data(FR.fc) * mapping(:t => "Time (UTC)", :q50 => "Water level (cm)"; color=:scenario => "Forecast") *
        lineribbon(bands=BANDS) +
    data(FR.obs) * mapping(:t => "Time (UTC)", :level => "Water level (cm)") *
        (visual(Lines; color=:ink, linewidth=1) + visual(Scatter; color=:ink, markersize=5))
) * LOOK * TIME_X * config(height=300, link=(; group="hours", key=:t))

precipitation() = (
    data(FR.precip) * mapping(:t => "Time (UTC)", :mm => "mm/h") * visual(BarPlot; color="#5598e7")
) * LOOK * TIME_X * config(height=80, link=(; group="hours", key=:t), scales=scales(Y=(; zero=true)),
                           readout=true)

# 3. The faceted comparison.
const NOISE = sorter(["Low noise", "Medium noise", "High noise"]) => ""
comparison() = (
    data(CR.reference) * mapping(:n => "Sample size", :bound => "Estimation error (RMSE)"; col=:noise => NOISE) *
        visual(Lines; color=:ink, linestyle=:dash, linewidth=1.5) +
    data(CR.runs) * mapping(:n => "Sample size", :rmse => "Estimation error (RMSE)"; color=:method => "Method", col=:noise => NOISE) *
        visual(Scatter; markersize=4, alpha=0.35) +
    data(CR.summary) * mapping(:n => "Sample size", :q50 => "Estimation error (RMSE)"; color=:method => "Method", col=:noise => NOISE) *
        lineribbon(bands=BANDS)
) * LOOK * config(height=240, scales=scales(X=(; scale=log10), Y=(; scale=log10)),
                  link=(; group="cells", key=:cell))

# ---------------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------------
const TEXTS = table_texts(:en)

function interval_table(cells)
    master_detail_table(["Site", "Change (%/yr), median with 50 % and 95 % intervals", "Estimate (95 % interval)", "True value", "Interval excludes 0"],
        IR; key=r -> "cell-" * r.site, link="sites-cells", link_key=r -> r.site,
        master=r -> (h.td(r.site), cells[r.site], IntervalEstimate(r.q50, r.q025, r.q975), r.truth, h.td(r.excludes_zero)),
        groupings=["Region" => r -> r.region, "None" => nothing], group_by=["Region"],
        group_order=["Region" => REGIONS], initially_open=true, texts=TEXTS, id="site-cells-table")
end

interval_forest_table() = render_table(
    [(; Site=r.site, Region=r.region, var"Estimate (95 % interval)"=IntervalEstimate(r.q50, r.q025, r.q975), var"True value"=r.truth) for r in IR];
    link="sites", link_key=r -> r.Site, texts=TEXTS, id="site-forest-table")

function forecast_table()
    byt = Dict{Tuple{DateTime,String},Any}((r.t, r.scenario) => r for r in FR.fc)
    rain = Dict(r.t => r.mm for r in FR.precip)
    rows = [(; Time=Dates.format(o.t, "yyyy-mm-dd HH:MM"),
               Observed=o.level,
               var"No further rain (95 % interval)"=(r = get(byt, (o.t, "No further rain"), nothing); isnothing(r) ? nothing : IntervalEstimate(r.q50, r.q025, r.q975)),
               var"Rain persists (95 % interval)"=(r = get(byt, (o.t, "Rain persists"), nothing); isnothing(r) ? nothing : IntervalEstimate(r.q50, r.q025, r.q975)),
               var"Precipitation (mm/h)"=rain[o.t], key=string(o.t)) for o in FR.obs]
    render_table([Base.structdiff(r, NamedTuple{(:key,)}) for r in rows]; link="hours",
        link_key=r -> string(DateTime(r.Time, dateformat"yyyy-mm-dd HH:MM")), texts=TEXTS, id="forecast-table")
end

function comparison_table()
    ref = Dict((r.noise, r.n) => r.bound for r in CR.reference)
    s = Dict((r.noise, r.n, r.method) => r for r in CR.summary)
    items = [(; noise, n, cell="$noise|$n") for noise in unique(r.noise for r in CR.summary) for n in (25, 50, 100, 200, 400)]
    iv(x) = IntervalEstimate(x.q50, x.q025, x.q975)
    master_detail_table(["Sample size", "Method A (95 % of runs)", "Method B (95 % of runs)", "Reference"], items;
        key=x -> "cmp-" * replace(x.cell, r"[^A-Za-z0-9]" => "-"), link="cells", link_key=x -> x.cell,
        master=x -> (h.td(string(x.n)), iv(s[(x.noise, x.n, "Method A")]), iv(s[(x.noise, x.n, "Method B")]), number_cell(ref[(x.noise, x.n)]; sigdigits=2, texts=TEXTS)),
        groupings=["Noise" => x -> x.noise, "None" => nothing], group_by=["Noise"], initially_open=true,
        texts=TEXTS, id="cmp-table")
end

# ---------------------------------------------------------------------------
# Page
# ---------------------------------------------------------------------------
const PAGE_CSS = """
:root { --aov-grid-color: light-dark(#e6e5e1, #34342f); --aov-domain-color: none; --aov-tick-color: none;
        --aov-view-color: none; --aov-axis-label-color: light-dark(#52514e, #c3c2b7);
        --aov-axis-title-color: light-dark(#52514e, #c3c2b7); --aov-legend-label-color: light-dark(#52514e, #c3c2b7);
        --aov-header-label-color: currentColor;
        --aov-category: light-dark(#2a78d6, #3987e5), light-dark(#eb6834, #d95926), light-dark(#1baf7a, #199e70); }
html { font-size: 100%; }
main.container { max-width: 1500px; }
section.view { margin: 2.2rem 0 3rem; }
section.view > p.lead { max-width: 70rem; }
/* A long table stays in a bounded box under its chart, so hovering its rows keeps the chart in view. */
.bounded { max-height: 26rem; overflow: auto; border: 1px solid var(--pico-muted-border-color); border-radius: 6px; }
"""

function page(body)
    htmx(h.main(; class="container")(body...); pico_version="2", title="AoV result views",
        extra_head=(vega_head(), h.style(PAGE_CSS)))
end

function build()
    cells = interval_cells()
    body = Any[
        h.h1("Result views with AlgebraOfVega"),
        h.p("Synthetic data, generated by examples/results-views/build.jl. Each view uses only AoV's and HTMXObjects' public API."),
        h.section(; class="view")(
            h.h2("1. Estimates with intervals"),
            h.p(; class="lead")("Change per site with its median, 50 % and 95 % intervals; the true value of the synthetic study as a tick, zero dashed."),
            h.h3("1a. Small charts in the rows of a grouped table (cell_charts)"),
            interval_table(cells),
            h.h3("1b. A forest plot linked to a table (pointinterval + config(link))"),
            with_plot_caption(forest(), CaptionSpec(; title="Change per site", short="median, 50 % and 95 % intervals; tick: true value"); plot_id="forest"),
            h.div(; class="bounded")(interval_forest_table())),
        h.section(; class="view")(
            h.h2("2. Forecast over time"),
            h.p(; class="lead")("Observed level, then a 12-hour forecast from the issue time under two scenarios (median, 50 % and 95 % bands); precipitation below."),
            with_plot_caption(forecast(), CaptionSpec(; title="Water level", short="observed and forecast"); plot_id="forecast"),
            with_plot_caption(precipitation(), CaptionSpec(; title="Precipitation", short="hourly"); plot_id="precip"),
            h.div(; class="bounded")(forecast_table())),
        h.section(; class="view")(
            h.h2("3. Faceted comparison"),
            h.p(; class="lead")("Estimation error of two methods over sample size, in three noise settings: single runs as dots, median with 50 % and 95 % of runs as bands, the reference curve dashed."),
            with_plot_caption(comparison(), CaptionSpec(; title="Estimation error", short="per noise setting"); plot_id="comparison"),
            comparison_table()),
    ]
    html = repr(MIME"text/html"(), page(body))
    write(joinpath(OUT, "index.html"), html)
    for (name, f) in (("forest", forest()), ("forecast", forecast()), ("precipitation", precipitation()), ("comparison", comparison()))
        try
            vsave(f, joinpath(OUT, "$name.svg"))
        catch e
            @warn "vsave failed" name exception=(e, catch_backtrace())
        end
    end
    OUT
end

if abspath(PROGRAM_FILE) == @__FILE__
    println(build())
end
