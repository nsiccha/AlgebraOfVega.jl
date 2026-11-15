using TestItemRunner

# AoG's `visual(...; label="Observed")` names a layer without a colour mapping:
# it gets a legend entry drawn in its own style, after the mapped scales'
# legends, and the readout names its series by it (decision 0qrccve, prong
# `layer-labels`). Before, AoV ignored `label` with a warning, so observed
# points and reference curves had no legend entry and the readout named them by
# the y title.
@testitem "visual(...; label) gives a legend entry in the layer's style" tags=[:labels] begin
    using AlgebraOfVega, AlgebraOfGraphics
    t = collect(1.0:5)
    obs = data((; t, y=[1.0, 2, 1.5, 3, 2.5])) * mapping(:t, :y) * visual(Scatter; color=:ink, markersize=6, label="Observed")
    ref = data((; t, y=[1.2, 1.8, 2.0, 2.6, 2.9])) * mapping(:t, :y) * visual(Lines; color=:gray, linestyle=:dash, linewidth=1.5, label="Reference")
    win = data((; a=[2.0], b=[3.0])) * mapping(:a, :b) * visual(VSpan; color=:ink, alpha=0.1, label="Window")
    fc = data((; t=repeat(t, 2), y=[1.0, 2, 1.5, 3, 2.5, 1.1, 2.2, 1.7, 3.3, 2.8], s=repeat(["A", "B"], inner=5))) *
        mapping(:t, :y; color=:s) * visual(Lines)
    enc(l) = get(l, "encoding", Dict())
    carrier(l, ch) = (e = get(enc(l), ch, nothing); e isa Dict && haskey(e, "datum") ? e : nothing)

    vl = @test_logs to_vegalite(obs + ref + win + fc)  # `label` is read, not reported as unread
    ls = vl["layer"]
    @test [get(l, "_aov_label", nothing) for l in ls] == ["Observed", "Reference", "Window", nothing]
    o, r, w = carrier(ls[1], "strokeDash"), carrier(ls[2], "strokeDash"), carrier(ls[3], "opacity")
    # Each entry's scale gives back the mark's own value, so nothing is redrawn.
    @test o["datum"] == "Observed" && o["scale"]["range"] == [[1, 0]] && o["legend"]["title"] === nothing
    @test o["legend"]["symbolSize"] == ls[1]["mark"]["size"]
    @test r["scale"]["range"] == [ls[2]["mark"]["strokeDash"]] && r["legend"]["symbolType"] == "stroke" &&
        r["legend"]["symbolStrokeWidth"] == 1.5
    @test w["type"] == "ordinal" && w["scale"]["range"] == [0.1] && w["legend"]["symbolType"] == "square"
    @test isnothing(carrier(ls[4], "strokeDash")) && isnothing(carrier(ls[4], "opacity"))
    # One legend per label, after the colour legend.
    @test vl["resolve"]["scale"] == Dict("strokeDash" => "independent", "opacity" => "independent")
    @test vl["resolve"]["legend"] == vl["resolve"]["scale"]

    # Layers sharing a label share one entry, carried by the line.
    both = data((; t, y=[1.0, 2, 1.5, 3, 2.5])) * mapping(:t, :y) *
        (visual(Lines; color=:ink, label="Observed") + visual(Scatter; color=:ink, label="Observed"))
    bl = to_vegalite(both)["layer"]
    @test all(l -> l["_aov_label"] == "Observed", bl)
    @test count(l -> !isnothing(carrier(l, "strokeDash")), bl) == 1 && !isnothing(carrier(bl[1], "strokeDash"))

    # One layer: its entry, nothing to resolve.
    one = to_vegalite(obs)
    @test carrier(one, "strokeDash")["datum"] == "Observed" && !haskey(one, "resolve")

    # Faceted: one shared legend per channel (resolving per layer would repeat it in
    # every panel), each label with its own dash.
    cmp = data((; n=repeat([10.0, 100], 2), m=repeat(["A", "B"], inner=2), e=[0.5, 0.15, 0.45, 0.14])) * mapping(:n, :e; color=:m) * visual(Lines) +
        data((; n=[10.0, 100], e=[0.3, 0.1])) * mapping(:n, :e) * visual(Lines; color=:ink, linestyle=:dot, label="1/√n") +
        data((; n=[10.0, 100], e=[0.2, 0.2])) * mapping(:n, :e) * visual(Lines; color=:gray, linestyle=:dash, label="Target")
    fv = to_vegalite(cmp * mapping(col=:m))
    inner = fv["spec"]
    @test !haskey(inner, "resolve")
    fc2 = [carrier(l, "strokeDash") for l in inner["layer"] if !isnothing(carrier(l, "strokeDash"))]
    @test [c["datum"] for c in fc2] == ["1/√n", "Target"] && all(c -> c["scale"]["domain"] == ["1/√n", "Target"], fc2)
    @test fc2[1]["scale"]["range"] == fc2[2]["scale"]["range"] && length(fc2[1]["scale"]["range"]) == 2

    # Both drawings of a ribbon figure.
    rib = data((; t=repeat(t, 2), g=repeat(["a", "b"], inner=5), q50=collect(1.0:10), lo=collect(0.5:9.5), hi=collect(1.5:10.5))) *
        mapping(:t, :q50; color=:g) * lineribbon(bands=[:lo => :hi]) + obs
    rv = to_vegalite(rib)
    for drawing in (rv, rv["_aov"]["ribbonView"]["alt"])
        @test count(l -> !isnothing(carrier(l, "strokeDash")), drawing["layer"]) == 1
    end

    # A channel a mapping uses stays the mapping's: no entry, and a warning.
    styled = data((; t=repeat(t, 2), y=collect(1.0:10), k=repeat(["u", "v"], inner=5))) * mapping(:t, :y; linestyle=:k) * visual(Lines)
    sv = @test_logs (:warn, r"no legend entry") match_mode=:any to_vegalite(styled + ref)
    @test isnothing(carrier(sv["layer"][2], "strokeDash"))
end

@testitem "label legends and readout names in the browser" tags=[:labels, :browser] begin
    using AlgebraOfVega, AlgebraOfGraphics, JSON
    html(x) = sprint(show, MIME"text/html"(), x)
    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        mktempdir(prefix="kb-layer-labels-") do dir
            t = collect(1.0:12)
            obs = data((; t, y=[1.0, 2, 1.5, 3, 2.5, 3.2, 3.0, 3.8, 4.1, 3.9, 4.6, 5.0])) * mapping(:t => "Time", :y => "Level") *
                visual(Scatter; color=:ink, label="Observed")
            ref = data((; t, y=0.35 .* t .+ 0.8)) * mapping(:t => "Time", :y => "Level") * visual(Lines; color="#8a8a85", linestyle=:dash, label="Reference")
            win = data((; a=[8.0], b=[12.0])) * mapping(:a, :b) * visual(VSpan; color=:ink, alpha=0.06, label="Forecast window")
            fc = data((; t=repeat(t, 2), y=vcat(0.4 .* t .+ 0.5, 0.45 .* t .+ 0.7), g=repeat(["A", "B"], inner=12))) *
                mapping(:t => "Time", :y => "Level"; color=:g => "Scenario") * visual(Lines)
            page = [vdraw((win + ref + fc + obs) * config(width=600, height=220); id="ll-fig"),
                auto_remap_node("ll-picker", (fc + ref + obs) * config(width=600, height=200); dims=["g" => "Scenario"])]
            head = join(html(n) for n in vega_head(; source=:inline))
            driver = """
            (async function () {
                const out = {errors: []};
                window.addEventListener('error', e => out.errors.push(String(e.message)));
                const pause = () => new Promise(r => setTimeout(r, 10));
                for (let i = 0; i < 500 && !(AoV.views['ll-fig'] && !AoV._inFlight['ll-fig']); i++) await pause();
                const view = AoV.views['ll-fig'];
                // Legend titles and labels, in drawing order.
                const legendsOf = v => {
                    const legends = [];
                    (function walk(it) {
                        if (it.mark && it.mark.role === 'legend-title' && it.text) legends.push('#' + it.text);
                        if (it.mark && it.mark.role === 'legend-label' && it.datum) legends.push(it.datum.label);
                        (it.items || []).forEach(walk);
                    })(v.scenegraph().root);
                    return legends;
                };
                out.legends = legendsOf(view);
                // The channel picker re-lowers in the browser: the entries stay.
                for (let i = 0; i < 500 && !(AoV.views['ll-picker'] && !AoV._inFlight['ll-picker']); i++) await pause();
                const before = AoV.views['ll-picker'];
                AoV.remapEncoding('ll-picker', {color: null});
                for (let i = 0; i < 500 && !(AoV.views['ll-picker'] && AoV.views['ll-picker'] !== before && !AoV._inFlight['ll-picker']); i++) await pause();
                out.picked = legendsOf(AoV.views['ll-picker']);
                // The readout at x = 9: pointer at that x, inside the plot.
                const canvas = document.querySelector('#ll-fig canvas');
                const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
                const opts = {bubbles: true, cancelable: true, clientX: rect.left + origin[0] + pad.left + view.scale('x')(9),
                    clientY: rect.top + origin[1] + pad.top + 60, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
                canvas.dispatchEvent(new PointerEvent('pointermove', opts));
                canvas.dispatchEvent(new MouseEvent('mousemove', opts));
                await pause(); await pause();
                const b = document.querySelector('#ll-fig .aov-readout');
                out.readout = b && b.style.display !== 'none' ? b.innerText.split('\\n').map(s => s.trim()).filter(Boolean) : null;
                const pre = document.createElement('pre'); pre.id = 'aov-layer-labels';
                pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
            })();
            """
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:900px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,800
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            result = match(r"<pre id=\"aov-layer-labels\">([^<]*)</pre>", output)
            @test !isnothing(result)
            if !isnothing(result)
                r = JSON.parse(replace(result[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "layer labels" r
                @test isempty(r["errors"])
                # The colour legend first, then the labelled layers in layer order.
                # (Vega's scenegraph holds a legend's title after its entries.)
                @test filter(!startswith("#"), r["legends"]) == ["A", "B", "Forecast window", "Reference", "Observed"]
                @test filter(startswith("#"), r["legends"]) == ["#Scenario"]  # the label legends are untitled
                @test r["picked"] == ["Reference", "Observed"]
                rows = something(r["readout"], String[])
                @test any(startswith("Reference: "), rows) && any(startswith("Observed: 4.1"), rows)
                @test !any(startswith("Level"), rows)
            end
        end
    end
end
