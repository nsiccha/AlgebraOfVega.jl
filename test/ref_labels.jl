using TestItemRunner

# Reference lines and periods name themselves through AoG's `text` mapping on
# their own layer, `mapping(:t; text=:name) * visual(VLines)`: the labels stand
# above the plot area at their lines and, close together, go into rows, so they
# never overprint (decision 0qrccve, prong `ref-labels`). Before, the `text`
# channel of a rule or rect drew nothing, and a hand-placed Text layer at a data
# height overprinted its neighbours.
@testitem "reference labels: lowering" tags=[:reflabels] begin
    using AlgebraOfVega
    import AlgebraOfGraphics
    refs = (; t=[3.0, 3.2, 7.0], name=["Issue", "Update", "Deadline"])
    line = data((; t=collect(1.0:10), y=sin.(1:10))) * mapping(:t, :y) * visual(Lines)
    vl = to_vegalite(line + data(refs) * mapping(:t; text=:name) * visual(VLines; color=:gray) +
        data((; a=[5.0], b=[6.0], name=["Window"])) * mapping(:a, :b; text=:name) * visual(VSpan; color=:ink, alpha=0.1))
    ls = vl["layer"]
    marks = [AlgebraOfVega._mark_type(l["mark"]) for l in ls]
    @test marks == ["line", "rule", "text", "rect", "text"]
    # The rule and rect keep their look and lose the text channel; each label follows its layer.
    @test !haskey(ls[2]["encoding"], "text") && !haskey(ls[4]["encoding"], "text")
    for (k, field) in ((3, "t"), (5, "a"))
        enc = ls[k]["encoding"]
        @test enc["x"]["field"] == field && enc["text"]["field"] == "name"
        @test enc["y"]["field"] == "__aov_ref_y" && enc["y"]["scale"] === nothing
        @test any(t -> get(t, "as", "") == "__aov_ref_key", ls[k]["transform"])
        @test "aov-passive" in ls[k]["mark"]["style"] && ls[k]["mark"]["clip"] === false
    end
    @test ls[3]["mark"]["color"] == "gray" && "aov-ink" in ls[5]["mark"]["style"]
    @test any(p -> p["name"] == "aov_ref_rows", vl["params"])
    # A figure of only a labelled reference layer becomes two layers.
    one = to_vegalite(data(refs) * mapping(:t; text=:name) * visual(VLines))
    @test length(one["layer"]) == 2 && AlgebraOfVega._mark_type(one["layer"][2]["mark"]) == "text"
    # A horizontal reference is labelled at the plot's right end.
    h = to_vegalite(line + data((; lv=[0.5], name=["Limit"])) * mapping(:lv; text=:name) * visual(HLines))
    hl = h["layer"][end]
    @test hl["encoding"]["y"]["field"] == "lv" && hl["encoding"]["x"]["value"] == Dict("expr" => "width")
    # In a `vconcat` stack the rows parameter is the stack's (a value parameter
    # lives at the top of a Vega-Lite spec), and vsave draws the labels.
    stack = to_vegalite(vconcat(line + data(refs) * mapping(:t; text=:name) * visual(VLines), line))
    @test any(p -> p["name"] == "aov_ref_rows", stack["params"])
    @test !any(p -> any(q -> get(q, "name", "") == "aov_ref_rows", get(p, "params", Any[])), stack["vconcat"])
    if !isnothing(Sys.which("vl-convert")) || haskey(ENV, "AOV_VL_CONVERT")
        mktempdir() do dir
            svg = vsave(vconcat(line + data(refs) * mapping(:t; text=:name) * visual(VLines), line), joinpath(dir, "refs.svg"))
            @test occursin("Deadline", read(svg, String))
        end
    end
    # No text mapping: no label, no parameter.
    plain = to_vegalite(line + data(refs) * mapping(:t) * visual(VLines))
    @test length(plain["layer"]) == 2 && !haskey(plain, "params") || !any(p -> p["name"] == "aov_ref_rows", plain["params"])
end

@testitem "reference labels in the browser: rows, never overprinting" tags=[:reflabels, :browser] begin
    using AlgebraOfVega, JSON
    import AlgebraOfGraphics
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        line = data((; t=collect(0.0:24), y=sin.(0:24))) * mapping(:t => "Hour", :y => "Level") * visual(Lines)
        refs = (; t=[6.0, 6.3, 6.6, 18.0, 18.2], name=["Forecast issued", "Update 1", "Update 2", "Warning", "Peak expected"])
        span = (; a=[12.0], b=[15.0], name=["Maintenance window"])
        fig = line + data(refs) * mapping(:t; text=:name) * visual(VLines; color=:ink, linestyle=:dash) +
            data(span) * mapping(:a, :b; text=:name) * visual(VSpan; color=:ink, alpha=0.08)
        page = [vdraw(fig * config(width=600, height=200); id="refs"),
            vdraw(fig * config(width=600, height=200, axis=(; limits=((0, 12), nothing))); id="limited")]
        driver = """
        (async function () {
            const out = {errors: []};
            window.addEventListener('error', e => out.errors.push(String(e.message)));
            const pause = () => new Promise(r => setTimeout(r, 20));
            for (let i = 0; i < 300 && !(AoV.views.refs && !AoV._inFlight.refs); i++) await pause();
            for (let i = 0; i < 15; i++) await pause();
            const labels = () => {
                const got = [];
                (function walk(it) {
                    if (it.mark && it.mark.marktype === 'text' && it.datum && it.datum.__aov_ref_key !== undefined && it.opacity !== 0)
                        got.push({name: it.datum.name, x1: it.bounds.x1, x2: it.bounds.x2, y1: it.bounds.y1, y2: it.bounds.y2});
                    (it.items || []).forEach(walk);
                })(AoV.views.refs.scenegraph().root);
                return got;
            };
            out.labels = labels();
            out.rows = AoV.views.refs.signal('aov_ref_rows');
            // A figure whose x stops at hour 12: the labels of later lines are hidden.
            for (let i = 0; i < 300 && !(AoV.views.limited && !AoV._inFlight.limited); i++) await pause();
            for (let i = 0; i < 15; i++) await pause();
            const shown = [];
            (function walk(it) {
                if (it.mark && it.mark.marktype === 'text' && it.datum && it.datum.__aov_ref_key !== undefined && it.opacity !== 0) shown.push(it.datum.name);
                (it.items || []).forEach(walk);
            })(AoV.views.limited.scenegraph().root);
            out.limited = shown;
            const pre = document.createElement('pre'); pre.id = 'aov-ref-labels';
            pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
        })();
        """
        mktempdir(prefix="kb-aov-ref-labels-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,800
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"aov-ref-labels\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                r = JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "reference labels" r
                @test isempty(r["errors"])
                ls = r["labels"]
                @test sort([l["name"] for l in ls]) == sort(vcat(refs.name, span.name))
                # Above the plot area, and no two labels overlap.
                @test all(l -> l["y2"] <= 0, ls)
                overlap(a, b) = a["x1"] < b["x2"] && b["x1"] < a["x2"] && a["y1"] < b["y2"] && b["y1"] < a["y2"]
                @test !any(overlap(ls[i], ls[j]) for i in eachindex(ls) for j in i+1:length(ls))
                # The close lines took rows; the lone span label the first.
                @test maximum(values(r["rows"])) >= 2
                # Lines out of view (here past the x limits; a zoom does the same) hide their labels.
                @test sort(r["limited"]) == ["Forecast issued", "Update 1", "Update 2"]
            end
        end
    end
end
