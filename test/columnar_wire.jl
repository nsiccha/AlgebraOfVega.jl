using TestItemRunner

"""
Rows bound for the browser travel column by column.

Regression (snag `compact-columnar-6a910a32`): `append_data`/`update_data` sent
every row as a JSON object repeating each key, the constant series label and a
17-digit regular-grid x — 67.5 B/row for a one-series time course of 6721
points (453,919 bytes), re-sent on every form edit. Now a table travels as
`{n, columns}`: a regular coordinate as a numeric sequence, a constant column
once, sorted labels as runs, other columns as one flat array; the inline
datasets `to_node`/`update_spec` embed use the same form. The runtime expands
it to the row objects the row-wise JSON parsed to, and a sequence is chosen only
when JavaScript's double arithmetic reproduces every value exactly. The browser
half checks that equivalence value by value (`Object.is`), and that streamed,
replaced, windowed and embedded data reach live views unchanged.
"""
@testitem "columnar wire round-trips rows exactly" tags=[:incremental, :browser, :regression] begin
    using AlgebraOfVega, AlgebraOfGraphics, Tables, JSON, FillArrays, Dates
    html(x) = sprint(show, MIME"text/html"(), x)
    script(x) = match(r"^<script>(.*)</script>$"s, html(x)).captures[1]
    payload(s) = match(r"^AoV\.\w+\('[^']*', (.*), '[^']*'(?:, [^,)]*)?\);$"s, s).captures[1]
    rowwise(t) = AlgebraOfVega._vl_json([Dict{String,Any}(string(k) => v for (k, v) in pairs(nt)) for nt in Tables.rowtable(t)])

    n = 6721
    grid = range(0, 28, length=n)
    y = [1.2 + sin(t) * exp(-t / 10) + 1e-3 * t for t in grid]
    reporter = (; scenario=Fill("Daily 100%", n), x=grid, y=y)
    long = (; scenario=repeat(["S$i" for i in 1:8], inner=200), x=repeat(collect(grid[1:200]), 8),
        y=repeat(y[1:200], 8))
    cases = Dict(
        "reporter" => reporter,
        "long" => long,
        "interleaved" => (; scenario=repeat(["a", "b", "c"], 100), x=repeat(collect(grid[1:100]), inner=3)),
        "grids" => (; a=0:0.1:10, b=range(-3.5, 2.25, length=101), c=collect(1:101) .* 0.1,
            d=0.5 .+ (0:100) .* 0.25, e=LinRange(0, 28, 101), f=collect(range(0, 1, length=101)),
            g=collect(-50:50), h=(0:100) .+ (2^53 - 100), k=(1:101) .* (1 / 3), l=Float32.(0:100) ./ 7),
        "constants" => (; s=fill("é \"q\" </x>", 5), i=fill(3, 5), f=fill(-0.0, 5), m=fill(missing, 5),
            b=fill(true, 5), d=fill(Date(2026, 10, 7), 5), sym=fill(:k, 5)),
        "runs" => (; g=["a", "a", "a", "b", "b", "b", "a", "a"], z=[0.0, 0.0, -0.0, -0.0, 0.0, 0.0, 1.0, 1.0],
            mixed=Any[1, 1, true, true, 1.0, 1.0, "1", "1"], big=[typemax(Int), typemax(Int), 1, 1, 2, 2, 3, 3]),
        "small" => (; x=[1.0], y=["only"]),
        "empty" => (; x=Float64[], y=String[]),
        "missing" => (; x=[1.0, missing, 3.0, 4.0], y=[missing, "b", "c", "d"]),
        "nonfinite" => (; a=[1.0, NaN, 3.0, Inf], b=fill(NaN, 4), c=[NaN, NaN, -Inf, -Inf]),
    )
    wire = Dict(k => payload(script(append_data("p", t))) for (k, t) in cases)
    reference = Dict(k => rowwise(t) for (k, t) in cases)

    # Server side: the reporter's fragment shrinks to under 30% of the row-wise one.
    columns(k) = JSON.parse(wire[k])["columns"]
    @test sizeof(wire["reporter"]) < 0.3 * sizeof(reference["reporter"])
    @test columns("reporter")["scenario"] == "Daily 100%"
    @test columns("reporter")["x"] == Dict("start" => 0.0, "step" => 1.0, "den" => 240.0)
    @test columns("long")["x"]["period"] == 200
    @test columns("long")["scenario"]["lengths"] == fill(200, 8)
    @test columns("grids")["e"] isa Vector        # LinRange: no exact sequence, sent as values
    @test columns("grids")["l"] isa Vector        # Float32: JSON digits are not the Float64 sequence
    @test columns("grids")["c"]["scale"] == 0.1
    @test occursin("AoV.appendData('p', {\"n\":6721,", html(append_data("p", reporter)))
    @test occursin("AoV.updateData('p', {\"n\":6721,", html(update_data("p", reporter)))

    # Embedded datasets use the same form; rows of different shapes stay rows.
    spec = data(reporter) * mapping(:x, :y; color=:scenario) * visual(Lines)
    vl = AlgebraOfVega._embed_spec(spec)
    wired = AlgebraOfVega._wire_spec(vl)
    @test wired["data"]["values"]["n"] == n
    @test vl["data"]["values"] isa Vector         # the lowered spec itself is not modified
    @test AlgebraOfVega._wire_rows([Dict("a" => 1), Dict("a" => 2, "b" => 3)]) === nothing

    plain = data((; x=Float64[], y=Float64[], scenario=String[])) *
        mapping(:x, :y; color=:scenario) * visual(Lines) * config(height=200)
    updates = Dict(
        "append" => script(append_data("live", reporter)),
        "append_window" => script(append_data("live", long; max_rows=500)),
        "update" => script(update_data("live", long)),
        "spec" => script(update_spec("emb", data((; x=grid[1:50], y=y[1:50], scenario=Fill("B", 50))) *
            mapping(:x, :y; color=:scenario) * visual(Lines) * config(height=200))),
    )
    expected = Dict("append" => reference["reporter"], "long" => reference["long"],
        "spec" => rowwise((; scenario=Fill("B", 50), x=grid[1:50], y=y[1:50])),
        "embedded" => rowwise(reporter))

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-columnar-wire-") do dir
            page = [vdraw(plain; id="live"), vdraw(spec * config(height=200); id="emb")]
            runtime = join(html(x) for x in vega_head(source=:inline))
            fixture = replace(JSON.json((; wire, reference, updates, expected)), "</" => "<\\/")
            driver = read(joinpath(@__DIR__, "columnar_wire.js"), String)
            write(joinpath(dir, "test.html"), "<!doctype html><meta charset='utf-8'>" * runtime *
                join(html(p) for p in page) *
                "<script>window.AOV_FIXTURE=" * fixture * ";</script><script>" * driver * "</script>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,900
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "test.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-columnar-results\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<",
                    "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 20
                @test isempty(report["failures"])
                @info "columnar wire browser checks" checks=report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            end
        end
    end
end
