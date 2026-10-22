# vsave(spec, path): the figure `vdraw` shows, written to a PDF, SVG or PNG file
# through the vl-convert CLI (snag `static-pdf-expor-6f71e52e`, design decision
# `0qoxatl`). Before it, a `geoshape` map had no file export at all: `sdraw`
# refuses it, and a consumer's own `to_json` + vl-convert call drew an empty
# map, with exit 0 and no warning, whenever the geometry was a local file.

@testitem "vsave: format, resolution and locale are checked before anything renders" setup=[AoVGeoshapeMapFixtures] tags=[:static, :geoshape, :vsave] begin
    @test_throws ArgumentError vsave(kreis_map, "map.jpg")
    @test_throws ArgumentError vsave(kreis_map, "map")
    # scale/ppi size a PNG; a PDF or SVG is vector output.
    @test_throws ArgumentError vsave(kreis_map, "map.pdf"; scale=2)
    @test_throws ArgumentError vsave(kreis_map, "map.svg"; ppi=300)
    @test_throws ArgumentError vsave(kreis_map, "map.svg"; locale=:xx)
    # An AOV_VL_CONVERT that names no file is an error naming the variable.
    err = withenv("AOV_VL_CONVERT" => joinpath(tempdir(), "no-such-vl-convert")) do
        try
            vsave(kreis_map, joinpath(tempdir(), "aov-vsave-never.svg"))
            nothing
        catch e
            e
        end
    end
    @test err isa ErrorException
    @test occursin("AOV_VL_CONVERT", sprint(showerror, err))
    @test !isfile(joinpath(tempdir(), "aov-vsave-never.svg"))
end

@testitem "vsave: a local geometry file is read into the spec, the caller's Dict untouched" setup=[AoVGeoshapeMapFixtures] tags=[:static, :geoshape, :vsave] begin
    using JSON
    inline = AlgebraOfVega._vsave_inline_data
    geo_unit(vl) = haskey(vl, "layer") ? vl["layer"][1] : vl
    lookup_data(vl) = only(t for t in geo_unit(vl)["transform"] if haskey(t, "lookup"))["from"]["data"]
    mktempdir() do dir
        file = joinpath(dir, "kreise.geojson")
        open(io -> JSON.print(io, kreise_geo), file, "w")
        expected = lookup_data(to_vegalite(data(kreise) * mapping(:AGS; color=:effect) *
            geoshape(kreise_geo) + points; interactive=false))
        for url in ("kreise.geojson", file, "file://" * file)
            vl = to_vegalite(data(kreise) * mapping(:AGS; color=:effect) * geoshape(url) + points;
                interactive=false)
            before = JSON.json(vl)
            got = lookup_data(cd(() -> inline(vl), dir))
            # The same features a parsed-Dict geometry lowers to.
            @test got["values"] == expected["values"]
            @test got["format"] == Dict{String,Any}("type" => "json", "property" => "features")
            @test !haskey(got, "url")
            @test JSON.json(vl) == before
        end
        # Remote and data: URLs are left to vl-convert.
        for url in ("https://example.invalid/kreise.geojson", "data:application/json,{}")
            vl = to_vegalite(data(kreise) * mapping(:AGS; color=:effect) * geoshape(url); interactive=false)
            @test lookup_data(inline(vl))["url"] == url
        end
        # A local path that names no file fails loudly instead of drawing nothing.
        missing_map = to_vegalite(data(kreise) * mapping(:AGS; color=:effect) * geoshape("nope.geojson");
            interactive=false)
        @test_throws ArgumentError cd(() -> inline(missing_map), dir)
        # CSV/TSV URL data keeps its text and gets the format the extension implied.
        write(joinpath(dir, "rows.csv"), "x,y\n1,2\n")
        csv = cd(() -> inline(Dict{String,Any}("data" => Dict{String,Any}("url" => "rows.csv"))), dir)
        @test csv["data"] == Dict{String,Any}("values" => "x,y\n1,2\n", "format" => Dict{String,Any}("type" => "csv"))
    end
end

@testitem "vsave: maps with lon/lat marks render to PDF, SVG and PNG through vl-convert" setup=[AoVGeoshapeMapFixtures] tags=[:static, :geoshape, :vsave] begin
    using JSON
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            cd(dir) do
                open(io -> JSON.print(io, kreise_geo), "kreise.geojson", "w")
                map_spec(geo) = (data(kreise) * mapping(:AGS; color=:effect) * geoshape(geo) + points) *
                    config(title="Kreise", width=300, height=200)
                polygons(svg) = count("aria-roledescription=\"geoshape\"", read(svg, String))

                @test vsave(map_spec(kreise_geo), "dict.svg") == "dict.svg"
                @test polygons("dict.svg") == length(kreise.AGS)
                @test count("aria-roledescription=\"point\"", read("dict.svg", String)) == length(sites.name)
                # A geometry file renders exactly like the parsed Dict.
                vsave(map_spec("kreise.geojson"), "file.svg")
                @test read("file.svg") == read("dict.svg")

                @test startswith(read(vsave(map_spec(kreise_geo), "map.pdf"), String), "%PDF-")
                png_width(f) = Int(ntoh(reinterpret(UInt32, read(f)[17:20])[1]))
                vsave(map_spec(kreise_geo), "map1.png")
                vsave(map_spec(kreise_geo), "map2.png"; scale=2)
                @test read("map1.png")[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
                @test png_width("map2.png") == 2 * png_width("map1.png")

                # One shared colour domain across a map series, German number format.
                counts = data((; AGS=kreise.AGS, n=[1200, 3400, 5600])) * mapping(:AGS; color=:n) *
                    geoshape(kreise_geo)
                shared = scales(Color=(; colormap=:viridis, colorrange=(0, 6000)))
                vsave(counts, shared, "de.svg"; locale=:de)
                vsave(counts, shared, "en.svg")
                @test occursin(r">\d\.000<", read("de.svg", String))
                @test occursin(r">\d,000<", read("en.svg", String))

                # A framed figure is written at its start frame.
                yearly = data((; AGS=["01001", "01002", "01001"], year=[2020, 2020, 2021], v=[1.0, 2.0, 3.0])) *
                    mapping(:AGS; color=:v) * geoshape(kreise_geo) * config(frame=(; field=:year, start=:last))
                vsave(yearly, "frame.svg")
                @test polygons("frame.svg") == 1
            end
        end
    end
end
