using TestItemRunner

# An analysis lowers to several Vega-Lite layers over one summary table (a
# ribbon's bands and median line, per colour group). Layered with anything else,
# `layers_to_vl` flattened those layers into the figure and gave each the
# summary as its own `data`, so the JSON carried the table once per layer: one
# reference line made a three-colour ribbon 8.4 times larger (snag
# `one-extra-layer-dfa741c3`). The shared table is now the figure's top-level
# `data`, which those layers inherit, as when the ribbon is drawn alone.
@testsnippet AoVSharedLayerDataFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    using JSON

    # Every Vega-Lite unit (a dict with a `mark`), in emission order.
    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            foreach(c -> units(c, out), get(node, key, Any[]))
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    # How often each distinct `values` vector is written: the number of
    # `data` objects holding it.
    function copies(node, seen=IdDict{Any,Int}())
        if node isa AbstractDict
            for (k, v) in node
                k == "_aov" && continue
                if k == "data" && v isa AbstractDict && haskey(v, "values")
                    seen[v["values"]] = get(seen, v["values"], 0) + 1
                else
                    copies(v, seen)
                end
            end
        elseif node isa AbstractVector
            foreach(v -> copies(v, seen), node)
        end
        seen
    end

    scenarios = ["A", "B", "C"]
    rows(n) = (; scenario=repeat(scenarios[1:n], inner=50), day=repeat(collect(0.0:49.0), n),
        lo=repeat(sin.(0:49) .- 1, n), mid=repeat(sin.(0:49), n), hi=repeat(sin.(0:49) .+ 1, n))
    ribbon(n) = data(rows(n)) * mapping(:day, :mid => "Change (%)"; (n > 1 ? (; color=:scenario) : (;))...) *
        lineribbon(bands=[:lo => :hi])
    hline = data((; level=[0.0])) * mapping(:level => "Change (%)") *
        visual(HLines; color=:ink, linewidth=0.5, inspectable=false)
end

@testitem "a table several layers draw is written once" setup=[AoVSharedLayerDataFixtures] tags=[:regression, :translation, :tidybayes] begin
    for n in (1, 3)
        alone = to_vegalite(ribbon(n))
        vl = to_vegalite(ribbon(n) + hline)
        # The ribbon's summary is the figure's top-level data, written once.
        @test vl["data"]["values"] == alone["data"]["values"]
        @test sort(collect(values(copies(vl)))) == [1, 1]
        ribbon_units = filter(u -> get(u, "_lr_layer", false), units(vl))
        @test length(ribbon_units) == (n == 1 ? 2 : 2n)
        @test !any(u -> haskey(u, "data"), ribbon_units)
        # The reference line keeps its own row.
        marktype(u) = (m = u["mark"]; m isa AbstractDict ? m["type"] : m)
        rule = only(filter(u -> marktype(u) == "rule", units(vl)))
        @test length(rule["data"]["values"]) == 1
        # One more layer adds its own row, not another copy of the ribbon's.
        @test length(to_json(ribbon(n) + hline)) < length(to_json(ribbon(n))) + 2_000
    end
end

@testitem "only a table every layer names is hoisted, the most used" setup=[AoVSharedLayerDataFixtures] tags=[:regression, :translation] begin
    hoist! = AlgebraOfVega._hoist_shared_data!
    t(n) = Dict{String,Any}("values" => Any[Dict("x" => i) for i in 1:n])
    layer(d) = Dict{String,Any}("mark" => "line", "data" => d)
    a, b, c = t(5), t(10), t(1)
    # The most layers win; the other shared table keeps its copies.
    ls = [layer(a), layer(b), layer(a), layer(b), layer(a), layer(c)]
    spec = hoist!(Dict{String,Any}(), ls)
    @test spec["data"] === a
    @test [get(l, "data", nothing) for l in ls] == [nothing, b, nothing, b, nothing, c]
    # Equal use: the larger table.
    ls = [layer(a), layer(b), layer(a), layer(b)]
    @test hoist!(Dict{String,Any}(), ls)["data"] === b
    # A table one layer draws, or equal tables that are separate objects, stay.
    ls = [layer(a), layer(t(5)), layer(c)]
    @test !haskey(hoist!(Dict{String,Any}(), ls), "data")
    @test all(l -> haskey(l, "data"), ls)
    # A layer without data would inherit the hoisted rows: nothing moves.
    ls = [layer(a), layer(a), Dict{String,Any}("mark" => "rule")]
    @test !haskey(hoist!(Dict{String,Any}(), ls), "data")
    @test haskey(ls[1], "data") && haskey(ls[2], "data")
    # Rows read from an address are not inline: not hoisted.
    url = Dict{String,Any}("url" => "/rows.json")
    ls = [layer(url), layer(url)]
    @test !haskey(hoist!(Dict{String,Any}(), ls), "data")
end
