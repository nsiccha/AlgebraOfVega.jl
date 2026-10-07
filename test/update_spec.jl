using TestItemRunner

"""
Refreshing an AoV-lowered plot in place.

Regression (snag `update-data-on-a-06f2e371`): a captioned, auto-remapped
`pointinterval` figure (plus a `VLines` guide layer) embeds a lowered dataset —
interval summary rows merged with the guide rows under `__src` filters. Pushing
the next raw table with `update_data` inserted it verbatim: no `__point__`,
`lo_*`/`hi_*` or `__src`, so every layer matched nothing and the figure went
blank with no error. `update_spec(id, spec; auto_remap)` now re-lowers the new
spec server-side; the runtime re-applies the reader's picker assignment and
swaps the data into the live view when only data changed (same view: zoom,
legend selection and canvas survive), re-embedding on structural change. Raw
`update_data`/`append_data` rows that lack a placement field the lowered rows
carry are refused with a console error instead of blanking the plot.
"""
@testitem "update_spec refreshes lowered plots in place" tags=[:incremental, :auto_remap, :browser, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    @test !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt))
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]

    # Synthetic stand-in for the reporter's measurement table: three models in
    # two families, one value column per metric facet.
    function measurements(scale; metrics=("density", "gradient"), models=("m1", "m2", "m3"))
        fam = Dict("m1" => "F1", "m2" => "F1", "m3" => "F2", "m4" => "F2")
        rows = [(; model=m, key=m, family=fam[m], group="G" * m[end:end], metric=t, value=scale * k * i)
            for m in models for (k, t) in enumerate(metrics) for i in 1:5]
        (; (c => [getproperty(r, c) for r in rows] for c in (:model, :key, :family, :group, :metric, :value))...)
    end
    function figure(t)
        guides = (; value=fill(2.0, length(unique(t.metric))), metric=unique(t.metric))
        (data(t) * mapping(:value => "Value"; y=:model => "Model", color=:family => "Family",
                col=:metric => "Measurement") * pointinterval() +
            data(guides) * mapping(:value; col=:metric => "Measurement") * visual(VLines; color="#d94848")) *
            config(height=140, scales=scales(X=(; scale=log10)), facet=(; linkxaxes=:none, linkyaxes=:none))
    end
    remap = (; dims=["family" => "Family", "group" => "Model group"], off=["family", "group"],
        pinned=:row, fixed=Dict(:column => "metric"))
    id = "refresh-interval"
    lowered(t) = AlgebraOfVega._embed_spec(AlgebraOfVega._auto_remap_lowering(figure(t); remap...).vl)
    intervals(t) = [[r["model"], r["metric"], r["lo_0_95_"]] for r in lowered(t)["data"]["values"]
        if haskey(r, "lo_0_95_")]

    # Server side: update_spec lowers exactly like the first render.
    @test occursin("AoV.updateSpec('$id', ", html(update_spec(id, figure(measurements(1.0)); auto_remap=remap)))
    @test JSON.parse(match(r"AoV\.updateSpec\('[^']*', (\{.*\}), \{actions"s,
            html(update_spec(id, figure(measurements(2.0)); auto_remap=remap))).captures[1]) ==
        JSON.parse(JSON.json(AlgebraOfVega._wire_spec(lowered(measurements(2.0)))))

    plain = data((; x=[1.0, 2.0, 3.0], y=[1.0, 4.0, 9.0], g=["a", "b", "a"])) *
        mapping(:x, :y; color=:g) * visual(Scatter) * config(height=200)
    updates = Dict(
        "raw" => script(update_data(id, measurements(2.0))),
        "same" => script(update_spec(id, figure(measurements(2.0)); auto_remap=remap)),
        "grow" => script(update_spec(id, figure(measurements(3.0; metrics=("density", "gradient", "hessian")));
            auto_remap=remap)),
        "grow_same" => script(update_spec(id, figure(measurements(4.0; metrics=("density", "gradient", "hessian")));
            auto_remap=remap)),
        "plain_update" => script(update_data("refresh-plain", (; x=[1.0, 2.0], y=[2.0, 3.0], g=["a", "b"]))),
        "plain_append_uncolored" => script(append_data("refresh-plain", (; x=[5.0], y=[5.0]))),
        "plain_append_unplaced" => script(append_data("refresh-plain", (; y=[6.0], g=["a"]))),
        "plain_spec" => script(update_spec("refresh-plain",
            data((; x=[1.0, 2.0, 3.0, 4.0], y=[4.0, 3.0, 2.0, 1.0], g=["a", "b", "a", "b"])) *
            mapping(:x, :y; color=:g) * visual(Scatter) * config(height=200))))
    expected = Dict("same" => intervals(measurements(2.0)),
        "grow_same" => intervals(measurements(4.0; metrics=("density", "gradient", "hessian"))))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-update-spec-") do dir
            page = [with_plot_caption(figure(measurements(1.0)), "Refresh"; plot_id=id, auto_remap=remap),
                vdraw(plain; id="refresh-plain")]
            runtime = join(html(n) for n in vega_head(source=:inline))
            payload = replace(JSON.json((; updates, expected)), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "update_spec.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>" *
                "embed(el,spec,Object.assign({},opts,{renderer:'svg'}));</script>" *
                join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,1100
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-update-spec-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 40
                @test isempty(report["failures"])
                @info "update_spec browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
