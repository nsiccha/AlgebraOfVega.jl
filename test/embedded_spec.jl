using TestItemRunner

"""
`embedded_spec` reads back the spec a page hands the browser, with its rows.

Regression (snag `bruno-s-web-pkpd-9b8d0076`): Bruno's web-pkpd test checked
that a picker figure's HTML hands the browser the same rows as its exported
JSON, by scraping the `AoV.embed('<id>', …)` call and comparing its
`data.values`. Once a faceted figure's merged tables travelled as compact
column parts (commit `b4e6407`), `data.values` in the page was
`{"n": …, "parts": […]}`: the comparison failed and filtering it as rows threw
`MethodError: no method matching haskey(::Pair{String, Any}, ::String)`. The
column form is internal, and there was no public reading of it.
"""
@testitem "embedded_spec reads the rows a page hands the browser" tags=[:incremental, :regression] begin
    using AlgebraOfVega, HTMXObjects, JSON
    h = AlgebraOfVega.h
    html(x) = repr(MIME"text/html"(), x)

    # Object.is: a number compares by its Float64 bits, anything else as is.
    same(a, b) = a isa Number && b isa Number && !(a isa Bool) && !(b isa Bool) ?
        Float64(a) === Float64(b) : isequal(a, b)
    same_row(x, y) = Set(keys(x)) == Set(keys(y)) && all(k -> same(x[k], y[k]), keys(x))
    same_rows(xs, ys) = length(xs) == length(ys) && all(splat(same_row), zip(xs, ys))
    # Every inline dataset of a spec, by where it sits.
    function inline_rows(v, path="", found=Dict{String,Any}())
        if v isa AbstractVector
            foreach(((i, x),) -> inline_rows(x, "$path[$i]", found), enumerate(v))
        elseif v isa AbstractDict
            for (k, x) in v
                if k == "data" && x isa AbstractDict && haskey(x, "values")
                    found["$path.data"] = x["values"]
                elseif k == "datasets" && x isa AbstractDict
                    foreach(((n, rows),) -> (found["$path.datasets.$n"] = rows), x)
                else
                    inline_rows(x, "$path.$k", found)
                end
            end
        end
        found
    end
    function same_data(embedded, exported)
        a, b = inline_rows(embedded), inline_rows(exported)
        keys(a) == keys(b) && all(k -> same_rows(a[k], b[k]), keys(a))
    end

    # The reporter's figure: posterior bands per source, observations of
    # another table with their own columns, and dose rules, faceted by source
    # through the picker. The three tables merge into one `__src`-tagged
    # dataset that travels in parts.
    days = collect(0.0:2.0:96.0)
    nd = length(days)
    sources = ["ECG", "Plasma"]
    function figure(s)
        bands = (; time_hours=repeat(days, 2), source=repeat(sources, inner=nd),
            pred_source=fill("in_sample", 2nd),
            q50=[s * (1 + sin(t / 9)) + 0.1i for (i, t) in enumerate(repeat(days, 2))])
        bands = merge(bands, (; q025=bands.q50 .- 1.5, q975=bands.q50 .+ 1.5, q25=bands.q50 .- 0.5, q75=bands.q50 .+ 0.5))
        observed = (; time_hours=[4.0, 8.0, 24.0, 4.0, 8.0, 24.0], source=repeat(sources, inner=3),
            value=s .* [1.1, 1.9, 0.7, 2.2, 3.1, 1.4], observation_status=["observed", "censored", "observed",
            "observed", "observed", "censored"])
        doses = (; time_hours=[0.0, 24.0, 0.0, 24.0], source=repeat(sources, inner=2), treatment=["A", "B", "A", "B"])
        (data(bands) * mapping(:time_hours => "Time (h)", :q50 => "Response"; row=:source) *
            lineribbon(bands=[:q025 => :q975, :q25 => :q75]) +
         data(observed) * mapping(:time_hours, :value; row=:source, color=:observation_status) * visual(Scatter) +
         data(doses) * mapping(:time_hours; row=:source) * visual(VLines; color=:ink, linestyle=:dash)) *
            config(height=140)
    end
    remap = (; dims=["source" => "Source"], pinned=:row, fixed=Dict(:row => "source"))
    exported(s) = JSON.parse(to_json(figure(s); auto_remap=remap))

    fig = with_plot_caption(figure(1.0), "Predictions"; plot_id="qt-ppc-plot", auto_remap=remap)
    page = html(fig)
    @test occursin("\"parts\":", page)            # control: the merged rows travel in parts
    embedded = embedded_spec(fig, "qt-ppc-plot")
    rows = embedded["data"]["values"]
    @test rows isa AbstractVector && all(r -> r isa AbstractDict, rows)
    @test rows == exported(1.0)["data"]["values"]
    @test same_data(embedded, exported(1.0))
    @test embedded_spec(page, "qt-ppc-plot") == embedded   # the HTML string reads the same
    # The reporter's filters work on the rows.
    observed = filter(r -> haskey(r, "value"), rows)
    @test length(observed) == 6
    @test Set(r["observation_status"] for r in observed) == Set(["observed", "censored"])
    @test all(r -> !haskey(r, "observation_status"), filter(r -> !haskey(r, "value"), rows))

    # `update_spec` hands the browser a spec too.
    update = update_spec("qt-ppc-plot", figure(2.0); auto_remap=remap)
    @test occursin("\"parts\":", html(update))
    @test same_data(embedded_spec(update, "qt-ppc-plot"), exported(2.0))

    # A plain figure, and one table in compact columns (a sequence, a constant,
    # runs): one plot needs no id.
    grid = range(0, 28, length=673)
    plain = data((; x=collect(grid), y=sin.(grid), scenario=fill("A", 673))) *
        mapping(:x, :y; color=:scenario) * visual(Lines)
    node = vdraw(plain)
    @test occursin("\"start\":", html(node))
    @test same_data(embedded_spec(node), JSON.parse(to_json(plain)))
    @test embedded_spec(node)["data"]["values"][end]["x"] === 28.0
    @test same_data(embedded_spec(vdraw(figure(1.0); id="two")), JSON.parse(to_json(figure(1.0))))

    # A stack of panels.
    stack = vconcat(plain * config(height=80), data((; x=collect(grid), mm=cos.(grid) .^ 2)) *
        mapping(:x, :mm) * visual(BarPlot) * config(height=60))
    @test same_data(embedded_spec(vdraw(stack; id="stack"), "stack"), JSON.parse(to_json(stack)))

    # Loud when the HTML holds no spec, or several, for the id.
    two = h.div(vdraw(plain; id="a"), vdraw(plain; id="b"))
    @test same_data(embedded_spec(two, "b"), JSON.parse(to_json(plain)))
    err(f) = try f(); "" catch e; e isa ArgumentError ? e.msg : rethrow() end
    @test occursin("pass the plot id", err(() -> embedded_spec(two)))
    @test occursin("1 for \"a\", 1 for \"b\"", err(() -> embedded_spec(two, "c")))
    @test occursin("2 for \"a\"", err(() -> embedded_spec(html(vdraw(plain; id="a")) * html(update_spec("a", plain)), "a")))
    @test occursin("no AoV plot spec", err(() -> embedded_spec("<p>no plot</p>")))
end
