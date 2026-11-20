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
