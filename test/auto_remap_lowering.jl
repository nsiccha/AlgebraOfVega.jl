using TestItemRunner

# `to_vegalite(spec; auto_remap=…)` is the public lowering of a channel-picker
# figure. A consumer exporting such a figure as JSON, markdown or a static render
# used to index the private `_auto_remap_parts(...)[3]`, which also built the
# picker controls and a plot node. That `[3]` was not even the clean lowering:
# `to_node` wrote its in-browser fallback `spec.width = 400` (and its
# cross-source facet broadcast) into the dict it was given
# (snag `public-auto-rema-7fa0583e`).
@testsnippet AoVRemapLoweringFixtures begin
    using AlgebraOfVega, JSON

    # A draws ribbon plus an observation scatter. The column facet is fixed;
    # the row facet is the picker's catch-all.
    function remap_fixture()
        xs = range(0, 10; length=8)
        rows = [(; x, y=sin(x) + 0.1d + (src == "fit" ? 0 : 1), draw=d, source=src, study=st, assay=as)
                for st in ("S1", "S2") for as in ("A", "B") for src in ("fit", "prior") for d in 1:5 for x in xs]
        pred = (; (c => [getproperty(r, c) for r in rows] for c in (:x, :y, :draw, :source, :study, :assay))...)
        obs = (; x=collect(xs), y=cos.(xs), study=fill("S1", 8), assay=fill("A", 8))
        data(pred) * mapping(:x, :y; group=:draw, color=:source, row=:study) * lineribbon() +
            data(obs) * mapping(:x, :y) * visual(Scatter)
    end
    remap = (; dims=["source" => "Source", "study" => "Study", "assay" => "Assay"],
               fixed=Dict(:column => "assay"), pinned=:row)
    canon(x) = JSON.parse(JSON.json(x))

    # Every `params` entry anywhere in a Vega-Lite tree.
    function all_params(node, out=Any[])
        node isa Dict || return out
        append!(out, get(node, "params", Any[]))
        for key in ("layer", "hconcat", "vconcat", "concat")
            for child in get(node, key, Any[])
                all_params(child, out)
            end
        end
        haskey(node, "spec") && all_params(node["spec"], out)
        out
    end
end

@testitem "to_vegalite(spec; auto_remap) returns the picker's lowering" setup=[AoVRemapLoweringFixtures] tags=[:auto_remap, :translation, :regression] begin
    spec = remap_fixture() * config(height=150)
    vl = to_vegalite(spec; auto_remap=remap)

    # Exactly the lowering the picker embeds and `update_spec` re-lowers through.
    @test canon(vl) == canon(AlgebraOfVega._auto_remap_lowering(spec; remap...).vl)
    @test vl["facet"]["column"]["field"] == "assay"
    @test vl["facet"]["row"]["field"] == "study"
    # The private triple's dict is that lowering too, now that `to_node` leaves it alone.
    @test canon(AlgebraOfVega._auto_remap_parts("remap-lowering", spec; remap...)[3]) == canon(vl)

    # Bare drawables, `to_json` and the positional `scales` form take the keyword too.
    @test canon(to_vegalite(remap_fixture(); auto_remap=remap)) == canon(to_vegalite(vlspec(remap_fixture()); auto_remap=remap))
    @test JSON.parse(to_json(spec; auto_remap=remap)) == canon(vl)
    ylog = scales(Y=(; scale=log10))
    @test canon(to_vegalite(spec, ylog; auto_remap=remap)) ==
        canon(to_vegalite(spec * config(scales=ylog); auto_remap=remap))

    # `interactive=false` drops AoV's generated params here as well.
    @test !isempty(all_params(vl))
    @test isempty(all_params(to_vegalite(spec; auto_remap=remap, interactive=false)))
    @test JSON.parse(to_json(spec; auto_remap=remap, interactive=false)) ==
        canon(to_vegalite(spec; auto_remap=remap, interactive=false))

    # Without `auto_remap` nothing changes.
    @test canon(to_vegalite(spec; auto_remap=nothing)) == canon(to_vegalite(spec))
    # refused: a lowered Vega-Lite Dict no longer carries the layer tables the
    # picker resolves channels from, so it cannot be remapped.
    @test_throws ArgumentError to_vegalite(vl; auto_remap=remap)
end

@testitem "to_node leaves the Vega-Lite dict it embeds unchanged" setup=[AoVRemapLoweringFixtures] tags=[:auto_remap, :embed, :regression] begin
    # Faceted figure without an authored width: the embed adds the fallback cell
    # width to its own copy only.
    vl = to_vegalite(remap_fixture() * config(height=150); auto_remap=remap)
    before = canon(vl)
    to_node(vl; id="remap-lowering")
    @test canon(vl) == before
    @test !haskey(vl["spec"], "width")
    @test AlgebraOfVega._embed_spec(vl)["spec"]["width"] == 400

    # Cross-source facets: the embed replicates the guide row into every panel
    # of its own copy, leaving the caller's rows as they were.
    pts = (; x=[1.0, 2.0, 3.0, 4.0], y=[1.0, 2.0, 3.0, 4.0], g=["a", "a", "b", "b"])
    cross = to_vegalite(data(pts) * mapping(:x, :y; col=:g) * visual(Scatter) +
                        data((; x=[2.5])) * mapping(:x) * visual(VLines))
    before = canon(cross)
    to_node(cross; id="cross-source")
    @test canon(cross) == before
    @test length(cross["data"]["values"]) == 5
    @test length(AlgebraOfVega._embed_spec(cross)["data"]["values"]) == 6
end

# A `fixed=` facet field is as much a facet field as one the picker resolves:
# the lowering broadcasts every layer that lacks it across its values. Before,
# only the picker's row/column fields were broadcast, and the exported
# Vega-Lite of a figure whose `fixed=` column only the ribbon carried left the
# observation and dose rows outside every column; until `5586d26` that was
# hidden by `to_node` broadcasting into `_auto_remap_parts(...)[3]` in place
# (snag `facet-broadcast-44b6e163`).
@testitem "to_vegalite(spec; auto_remap) broadcasts layers across fixed facet fields" setup=[AoVRemapLoweringFixtures] tags=[:auto_remap, :translation, :regression] begin
    bases = ["CV", "In-sample"]
    pred = (; subject=repeat(["S1", "S2"], inner=4), t=repeat([0.0, 24.0], 4),
              basis=repeat(bases, inner=2, outer=2), median=fill(90.0, 8),
              lo=fill(75.0, 8), hi=fill(105.0, 8))
    obs = (; subject=["S1", "S2"], t=[24.0, 24.0], value=[91.0, 92.0])
    dose = (; subject=["S1", "S2"], t=[1.0, 1.0])
    figure() = data(pred) * mapping(:t, :median; row=:subject) * lineribbon(bands=[:lo => :hi]) +
        data(obs) * mapping(:t, :value) * visual(Scatter) +
        data(dose) * mapping(:t) * visual(VLines)
    ar = (; dims=["subject" => "Subject", "basis" => "Prediction basis"],
            fixed=Dict(:column => "basis"), pinned=:row)
    rows(vl, has) = [r for r in canon(vl)["data"]["values"] if haskey(r, has)]

    vl = to_vegalite(figure(); auto_remap=ar)
    @test vl["facet"]["column"]["field"] == "basis"
    # every observation and dose row stands once in each basis column
    @test sort([(r["subject"], r["basis"]) for r in rows(vl, "value")]) ==
          [(s, b) for s in ("S1", "S2") for b in bases]
    dose_rows = [r for r in canon(vl)["data"]["values"] if !haskey(r, "value") && !haskey(r, "median")]
    @test sort([(r["subject"], r["basis"]) for r in dose_rows]) ==
          [(s, b) for s in ("S1", "S2") for b in bases]
    # the embed has nothing left to broadcast, and lowering twice from the same
    # spec gives the same Vega-Lite
    @test canon(AlgebraOfVega._embed_spec(vl))["data"] == canon(vl)["data"]
    @test canon(to_vegalite(figure(); auto_remap=ar)) == canon(vl)
    @test canon(AlgebraOfVega._auto_remap_parts("fixed-bcast", figure(); ar...)[3]) == canon(vl)

    # Several fixed fields on one channel facet by their combined column, which
    # every layer carries after the broadcast.
    pts = (; x=collect(1.0:8.0), y=collect(1.0:8.0), a=repeat(["A1", "A2"], 4), b=repeat(["B1", "B2"], inner=4))
    combo = to_vegalite(data(pts) * mapping(:x, :y) * visual(Scatter) +
                        data((; x=[4.5])) * mapping(:x) * visual(VLines);
                        auto_remap=(; dims=["a" => "A", "b" => "B"], fixed=Dict(:column => ["a", "b"]), pinned=:row))
    @test combo["facet"]["column"]["field"] == "__aov_column"
    cvals = canon(combo)["data"]["values"]
    @test all(r -> haskey(r, "__aov_column"), cvals)
    @test sort([r["__aov_column"] for r in cvals if !haskey(r, "y")]) ==
          ["A1 / B1", "A1 / B2", "A2 / B1", "A2 / B2"]
end
