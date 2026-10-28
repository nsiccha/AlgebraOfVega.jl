using TestItemRunner

# `a * config(encoding=…) + b` scopes the encoding override to `a`: `*` binds
# tighter than `+`, exactly as `a * visual(...) + b` styles only `a`. Before, every
# summand's `config` was merged into one spec-level config, so one summand's
# tooltip replaced every other layer's tooltip, and a later whole-spec
# `config(encoding=…)` replaced all summand tooltips wholesale
# (snag `per-layer-toolti-162cb718`).
@testsnippet AoVLayerEncodingFixtures begin
    using AlgebraOfVega
    using AlgebraOfGraphics

    # Every Vega-Lite unit (a dict with a `mark`), in emission order.
    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            for child in get(node, key, Any[])
                units(child, out)
            end
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    tooltip_fields(unit) = [string(t["field"]) for t in get(unit["encoding"], "tooltip", Any[])]
    rules(vl) = filter(u -> u["mark"] isa Dict && u["mark"]["type"] == "rule", units(vl))
    points(vl) = filter(u -> (u["mark"] isa Dict ? u["mark"]["type"] : u["mark"]) == "point", units(vl))
    tip(fields...) = [Dict("field" => f, "title" => uppercase(f)) for f in fields]

    # A posterior summary per group, pre-aggregated (median + three bands).
    posterior_rows = (; group=["A", "B", "C"], median=[0.2, 0.5, 0.7],
        q025=[0.1, 0.3, 0.5], q975=[0.4, 0.7, 0.9], q10=[0.12, 0.35, 0.55],
        q90=[0.35, 0.65, 0.85], q25=[0.15, 0.4, 0.6], q75=[0.3, 0.6, 0.8],
        n_finite=[100, 100, 98])
    bands = [:q025 => :q975, :q10 => :q90, :q25 => :q75]
    # Observed summaries that only some layers carry.
    observed_rows = (; group=["A", "B"], value=[0.25, 0.45], n_obs=[12, 9],
        label=["3/12", "4/9"])
end

@testitem "summand encoding override stays on its own layers" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    # Dose-response shape: a posterior interval layer plus observed marks that
    # carry their own tooltip.
    intervals = data(posterior_rows) * mapping(:group, :median => "Fraction") *
        pointinterval(bands=bands, orientation=:vertical)
    marks = data(observed_rows) * mapping(:group, :value => "Fraction") *
        visual(Scatter; color="black") *
        config(encoding=Dict(:tooltip => tip("group", "n_obs", "label")))
    vl = to_vegalite((intervals + marks) * config(height=300))

    us = units(vl)
    @test length(us) == 5                       # 3 rules + median + observed
    @test vl["height"] == 300                   # view-level config still applies
    # The posterior keeps AoV's automatic interval tooltip on all four of its
    # units — it never sees the observed marks' fields.
    for u in us[1:4]
        @test tooltip_fields(u) == ["median", "group", "q025", "q975"]
    end
    # The observed marks show exactly their own tooltip.
    @test tooltip_fields(us[5]) == ["group", "n_obs", "label"]
    @test us[5]["encoding"]["tooltip"][3]["title"] == "LABEL"
end

@testitem "summand tooltips survive a later whole-spec encoding" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    # Waterfall shape: every summand carries a different tooltip, and the whole
    # figure then gets its own encoding override (a y sort). The whole-spec
    # override used to replace every summand tooltip.
    order = ["C", "A", "B"]
    posterior = data(posterior_rows) * mapping(:median => "Change"; y=:group => "Group") *
        pointinterval(bands=bands) *
        config(encoding=Dict(:tooltip => tip("group", "median", "q025", "q975", "n_finite")))
    exact = data(observed_rows) * mapping(:value => "Change"; y=:group => "Group") *
        visual(Scatter; color="black") *
        config(encoding=Dict(:tooltip => tip("group", "value")))
    bounded = data(observed_rows) * mapping(:value => "Change"; y=:group => "Group") *
        visual(Scatter; filled=false, color="black") *
        config(encoding=Dict(:tooltip => tip("group", "label")))
    spec = (posterior + exact + bounded) *
        config(height=200, encoding=Dict("y" => Dict("sort" => order)))
    vl = to_vegalite(spec)

    us = units(vl)
    @test length(us) == 6                       # 3 rules + median + 2 observed
    for u in us[1:4]
        @test tooltip_fields(u) == ["group", "median", "q025", "q975", "n_finite"]
    end
    @test tooltip_fields(us[5]) == ["group", "value"]
    @test tooltip_fields(us[6]) == ["group", "label"]
    # The whole-spec y sort reaches every layer, and the y field stays intact.
    for u in us
        @test u["encoding"]["y"]["sort"] == order
        @test u["encoding"]["y"]["field"] == "group"
    end
end

@testitem "whole-spec encoding override still reaches every layer" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    a = data(observed_rows) * mapping(:group, :value) * visual(Scatter)
    b = data(observed_rows) * mapping(:group, :value) * visual(Lines)
    shared = tip("group", "value", "n_obs")

    # `(a + b) * config(encoding=E)` and `a + b` then `* config(encoding=E)` — the
    # override is applied to the sum, so every layer gets it.
    for spec in ((a + b) * config(encoding=Dict(:tooltip => shared)),
                 (a * config(width=300) + b) * config(encoding=Dict(:tooltip => shared)))
        us = units(to_vegalite(spec))
        @test length(us) == 2
        @test all(u -> tooltip_fields(u) == ["group", "value", "n_obs"], us)
    end

    # A single-layer spec is its own whole spec: the override reaches every unit
    # its analysis emits.
    single = data(posterior_rows) * mapping(:group, :median) *
        pointinterval(bands=bands, orientation=:vertical) *
        config(encoding=Dict(:tooltip => tip("group", "n_finite")))
    @test all(u -> tooltip_fields(u) == ["group", "n_finite"], units(to_vegalite(single)))

    # A summand override and a whole-spec override of the same channel: the
    # whole-spec one comes later in the expression and wins on that layer too.
    both = (a * config(encoding=Dict(:tooltip => tip("label"))) + b) *
        config(encoding=Dict(:tooltip => shared))
    @test all(u -> tooltip_fields(u) == ["group", "value", "n_obs"], units(to_vegalite(both)))
end

@testitem "nested sums scope each override to the layers it was written on" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    a = data(observed_rows) * mapping(:group, :value) * visual(Scatter)
    b = data(observed_rows) * mapping(:group, :value) * visual(Lines)
    c = data(observed_rows) * mapping(:group, :value) * visual(BarPlot)
    # `cab` applies to the sub-sum `a + b` only; `ca` is `a`'s own and loses to
    # `cab` on a conflict because `cab` comes later; `cc` is `c`'s own.
    spec = ((a * config(encoding=Dict(:tooltip => tip("label"), "x" => Dict("title" => "A x"))) + b) *
            config(encoding=Dict(:tooltip => tip("n_obs"))) +
           c * config(encoding=Dict(:tooltip => tip("value"))))
    us = units(to_vegalite(spec))
    @test length(us) == 3
    @test tooltip_fields(us[1]) == ["n_obs"]
    @test us[1]["encoding"]["x"]["title"] == "A x"  # `ca`'s non-conflicting channel stays
    @test tooltip_fields(us[2]) == ["n_obs"]
    @test get(us[2]["encoding"]["x"], "title", nothing) != "A x"
    @test tooltip_fields(us[3]) == ["value"]
end

@testitem "summand facet-channel overrides stay on the shared facet" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    rows = (; x=[1.0, 2.0, 3.0, 4.0], y=[1.0, 2.0, 3.0, 4.0], panel=["p", "q", "p", "q"])
    a = data(rows) * mapping(:x, :y; row=:panel) * visual(Scatter) *
        config(encoding=Dict("row" => Dict("sort" => ["q", "p"]),
                             :tooltip => [Dict("field" => "x")]))
    b = data(rows) * mapping(:x, :y; row=:panel) * visual(Lines)
    vl = to_vegalite(a + b)
    # The row facet is one operator for every layer: a summand's row override
    # configures it rather than vanishing into one layer's encoding.
    @test vl["facet"]["row"]["sort"] == ["q", "p"]
    us = units(vl)
    @test tooltip_fields(us[1]) == ["x"]
    @test tooltip_fields(us[2]) != ["x"]
end

@testitem "successive config(encoding=...) terms merge per channel" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    base = data(observed_rows) * mapping(:group, :value) * visual(Scatter)
    tooltip = tip("group", "label")
    sort_enc = Dict("y" => Dict("sort" => "descending"))
    tooltip_cfg = config(encoding=Dict(:tooltip => tooltip))
    sort_cfg = config(encoding=sort_enc)
    vl = to_vegalite(base * tooltip_cfg * sort_cfg)
    # A later `encoding` no longer replaces an earlier one wholesale.
    @test tooltip_fields(vl) == ["group", "label"]
    @test vl["encoding"]["y"]["sort"] == "descending"
    # Same channel: the later term wins.
    later = to_vegalite(base * tooltip_cfg * config(encoding=Dict(:tooltip => tip("value"))))
    @test tooltip_fields(later) == ["value"]
    # Merging never mutates the caller's dicts, nor the config's own lowered copy
    # (`config` stores the override with string keys).
    @test sort_enc == Dict("y" => Dict("sort" => "descending"))
    @test tooltip == tip("group", "label")
    @test tooltip_cfg.properties[:encoding] == Dict("tooltip" => tooltip)
end

@testitem "a summand's scale type still sets the shared static axis" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config, :static] begin
    rows = (; x=[1.0, 10.0, 100.0], y=[1.0, 2.0, 3.0])
    a = data(rows) * mapping(:x, :y) * visual(Scatter) *
        config(encoding=Dict("x" => Dict("scale" => Dict("type" => "log"))))
    b = data(rows) * mapping(:x, :y) * visual(Lines)
    spec = a + b
    # Vega-Lite: the override sits on `a`'s layer and merges into the shared x scale.
    us = units(to_vegalite(spec))
    @test us[1]["encoding"]["x"]["scale"]["type"] == "log"
    @test get(get(us[2]["encoding"]["x"], "scale", Dict()), "type", nothing) === nothing
    # Makie: the axis is shared, so the summand's scale type still reaches it.
    kw = AlgebraOfVega._draw_kwargs(spec.config;
        layer_encodings=AlgebraOfVega._spec_layer_encodings(spec))
    @test kw.axis.xscale === log10
end

@testitem "summand overrides survive the channel picker and update_spec" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config, :remap] begin
    posterior = data(merge(posterior_rows, (; arm=["x", "y", "x"]))) *
        mapping(:group, :median => "Fraction"; color=:arm) *
        pointinterval(bands=bands, orientation=:vertical)
    marks = data(merge(observed_rows, (; arm=["x", "y"]))) *
        mapping(:group, :value => "Fraction") *
        visual(Scatter; color="black") *
        config(encoding=Dict(:tooltip => tip("group", "n_obs", "label")))
    spec = (posterior + marks) * config(height=250)
    remap = (; dims=["arm" => "Arm"])

    (; vl) = AlgebraOfVega._auto_remap_lowering(spec; remap...)
    us = units(vl)
    @test tooltip_fields(us[end]) == ["group", "n_obs", "label"]
    @test all(u -> "n_obs" ∉ tooltip_fields(u), us[1:end-1])
    @test all(u -> "q025" in tooltip_fields(u), us[1:end-1])

    # update_spec re-lowers through the same path.
    html = repr(MIME"text/html"(), update_spec("fig", spec; auto_remap=remap))
    @test occursin("\"title\":\"LABEL\"", html)
end

# A further algebra term multiplied onto a configured spec reaches its layers as
# AoG distributes `*` over `+`, each layer keeping its own encoding override.
# Before, `config(...)` was a terminal factor: `spec * visual(...)` threw
# `MethodError: no method matching *(::VegaSpec, ::Layer)`, so library code could
# not add a mark property (RegionExplorer's `visual(; clip=true)` on a framed
# map's marks) to an app layer carrying its own tooltip
# (snag `vegaspec-times-l-9296bb34`).
@testitem "a further term multiplied onto a configured spec reaches its layers" setup=[AoVLayerEncodingFixtures] tags=[:translation, :config] begin
    same(x, y) = to_vegalite(x) == to_vegalite(y)
    pts = data(observed_rows) * mapping(:group, :value) * visual(Scatter)
    line = data(observed_rows) * mapping(:group, :value) * visual(Lines)
    tipped = config(encoding=Dict(:tooltip => tip("group", "label")))
    clip = visual(; clip=true)

    # The snag's shapes, each against the expression with the term written first.
    @test same((pts * tipped) * clip, pts * clip * tipped)
    @test same(clip * (pts * tipped), clip * pts * tipped)
    @test same(pts * (clip * tipped), pts * clip * tipped)
    @test same((pts * tipped + pts * tipped) * clip, pts * clip * tipped + pts * clip * tipped)
    us = units(to_vegalite((pts * tipped + line) * clip))
    @test length(us) == 2
    @test all(u -> u["mark"]["clip"] == true, us)
    @test tooltip_fields(us[1]) == ["group", "label"]
    @test "label" ∉ tooltip_fields(us[2])

    # Every summand keeps its own override and the whole-view config.
    other = config(encoding=Dict(:tooltip => tip("n_obs")))
    @test same((pts * tipped + line * other) * config(height=200) * clip,
               (pts * clip * tipped + line * clip * other) * config(height=200))

    # A product of sums: AoG's order, the left factor's layers outer.
    big = visual(; markersize=8)
    @test same((pts * tipped + line) * (clip + big),
               pts * clip * tipped + pts * big * tipped + line * clip + line * big)
    @test length(units(to_vegalite((pts * tipped + line) * (clip + big)))) == 4

    # Two configured factors: on a conflicting key the later one wins on every
    # layer, whichever factor carries the per-layer overrides.
    @test same((pts * tipped + line) * (clip * other),
               pts * clip * tipped * other + line * clip * other)
    @test same((clip * other) * (pts * tipped + line),
               clip * pts * other * tipped + clip * line * other)
    us = units(to_vegalite((clip * other) * (pts * tipped + line)))
    @test tooltip_fields(us[1]) == ["group", "label"]
    @test tooltip_fields(us[2]) == ["n_obs"]

    # A config written before the algebra terms applies like one written last.
    @test same(config(width=300) * data(observed_rows) * mapping(:group, :value) * visual(Scatter),
               pts * config(width=300))
end
