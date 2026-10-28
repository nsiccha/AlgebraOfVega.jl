using TestItemRunner

"""
A plot whose data changes is laid out again, as a render of the same rows is.

Snag `drew-a-scatter-f-1c34853b`: a scatter drawn from a typed-empty table and
filled by `append_data` (aov-use §11b) lost both axis titles once its first
rows arrived, and the y labels were cut off on the left. Vega sizes a view
(the autosize padding around the plot, and the plot width of an autosize
`fit` view) only when it is embedded or resized: `autosize.resize` is false,
so a plain run after a data change kept the layout of the empty first paint,
which has no axis labels. The labels and titles the rows brought were drawn
outside the canvas. The same held for `update_spec`'s in-place data swap and
for rows whose labels are wider than the first paint's. A data change now runs
the view with `resize()`, and a plot the runtime sizes to its container is
corrected once more when that relayout widens it past its column.
"""
@testitem "plots whose data changes are laid out again" tags=[:incremental, :browser, :regression] begin
    using AlgebraOfVega, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]

    dose = [10.0, 20.0, 40.0, 80.0, 160.0, 320.0]
    auc = round.(3 .* dose .^ 0.8)
    typed_empty = (; dose=Float64[], auc=Float64[])
    full = (; dose, auc)
    row(i) = (; dose=dose[i:i], auc=auc[i:i])
    sweep(t) = data(t) * mapping(:dose => "Dose (mg)", :auc => "AUC")
    appends(id) = [script(append_data(id, row(i))) for i in eachindex(dose)]
    small = (; dose=[1.0, 2.0], auc=[1.0, 2.0])
    wide = (; dose=[1.0, 2.0, 3000.0], auc=[1.0, 2.0, 123456.0])

    # Each case: the plot that changes, the same spec drawn with its final rows
    # (`<id>-full`), and the scripts that change it.
    cases = [
        # The report: an authored width, filled one row at a time.
        ("explicit", t -> sweep(t) * visual(Scatter) * config(width=480, height=280, title="Dose–response"),
            typed_empty, full, appends("explicit")),
        # A single view sized by Vega-Lite to its container (autosize fit).
        ("container", t -> sweep(t) * visual(Scatter) * config(height=200), typed_empty, full, appends("container")),
        # A layered plot the runtime sizes to its container.
        ("layered", t -> sweep(t) * (visual(Scatter) + visual(Lines)) * config(height=200),
            typed_empty, full, appends("layered")),
        # update_spec's in-place swap of the rows.
        ("swap", t -> sweep(t) * visual(Scatter) * config(width=480, height=200), typed_empty, full,
            [script(update_spec("swap", sweep(full) * visual(Scatter) * config(width=480, height=200)))]),
        # Not empty at first: rows whose labels are wider than the first paint's.
        ("wider", t -> sweep(t) * visual(Scatter) * config(width=480, height=200), small, wide,
            [script(append_data("wider", (; dose=[3000.0], auc=[123456.0])))]),
        # update_data and replace_data take the same path as append_data.
        ("update", t -> sweep(t) * visual(Scatter) * config(width=480, height=200), typed_empty, full,
            [script(update_data("update", full))]),
    ]

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-data-relayout-") do dir
            column(n) = "<div style='width:700px'>" * html(n) * "</div>"
            page = join(column(vdraw(spec(first_rows); id)) * column(vdraw(spec(last_rows); id=id * "-full"))
                for (id, spec, first_rows, last_rows, _) in cases)
            fixture = (; cases=[(; id, steps) for (id, _, _, _, steps) in cases])
            runtime = join(html(n) for n in vega_head(source=:inline))
            payload = replace(JSON.json(fixture), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "data_relayout.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                "<script>window.AOV_EMBEDS={};const embed=vegaEmbed;vegaEmbed=(el,spec,opts)=>{" *
                "const k=String(el).slice(1);AOV_EMBEDS[k]=(AOV_EMBEDS[k]||0)+1;return embed(el,spec,opts);};</script>" *
                page * "<script>window.AOV_FIXTURE=" * payload * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1400,3000
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-data-relayout-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "data relayout browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
