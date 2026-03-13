using Test
using AlgebraOfVega
using Tables

@testset "AlgebraOfVega" begin

@testset "classify_columns" begin
    nt = AlgebraOfVega.sample_cars()
    cols = AlgebraOfVega.classify_columns(nt)
    @test "horsepower" in cols.numeric
    @test "mpg" in cols.numeric
    @test "origin" in cols.categorical
    @test "origin" ∉ cols.numeric
    @test Set(cols.all) == Set(vcat(cols.numeric, cols.categorical))

    # Works with any Tables.jl columnar table
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
    # default width is 'container'
    @test occursin("'container'", js)
    @test occursin("height: 350", js)

    # namespace and selectors
    js2 = AlgebraOfVega.explorer_js(; namespace="Foo.", plot_selector="#myplot", spec_selector="#myspec")
    @test occursin("Foo.", js2)
    @test occursin("#myplot", js2)
    @test occursin("#myspec", js2)

    # custom width/height
    js3 = AlgebraOfVega.explorer_js(; width=800, height=500)
    @test occursin("width: 800", js3)
    @test occursin("height: 500", js3)
    @test !occursin("'container'", js3)
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

    # default column selections
    html2 = AlgebraOfVega.explorer_controls_html(datasets; default_x="mpg", default_y="horsepower", default_color="origin")
    @test occursin("<option value=\"mpg\" selected>", html2)
    @test occursin("<option value=\"horsepower\" selected>", html2)
    @test occursin("<option value=\"origin\" selected>", html2)

    # custom marks
    html3 = AlgebraOfVega.explorer_controls_html(datasets; marks=["point" => "scatter", "line" => "line"])
    @test occursin("scatter", html3)
    @test !occursin("boxplot", html3)

    # default mark selection
    html4 = AlgebraOfVega.explorer_controls_html(datasets; default_mark="line")
    @test occursin("<option value=\"line\" selected>", html4)
end

@testset "explorer_widget" begin
    datasets = AlgebraOfVega.default_explorer_datasets()

    # default usage
    w = AlgebraOfVega.explorer_widget(datasets)
    @test w !== nothing

    # custom title/subtitle
    w2 = AlgebraOfVega.explorer_widget(datasets; title="My Explorer", subtitle="Custom subtitle")
    @test w2 !== nothing

    # hidden title/subtitle
    w3 = AlgebraOfVega.explorer_widget(datasets; title=nothing, subtitle=nothing)
    @test w3 !== nothing

    # show_spec=false
    w4 = AlgebraOfVega.explorer_widget(datasets; show_spec=false)
    @test w4 !== nothing

    # custom defaults
    w5 = AlgebraOfVega.explorer_widget(datasets;
        default_x="mpg", default_y="horsepower", default_color="origin",
        default_mark="line", width=800, height=400)
    @test w5 !== nothing

    # custom marks
    w6 = AlgebraOfVega.explorer_widget(datasets; marks=["point" => "scatter"])
    @test w6 !== nothing
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
        # All columns same length
        for c in cols
            @test length(Tables.getcolumn(tbl, c)) == n
        end
    end
end

@testset "_default_marks" begin
    marks = AlgebraOfVega._default_marks()
    @test marks isa Vector{Pair{String,String}}
    @test length(marks) == 6
    @test first(first(marks)) == "point"
end

end
