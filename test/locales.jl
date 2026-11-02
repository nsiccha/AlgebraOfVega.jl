using TestItemRunner

@testsnippet AoVLocaleFixtures begin
    using AlgebraOfVega, Dates, JSON

    rows = (; date=[Date(2026, 3, 1), Date(2026, 3, 2)], value=[1234.5, 2345.6])
    base = data(rows) * mapping(:date, :value) * visual(Scatter)
    locales_dir = joinpath(pkgdir(AlgebraOfVega), "vendor", "locales")
    labeled = base * config(encoding=(;
        x=(; axis=(; format="%B", values=["2026-03-01"])),
        y=(; axis=(; format=",.1f", values=[1234.5])),
    ))
end

@testitem "built-in locales carry the complete pinned d3 definitions" setup=[AoVLocaleFixtures] tags=[:translation, :config, :locale] begin
    using SHA

    # Byte-identical upstream locale files; see vendor/README.md for release tags.
    hashes = Dict(
        ("d3-format", "de-DE") => "9e9054a1ad7750059a089d589a2b805b326be35a3196b7098b435c8297c4a1d1",
        ("d3-format", "en-US") => "ac06458336a0665726aef1ffdd8fa1d9d8f13405c4866079c940e2acdf88c4ba",
        ("d3-time-format", "de-DE") => "233fd22a5a4400aee8d85f8cf47cd82c7a7bfacf15173515c686713d9995bcf8",
        ("d3-time-format", "en-US") => "937a4bf3598dd821f77dd77c1f0a5440944e0fa58cf76766c6820f10e97d987e",
    )
    for (lang, name) in (:de => "de-DE", :en => "en-US")
        expected = Dict{String,Any}()
        for (kind, package) in ("number" => "d3-format", "time" => "d3-time-format")
            bytes = read(joinpath(locales_dir, package, "$name.json"))
            @test bytes2hex(sha256(bytes)) == hashes[(package, name)]
            expected[kind] = JSON.parse(String(bytes); dicttype=Dict{String,Any})
        end
        cfg = locale_config(lang)
        @test cfg isa AlgebraOfVega.Config
        for interactive in (true, false)
            vl = to_vegalite(base * cfg; interactive)
            @test vl["config"]["locale"] == expected
            @test !haskey(vl, "locale")
        end
        @test JSON.parse(to_json(base * cfg))["config"]["locale"] == expected
        @test AlgebraOfVega._vsave_locale(lang) == name
    end
    de = to_vegalite(base * locale_config(:de))["config"]["locale"]
    @test de["number"]["currency"] == ["", "\u00a0€"]
    @test de["time"]["shortMonths"][3] == "Mrz"
    @test to_vegalite(base * locale_config()) == to_vegalite(base * locale_config(:en))
    @test !haskey(to_vegalite(base)["config"], "locale")
    @test_throws ArgumentError locale_config(:unknown)
end

@testitem "locale configs compose with app settings and explicitly restore English" setup=[AoVLocaleFixtures] tags=[:translation, :config, :locale] begin
    # RegionExplorer's time layout stays an app choice, separate from the locale.
    extras = config(config=(;
        timeFormat="%d.%m.%Y",
        axisTemporal=(; format=(; milliseconds=".%L", seconds=":%S",
            minutes="%H:%M", hours="%H:%M", date="%a %-d.", week="%-d. %b",
            month="%B", year="%Y")),
        axisX=(; labelAngle=0), legend=(; orient="top"),
    ))
    german = locale_config(:de)
    expected = to_vegalite(base * german * extras)
    @test to_vegalite(base * (german * extras)) == expected
    @test to_vegalite(base * extras * german) == expected
    @test to_vegalite((german * extras) * base) == expected
    @test expected["config"]["axisTemporal"] == extras.properties[:config]["axisTemporal"]
    @test expected["config"]["timeFormat"] == "%d.%m.%Y"
    @test expected["config"]["axisX"]["labelAngle"] == 0
    @test expected["config"]["legend"]["orient"] == "top"
    @test expected["config"]["axis"]["labelLimit"] == 0
    @test to_vegalite(base * german * locale_config(:en)) == to_vegalite(base * locale_config(:en))
    @test to_vegalite(base * locale_config(:en) * german) == to_vegalite(base * german)
end

@testitem "locale configs own their nested data across calls and spec lowering" setup=[AoVLocaleFixtures] tags=[:config, :locale] begin
    german = locale_config(:de)
    before = deepcopy(german.properties)
    vl = to_vegalite(base * german)
    vl["config"]["locale"]["time"]["months"][1] = "changed in a spec"
    vl["config"]["locale"]["number"]["grouping"][1] = 2
    @test german.properties == before
    german.properties[:config]["locale"]["time"]["months"][1] = "changed in a config"
    german.properties[:config]["locale"]["number"]["currency"][2] = "changed"
    @test locale_config(:de).properties == before
    @test locale_config(:en).properties[:config]["locale"]["time"]["months"][1] == "January"
end

@testitem "Vega renders number and time formats from the emitted locales" setup=[AoVLocaleFixtures] tags=[:translation, :locale] begin
    node = Sys.which("node")
    if isnothing(node)
        @test_skip "node is not installed"
    else
        mktempdir() do dir
            paths = String[]
            for lang in (:de, :en)
                path = joinpath(dir, "$lang.json")
                write(path, to_json(labeled * locale_config(lang); interactive=false))
                push!(paths, path)
            end
            driver = joinpath(@__DIR__, "locales.js")
            @test success(`$node $driver $(AlgebraOfVega.vega_vendor_dir()) $paths`)
        end
    end
end

@testitem "vsave retains the plot's built-in German locale" setup=[AoVLocaleFixtures] tags=[:static, :locale, :vsave] begin
    if isnothing(Sys.which("vl-convert")) && !haskey(ENV, "AOV_VL_CONVERT")
        @test_skip "vl-convert is not installed"
    else
        mktempdir() do dir
            svg = read(vsave(labeled * locale_config(:de), joinpath(dir, "de.svg")), String)
            @test occursin(">1.234,5</text>", svg)
            @test occursin(">März</text>", svg)
        end
    end
end
