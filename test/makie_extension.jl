using TestItemRunner

"""
`using AlgebraOfVega` loads neither Makie nor AlgebraOfGraphics (snag
`aov-load-cost-ma-f778daf2`, Bruno decision `1sw34ux`: AlgebraOfGraphics needs
Makie, and the two made up most of the load of a Vega-only consumer). AoV owns
its algebra; the static path is the `AlgebraOfVegaMakieExt` extension, and
calling it without the extension names what to load. Makie alone loads
`AlgebraOfVegaMakiePlotTypesExt`, so `visual(Makie.Text)` reads as
`visual(AlgebraOfVega.Makie.Text)` without AlgebraOfGraphics. Checked in a fresh
process, since this test process imports AlgebraOfGraphics.
"""
@testitem "using AlgebraOfVega loads no Makie" tags=[:load, :static] begin
    script = """
        using AlgebraOfVega
        loaded = Set(string(k.name) for k in keys(Base.loaded_modules))
        println("MAKIE=", "Makie" in loaded)
        println("AOG=", "AlgebraOfGraphics" in loaded)
        println("HTMXOEXT=", !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaHTMXObjectsExt)))
        spec = data((; x=[1, 2], y=[3, 4])) * mapping(:x, :y) * visual(Scatter)
        println("MARK=", to_vegalite(spec)["mark"]["type"])
        msg = try
            sdraw_file(spec, "unused.png"); "no error"
        catch err
            sprint(showerror, err)
        end
        println("HINT=", occursin("AlgebraOfVegaMakieExt", msg))
        # Makie alone (no AlgebraOfGraphics): its plot types and values are read,
        # but the drawing extension stays unloaded.
        import Makie
        println("TYPESEXT=", !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaMakiePlotTypesExt)))
        println("DRAWEXT=", !isnothing(Base.get_extension(AlgebraOfVega, :AlgebraOfVegaMakieExt)))
        t = data((; x=[1, 2], y=[3, 4], s=["a", "b"])) * mapping(:x, :y; text=:s => verbatim)
        println("MAKIETEXT=", to_vegalite(t * visual(Makie.Text)) == to_vegalite(t * visual(AlgebraOfVega.Makie.Text)))
        """
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $script`
    out = read(cmd, String)
    @test occursin("MAKIE=false", out)
    @test occursin("AOG=false", out)
    @test occursin("HTMXOEXT=true", out)
    @test occursin("MARK=point", out)
    @test occursin("HINT=true", out)
    @test occursin("TYPESEXT=true", out)
    @test occursin("DRAWEXT=false", out)
    @test occursin("MAKIETEXT=true", out)
end

"""
The plot-type vocabulary and the Makie extension's compatibility surfaces:
`AlgebraOfVega.Makie` stays an alias of the vocabulary (consumers spell
`visual(AlgebraOfVega.Makie.Text)`, `.Scatter`, `.Lines`, `.Rangebars`), Makie's
own plot types are accepted by `visual` and lower identically, tokens map back
to Makie's exported plot types, AlgebraOfGraphics' own helpers and Makie's
`pseudolog10` keep their meaning in an AoV spec, and
`AlgebraOfGraphics.draw`/`draw!` accept AoV specs.
"""
@testitem "plot-type vocabulary and the Makie extension" tags=[:static, :translation] begin
    using AlgebraOfVega
    import AlgebraOfGraphics, Makie
    tbl = (; x=[1.0, 2.0], y=[3.0, 4.0], label=["a", "b"])

    @test AlgebraOfVega.Makie === AlgebraOfVega.PlotTypes
    @test Scatter === AlgebraOfVega.PlotTypes.Plot{:scatter}
    for name in (:Text, :Scatter, :Lines, :Rangebars)
        @test getfield(AlgebraOfVega.Makie, name) === AlgebraOfVega.PlotTypes.Plot{Symbol(lowercase(string(name)))}
    end
    vl_text = to_vegalite(data(tbl) * mapping(:x, :y; text=:label => verbatim) *
                          visual(AlgebraOfVega.Makie.Text))
    @test vl_text["mark"] == "text" || vl_text["mark"]["type"] == "text"

    ext = Base.get_extension(AlgebraOfVega, :AlgebraOfVegaMakieExt)
    @test !isnothing(ext)
    @test to_vegalite(data(tbl) * mapping(:x, :y) * visual(Makie.Scatter; markersize=8)) ==
          to_vegalite(data(tbl) * mapping(:x, :y) * visual(Scatter; markersize=8))
    @test to_vegalite(data(tbl) * mapping(:x, :y; text=:label => verbatim) * visual(Makie.Text)) == vl_text
    @test AlgebraOfVega.extract_visual(visual(Makie.Lines)).plottype === Lines
    @test ext._makie_plottype(Scatter) === Makie.Scatter
    @test ext._makie_plottype(AlgebraOfVega.Makie.Text) === Makie.Text
    @test ext._makie_plottype(HSpan) === Makie.HSpan
    @test ext._makie_plottype(AlgebraOfVega.PlotTypes.Plot{:plot}) == Makie.Plot{Makie.plot}

    spec = data(tbl) * mapping(:x, :y; color=:label => sorter("b", "a")) * visual(Scatter) +
           data(tbl) * mapping(:x, :y) * visual(Lines; linestyle=:dash)
    aog = ext._to_aog(spec)
    @test aog isa AlgebraOfGraphics.Layers
    @test aog.layers[1].named[:color] == (:label => AlgebraOfGraphics.sorter("b", "a"))
    @test aog.layers[1].data isa AlgebraOfGraphics.Columns
    @test AlgebraOfGraphics.draw(spec) isa AlgebraOfGraphics.FigureGrid
    @test !isempty(AlgebraOfGraphics.draw!(Makie.Figure()[1, 1], spec))
    @test ext._to_aog(scales(Y=(; scale=symlog))).dict[:Y][:scale] === Makie.pseudolog10
    @test ext._to_aog(wrapped(cols=3)) == AlgebraOfGraphics.wrapped(cols=3)
    @test ext._to_aog(wrapped()) == AlgebraOfGraphics.wrapped()

    # AlgebraOfGraphics' own selector helpers inside an AoV mapping keep their
    # meaning on the Vega-Lite path (normalized onto AoV's when the mapping is built).
    aov_sorted = data(tbl) * mapping(:x, :y; color=:label => sorter("b", "a")) * visual(Scatter)
    aog_sorted = data(tbl) * mapping(:x, :y; color=:label => AlgebraOfGraphics.sorter("b", "a")) * visual(Scatter)
    @test to_vegalite(aog_sorted) == to_vegalite(aov_sorted)
    @test to_vegalite(aov_sorted)["encoding"]["color"]["sort"] == ["b", "a"]
    @test to_vegalite(data(tbl) * mapping(:x => AlgebraOfGraphics.nonnumeric, :y) * visual(Scatter)) ==
          to_vegalite(data(tbl) * mapping(:x => nonnumeric, :y) * visual(Scatter))
    @test scales(X=(; scale=Makie.pseudolog10)).dict[:X][:scale] === symlog
    @test scales(Layout=(; palette=AlgebraOfGraphics.wrapped(cols=2))).dict[:Layout][:palette] == wrapped(cols=2)
    # Makie's pseudolog10 is symlog wherever a Vega-Lite scale is read.
    @test AlgebraOfVega._aog_scale_fn_to_vl(Makie.pseudolog10) == AlgebraOfVega._aog_scale_fn_to_vl(symlog)
end
