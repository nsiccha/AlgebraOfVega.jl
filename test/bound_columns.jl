using TestItemRunner

# Plots drawn from rows an HTMXObjects `semantic_app` page computes in the
# browser: `data(bound(p; columns))` inside an `@htmx` struct whose property
# `p` has a browser twin (`@browser`). See src/bound_columns.jl.
@testmodule AoVBoundFixtures begin
    using HTMXObjects, AlgebraOfVega, AlgebraOfGraphics
    export BoundLines, LINE_JS, OBS, bound_html, bound_marker

    # A module in the contract `ReactiveKernels.js_source` emits: positional
    # arguments in `INPUTS` order, a named tuple returned as an object.
    const LINE_JS = """
    export class JuliaError extends Error {
      constructor(type, message) { super(message); this.name = type; }
    }
    export function line(grid, a, b) {
      const n = grid.length, x = new Array(n), y = new Array(n), g = new Array(n), k = new Array(n);
      for (let i = 0; i < n; i++) {
        x[i] = grid[i]; y[i] = a * grid[i] + b; g[i] = i % 2 === 0 ? "p" : "q"; k[i] = i < 2 ? "lo" : "hi";
      }
      return { x, y, g, k };
    }
    export const INPUTS = [{ name: "grid", type: "Vector{Float64}" }, { name: "a", type: "Float64" },
      { name: "b", type: "Float64" }];
    export const OUTPUTS = [{ name: "x" }, { name: "y" }, { name: "g" }, { name: "k" }];
    """

    # Observations drawn beside the line, written into the plot as usual.
    const OBS = (; x=[0.5, 1.5, 2.5], y=[1.0, 4.0, 6.0], g=["p", "q", "p"])

    @htmx struct BoundLines
        "Slope"
        @param a::Float64 = 2.0
        @options(a) = number_domain(0.0, 10.0)
        "Intercept"
        @param b::Float64 = 1.0
        "Mark"
        @param mark::Symbol = :line
        @options(mark) = [:line, :point]
        grid = [0.0, 1.0, 2.0, 3.0]
        line = (; x = grid, y = a .* grid .+ b, g = [isodd(i) ? "p" : "q" for i in eachindex(grid)],
                k = [i <= 2 ? "lo" : "hi" for i in eachindex(grid)])
        @browser(line) = browser_module(; source = LINE_JS, entry = :line)
        # The table as the plots below draw it, for the server-side checks.
        rows = bound(line; columns = (:x, :y, :g, :k))
        __page__(content) = HTMXObjects.htmx(content; title = "Bound plots", assets = "assets/vendor",
            runtime = :linked, extra_head = vega_head(; source = :inline))
        @get index() = h.main(semantic_app(__self__; presentation = :tabs, select = e -> e.name != :index))
        "Result"
        @get result() = h.div(
            # One layer; the mark is a finite input, so each mark is a view of its own.
            to_node(data(bound(line; columns = (:x, :y))) * mapping(:x, :y) *
                visual(mark == :line ? Lines : Scatter) * config(height = 120); id = "bound-plain"),
            # Observations as they are, the line from the browser: a dataset of its own.
            to_node(data(OBS) * mapping(:x, :y) * visual(Scatter) +
                data(bound(line; columns = (:x, :y))) * mapping(:x, :y) * visual(Lines); id = "bound-obs"),
            # Two layers of one table in panels: the facet's own data, no merge.
            to_node(data(bound(line; columns = (:x, :y, :g))) * mapping(:x, :y; col = :g) *
                (visual(Lines) + visual(Scatter)); id = "bound-facet"),
            # The channel picker, through the captioned figure.
            with_plot_caption(data(bound(line; columns = (:x, :y, :g))) * mapping(:x, :y; color = :g) *
                visual(Lines) * config(height = 120), "Picker";
                plot_id = "bound-picker", auto_remap = (; dims = ["g" => "Group"])))
    end

    bound_html(x) = sprint(show, MIME"text/html"(), x)
    # The binding a node's plot area carries: its `data-htmxo-bound-columns`
    # JSON (decoded from the attribute) and the plot it names, or `nothing`.
    function bound_marker(html)
        m = match(r"<div class=\"aov-plot-area\" data-aov-bound-for=\"([^\"]+)\" data-htmxo-bound-columns=\"([^\"]+)\"", html)
        isnothing(m) && return nothing
        json = replace(m[2], "&quot;" => "\"", "&#39;" => "'", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&")
        (; plot=m[1], marker=AlgebraOfVega.JSON.parse(json))
    end
end

@testitem "a plot drawn from bound(p; columns) marks its plot area, and lowered rows are refused" setup=[AoVBoundFixtures] tags=[:unit, :semantic] begin
    using AlgebraOfVega, AlgebraOfGraphics, HTMXObjects

    obj = BoundLines()
    rows = obj.rows
    @test AlgebraOfVega._bound_binding(AlgebraOfVega.extract_data(data(rows))) === rows

    # One layer: the plot's top-level rows, Vega-Lite's `source_0`.
    plain = bound_html(to_node(data(rows) * mapping(:x, :y) * visual(Lines); id = "u-plain"))
    m = bound_marker(plain)
    @test !isnothing(m) && m.plot == "u-plain"
    @test !isnothing(m) && m.marker["dataset"] == "source_0" && m.marker["path"] == ["line"] &&
          m.marker["columns"] == ["x", "y", "g", "k"]
    # The embed script is inside the marked area, so an export reads its rows as bound.
    @test occursin(r"data-aov-bound-for=\"u-plain\"[^>]*><div id=\"u-plain\" class=\"u-w-full\"></div><script>AoV\.embed\('u-plain'", plain)

    # Beside other rows: the bound rows get a dataset name of their own.
    obs = bound_html(to_node(data(OBS) * mapping(:x, :y) * visual(Scatter) +
        data(rows) * mapping(:x, :y) * visual(Lines); id = "u-obs"))
    m = bound_marker(obs)
    @test !isnothing(m) && m.marker["dataset"] == "aov_bound"
    @test occursin("\"name\":\"aov_bound\"", obs)

    # Panels of one table, one layer or two: the facet's data, not a merge.
    for spec in (data(rows) * mapping(:x, :y; col = :g) * visual(Lines),
                 data(rows) * mapping(:x, :y; col = :g) * (visual(Lines) + visual(Scatter)))
        html = bound_html(to_node(spec; id = "u-facet"))
        facet = bound_marker(html)
        @test !isnothing(facet) && facet.marker["dataset"] == "source_0"
        @test !occursin("__src", html)
    end

    # The bound rows first, other rows after them, in a captioned figure (aov-use §11h).
    level = bound_html(with_plot_caption(
        (data(rows) * mapping(:x, :y) * visual(Lines) + data(OBS) * mapping(:x, :y) * visual(Scatter)) *
        config(height = 120), "Level"; plot_id = "u-level"))
    m = bound_marker(level)
    @test !isnothing(m) && m.plot == "u-level" && m.marker["dataset"] == "source_0"

    # The picker, when it leaves the rows as they are.
    picker = bound_html(with_plot_caption(data(rows) * mapping(:x, :y; color = :g) * visual(Lines) * config(height = 100),
        "Picker"; plot_id = "u-picker", auto_remap = (; dims = ["g" => "Group"])))
    m = bound_marker(picker)
    @test !isnothing(m) && m.plot == "u-picker" && m.marker["dataset"] == "source_0"

    # Another value of the inputs: the same plot id by default, the same
    # markup outside the rows.
    other = BoundLines(; a = 3.0).rows
    id_of(r) = match(r"data-aov-bound-for=\"([^\"]+)\"", bound_html(to_node(data(r) * mapping(:x, :y) * visual(Lines))))[1]
    @test id_of(rows) == id_of(other)

    # An ordinary table: no marker, the markup as before.
    ordinary = bound_html(to_node(data(OBS) * mapping(:x, :y) * visual(Scatter); id = "u-ordinary"))
    @test !occursin("data-htmxo-bound-columns", ordinary) && !occursin("data-aov-bound-for", ordinary)
    @test startswith(ordinary, "<div class=\"aov-plot-area\"><div id=\"u-ordinary\" class=\"u-w-full\"></div><script>")

    # Rows AoV computes from the table in Julia cannot follow the browser's columns.
    refused(f) = try
        f()
        ""
    catch err
        err isa ArgumentError ? sprint(showerror, err) : rethrow()
    end
    for (what, f) in (
            "a ribbon summary of raw draws" => () -> to_node(data(rows) * mapping(:x, :y) * lineribbon(); id = "u-r"),
            "a faceted figure whose layers draw different tables" => () -> to_node(
                (data(OBS) * mapping(:x, :y) * visual(Scatter) + data(rows) * mapping(:x, :y) * visual(Lines)) *
                mapping(; col = :g); id = "u-r"),
            "the picker's combined columns" => () -> with_plot_caption(
                data(rows) * mapping(:x, :y) * visual(Lines) * config(height = 100), "Combo";
                plot_id = "u-r", auto_remap = (; dims = ["g" => "Group", "k" => "Half"], pinned = :row)))
        message = refused(f)
        @test occursin("update_spec", message)
        isempty(message) && @info "not refused: $what"
    end
    # Two bound tables: a plot follows one.
    @test occursin("follows one table", refused(() -> to_node(
        data(rows) * mapping(:x, :y) * visual(Lines) + data(other) * mapping(:x, :y) * visual(Scatter); id = "u-two")))

    # Away from a page, the rows are rows: a refresh and an export draw them.
    @test occursin("AoV.updateSpec('u-plain'", bound_html(update_spec("u-plain", data(rows) * mapping(:x, :y) * lineribbon())))
    @test length(to_vegalite(data(rows) * mapping(:x, :y) * visual(Lines))["data"]["values"]) == 4
end

@testitem "a static semantic page redraws a bound plot in the browser, offline" setup=[AoVBoundFixtures, AoVBrowserServer] tags=[:browser, :semantic] begin
    using AlgebraOfVega, HTMXObjects, JSON

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    route!(BoundLines(); operation_policy = :blocking)
    HTMXObjects.vendorfiles("assets/vendor")
    mktempdir(prefix = "kb-aov-bound-") do dir
        site = joinpath(dir, "site")
        # The export checks each result with its inputs changed: a plot whose
        # rows were not marked as bound would fail it as stale.
        out = export_site(site; pages = ["/"])
        @test out.files > 0
        index = joinpath(site, "index.html")
        page = read(index, String)
        @test occursin("data-aov-bound-for=\"bound-plain\"", page)
        if isempty(chrome)
            @test_skip "headless Chrome is not installed"
        else
            driver = read(joinpath(@__DIR__, "bound_columns.js"), String)
            # The inlined vega-embed carries a literal `</body>`: splice at the last one.
            at = findlast("</body>", page)
            write(index, page[1:prevind(page, first(at))] * "<pre id=\"aov-bound-results\"></pre><script>" *
                driver * "</script>" * page[first(at):end])
            output = with_page_server(site) do base
                read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                    --user-data-dir=$(joinpath(dir, "profile")) --window-size=1200,1600
                    --virtual-time-budget=60000 --dump-dom $(base * "/index.html")`,
                    stderr = joinpath(dir, "chrome.log")), String)
            end
            result = match(r"<pre id=\"aov-bound-results\">([^<]+)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                report = JSON.parse(replace(result[1], "&quot;" => "\"", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&"))
                @test report["checks"] >= 30
                @test isempty(report["failures"])
                @info "bound plot browser checks" checks = report["checks"]
                isempty(report["failures"]) || println(JSON.json(report["failures"]))
            else
                println(read(joinpath(dir, "chrome.log"), String)[max(1, end - 3000):end])
            end
        end
    end
end
