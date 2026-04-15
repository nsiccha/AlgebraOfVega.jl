using TestModules
using AlgebraOfVega
using AlgebraOfGraphics
using Tables
using HTMX

@testset "classify_columns" begin
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

@testset "table_to_rows" begin
    nt = AlgebraOfVega.sample_tips()
    rows = AlgebraOfVega.table_to_rows(nt)
    @test length(rows) == length(nt.total_bill)
    @test rows[1] isa Dict{String,Any}
    @test rows[1]["total_bill"] == nt.total_bill[1]
    @test rows[1]["sex"] == nt.sex[1]
end

@testset "explorer_js" begin
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

@testset "explorer_controls_html" begin
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

@testset "explorer_widget" begin
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

@testset "explorer_data_init_js" begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    js = AlgebraOfVega.explorer_data_init_js(datasets)
    @test occursin("_explorerDatasets", js)
    @test occursin("_explorerColumns", js)
end

@testset "sample datasets" begin
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

@testset "filter_include" begin
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

@testset "_default_marks" begin
    marks = AlgebraOfVega._default_marks()
    @test marks isa Vector{Pair{String,String}}
    @test length(marks) == 7
    @test first(first(marks)) == "point"
    @test any(p -> first(p) == "line+ribbon", marks)
end

@testset "explorer_js log scale" begin
    js = AlgebraOfVega.explorer_js()
    @test occursin("ex-log-x", js)
    @test occursin("ex-log-y", js)
    @test occursin("type: 'log'", js)
end

@testset "explorer_js line+ribbon" begin
    js = AlgebraOfVega.explorer_js()
    @test occursin("line+ribbon", js)
    @test occursin("_quantile", js)
    @test occursin("_median", js)
    @test occursin("ex-ribbon-levels", js)
    @test occursin("summaryData", js)
end

@testset "explorer_controls_html log and ribbon" begin
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

@testset "explorer_controls_html dataset hiding" begin
    single = Dict("mydata" => AlgebraOfVega.sample_cars())
    html = AlgebraOfVega.explorer_controls_html(single)
    @test occursin("display:none;", html)
    @test occursin("ex-dataset", html)

    multi = AlgebraOfVega.default_explorer_datasets()
    html2 = AlgebraOfVega.explorer_controls_html(multi)
    @test occursin("Dataset:", html2)
end

@testset "bare table support" begin
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

@testset "explorer_widget log and ribbon" begin
    datasets = AlgebraOfVega.default_explorer_datasets()
    ws = string(AlgebraOfVega.explorer_widget(datasets))
    @test occursin("ex-log-x", ws)
    @test occursin("ex-log-y", ws)
    @test occursin("Log X", ws)
    @test occursin("Log Y", ws)
    @test occursin("ex-ribbon-levels", ws)
    @test occursin("Ribbon levels", ws)
end

@testset "pregrouped boxplot" begin
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

@testset "vdata alias" begin
    df = (; x=[1, 2, 3], y=[4, 5, 6])
    # vdata should work identically to data
    spec1 = data(df) * mapping(:x, :y) * visual(Scatter)
    spec2 = vdata(df) * mapping(:x, :y) * visual(Scatter)
    @test to_vegalite(spec1) == to_vegalite(spec2)
end

@testset "independent_scales config" begin
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

@testset "scales / facet config (AoG mirror)" begin
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
end

@testset "VL helpers" begin
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

@testset "extract_transformation generic" begin
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

@testset "layer_to_vl dispatch" begin
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

@testset "ecdf_grid" begin
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

@testset "ppc_overlay" begin
    obs = (; x=[1.0, 2.0, 3.0], y=[4.0, 5.0, 6.0])
    pred = (; x=[1.0, 1.0, 2.0, 2.0, 3.0, 3.0], y=[3.5, 4.5, 4.5, 5.5, 5.5, 6.5], draw=[1, 2, 1, 2, 1, 2])

    # Basic overlay returns Layers
    layers = ppc_overlay(obs, pred; x=:x, y=:y, group=:draw)
    @test layers isa AlgebraOfGraphics.Layers

    # Composable with config
    spec = layers * config(width=300, height=200, independent_scales=true)
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

@testset "VL_SCHEMA constant" begin
    @test AlgebraOfVega.VL_SCHEMA == "https://vega.github.io/schema/vega-lite/v5.json"

    # All top-level specs should have schema
    df = (; x=[1], y=[2])
    vl = to_vegalite(data(df) * mapping(:x, :y) * visual(Scatter))
    @test vl["\$schema"] == AlgebraOfVega.VL_SCHEMA
end

@testset "lookup tables" begin
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

@testset "ECDFPlot" begin
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
