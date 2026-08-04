using TestItemRunner

# Shared imports — re-evaluated independently inside every test item that lists
# `AoVTestImports` in its `setup`. Test bodies stay isolated; each item module
# gets its own copy of these `using`s. `Test` is injected automatically.
@testsnippet AoVTestImports begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    using Tables
    using HTMX
    import Statistics
end

# --- Tests ---

"""
`classify_columns` buckets a Tables.jl source's columns into numeric vs
categorical, and the result is invariant to `Tables.columntable` normalization.
"""
@testitem "classify_columns" setup=[AoVTestImports] tags=[:columns] begin
    nt = AlgebraOfVega.sample_cars()
    cols = AlgebraOfVega.classify_columns(nt)
    @test "horsepower" in cols.numeric
    @test "mpg" in cols.numeric
    @test "origin" in cols.categorical
    @test "origin" ∉ cols.numeric
    @test Set(cols.all) == Set(vcat(cols.numeric, cols.categorical))

    ct = Tables.columntable(nt)
    cols2 = AlgebraOfVega.classify_columns(ct)
    @test cols2.numeric == cols.numeric
    @test cols2.categorical == cols.categorical
end

"""
`table_to_rows` transposes a column table into a `Vector{Dict{String,Any}}`,
one dict per row, preserving values by column name.
"""
@testitem "table_to_rows" setup=[AoVTestImports] tags=[:columns] begin
    nt = AlgebraOfVega.sample_tips()
    rows = AlgebraOfVega.table_to_rows(nt)
    @test length(rows) == length(nt.total_bill)
    @test rows[1] isa Dict{String,Any}
    @test rows[1]["total_bill"] == nt.total_bill[1]
    @test rows[1]["sex"] == nt.sex[1]

    # Regression: the element type must be concretely Dict{String,Any} even for
    # an EMPTY table or a column whose eltype is `Any` (e.g. preaggregate()'s
    # group-key columns). An untyped comprehension infers `Any` there and
    # returns a `Vector{Any}`, which misses `_ribbon_to_vl(::Vector{<:Dict{String}})`
    # and 500s a pre-aggregated lineribbon over an empty study.
    empty_rows = AlgebraOfVega.table_to_rows((x=Float64[], median=Float64[], lo=Float64[]))
    @test empty_rows isa Vector{Dict{String,Any}}
    @test isempty(empty_rows)
    anycol_rows = AlgebraOfVega.table_to_rows((study=Any[], x=Any[], median=Float64[]))
    @test anycol_rows isa Vector{Dict{String,Any}}
end

"""
`explorer_js` emits the client-side data-explorer runtime: channel selectors,
container sizing, independent-axis resolve, and default cell dimensions.
"""
@testitem "explorer_js" setup=[AoVTestImports] tags=[:explorer] begin
    js = AlgebraOfVega.explorer_js()
    @test occursin("ex-group", js)
    @test occursin("encoding.detail", js)
    @test occursin("ex-color", js)
    @test occursin("ex-x", js)
    @test occursin("'container'", js)
    @test occursin("height: 350", js)

    js2 = AlgebraOfVega.explorer_js(; namespace="Foo.", plot_selector="#myplot", spec_selector="#myspec")
    @test occursin("Foo.", js2)
    @test occursin("#myplot", js2)
    @test occursin("#myspec", js2)

    js3 = AlgebraOfVega.explorer_js(; width=800, height=500)
    @test occursin("width: 800", js3)
    @test occursin("height: 500", js3)
    @test !occursin("'container'", js3)

    @test occursin("var cellWidth = 250", js)
    @test occursin("Math.max(100, Math.floor((availWidth - 60) / nCols))", js)
    @test occursin("clientWidth", js)

    @test occursin("ex-indep-x", js)
    @test occursin("ex-indep-y", js)
    @test occursin("resolve", js)
    @test occursin("independent", js)
end

"""
`explorer_controls_html` renders the explorer's control panel — channel/mark
pickers, per-dataset defaults, and independent-axis toggles.
"""
@testitem "explorer_controls_html" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    html = AlgebraOfVega.explorer_controls_html(datasets)
    @test occursin("ex-group", html)
    @test occursin("ex-color", html)
    @test occursin("ex-col", html)
    @test occursin("ex-row", html)
    @test occursin("ex-mark", html)
    @test occursin("Group:", html)

    # default dataset gets selected attribute
    @test occursin("<option value=\"penguins\" selected>", html)

    html2 = AlgebraOfVega.explorer_controls_html(datasets; default_ds="cars", default_x="mpg", default_y="horsepower", default_color="origin")
    @test occursin("<option value=\"cars\" selected>", html2)
    @test occursin("<option value=\"mpg\" selected>", html2)
    @test occursin("<option value=\"horsepower\" selected>", html2)
    @test occursin("<option value=\"origin\" selected>", html2)

    html3 = AlgebraOfVega.explorer_controls_html(datasets; marks=["point" => "scatter", "line" => "line"])
    @test occursin("scatter", html3)
    @test !occursin("boxplot", html3)

    html4 = AlgebraOfVega.explorer_controls_html(datasets; default_mark="line")
    @test occursin("<option value=\"line\" selected>", html4)

    @test occursin("ex-indep-x", html)
    @test occursin("ex-indep-y", html)
    @test occursin("Independent X", html)
    @test occursin("Independent Y", html)
end

"""
`explorer_widget` assembles the full explorer node; it returns a renderable for
a range of options (titles, spec visibility, defaults, custom marks).
"""
@testitem "explorer_widget" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()

    w = AlgebraOfVega.explorer_widget(datasets)
    @test w !== nothing

    w2 = AlgebraOfVega.explorer_widget(datasets; title="My Explorer", subtitle="Custom subtitle")
    @test w2 !== nothing

    w3 = AlgebraOfVega.explorer_widget(datasets; title=nothing, subtitle=nothing)
    @test w3 !== nothing

    w4 = AlgebraOfVega.explorer_widget(datasets; show_spec=false)
    @test w4 !== nothing

    w5 = AlgebraOfVega.explorer_widget(datasets;
        default_x="mpg", default_y="horsepower", default_color="origin",
        default_mark="line", width=800, height=400)
    @test w5 !== nothing

    w6 = AlgebraOfVega.explorer_widget(datasets; marks=["point" => "scatter"])
    @test w6 !== nothing

    ws = string(w)
    @test occursin("ex-indep-x", ws)
    @test occursin("ex-indep-y", ws)
    @test occursin("Independent X", ws)
    @test occursin("Independent Y", ws)
end

"""
`explorer_data_init_js` serializes the explorer datasets + column metadata into
the client-side bootstrap globals `_explorerDatasets` / `_explorerColumns`.
"""
@testitem "explorer_data_init_js" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    js = AlgebraOfVega.explorer_data_init_js(datasets)
    @test occursin("_explorerDatasets", js)
    @test occursin("_explorerColumns", js)
end

"""
The bundled sample datasets are well-formed Tables.jl sources: non-empty, with
every column the same length.
"""
@testitem "sample datasets" setup=[AoVTestImports] tags=[:datasets] begin
    for f in [AlgebraOfVega.sample_cars, AlgebraOfVega.sample_tips,
              AlgebraOfVega.sample_stocks, AlgebraOfVega.sample_temperatures]
        tbl = f()
        cols = Tables.columnnames(tbl)
        @test length(cols) > 0
        n = length(Tables.getcolumn(tbl, first(cols)))
        @test n > 0
        for c in cols
            @test length(Tables.getcolumn(tbl, c)) == n
        end
    end
end

"""
`_resolve_filter_include` normalizes the explorer's `filter_include` spec
(list, unary predicate, or `(col, val)` predicate) to `Dict{String,Vector{String}}`,
and `_filter_init_js` emits the matching client bootstrap.
"""
@testitem "filter_include" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    tbl = datasets["cars"]

    @test AlgebraOfVega._resolve_filter_include(nothing, tbl) === nothing

    resolved = AlgebraOfVega._resolve_filter_include(Dict("origin" => ["USA", "Japan"]), tbl)
    @test resolved isa Dict{String, Vector{String}}
    @test Set(resolved["origin"]) == Set(["USA", "Japan"])

    resolved2 = AlgebraOfVega._resolve_filter_include(Dict("origin" => v -> v != "Europe"), tbl)
    @test resolved2 isa Dict{String, Vector{String}}
    @test "Europe" ∉ resolved2["origin"]
    @test length(resolved2["origin"]) > 0

    resolved3 = AlgebraOfVega._resolve_filter_include((col, val) -> col != "origin" || val != "Europe", tbl)
    @test resolved3 isa Dict{String, Vector{String}}
    @test "Europe" ∉ resolved3["origin"]

    @test AlgebraOfVega._filter_init_js(nothing, "AoV.") == ""

    js = AlgebraOfVega._filter_init_js(Dict("origin" => ["USA"]), "AoV.")
    @test occursin("_explorerFilterSelected", js)
    @test occursin("new Set", js)

    w = AlgebraOfVega.explorer_widget(datasets; default_filter_include=Dict("species" => ["Adelie"]))
    @test w !== nothing
end

"""
`_default_marks` is the explorer's canonical mark menu — seven entries, `point`
first, including the `line+ribbon` uncertainty mark.
"""
@testitem "_default_marks" setup=[AoVTestImports] tags=[:explorer] begin
    marks = AlgebraOfVega._default_marks()
    @test marks isa Vector{Pair{String,String}}
    @test length(marks) == 7
    @test first(first(marks)) == "point"
    @test any(p -> first(p) == "line+ribbon", marks)
end

"""
The explorer runtime supports per-axis log scales via the `ex-log-x` / `ex-log-y`
toggles.
"""
@testitem "explorer_js log scale" setup=[AoVTestImports] tags=[:explorer] begin
    js = AlgebraOfVega.explorer_js()
    @test occursin("ex-log-x", js)
    @test occursin("ex-log-y", js)
    @test occursin("type: 'log'", js)
end

"""
The explorer runtime implements the client-side line+ribbon summary (per-x
median + quantile bands) driven by the `ex-ribbon-levels` control.
"""
@testitem "explorer_js line+ribbon" setup=[AoVTestImports] tags=[:explorer] begin
    js = AlgebraOfVega.explorer_js()
    @test occursin("line+ribbon", js)
    @test occursin("_quantile", js)
    @test occursin("_median", js)
    @test occursin("ex-ribbon-levels", js)
    @test occursin("summaryData", js)
end

"""
The explorer control panel exposes the log-scale toggles and the (initially
hidden) ribbon-levels control, revealed for the `line+ribbon` mark.
"""
@testitem "explorer_controls_html log and ribbon" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    html = AlgebraOfVega.explorer_controls_html(datasets)
    @test occursin("ex-log-x", html)
    @test occursin("ex-log-y", html)
    @test occursin("Log X", html)
    @test occursin("Log Y", html)
    @test occursin("ex-ribbon-levels", html)
    @test occursin("Ribbon levels:", html)
    @test occursin("id=\"ex-ribbon-levels-label\" class=\"u-hidden\"", html)

    html2 = AlgebraOfVega.explorer_controls_html(datasets; default_mark="line+ribbon")
    @test occursin("line + ribbon", html2)
end

"""
The dataset dropdown is hidden when only one dataset is present and shown
(labelled `Dataset:`) when several are.
"""
@testitem "explorer_controls_html dataset hiding" setup=[AoVTestImports] tags=[:explorer] begin
    single = Dict("mydata" => AlgebraOfVega.sample_cars())
    html = AlgebraOfVega.explorer_controls_html(single)
    @test occursin("<label class=\"u-hidden\">Dataset:", html)
    @test occursin("ex-dataset", html)

    multi = AlgebraOfVega.default_explorer_datasets()
    html2 = AlgebraOfVega.explorer_controls_html(multi)
    @test occursin("Dataset:", html2)
end

"""
The explorer accepts a bare (single) Tables.jl source in addition to a
`Dict` of datasets; `_wrap_datasets` normalizes a bare table under a `"data"` key.
"""
@testitem "bare table support" setup=[AoVTestImports] tags=[:explorer] begin
    tbl = AlgebraOfVega.sample_penguins()

    html = AlgebraOfVega.explorer_controls_html(tbl)
    @test occursin("ex-x", html)
    @test occursin("<label class=\"u-hidden\">Dataset:", html)

    w = AlgebraOfVega.explorer_widget(tbl;
        default_x="bill_length", default_y="bill_depth")
    @test w !== nothing

    d = Dict("a" => tbl)
    @test AlgebraOfVega._wrap_datasets(d) === d

    wrapped = AlgebraOfVega._wrap_datasets(tbl)
    @test wrapped isa Dict
    @test haskey(wrapped, "data")
end

"""
The assembled `explorer_widget` string carries the log-scale and ribbon-levels
controls end-to-end.
"""
@testitem "explorer_widget log and ribbon" setup=[AoVTestImports] tags=[:explorer] begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    ws = string(AlgebraOfVega.explorer_widget(datasets))
    @test occursin("ex-log-x", ws)
    @test occursin("ex-log-y", ws)
    @test occursin("Log X", ws)
    @test occursin("Log Y", ws)
    @test occursin("ex-ribbon-levels", ws)
    @test occursin("Ribbon levels", ws)
end

"""
`pregrouped` builds a boxplot layer from parallel group/value vectors. Renamer
labels feed the nominal-x `sort` order; without a renamer, group keys stringify.
`is_pregrouped` detects the resulting layer.
"""
@testitem "pregrouped boxplot" setup=[AoVTestImports] tags=[:translation] begin
    # Basic pregrouped with renamer
    spec_obj = pregrouped(
        fill.(1:3, 10) => renamer(["A", "B", "C"]),
        [randn(10) for _ in 1:3]
    ) * visual(BoxPlot)
    vl = to_vegalite(spec_obj)
    @test vl["mark"] == "boxplot"
    @test haskey(vl, "data")
    @test length(vl["data"]["values"]) == 30  # 3 groups x 10 obs
    @test vl["encoding"]["x"]["type"] == "nominal"
    @test vl["encoding"]["y"]["type"] == "quantitative"
    @test vl["encoding"]["x"]["sort"] == ["A", "B", "C"]
    # Check that renamer labels are applied
    labels = Set(r["x"] for r in vl["data"]["values"])
    @test labels == Set(["A", "B", "C"])

    # Pregrouped without renamer
    spec_obj2 = pregrouped(
        fill.(1:2, 5),
        [randn(5) for _ in 1:2]
    ) * visual(BoxPlot)
    vl2 = to_vegalite(spec_obj2)
    @test vl2["mark"] == "boxplot"
    @test length(vl2["data"]["values"]) == 10
    labels2 = Set(r["x"] for r in vl2["data"]["values"])
    @test labels2 == Set(["1", "2"])

    # is_pregrouped detection
    layer = pregrouped(fill.(1:2, 5), [randn(5) for _ in 1:2])
    # pregrouped() returns a single Layer (data * mapping)
    @test AlgebraOfVega.is_pregrouped(layer)
end

"""
`vdata` is an alias for `data`; specs built with either lower to identical
Vega-Lite.
"""
@testitem "vdata alias" setup=[AoVTestImports] tags=[:translation] begin
    df = (; x=[1, 2, 3], y=[4, 5, 6])
    # vdata should work identically to data
    spec1 = data(df) * mapping(:x, :y) * visual(Scatter)
    spec2 = vdata(df) * mapping(:x, :y) * visual(Scatter)
    @test to_vegalite(spec1) == to_vegalite(spec2)
end

"""
`config(independent_scales=...)` lowers to a Vega-Lite `resolve.scale` block —
`true` frees both axes, a `Symbol` or tuple frees the named ones.
"""
@testitem "independent_scales config" setup=[AoVTestImports] tags=[:translation, :config] begin
    df = (; x=[1, 2], y=[3, 4], g=["a", "b"])

    # independent_scales=true → resolve both axes
    spec = data(df) * mapping(:x, :y, col=:g) * visual(Scatter) *
        config(independent_scales=true)
    vl = to_vegalite(spec)
    @test haskey(vl, "resolve")
    @test vl["resolve"]["scale"]["x"] == "independent"
    @test vl["resolve"]["scale"]["y"] == "independent"

    # independent_scales=:x → only x
    spec2 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(independent_scales=:x)
    vl2 = to_vegalite(spec2)
    @test vl2["resolve"]["scale"]["x"] == "independent"
    @test !haskey(vl2["resolve"]["scale"], "y")

    # independent_scales=(:x, :y) → explicit tuple
    spec3 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(independent_scales=(:x, :y))
    vl3 = to_vegalite(spec3)
    @test vl3["resolve"]["scale"]["x"] == "independent"
    @test vl3["resolve"]["scale"]["y"] == "independent"
end

"""
A second `* config(...)` on an existing `VegaSpec` MERGES into the config already
there instead of replacing it. Replacing silently dropped every earlier prop — an
app helper appending `config(width=…, height=…)` after a caller's
`config(facet=…, title=…)` emitted no `resolve` and no `title`, with no warning
(and no `independent_scales` deprecation, since the props never reached
`to_vegalite`). Later-wins on conflict, matching `+`.
"""
@testitem "config accumulates under repeated `*`" setup=[AoVTestImports] tags=[:translation, :config] begin
    df = (; x=[1.0, 2.0], y=[3.0, 4.0], g=["a", "b"])
    base = data(df) * mapping(:x, :y, col=:g) * visual(Scatter)

    # Earlier props survive a later `* config(...)`.
    vl = to_vegalite(base * config(title="T", facet=(; linkyaxes=:none)) *
                     config(width=620, height=150))
    @test vl["resolve"]["scale"]["y"] == "independent"
    @test vl["title"] == "T"
    # width/height land inner on facet-operator specs, top-level otherwise.
    sized = get(vl, "spec", vl)
    @test sized["width"] == 620
    @test sized["height"] == 150

    # The deprecated spelling still reaches to_vegalite (and still warns).
    vl2 = (@test_logs (:warn, r"deprecated") match_mode=:any to_vegalite(
        base * config(independent_scales=true) * config(width=620)))
    @test vl2["resolve"]["scale"]["x"] == "independent"
    @test vl2["resolve"]["scale"]["y"] == "independent"

    # Later wins on conflict.
    vl3 = to_vegalite(base * config(title="first") * config(title="second"))
    @test vl3["title"] == "second"

    # Config on the left: the spec's own config comes later, so it wins.
    vl4 = to_vegalite(config(title="outer") * (base * config(title="inner")))
    @test vl4["title"] == "inner"
end

"""
The AoG-mirror `scales(...)` / `facet=(; linkxaxes/linkyaxes)` / `axis=(; limits, clamp)`
config sugar lowers to Vega-Lite encoding scale (`type`/`base`/`domain`/`clamp`)
and `resolve.scale`. Explicit user `encoding` always wins on conflict, and the
legacy `independent_scales=true` path still works (with a deprecation warning).
"""
@testitem "scales / facet config (AoG mirror)" setup=[AoVTestImports] tags=[:translation, :config] begin
    df = (; x=[1.0, 2.0], y=[3.0, 4.0], g=["a", "b"])

    # scales(Y=(; scale=log10)) → VL encoding y.scale.type == "log"
    spec = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(Y=(; scale=log10)))
    vl = to_vegalite(spec)
    @test vl["encoding"]["y"]["scale"]["type"] == "log"
    @test !haskey(vl["encoding"]["y"]["scale"], "base")

    # scales(X=(; scale=log2)) → base=2
    spec2 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(X=(; scale=log2)))
    vl2 = to_vegalite(spec2)
    @test vl2["encoding"]["x"]["scale"]["type"] == "log"
    @test vl2["encoding"]["x"]["scale"]["base"] == 2

    # scales + independent X+Y on both axes via facet= NamedTuple
    spec3 = data(df) * mapping(:x, :y, col=:g) * visual(Scatter) *
        config(scales=scales(Y=(; scale=log10)),
               facet=(; linkxaxes=:none, linkyaxes=:none))
    vl3 = to_vegalite(spec3)
    @test vl3["resolve"]["scale"]["x"] == "independent"
    @test vl3["resolve"]["scale"]["y"] == "independent"

    # facet=(; linkxaxes=:none) only → only x is independent
    spec4 = data(df) * mapping(:x, :y, col=:g) * visual(Scatter) *
        config(facet=(; linkxaxes=:none))
    vl4 = to_vegalite(spec4)
    @test vl4["resolve"]["scale"]["x"] == "independent"
    @test !haskey(vl4["resolve"]["scale"], "y")

    # Explicit user `encoding` overrides `scales` sugar on conflict
    spec5 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(Y=(; scale=log10)),
               encoding=Dict(:y => Dict("scale" => Dict("type" => "sqrt"))))
    vl5 = to_vegalite(spec5)
    @test vl5["encoding"]["y"]["scale"]["type"] == "sqrt"

    # Backwards compat: independent_scales=true still works (emits deprecation)
    spec6 = data(df) * mapping(:x, :y, col=:g) * visual(Scatter) *
        config(independent_scales=true)
    vl6 = (@test_logs (:warn, r"deprecated") match_mode=:any to_vegalite(spec6))
    @test vl6["resolve"]["scale"]["x"] == "independent"
    @test vl6["resolve"]["scale"]["y"] == "independent"

    # axis=(; limits=((xlo, xhi), nothing)) → encoding.x.scale.domain
    spec7 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(axis=(; limits=((0.0, 10.0), nothing)))
    vl7 = to_vegalite(spec7)
    @test vl7["encoding"]["x"]["scale"]["domain"] == [0.0, 10.0]
    @test !haskey(vl7["encoding"]["y"], "scale") ||
        !haskey(vl7["encoding"]["y"]["scale"], "domain")

    # axis=(; limits=(nothing, (ylo, yhi)), clamp=true) → y domain + clamp only on y
    spec8 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(axis=(; limits=(nothing, (1.0, 5.0)), clamp=true))
    vl8 = to_vegalite(spec8)
    @test vl8["encoding"]["y"]["scale"]["domain"] == [1.0, 5.0]
    @test vl8["encoding"]["y"]["scale"]["clamp"] == true
    @test !haskey(get(vl8["encoding"]["x"], "scale", Dict()), "domain")

    # axis=(; limits=((x...), (y...))) both axes
    spec9 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(axis=(; limits=((0.0, 10.0), (1.0, 5.0))))
    vl9 = to_vegalite(spec9)
    @test vl9["encoding"]["x"]["scale"]["domain"] == [0.0, 10.0]
    @test vl9["encoding"]["y"]["scale"]["domain"] == [1.0, 5.0]

    # axis + scales compose: log y-scale with limits on x
    spec10 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(scales=scales(Y=(; scale=log10)),
               axis=(; limits=((0.0, 10.0), nothing)))
    vl10 = to_vegalite(spec10)
    @test vl10["encoding"]["y"]["scale"]["type"] == "log"
    @test vl10["encoding"]["x"]["scale"]["domain"] == [0.0, 10.0]

    # Explicit user `encoding` overrides `axis` sugar on conflict
    spec11 = data(df) * mapping(:x, :y) * visual(Scatter) *
        config(axis=(; limits=((0.0, 10.0), nothing)),
               encoding=Dict(:x => Dict("scale" => Dict("domain" => [-1.0, 1.0]))))
    vl11 = to_vegalite(spec11)
    @test vl11["encoding"]["x"]["scale"]["domain"] == [-1.0, 1.0]
end

"""
The low-level Vega-Lite helpers: `vl_enc` builds an encoding dict (dropping
`nothing` fields), `vl_mark` returns a bare string or a props dict, and
`vl_tooltips` collects the field-bearing channels.
"""
@testitem "VL helpers" setup=[AoVTestImports] tags=[:translation] begin
    # vl_enc
    enc = AlgebraOfVega.vl_enc(:x; type="quantitative", title="X axis")
    @test enc["field"] == "x"
    @test enc["type"] == "quantitative"
    @test enc["title"] == "X axis"

    # vl_enc filters nothing
    enc2 = AlgebraOfVega.vl_enc(:y; type=nothing)
    @test enc2["field"] == "y"
    @test !haskey(enc2, "type")

    # vl_mark — string when no kwargs
    @test AlgebraOfVega.vl_mark("point") == "point"

    # vl_mark — dict with kwargs
    m = AlgebraOfVega.vl_mark("line"; strokeWidth=2, color="red")
    @test m["type"] == "line"
    @test m["strokeWidth"] == 2
    @test m["color"] == "red"

    # vl_tooltips
    encoding = Dict{String,Any}(
        "x" => Dict{String,Any}("field" => "hp", "type" => "quantitative"),
        "y" => Dict{String,Any}("field" => "mpg", "type" => "quantitative"),
        "color" => Dict{String,Any}("field" => "origin", "type" => "nominal"),
        "opacity" => Dict{String,Any}("value" => 0.5),  # no field → skipped
    )
    tt = AlgebraOfVega.vl_tooltips(encoding)
    @test length(tt) == 3
    fields = Set(d["field"] for d in tt)
    @test fields == Set(["hp", "mpg", "origin"])
end

"""
`extract_transformation` pulls a layer's analysis of a requested type (tidybayes
`LineRibbonAnalysis`, AoG `DensityAnalysis`, …) and returns `nothing` for a
mismatched type or a plain visual layer.
"""
@testitem "extract_transformation generic" setup=[AoVTestImports] tags=[:translation] begin
    # TidybayesAnalysis
    layer = data((; x=[1.0], y=[1.0])) * mapping(:x, :y, group=:x) * lineribbon()
    a = AlgebraOfVega.extract_transformation(layer, AlgebraOfVega.TidybayesAnalysis)
    @test a isa AlgebraOfVega.LineRibbonAnalysis

    # DensityAnalysis
    layer2 = data((; x=[1.0])) * mapping(:x) * density()
    a2 = AlgebraOfVega.extract_transformation(layer2, AlgebraOfGraphics.DensityAnalysis)
    @test !isnothing(a2)

    # Returns nothing for wrong type
    a3 = AlgebraOfVega.extract_transformation(layer, AlgebraOfGraphics.DensityAnalysis)
    @test isnothing(a3)

    # Plain visual layer → no analysis
    layer3 = data((; x=[1.0])) * mapping(:x) * visual(Scatter)
    a4 = AlgebraOfVega.extract_transformation(layer3, AlgebraOfVega.TidybayesAnalysis)
    @test isnothing(a4)
end

"""
`to_vegalite` dispatches each layer kind to its handler — plain marks, density
(`transform`), histogram (`bin`), lineribbon (`layer`), ECDF (`step-after`) —
and emits `\$schema` only at the top level, never in sublayers.
"""
@testitem "layer_to_vl dispatch" setup=[AoVTestImports] tags=[:translation] begin
    # Plain layer
    df = (; x=[1, 2], y=[3, 4])
    vl = to_vegalite(data(df) * mapping(:x, :y) * visual(Scatter))
    @test vl["mark"] == Dict{String,Any}("type" => "point", "filled" => true)
    @test haskey(vl, "\$schema")

    # Density → dispatched correctly
    vl2 = to_vegalite(data(df) * mapping(:x) * density())
    @test haskey(vl2, "transform")

    # Histogram → dispatched correctly
    vl3 = to_vegalite(data(df) * mapping(:x) * histogram())
    @test vl3["mark"] == "bar"
    @test vl3["encoding"]["x"]["bin"] == true

    # Lineribbon → dispatched correctly
    pred = (; x=[1.0, 1.0, 2.0, 2.0], y=[3.0, 4.0, 5.0, 6.0], d=[1, 2, 1, 2])
    vl4 = to_vegalite(data(pred) * mapping(:x, :y, group=:d) * lineribbon())
    @test haskey(vl4, "layer")

    # ECDF → dispatched correctly
    vl5 = to_vegalite(data(df) * mapping(:x) * visual(ECDFPlot))
    @test vl5["mark"]["interpolate"] == "step-after"

    # Schema only at top level, not in sublayers
    layers = data(df) * mapping(:x, :y) * (visual(Scatter) + visual(Lines))
    vl6 = to_vegalite(layers)
    @test haskey(vl6, "\$schema")
    for sl in vl6["layer"]
        @test !haskey(sl, "\$schema")
    end
end

"""
`ecdf_grid` renders a grid of ECDF panels (one per parameter) as an `HTMX.Node`,
optionally grouped by a color column.
"""
@testitem "ecdf_grid" setup=[AoVTestImports] tags=[:analysis] begin
    tbl = (; alpha=collect(1.0:10.0), beta=collect(11.0:20.0), chain=repeat(1:2, 5))
    grid = ecdf_grid(tbl, [:alpha, :beta]; group=:chain)
    @test grid isa HTMX.Node
    s = string(grid)
    @test occursin("alpha", s)
    @test occursin("beta", s)

    # Without group
    grid2 = ecdf_grid(tbl, [:alpha])
    @test grid2 isa HTMX.Node
end

"""
`ppc_overlay` builds a posterior-predictive-check layer stack (`Layers`) over
observed + predicted data, optionally adding a truth layer and a model-comparison
color channel; it composes with `config`.
"""
@testitem "ppc_overlay" setup=[AoVTestImports] tags=[:tidybayes] begin
    obs = (; x=[1.0, 2.0, 3.0], y=[4.0, 5.0, 6.0])
    pred = (; x=[1.0, 1.0, 2.0, 2.0, 3.0, 3.0], y=[3.5, 4.5, 4.5, 5.5, 5.5, 6.5], draw=[1, 2, 1, 2, 1, 2])

    # Basic overlay returns Layers
    layers = ppc_overlay(obs, pred; x=:x, y=:y, group=:draw)
    @test layers isa AlgebraOfGraphics.Layers

    # Composable with config
    spec = layers * config(width=300, height=200, facet=(; linkxaxes=:none, linkyaxes=:none))
    vl = to_vegalite(spec)
    @test haskey(vl, "resolve")

    # With truth data
    truth = (; x=[1.0, 2.0, 3.0], y=[4.1, 5.1, 6.1])
    layers2 = ppc_overlay(obs, pred; x=:x, y=:y, group=:draw, truth=truth)
    @test layers2 isa AlgebraOfGraphics.Layers
    # truth adds a third layer
    @test length(layers2.layers) == length(layers.layers) + 1

    # With color (model comparison)
    pred2 = (; x=pred.x, y=pred.y, draw=pred.draw, model=repeat(["A"], 6))
    layers3 = ppc_overlay(obs, pred2; x=:x, y=:y, group=:draw, color=:model)
    @test layers3 isa AlgebraOfGraphics.Layers
end

"""
`VL_SCHEMA` is the pinned Vega-Lite v5 schema URL, stamped as `\$schema` on every
top-level spec.
"""
@testitem "VL_SCHEMA constant" setup=[AoVTestImports] tags=[:translation] begin
    @test AlgebraOfVega.VL_SCHEMA == "https://vega.github.io/schema/vega-lite/v5.json"

    # All top-level specs should have schema
    df = (; x=[1], y=[2])
    vl = to_vegalite(data(df) * mapping(:x, :y) * visual(Scatter))
    @test vl["\$schema"] == AlgebraOfVega.VL_SCHEMA
end

"""
The dispatch tables: `plottype_to_mark` (`_MARK_MAP`), `plottype_to_mark_props`
(`_MARK_PROPS`), `aog_named_to_vl_channel` (`_CHANNEL_MAP`, with passthrough),
and `selector_to_field`. Unsupported plot types throw.
"""
@testitem "lookup tables" setup=[AoVTestImports] tags=[:translation] begin
    # _MARK_MAP coverage
    @test AlgebraOfVega.plottype_to_mark(Scatter) == "point"
    @test AlgebraOfVega.plottype_to_mark(Lines) == "line"
    @test AlgebraOfVega.plottype_to_mark(BarPlot) == "bar"
    @test AlgebraOfVega.plottype_to_mark(BoxPlot) == "boxplot"
    @test AlgebraOfVega.plottype_to_mark(ECDFPlot) == "line"
    @test_throws ErrorException AlgebraOfVega.plottype_to_mark(Int)  # unsupported

    # _MARK_PROPS
    @test AlgebraOfVega.plottype_to_mark_props(ScatterLines) == Dict{String,Any}("point" => true)
    @test AlgebraOfVega.plottype_to_mark_props(Stairs) == Dict{String,Any}("interpolate" => "step-after")
    @test AlgebraOfVega.plottype_to_mark_props(Scatter) == Dict{String,Any}("filled" => true)

    # _CHANNEL_MAP
    @test AlgebraOfVega.aog_named_to_vl_channel(:color) == "color"
    @test AlgebraOfVega.aog_named_to_vl_channel(:col) == "column"
    @test AlgebraOfVega.aog_named_to_vl_channel(:row) == "row"
    @test AlgebraOfVega.aog_named_to_vl_channel(:group) == "detail"
    @test AlgebraOfVega.aog_named_to_vl_channel(:stack) === nothing
    @test AlgebraOfVega.aog_named_to_vl_channel(:unknown_thing) == "unknown_thing"  # passthrough

    # selector_to_field dispatch
    @test AlgebraOfVega.selector_to_field(:foo)["field"] == "foo"
    @test AlgebraOfVega.selector_to_field(3)["field"] == "column_3"
    p = AlgebraOfVega.selector_to_field(:col => "Label")
    @test p["field"] == "col"
    @test p["title"] == "Label"
end

"""
`ScatterLines` lowers to a line with point markers but never sets Vega-Lite's
`filled` mark property, which would close each colored line into a polygon.
"""
@testitem "ScatterLines stays unfilled" setup=[AoVTestImports] tags=[:translation, :regression] begin
    tbl = (;
        x=[1, 2, 3, 1, 2, 3],
        y=[1.0, 2.0, 1.5, 3.0, 2.5, 4.0],
        subject=["a", "a", "a", "b", "b", "b"],
    )
    vl = to_vegalite(
        data(tbl) * mapping(:x, :y; color=:subject) * visual(ScatterLines),
    )

    @test vl["mark"] == Dict{String,Any}("type" => "line", "point" => true)
    @test !haskey(vl["mark"], "filled")
end

"""
The `ECDFPlot` mark lowers to a stepped line with three `transform`s (two window
+ one calculate) over the synthesized `__ecdf__` field; a color channel adds the
matching window `groupby`.
"""
@testitem "ECDFPlot" setup=[AoVTestImports] tags=[:translation] begin
    # Basic ECDF
    df = (; x=collect(1.0:10.0))
    spec_obj = data(df) * mapping(:x) * visual(ECDFPlot)
    vl = to_vegalite(spec_obj)
    @test vl["mark"]["type"] == "line"
    @test vl["mark"]["interpolate"] == "step-after"
    @test haskey(vl, "transform")
    @test length(vl["transform"]) == 3  # window, window, calculate
    @test vl["encoding"]["x"]["field"] == "x"
    @test vl["encoding"]["y"]["field"] == "__ecdf__"
    @test vl["encoding"]["y"]["type"] == "quantitative"

    # Grouped ECDF with color
    df2 = (; x=[1.0, 2.0, 3.0, 4.0], c=["a", "a", "b", "b"])
    spec_obj2 = data(df2) * mapping(:x, color=:c) * visual(ECDFPlot)
    vl2 = to_vegalite(spec_obj2)
    @test haskey(vl2["encoding"], "color")
    @test vl2["encoding"]["color"]["field"] == "c"
    # Check that groupby is set on window transforms
    @test vl2["transform"][1]["groupby"] == ["c"]
    @test vl2["transform"][2]["groupby"] == ["c"]
end

"""
The pipeline accepts a bare, non-DataFrame Tables.jl source — a `NamedTuple` of
vectors carrying a lazy `TiledCol` coordinate column and a `FillArrays.Fill`
constant — through both a plain mark and a grouped tidybayes lineribbon.
It also pins the empirical `Tables.columntable` question: `Fill` and `TiledCol`
survive the round-trip without densifying. Stand-in for TreeArrays' `TreeData`.
"""
@testitem "non-DataFrame Tables source (NamedTuple + Fill + tiled lazy column)" setup=[AoVTestImports] tags=[:tables, :tidybayes] begin
    using FillArrays

    # Lazy ND->1D tiled column (mirrors `repeat(vals; inner, outer)` without
    # materializing) — a stand-in for TreeArrays' `TreeData` axis-coordinate
    # columns, which flatten combinatorially and must stay lazy until the JSON
    # `values` boundary.
    struct TiledCol{T} <: AbstractVector{T}
        vals::Vector{T}
        inner::Int
        outer::Int
    end
    Base.size(t::TiledCol) = (length(t.vals) * t.inner * t.outer,)
    function Base.getindex(t::TiledCol, i::Int)
        @boundscheck checkbounds(t, i)
        blocklen = length(t.vals) * t.inner
        p = mod1(i, blocklen)
        j = fld(p - 1, t.inner) + 1
        @inbounds t.vals[j]
    end

    # Bare, non-DataFrame Tables.jl source: a plain `NamedTuple` of vectors,
    # with a constant `FillArrays.Fill` column and a lazy `TiledCol` coordinate
    # column — no DataFrames anywhere in this file. Factored out so TreeArrays'
    # real `TreeData` can later be dropped in as a second case (swap the body
    # for `src = tree_data`) exercising the identical asserts below.
    function _nondf_source(; n_x=5, n_draws=8, cats=["a", "b"])
        n = n_x * n_draws * length(cats)
        xs = TiledCol(collect(1:n_x), n_draws, length(cats))
        draw = repeat(1:n_draws, outer=n_x * length(cats))
        cat = repeat(cats, inner=n_x * n_draws)
        ys = Float64.(collect(xs)) .+ Float64.(mod1.(1:n, 7))
        (; x=xs, y=ys, draw=draw, cat=cat, model=FillArrays.Fill("m1", n)), n
    end

    function _assert_nondf_pipeline(src, n)
        # 1. Plain mark over the bare source.
        vl1 = to_vegalite(data(src) * mapping(:x, :y) * visual(Scatter))
        @test vl1["mark"]["type"] == "point"
        @test haskey(vl1, "encoding")
        @test length(vl1["data"]["values"]) == n

        # 2. Tidybayes lineribbon, grouped: `draw` (8 samples per (x, cat) cell)
        # is the AoG tidybayes sample dimension `compute_ribbon_summary`
        # aggregates over; `cat` is the varying group/color column that must
        # actually partition the data — this exercises `_group_indices` for real
        # (multi-row groups), including grouping BY the lazy `TiledCol` `x`.
        vl2 = to_vegalite(data(src) * mapping(:x, :y, group=:draw, color=:cat) * lineribbon())
        @test haskey(vl2, "layer")
        @test length(vl2["layer"]) >= 2
    end

    src, n = _nondf_source()
    @test src isa NamedTuple
    _assert_nondf_pipeline(src, n)

    ct = Tables.columntable(src)

    # 3. THE EMPIRICAL QUESTION: does Tables.columntable preserve `Fill`
    # (O(1) storage) or densify it into a plain Vector?
    fill_type = typeof(ct.model)
    println("Tables.columntable(src).model :: ", fill_type)
    @test ct.model isa FillArrays.Fill
    @test collect(ct.model) == collect(src.model)

    # 4. Same empirical question for the lazy tiled coordinate column.
    tiled_type = typeof(ct.x)
    println("Tables.columntable(src).x :: ", tiled_type)
    @test ct.x isa TiledCol
    @test collect(ct.x) == collect(src.x)
end

"""
Ungrouped point/gradient/dot interval analyses emit summary data instead of an
empty plot, while explicitly grouped data still yields one row per group.
"""
@testitem "ungrouped interval analyses emit a summary row" setup=[AoVTestImports] tags=[:tidybayes, :regression] begin
    # Regression: with NO group/color/facet/detail field, `_group_indices` used
    # to return an empty Dict, so the interval summaries produced zero rows and
    # the spec serialized as `data.values: []` — a blank plot, no error.
    v = collect(range(-2.0, 2.0; length=64))
    tbl = (; value=v)

    for an in (pointinterval(), gradient_interval())
        vl = to_vegalite(data(tbl) * mapping(:value) * an)
        rows = vl["data"]["values"]
        @test length(rows) == 1
        @test rows[1]["__point__"] ≈ Statistics.quantile(v, 0.5)
        @test rows[1][AlgebraOfVega._vl_prob_field("lo", 0.95)] ≈ Statistics.quantile(v, 0.025)
        @test rows[1][AlgebraOfVega._vl_prob_field("hi", 0.95)] ≈ Statistics.quantile(v, 0.975)
    end

    # dotinterval carries its rows on per-layer data instead of a top-level one.
    dvl = to_vegalite(data(tbl) * mapping(:value) * dotinterval())
    layer_rows = [length(l["data"]["values"]) for l in dvl["layer"] if haskey(l, "data")]
    @test !isempty(layer_rows)
    @test all(>(0), layer_rows)

    # Grouping still works and is unaffected.
    g = (; value=vcat(v, v), grp=vcat(fill("a", 64), fill("b", 64)))
    gvl = to_vegalite(data(g) * mapping(:value; color=:grp) * pointinterval())
    @test length(gvl["data"]["values"]) == 2
end

"""
A pre-aggregated `lineribbon(bands=...)` over an EMPTY table serializes to an
empty ribbon (`data.values: []`) rather than 500-ing — e.g. a single-study
facet page whose study has no rows after dropping NaNs.
"""
@testitem "pre-aggregated lineribbon over an empty table" setup=[AoVTestImports] tags=[:tidybayes, :regression] begin
    # Regression: preaggregate() emits `Any`-eltype group-key columns, so an
    # empty result made `table_to_rows` infer `Vector{Any}`, which missed
    # `_ribbon_to_vl(::Vector{<:Dict{String}})` — MethodError, a 500 on valid
    # (empty) input.
    agg = AlgebraOfVega.preaggregate((study=String[], x=Float64[], y=Float64[]);
                                     y=:y, group_keys=[:study, :x], probs=[0.025, 0.5, 0.975])
    med = Symbol(AlgebraOfVega._quantile_colname(0.5))
    lo = Symbol(AlgebraOfVega._quantile_colname(0.025))
    hi = Symbol(AlgebraOfVega._quantile_colname(0.975))

    # no colour and colour-grouped both used to throw; both must now serialize.
    vl = to_vegalite(data(agg) * mapping(:x, med => "Response") * lineribbon(bands=[lo => hi]))
    @test isempty(vl["data"]["values"])
    vlc = to_vegalite(data(agg) * mapping(:x, med => "Response", color=:study) * lineribbon(bands=[lo => hi]))
    @test isempty(vlc["data"]["values"])

    # Non-empty is unaffected: one row per (study, x) cell.
    ne = AlgebraOfVega.preaggregate((study=["A", "A", "B", "B"], x=[1.0, 2.0, 1.0, 2.0], y=[0.1, 0.2, 0.3, 0.4]);
                                    y=:y, group_keys=[:study, :x], probs=[0.025, 0.5, 0.975])
    nvl = to_vegalite(data(ne) * mapping(:x, med => "Response", color=:study) * lineribbon(bands=[lo => hi]))
    @test length(nvl["data"]["values"]) == 4
end

"""
Interval analyses reject a non-numeric default value channel with a useful
orientation hint; both documented vertical spellings remain valid.
"""
@testitem "interval analyses reject a non-numeric value column" setup=[AoVTestImports] tags=[:tidybayes, :regression] begin
    # Regression: `mapping(category, value)` is the :vertical form. Under the
    # default :horizontal it summarized the CATEGORY column, which used to blow
    # up as `MethodError: isfinite(::String)` from inside Statistics.
    tbl = (; parameter=repeat(["a", "b"], inner=8), value=randn(16))

    err = try
        to_vegalite(data(tbl) * mapping(:parameter, :value; color=:parameter) * pointinterval())
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("parameter", err.msg)
    @test occursin("orientation=:vertical", err.msg)

    # Both documented spellings keep working.
    @test length(to_vegalite(data(tbl) * mapping(:value; y=:parameter) * pointinterval())["data"]["values"]) == 2
    @test length(to_vegalite(data(tbl) * mapping(:parameter, :value) * pointinterval(orientation=:vertical))["data"]["values"]) == 2
end

"""
The structural `plot_size` estimator computes `(width, height)` from a Vega-Lite
spec Dict — continuous vs discrete axes, title/axis chrome, facet operator and
row/column shorthand, `config.view.step` / `config.facet.spacing` overrides,
`width:"container"` fallback, and explicit numeric sizes. The `Layer`/`VegaSpec`
convenience method lowers through `to_vegalite` into the same estimator.
"""
@testitem "plot_size structural estimator" setup=[AoVTestImports] tags=[:plotsize] begin
    # Unit tests over hand-built VL spec Dicts — the four geometries plot_size
    # claims to handle, plus the config overrides and the width:"container"
    # guard. Exact px follow deterministically from the named VL-default +
    # chrome-overhead constants (continuous 200, discrete step 20, facet spacing
    # 20, axis 40, title 30, facet-header 20). See plot_size.jl.
    D(kv...) = Dict{String,Any}(kv...)
    vals(v) = D("values" => v)
    q(f) = D("field" => f, "type" => "quantitative")
    nom(f) = D("field" => f, "type" => "nominal")

    # 1. plain continuous scatter → 200 + 40 (axis) each way.
    @test plot_size(D("mark" => "point", "encoding" => D("x" => q("a"), "y" => q("b")),
                      "data" => vals([D("a" => 1, "b" => 2)]))) == (; width = 240.0, height = 240.0)

    # 2. title band adds 30 to height only.
    @test plot_size(D("mark" => "point", "title" => "T", "encoding" => D("x" => q("a"), "y" => q("b")),
                      "data" => vals([D("a" => 1, "b" => 2)]))) == (; width = 240.0, height = 270.0)

    # 3. categorical-y (4 nominal bands) → 4*20 tall panel; +30 title.
    @test plot_size(D("mark" => "bar", "title" => "T", "encoding" => D("x" => q("v"), "y" => nom("g")),
                      "data" => vals([D("g" => "a", "v" => 1), D("g" => "b", "v" => 2),
                                      D("g" => "c", "v" => 3), D("g" => "d", "v" => 4)]))) ==
        (; width = 240.0, height = 150.0)

    # 4. facet operator, single field, columns:1, N=3, inner explicit 500x60; +title.
    @test plot_size(D("title" => "T", "facet" => nom("grp"), "columns" => 1,
                      "spec" => D("width" => 500, "height" => 60,
                                  "layer" => [D("mark" => "area", "encoding" => D("x" => q("v")))]),
                      "data" => vals([D("grp" => "a"), D("grp" => "b"), D("grp" => "c")]))) ==
        (; width = 540.0, height = 310.0)

    # 5. facet operator, single field, columns:3, N=6 → wraps to 2 rows x 3 cols.
    @test plot_size(D("facet" => nom("grp"), "columns" => 3,
                      "spec" => D("encoding" => D("x" => q("v"), "y" => q("w"))),
                      "data" => vals([D("grp" => string(i)) for i in 1:6]))) ==
        (; width = 700.0, height = 480.0)

    # 6. encoding-shorthand row(2) x column(3) facet; +title.
    @test plot_size(D("mark" => "point", "title" => "T",
                      "encoding" => D("x" => q("a"), "y" => q("b"), "row" => nom("r"), "column" => nom("c")),
                      "data" => vals([D("r" => ri, "c" => ci, "a" => 1, "b" => 2)
                                      for ri in ["x", "y"] for ci in ["p", "q", "s"]]))) ==
        (; width = 700.0, height = 510.0)

    # 7. config.view.step override honoured on a discrete axis (5 bands * 30).
    @test plot_size(D("encoding" => D("y" => D("field" => "g", "type" => "ordinal"), "x" => q("v")),
                      "config" => D("view" => D("step" => 30)),
                      "data" => vals([D("g" => string(i), "v" => i) for i in 1:5]))) ==
        (; width = 240.0, height = 190.0)

    # 8. explicit numeric top-level width/height win over the structural model.
    @test plot_size(D("width" => 400, "height" => 300, "encoding" => D("x" => q("a")),
                      "data" => vals(Any[]))) == (; width = 440.0, height = 340.0)

    # 9. width:"container" is non-numeric → continuous fallback, no crash.
    @test plot_size(D("width" => "container", "encoding" => D("x" => q("a"), "y" => q("b")),
                      "data" => vals([D("a" => 1, "b" => 2)]))) == (; width = 240.0, height = 240.0)

    # 10. config.facet.spacing override changes the inter-panel gap (3 panels → 2 gaps).
    @test plot_size(D("facet" => nom("grp"), "columns" => 1,
                      "spec" => D("width" => 500, "height" => 60,
                                  "layer" => [D("mark" => "area", "encoding" => D("x" => q("v")))]),
                      "config" => D("facet" => D("spacing" => 40)),
                      "data" => vals([D("grp" => "a"), D("grp" => "b"), D("grp" => "c")]))) ==
        (; width = 540.0, height = 320.0)

    # 11. cardinality scan dedupes: repeated facet-field values count once.
    @test plot_size(D("facet" => nom("grp"), "columns" => 1,
                      "spec" => D("width" => 500, "height" => 60,
                                  "layer" => [D("mark" => "area", "encoding" => D("x" => q("v")))]),
                      "data" => vals([D("grp" => "a"), D("grp" => "a"), D("grp" => "b")]))).height ==
        plot_size(D("facet" => nom("grp"), "columns" => 1,
                    "spec" => D("width" => 500, "height" => 60,
                                "layer" => [D("mark" => "area", "encoding" => D("x" => q("v")))]),
                    "data" => vals([D("grp" => "a"), D("grp" => "b")]))).height  # 2 distinct panels either way

    # 12. destructuring + field-access contract.
    let s = D("mark" => "point", "encoding" => D("x" => q("a"), "y" => q("b")),
              "data" => vals([D("a" => 1, "b" => 2)]))
        w, h = plot_size(s)
        @test w == 240.0 && h == 240.0
        @test plot_size(s).width == 240.0
        @test plot_size(s).height == 240.0
    end

    # Integration: the Layer/Layers/VegaSpec convenience method lowers via
    # to_vegalite, so real emission flows through the same estimator.
    # Invariants only here (not exact px): the exact structural model is pinned
    # by the Dict-method cases above; this just proves the convenience method
    # lowers a real spec through to_vegalite and out the same estimator.
    df = (; x = [1.0, 2.0, 3.0], y = [4.0, 5.0, 6.0], g = ["a", "b", "c"])
    plain = plot_size(data(df) * mapping(:x, :y) * visual(Scatter))
    @test plain isa NamedTuple && plain.width > 0 && plain.height > 0

    # A col-faceted spec is wider than the same single-panel spec (more columns).
    faceted = plot_size(data(df) * mapping(:x, :y, col=:g) * visual(Scatter))
    @test faceted.width > plain.width
end

"""
A plot node's `text/markdown` rendering (the `?plain` channel) is non-empty and
structurally faithful, while its HTML rendering is unchanged.

Regression: `to_node` emits an empty `<div>` plus a `<script>`; HTMX's markdown
renderer recurses transparently through `<div>` and skips `<script>`, so a
figure-only route served a 0-byte `?plain` body — making "renders a correct
figure" byte-indistinguishable from "renders nothing" for every non-browser
consumer.
"""
@testitem "plot nodes render a bounded markdown summary" setup=[AoVTestImports] tags=[:markdown, :regression] begin
    md(x) = sprint(show, MIME"text/markdown"(), x)
    html(x) = sprint(show, MIME"text/html"(), x)

    D(ps...) = Dict{String,Any}(ps...)
    q(f) = D("field" => f, "type" => "quantitative")
    nom(f) = D("field" => f, "type" => "nominal")

    # --- Dict-level: the summary content is pinned exactly. ---
    spec = D("mark" => "bar",
             "encoding" => D("y" => q("count"), "x" => nom("species"), "color" => nom("island")),
             "width" => 400, "height" => 300,
             "data" => D("values" => [D("species" => "a", "count" => 1, "island" => "x")]))
    s = plot_summary_md(spec; id="vega-abc")
    @test occursin("**Vega-Lite figure** `vega-abc`", s)
    @test occursin("- mark: `bar`", s)
    @test occursin("- data: 1 rows × 3 columns (inline)", s)
    @test occursin("- size: 400 × 300", s)
    # Canonical channel order (x before y before color), not Dict iteration order.
    let ix = first(findfirst("| x |", s)),
        iy = first(findfirst("| y |", s)),
        ic = first(findfirst("| color |", s))
        @test ix < iy < ic
    end
    @test occursin("| color | island | nominal |", s)
    # Data VALUES are never emitted — only counts.
    @test !occursin("\"a\"", s)

    # Faceted specs: the partition channel is reported, and the nested
    # `spec.width` is found.
    fac = D("facet" => D("column" => nom("island")),
            "spec" => D("width" => 200, "mark" => "point", "encoding" => D("x" => q("v"))),
            "data" => D("values" => [D("island" => "x", "v" => 1)]))
    @test occursin("- facet: `island`", plot_summary_md(fac))
    @test occursin("- size: 200 × auto", plot_summary_md(fac))

    # Layered specs list every distinct mark and the layer count.
    lay = D("layer" => [D("mark" => "line", "encoding" => D("x" => q("a"))),
                        D("mark" => "point", "encoding" => D("y" => q("b")))])
    @test occursin("- mark: `line` + `point` (2 layers)", plot_summary_md(lay))

    # Multi-field channels (tooltip) list field names, not the raw container.
    tip = D("mark" => "bar",
            "encoding" => D("tooltip" => [nom("g"), q("v")]))
    @test occursin("| tooltip | g, v |", plot_summary_md(tip))
    @test !occursin("Dict", plot_summary_md(tip))

    # Bounded: a wide encoding elides, and says so.
    wide = D("mark" => "point",
             "encoding" => D(string("c", i) => q("f$i") for i in 1:30))
    ws = plot_summary_md(wide)
    @test occursin("more channels elided", ws)
    @test count("\n| ", ws) <= 16  # header + separator + 12 rows + elision row

    # A spec with no encoding at all still names its mark (never empty).
    bare = plot_summary_md(D("mark" => "rect"))
    @test occursin("- mark: `rect`", bare)
    @test occursin("no encoding channels", bare)

    # --- Integration: through the real node. ---
    df = (; x = [1.0, 2.0, 3.0], y = [4.0, 5.0, 6.0], g = ["a", "b", "c"])
    node = vdraw(data(df) * mapping(:x, :y, color=:g) * visual(Scatter))
    @test !isempty(md(node))
    @test occursin("**Vega-Lite figure**", md(node))
    @test occursin("`point`", md(node))

    # The summary is markdown-ONLY: it must contribute ZERO bytes of HTML, so
    # the rendered page is byte-identical to the same node without it.
    @test !occursin("Vega-Lite figure", html(node))
    @test !occursin("| channel |", html(node))
    let kids = HTMX.children(node)
        @test last(kids) isa PlotSummary
        @test html(node) == html(HTMX.Node(HTMX.tag(node), HTMX.attrs(node), kids[1:end-1]))
    end

    # The property that actually matters: a route rendering a real figure is not
    # byte-identical to one rendering nothing, nor to a different figure.
    @test md(node) != ""
    @test md(node) != md(h.div())
    @test md(node) != md(vdraw(data(df) * mapping(:x, :y) * visual(BarPlot)))

    # A spec returned directly (no `vdraw`) gets the same summary rather than
    # falling to HTMX's `string(val)` catch-all.
    vs = data(df) * mapping(:x, :y) * visual(Scatter) * config(width=300)
    @test occursin("**Vega-Lite figure**", md(vs))
    @test occursin("- mark: `point`", md(vs))
end

"""
`density()` honours the `col=` / `row=` / `layout=` facet channels, like every
other analysis. It used to read only `y=` and `color=`, so a faceted density
emitted a FLAT spec with no facet operator at all — one KDE pooled over every
panel's rows, rendered as a single plausible-looking curve.

A faceted density is now PREAGGREGATED in Julia (`compute_density_summary`), so
the emitted spec carries `data.values` of `{val, dens, <group fields>}` rows and
no `density` transform. The grouping key is asserted here through those rows;
the per-panel extents that motivated the preaggregation are the next item.
"""
@testitem "density honours col=/row=/layout= faceting" setup=[AoVTestImports] tags=[:translation, :regression] begin
    # Every group must have enough rows for a KDE, so the grid case (col= × row=)
    # needs a real cell population — hence chains × draws, not one row per cell.
    params = ["a", "b", "c"]
    ndraw = 40
    tbl = (; parameter = repeat(params, inner=2ndraw),
             chain     = repeat(repeat([1, 2], inner=ndraw), outer=3),
             value     = vcat((randn(2ndraw) .+ 10i for i in 1:3)...))

    # group field → sorted distinct levels present in the emitted KDE rows
    levels(vl, field) = sort(unique(r[field] for r in vl["data"]["values"]))
    rowkeys(vl) = sort(collect(keys(first(vl["data"]["values"]))))

    # --- The reported case: col= produced a flat, pooled, single-curve spec. ---
    vl = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter) * density())
    @test vl["facet"]["column"]["field"] == "parameter"
    @test haskey(vl, "spec")                      # the facet OPERATOR, not encoding.column
    @test !haskey(vl, "mark")                     # mark moved inside `spec`
    @test !haskey(vl["spec"], "transform")        # preaggregated: no VL density transform
    @test vl["spec"]["mark"]["type"] == "area"
    @test vl["data"]["values"] isa AbstractVector  # data stays OUTSIDE the facet
    @test rowkeys(vl) == ["dens", "parameter", "val"]
    @test levels(vl, "parameter") == params

    # --- row= takes the other grid channel. ---
    rvl = to_vegalite(vdata(tbl) * mapping(:value; row=:parameter) * density())
    @test rvl["facet"]["row"]["field"] == "parameter"
    @test levels(rvl, "parameter") == params

    # --- layout= is the WRAP form, so a sibling `columns` actually governs. ---
    lvl = to_vegalite(vdata(tbl) * mapping(:value; layout=:parameter) * density() * config(columns=3))
    @test lvl["facet"]["field"] == "parameter"    # wrap form: facet:{field,type}
    @test !haskey(lvl["facet"], "column")
    @test lvl["columns"] == 3
    @test levels(lvl, "parameter") == params

    # --- col= AND row= together: both grid channels, both in the grouping key. ---
    gvl = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter, row=:chain) * density())
    @test gvl["facet"]["column"]["field"] == "parameter"
    @test gvl["facet"]["row"]["field"] == "chain"
    @test rowkeys(gvl) == ["chain", "dens", "parameter", "val"]
    @test levels(gvl, "chain") == [1, 2]
    @test levels(gvl, "parameter") == params

    # --- col= plus color=: both are grouping fields, and NOT duplicated when
    #     they name the same field (a repeated key would double every curve).
    cvl = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter, color=:chain) * density())
    @test rowkeys(cvl) == ["chain", "dens", "parameter", "val"]
    @test cvl["spec"]["encoding"]["color"]["field"] == "chain"
    same = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter, color=:parameter) * density())
    @test rowkeys(same) == ["dens", "parameter", "val"]
    @test length(same["data"]["values"]) == 3 * 200   # 3 groups, not 3 groups twice over

    # --- `config(facet=(; linkxaxes=:none))` now lands on a spec that HAS a
    #     facet to resolve against — the reported spec carried it over nothing.
    fvl = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter) * density() *
                      config(width=160, height=180, facet=(; linkxaxes=:none)))
    @test fvl["resolve"]["scale"]["x"] == "independent"
    @test haskey(fvl, "facet")
    @test fvl["spec"]["width"] == 160             # size routes INTO the inner spec
    @test fvl["spec"]["height"] == 180

    # --- Unfaceted output is untouched: it KEEPS the VL density transform (one
    #     shared axis wants one shared extent, and the curve stays live under a
    #     brush selection). Bare density has no groupby at all; colour-only keeps
    #     exactly the single-field groupby it always had.
    bare = to_vegalite(vdata(tbl) * mapping(:value) * density())
    @test !haskey(bare["transform"][1], "groupby")
    @test bare["transform"][1]["density"] == "value"
    @test !haskey(bare, "facet")
    conly = to_vegalite(vdata(tbl) * mapping(:value; color=:parameter) * density())
    @test conly["transform"][1]["groupby"] == ["parameter"]
    @test !haskey(conly, "facet")

    # --- The `y=` ridgeline already owns the facet operator and VL cannot nest
    #     two, so a sibling col= is named in a warning rather than dropped mute.
    ridge = @test_logs (:warn,) match_mode=:any to_vegalite(
        vdata(tbl) * mapping(:value; y=:parameter, col=:chain) * density())
    @test ridge["facet"]["field"] == "parameter"   # ridgeline preserved
    @test ridge["columns"] == 1

    # --- Multi-layer (`+`): the density sublayer's precomputed rows are merged
    #     into the shared faceted dataset behind a `__src` filter, and they carry
    #     the facet field so the lifted facet has something to partition on.
    mvl = to_vegalite((vdata(tbl) * mapping(:value; col=:parameter) * density()) +
                      (vdata(tbl) * mapping(:value; col=:parameter) * visual(Scatter)))
    @test mvl["facet"]["column"]["field"] == "parameter"
    dens_sub = only(l for l in mvl["spec"]["layer"] if l["mark"]["type"] == "area")
    @test !any(haskey(t, "density") for t in dens_sub["transform"])
    dens_tag = match(r"'(\w+)'", only(t for t in dens_sub["transform"])["filter"])[1]
    dens_rows = [r for r in mvl["data"]["values"] if r["__src"] == dens_tag]
    @test length(dens_rows) == 3 * 200
    @test sort(unique(r["parameter"] for r in dens_rows)) == params
end

"""
A faceted `density()` samples each panel over its OWN `[min, max]`.

Vega-Lite's `density` transform computes ONE extent for the whole dataset even
when it carries a `groupby`. Measured against a headless Vega render, two groups
drawn from `N(0,1)` and `N(1000,50)` both came back spanning the pooled
`[-2.62, 1136.16]`, so the tight group occupied a fraction of a percent of its
own panel — and `resolve.scale.x = independent` cannot repair it, because the
shared quantity is the DATA extent, not the scale.

`compute_density_summary` replaces the transform for faceted specs. It matches
vega-statistics exactly where it can (`bandwidthNRD`; verified to ~2e-15 relative
against `vega.randomKDE`) and differs only in the one place that is the point:
the grid is per group.
"""
@testitem "density computes per-panel KDE extents" setup=[AoVTestImports] tags=[:translation, :regression] begin
    n = 200
    # Three parameters on wildly different scales — the shape that made the
    # shared extent visible in the first place.
    tbl = (; parameter = repeat(["tight", "mid", "wide"], inner=n),
             value     = vcat(0.5 .+ 0.1 .* randn(n),
                              3.0 .+ 0.4 .* randn(n),
                              1000.0 .+ 50.0 .* randn(n)))
    raw = Dict(p => [tbl.value[i] for i in eachindex(tbl.value) if tbl.parameter[i] == p]
               for p in unique(tbl.parameter))

    vl = to_vegalite(vdata(tbl) * mapping(:value; col=:parameter) * density())
    rows = vl["data"]["values"]
    @test length(rows) == 3 * 200          # npoints=200 per group (AoG's default, Vega's maxsteps)

    # `stack: null` is part of the fix, not tidiness: a stacked VL `area` imputes
    # every series out to the UNION of all series' x values, and it does so before
    # the facet split — which put the pooled extent straight back into every panel.
    @test haskey(vl["spec"]["encoding"]["y"], "stack")
    @test isnothing(vl["spec"]["encoding"]["y"]["stack"])
    # The unfaceted path keeps the VL transform but is unstacked too — densities
    # overlay, they do not stack (user decision `1ceow72`). Both spellings, since
    # only the colour-grouped one had anything to stack in the first place.
    unf = to_vegalite(vdata(tbl) * mapping(:value) * density())
    @test haskey(unf["encoding"]["y"], "stack") && isnothing(unf["encoding"]["y"]["stack"])
    @test haskey(unf, "transform")   # …and it is still the transform, not preaggregated rows
    unf_c = to_vegalite(vdata(tbl) * mapping(:value; color=:parameter) * density())
    @test haskey(unf_c["encoding"]["y"], "stack") && isnothing(unf_c["encoding"]["y"]["stack"])
    @test haskey(unf_c, "transform")

    for (p, vals) in raw
        grid = [r["val"] for r in rows if r["parameter"] == p]
        dens = [r["dens"] for r in rows if r["parameter"] == p]
        @test length(grid) == 200
        # The panel's grid is EXACTLY its own group's observed range — the same
        # convention the VL transform's default extent uses, applied per group.
        @test minimum(grid) == minimum(vals)
        @test maximum(grid) == maximum(vals)
        @test issorted(grid)
        @test all(>=(0), dens)
        # A pdf on its own support: the truncated trapezoid area is just under 1.
        area = sum((grid[i+1] - grid[i]) * (dens[i+1] + dens[i]) / 2 for i in 1:199)
        @test 0.9 < area <= 1.0
    end

    # The three extents are disjoint — under the old shared extent all three
    # spanned the pooled range and this test could not tell them apart.
    ext(p) = extrema(r["val"] for r in rows if r["parameter"] == p)
    @test ext("tight")[2] < ext("mid")[1]
    @test ext("mid")[2] < ext("wide")[1]

    # A group with no computable KDE (every value identical, or a single row) is
    # dropped with a warning rather than emitting a spike or a NaN curve.
    degen = (; parameter = ["a", "a", "a", "b", "b", "b"],
               value     = [1.0, 1.0, 1.0, 2.0, 3.0, 4.0])
    dvl = @test_logs (:warn, r"no computable KDE") match_mode=:any to_vegalite(
        vdata(degen) * mapping(:value; col=:parameter) * density())
    @test sort(unique(r["parameter"] for r in dvl["data"]["values"])) == ["b"]

    # The `y=` ridgeline is preaggregated too. With the VL transform this
    # single-sublayer spec was hoisted above the facet split: one pooled curve,
    # and — the transform having dropped the level field — a single panel.
    rvl = to_vegalite(vdata(tbl) * mapping(:value; y=:parameter) * density())
    @test rvl["facet"]["field"] == "parameter"
    @test rvl["columns"] == 1
    rrows = rvl["data"]["values"]
    @test length(rrows) == 3 * 200
    @test sort(collect(keys(first(rrows)))) == ["dens", "parameter", "val"]
    @test !haskey(only(rvl["spec"]["layer"]), "transform")
    @test isnothing(only(rvl["spec"]["layer"])["encoding"]["y"]["stack"])
    for (p, vals) in raw
        grid = [r["val"] for r in rrows if r["parameter"] == p]
        @test minimum(grid) == minimum(vals)
        @test maximum(grid) == maximum(vals)
    end
end
