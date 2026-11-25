using TestItemRunner

# `vconcat(a, b)` stacks figures on one shared x scale as one plot: their plot
# areas line up to the pixel, the x axis is labelled once under the bottom panel,
# and the readout and an x zoom run across the panels (decision 0qrccve, prong
# `shared-x`). Before, a level chart and a precipitation panel drawn as two
# figures had plot areas 1,427 and 1,384 px wide, so 18:00 sat 40 px apart.
@testitem "vconcat: lowering" tags=[:vconcat] begin
    using AlgebraOfVega
    import AlgebraOfGraphics
    t = collect(1.0:24)
    level = data((; t, y=sin.(t) .+ 10)) * mapping(:t => "Hour", :y => "Level (cm)") * visual(Lines) *
        config(height=200, link=(; group="hours", key=:t))
    rain = data((; t, mm=abs.(cos.(t)))) * mapping(:t => "Hour", :mm => "mm/h") * visual(BarPlot) *
        config(height=60, readout=true, link=(; group="hours", key=:t))
    vl = to_vegalite(vconcat(level, rain; spacing=4))
    @test length(vl["vconcat"]) == 2 && vl["spacing"] == 4 && vl["bounds"] == "flush"
    @test vl["resolve"]["scale"]["x"] == "shared"
    @test vl["_aov"]["link"]["group"] == "hours" && vl["_aov"]["readout"] === true
    @test [p["readout"] for p in vl["_aov"]["panels"]] == [nothing, true]
    # The panels keep their own height; the config and runtime metadata go to the top.
    @test [p["height"] for p in vl["vconcat"]] == [200, 60]
    @test !any(p -> haskey(p, "config") || haskey(p, "_aov") || haskey(p, "\$schema"), vl["vconcat"])
    @test haskey(vl, "config")
    # The x axis is labelled under the bottom panel only.
    xaxis(p) = (u = haskey(p, "layer") ? first(p["layer"]) : p; get(u["encoding"]["x"], "axis", Dict()))
    @test xaxis(vl["vconcat"][1])["labels"] === false && xaxis(vl["vconcat"][1])["title"] === nothing
    @test get(xaxis(vl["vconcat"][2]), "labels", true) !== false
    # Sized to the container in the browser; plot_size stacks the panels.
    @test plot_size(vconcat(level, rain)).height > 260
    node = sprint(show, MIME"text/html"(), vdraw(vconcat(level, rain); id="stack"))
    @test occursin("\"fitWidth\":true", node)

    # Refused: one panel, a faceted panel, different link groups, the picker, sdraw.
    @test_throws ArgumentError vconcat(level)
    @test_throws ArgumentError to_vegalite(vconcat(level, data((; t, y=t, g=repeat(["a", "b"], 12))) *
        mapping(:t, :y; col=:g) * visual(Lines)))
    @test_throws ArgumentError to_vegalite(vconcat(level, rain * config(link=(; group="other", key=:t))))
    @test_throws ArgumentError to_vegalite(vconcat(level, rain); auto_remap=(; dims=["t" => "Hour"]))
    @test_throws ArgumentError sdraw(vconcat(level, rain), "x.png")
end

# Panels that keep their own x (`linkxaxes=:none`), and the zoom of every panel
# composition (snag `vconcat-panels-w-4a6f3581`, decision `1hmw16g`). Bruno's
# zoomed clinical-parameter forests stack a QT panel near 400 ms over
# coefficients near 0; `vconcat` shared x, so it hand-stacked `to_vegalite`
# dicts. Every panel then carried AoV's zoom selection `grid`, Vega-Lite merged
# the same-named selections into one, and a wheel over one panel put every
# panel on its x interval. The same merge re-domained the y of a shared-x
# stack's panels that plot one column, and of row and wrap per-panel-Y stacks
# (todo `04imxgm`). Shared axes now keep one `grid`; a panel's own axes zoom
# through its own `grid_p<k>`.
@testitem "vconcat: linkxaxes=:none and a zoom selection per panel axis" tags=[:vconcat] begin
    using AlgebraOfVega
    # The zoom selections of a panel, by name: their encodings.
    function zooms(panel)
        out = Dict{String,Vector{String}}()
        walk(_) = nothing
        function walk(n::AbstractDict)
            for p in get(n, "params", Any[])
                p isa AbstractDict && get(p, "bind", nothing) == "scales" &&
                    append!(get!(out, p["name"], String[]), p["select"]["encodings"])
            end
            foreach(walk, get(n, "layer", Any[]))
            haskey(n, "spec") && walk(n["spec"])
        end
        walk(panel)
        out
    end
    t = collect(1.0:24)
    a = data((; t, v=sin.(t))) * mapping(:t, :v) * visual(Lines)
    b = data((; t, v=100 .* cos.(t))) * mapping(:t, :v) * visual(Lines)
    # Linked x (the default): one zoom on the x the panels share; each panel's
    # y, the same column in both, zooms on its own.
    vl = to_vegalite(vconcat(a, b))
    @test vl["resolve"]["scale"]["x"] == "shared" && vl["bounds"] == "flush"
    @test zooms.(vl["vconcat"]) == [Dict("grid" => ["x"], "grid_p0" => ["y"]), Dict("grid" => ["x"], "grid_p1" => ["y"])]
    # Own x: each panel zooms every axis through its own selection and labels its own x.
    free = to_vegalite(vconcat(a, b; linkxaxes=:none))
    @test free["resolve"]["scale"]["x"] == "independent"
    @test zooms.(free["vconcat"]) == [Dict("grid_p0" => ["x", "y"]), Dict("grid_p1" => ["x", "y"])]
    xaxis(p) = (u = haskey(p, "layer") ? first(p["layer"]) : p; get(u["encoding"]["x"], "axis", Dict()))
    @test all(p -> get(xaxis(p), "labels", true) !== false, free["vconcat"])
    # AlgebraOfGraphics' other values, for one column of panels; anything else is refused.
    @test to_vegalite(vconcat(a, b; linkxaxes=:minimal)) == free
    @test to_vegalite(vconcat(a, b; linkxaxes=:colwise)) == vl
    @test_throws ArgumentError vconcat(a, b; linkxaxes=:rows)
    # No pan/zoom asked for, none added.
    @test all(isempty, zooms.(to_vegalite(vconcat(a, b; linkxaxes=:none); interactive=false)["vconcat"]))
    # The bare `to_html` page clips the marks of a stack whose panels zoom on their own.
    @test occursin("_tuple_fields", to_html(vconcat(a, b; linkxaxes=:none); id="free"))

    # The reporter's forests: a nominal y, so each panel zooms its x alone; the
    # stack offers the "Show intervals" switch its panels offer alone.
    forest(rows) = data(rows) * mapping(:median => "Value"; y=:parameter) * pointinterval(bands=[:q025 => :q975])
    qt = (; parameter=["QT0", "QT1"], median=[400.0, 402.0], q025=[396.0, 398.0], q975=[404.0, 406.0])
    coef = (; parameter=["b1", "b2"], median=[0.5, -1.0], q025=[-2.0, -3.0], q975=[3.0, 1.0])
    st = to_vegalite(vconcat(forest(qt), forest(coef); linkxaxes=:none))
    @test zooms.(st["vconcat"]) == [Dict("grid_p0" => ["x"]), Dict("grid_p1" => ["x"])]
    @test st["_aov"]["intervals"] === true
    # Panels given as lowered Dicts, as Bruno post-processes `to_vegalite`'s
    # output: each still zooms on its own, and the caller's Dicts stay as they were.
    raw = to_vegalite(forest(qt)); kept = deepcopy(raw)
    st2 = to_vegalite(vconcat(AlgebraOfVega.VegaSpec(raw, nothing),
        AlgebraOfVega.VegaSpec(to_vegalite(forest(coef)), nothing); linkxaxes=:none, spacing=20))
    @test raw == kept
    @test zooms.(st2["vconcat"]) == [Dict("grid_p0" => ["x"]), Dict("grid_p1" => ["x"])]
    # A lowered figure lowered again keeps its one zoom (it used to gain a second).
    @test zooms(to_vegalite(AlgebraOfVega.VegaSpec(to_vegalite(forest(qt)), nothing))) == Dict("grid" => ["x"])

    # Row and wrap per-panel-Y stacks: one x zoom, each panel's y its own (todo `04imxgm`).
    rows = (; dose=repeat([1.0, 2, 3], 2), q50=[1.0, 2, 3, 100, 200, 300], panel=repeat(["Cmax", "AUC"], inner=3))
    perpanel = config(scales=scales(Y=(; scale=Dict("Cmax" => log10))))
    stack = to_vegalite(data(rows) * mapping(:dose, :q50; row=:panel) * visual(Scatter) * perpanel)
    @test zooms.(stack["vconcat"]) == [Dict("grid" => ["x"], "grid_p0" => ["y"]), Dict("grid" => ["x"], "grid_p1" => ["y"])]
    wrap = to_vegalite(data(rows) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) * perpanel)
    @test zooms.(wrap["concat"]) == [Dict("grid" => ["x"], "grid_p0" => ["y"]), Dict("grid" => ["x"], "grid_p1" => ["y"])]
    # With the facet's x unlinked, every axis is the panel's own.
    unlinked = to_vegalite(data(rows) * mapping(:dose, :q50; row=:panel) * visual(Scatter) * perpanel *
        config(facet=(; linkxaxes=:none)))
    @test zooms.(unlinked["vconcat"]) == [Dict("grid_p0" => ["x", "y"]), Dict("grid_p1" => ["x", "y"])]
    # Per-column Y: the columns keep one x zoom, each column's y its own.
    cols = to_vegalite(data(rows) * mapping(:dose, :q50; col=:panel) * visual(Scatter) * perpanel)
    @test zooms.(cols["hconcat"]) == [Dict("grid" => ["x"], "grid_p0" => ["y"]), Dict("grid" => ["x"], "grid_p1" => ["y"])]
    # The positional `scales` form lowers alike.
    @test zooms.(to_vegalite(data(rows) * mapping(:dose, :q50; row=:panel) * visual(Scatter),
        scales(Y=(; scale=Dict("Cmax" => log10))))["vconcat"]) == zooms.(stack["vconcat"])
end

@testitem "vconcat in the browser: aligned panels, one readout, one x zoom" tags=[:vconcat, :browser] begin
    using AlgebraOfVega, JSON
    import AlgebraOfGraphics
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        t = collect(1.0:24)
        # y labels of very different widths: aligned plot areas all the same.
        level = data((; t, y=1000 .* sin.(t) .+ 12000)) * mapping(:t => "Hour", :y => "Level") * visual(Lines) *
            config(height=200, link=(; group="hours", key=:t))
        rain = data((; t, mm=abs.(cos.(t)))) * mapping(:t => "Hour", :mm => "mm/h") * visual(BarPlot) *
            config(height=60, readout=true, link=(; group="hours", key=:t))
        page = [vdraw(vconcat(level, rain); id="stack")]
        driver = """
        (async function () {
            const out = {errors: []};
            window.addEventListener('error', e => out.errors.push(String(e.message)));
            const pause = () => new Promise(r => setTimeout(r, 20));
            for (let i = 0; i < 300 && !(AoV.views.stack && !AoV._inFlight.stack); i++) await pause();
            for (let i = 0; i < 10; i++) await pause();
            const view = AoV.views.stack, frame = view.scenegraph().root.items[0];
            const panels = [];
            frame.items.forEach(m => { if (/^concat_\\d+_group\$/.test(m.name || '')) m.items.forEach(g => panels.push(g)); });
            out.panels = panels.map(g => [g.x, g.width]);
            out.width = view.container().querySelector('canvas').clientWidth;
            out.el = view.container().clientWidth;
            // The readout over the upper panel lists the lower panel's series too.
            const canvas = view.container().querySelector('canvas'), rect = canvas.getBoundingClientRect();
            const o = view.origin(), p = view.padding(), x = view.scale('x')(12);
            const at = (px, py) => {
                const opts = {bubbles: true, cancelable: true, clientX: rect.left + o[0] + p.left + px,
                    clientY: rect.top + o[1] + p.top + py, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
                canvas.dispatchEvent(new PointerEvent('pointermove', opts));
                canvas.dispatchEvent(new MouseEvent('mousemove', opts));
            };
            const box = () => { const b = document.querySelector('#stack .aov-readout');
                return b && b.style.display !== 'none' ? b.innerText.split('\\n').map(s => s.trim()).filter(Boolean) : null; };
            const rule = () => { const r = document.querySelector('#stack .aov-readout-rule'); return r ? r.getBoundingClientRect() : null; };
            at(x, panels[0].y + 50); await pause(); await pause();
            out.upper = box();
            const ru = rule(); out.ruleSpan = ru ? [ru.height, panels[1].y + panels[1].height - panels[0].y] : null;
            at(x, panels[1].y + 30); await pause(); await pause();
            out.lower = box();
            // A link-group member (a table row) announcing hour 6.
            document.dispatchEvent(new CustomEvent('htmxo:link', {detail: {group: 'hours', key: '6', keys: ['6']}}));
            await pause(); await pause();
            out.announced = box();
            // One x zoom: a wheel over the lower panel zooms the shared x.
            const before = view.scale('x').domain().slice();
            const wheel = {bubbles: true, cancelable: true, deltaY: -400, clientX: rect.left + o[0] + p.left + x,
                clientY: rect.top + o[1] + p.top + panels[1].y + 30};
            canvas.dispatchEvent(new WheelEvent('wheel', wheel));
            await pause(); await view.runAsync(); await pause();
            out.zoomed = [before, view.scale('x').domain()];
            const pre = document.createElement('pre'); pre.id = 'aov-vconcat';
            pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
        })();
        """
        mktempdir(prefix="kb-aov-vconcat-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:900px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,800
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"aov-vconcat\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                r = JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "vconcat" r
                @test isempty(r["errors"])
                # Both plot areas start and end at the same pixel, and the plot fits its column.
                @test length(r["panels"]) == 2 && r["panels"][1] == r["panels"][2]
                @test r["width"] <= r["el"] + 1 && r["panels"][1][2] > 700
                # One readout for the stack, from either panel, with one rule through both.
                for rows in (r["upper"], r["lower"])
                    @test !isnothing(rows) && any(startswith("Level: "), rows) && any(startswith("mm/h: "), rows)
                end
                @test !isnothing(r["ruleSpan"]) && abs(r["ruleSpan"][1] - r["ruleSpan"][2]) <= 1
                @test !isnothing(r["announced"]) && startswith(r["announced"][1], "Hour: 6")
                # The wheel over the bars zoomed the x both panels share.
                b, a = r["zoomed"]
                @test a[2] - a[1] < b[2] - b[1]
            end
        end
    end
end

# The zoom of each composition, driven in headless Chrome: a wheel over one
# panel moves that panel's own axes only, and an axis the panels share moves
# in every panel (snag `vconcat-panels-w-4a6f3581`, todo `04imxgm`).
@testitem "vconcat in the browser: a panel's own axes zoom alone" tags=[:vconcat, :browser] begin
    using AlgebraOfVega, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        t = collect(0.0:0.5:10)
        # Panels in different units: a QT interval near 400 ms over coefficients near 0.
        qt = data((; x=390 .+ 2 .* t, y=sin.(t))) * mapping(:x => "QT (ms)", :y => "Level") * visual(Lines) *
            config(height=120)
        # Its y labels ("-10,000") are much wider than the upper panel's ("-1.0").
        coef = data((; x=t .- 4, y=10_000 .* cos.(t))) * mapping(:x => "Coefficient", :y => "Coef") * visual(Lines) *
            config(height=120)
        # Two panels on one x, plotting the same y column.
        same_a = data((; t, v=sin.(t))) * mapping(:t, :v => "A") * visual(Lines) * config(height=100)
        same_b = data((; t, v=100 .* cos.(t))) * mapping(:t, :v => "B") * visual(Lines) * config(height=100)
        rows = (; dose=repeat([1.0, 2, 4, 8], 2), q50=[1.0, 3, 9, 27, 100, 300, 900, 2700],
            panel=repeat(["Cmax", "AUC"], inner=4))
        perpanel = config(height=100, scales=scales(Y=(; scale=Dict("Cmax" => log10))))
        page = [vdraw(vconcat(qt, coef; linkxaxes=:none, spacing=20); id="free"),
            vdraw(vconcat(same_a, same_b); id="linked"),
            vdraw(data(rows) * mapping(:dose, :q50; row=:panel) * visual(Scatter) * perpanel; id="rows"),
            vdraw(data(rows) * mapping(:dose, :q50; layout=:panel) * visual(Scatter) * perpanel *
                config(columns=2); id="wrap")]
        driver = """
        (async function () {
            const out = {errors: []};
            window.addEventListener('error', e => out.errors.push(String(e.message)));
            const pause = () => new Promise(r => setTimeout(r, 20));
            const ids = ['free', 'linked', 'rows', 'wrap'];
            for (let i = 0; i < 400 && !ids.every(id => AoV.views[id] && !AoV._inFlight[id]); i++) await pause();
            for (let i = 0; i < 10; i++) await pause();
            const dom = (view, name) => { try { return view.scale(name).domain().map(Number); } catch (e) { return null; } };
            const panelsOf = view => {
                const ps = [];
                view.scenegraph().root.items[0].items.forEach(m => {
                    if (/^concat_\\d+_group\$/.test(m.name || '')) m.items.forEach(g => ps.push(g));
                });
                return ps;
            };
            const scaleNames = ['x', 'concat_0_x', 'concat_1_x', 'concat_0_y', 'concat_1_y'];
            const domains = view => Object.fromEntries(scaleNames.map(n => [n, dom(view, n)]));
            // A wheel and a pointer move over the middle of panel k's plot area.
            const at = (view, k) => {
                const g = panelsOf(view)[k], canvas = view.container().querySelector('canvas');
                const rect = canvas.getBoundingClientRect(), o = view.origin(), p = view.padding();
                return {canvas, clientX: rect.left + o[0] + p.left + g.x + g.width / 2,
                    clientY: rect.top + o[1] + p.top + g.y + g.height / 2};
            };
            for (const id of ids) {
                const view = AoV.views[id], r = out[id] = {};
                r.panels = panelsOf(view).map(g => ({x: g.x, y: g.y, w: g.width, h: g.height,
                    top: g.bounds.y1, bottom: g.bounds.y2}));
                r.before = domains(view);
                // Vega sends a wheel to the item the last pointer move found.
                const w = at(view, 1), move = {bubbles: true, cancelable: true, clientX: w.clientX,
                    clientY: w.clientY, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
                w.canvas.dispatchEvent(new PointerEvent('pointermove', move));
                w.canvas.dispatchEvent(new MouseEvent('mousemove', move));
                await pause();
                w.canvas.dispatchEvent(new WheelEvent('wheel', {bubbles: true, cancelable: true, deltaY: -400,
                    clientX: w.clientX, clientY: w.clientY}));
                await pause(); await view.runAsync(); await pause();
                r.after = domains(view);
            }
            // The readout of the stack with its own x follows the hovered panel.
            const view = AoV.views.free, w = at(view, 1);
            const opts = {bubbles: true, cancelable: true, clientX: w.clientX, clientY: w.clientY,
                pointerId: 1, isPrimary: true, pointerType: 'mouse'};
            w.canvas.dispatchEvent(new PointerEvent('pointermove', opts));
            w.canvas.dispatchEvent(new MouseEvent('mousemove', opts));
            await pause(); await pause();
            const b = document.querySelector('#free .aov-readout');
            out.readout = b && b.style.display !== 'none' ? b.innerText.split('\\n').map(s => s.trim()).filter(Boolean) : null;
            const pre = document.createElement('pre'); pre.id = 'aov-vconcat-zoom';
            pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
        })();
        """
        mktempdir(prefix="kb-aov-vconcat-zoom-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:900px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,1400
                --virtual-time-budget=30000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"aov-vconcat-zoom\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                r = JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "vconcat zoom" r
                @test isempty(r["errors"])
                span(d) = d[2] - d[1]
                zoomed(d0, d1) = !isnothing(d0) && !isnothing(d1) && span(d1) < 0.95 * span(d0)
                same(d0, d1) = !isnothing(d0) && d0 == d1
                # Own x: the wheel zoomed the lower panel's x and y only.
                f = r["free"]
                @test isnothing(f["before"]["x"])
                @test zoomed(f["before"]["concat_1_x"], f["after"]["concat_1_x"])
                @test zoomed(f["before"]["concat_1_y"], f["after"]["concat_1_y"])
                @test same(f["before"]["concat_0_x"], f["after"]["concat_0_x"])
                @test same(f["before"]["concat_0_y"], f["after"]["concat_0_y"])
                @test 385 < f["before"]["concat_0_x"][1] && f["before"]["concat_1_x"][2] < 10
                # Each panel's x axis sits above the next panel, and the plot areas line up.
                p1, p2 = f["panels"]
                @test p1["bottom"] <= p2["top"] + 1 && p1["x"] == p2["x"]
                # The readout lists the hovered panel's series only.
                @test !isnothing(r["readout"]) && any(startswith("Coef"), r["readout"]) &&
                    !any(startswith("Level"), r["readout"])
                # Shared x and one y column: x moved in both panels, the upper panel's y stayed.
                l = r["linked"]
                @test zoomed(l["before"]["x"], l["after"]["x"])
                @test zoomed(l["before"]["concat_1_y"], l["after"]["concat_1_y"])
                @test same(l["before"]["concat_0_y"], l["after"]["concat_0_y"])
                # Row and wrap per-panel-Y stacks: the other panel's y stayed (todo `04imxgm`).
                for id in ("rows", "wrap")
                    s = r[id]
                    @test zoomed(s["before"]["x"], s["after"]["x"])
                    @test zoomed(s["before"]["concat_1_y"], s["after"]["concat_1_y"])
                    @test same(s["before"]["concat_0_y"], s["after"]["concat_0_y"])
                end
            end
        end
    end
end
