using TestItemRunner

# Shared imports — re-evaluated independently inside every test item that lists
# `AoVTestImports` in its `setup`. Test bodies stay isolated; each item module
# gets its own copy of these `using`s. `Test` is injected automatically.
@testsnippet AoVTestImports begin
    using AlgebraOfVega
    using AlgebraOfGraphics
    using Tables
    using HTMX
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
    @test occursin("display:none;", html)

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
    @test occursin("display:none;", html)
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
    @test occursin("display:none;", html)

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
    @test vl["mark"] == "point"
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
    @test AlgebraOfVega.plottype_to_mark_props(Scatter) == Dict{String,Any}()

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
