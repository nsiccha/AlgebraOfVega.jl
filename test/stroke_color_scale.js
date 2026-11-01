// A mapped stroke under `scales(Color=…)`, in the browser: each cell's stroke is
// the colour of its fill, clip and NaN colours included; the two channels draw
// one legend; a stroke alone takes the scale; and frames keep fill and stroke
// together.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // Fill and stroke of each drawn geoshape, by key.
    function paints(view) {
        const out = {};
        (function walk(item) {
            if (item.mark?.marktype === 'shape' && item.datum && item.datum.k !== undefined)
                out[item.datum.k] = {fill: item.fill, stroke: item.stroke};
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    // The legend titles of a view: one per legend drawn.
    function titles(view) {
        const out = [];
        (function walk(item) {
            if (item.mark?.role === 'legend-title') out.push(String(item.text));
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const legends = view => titles(view).length;

    try {
        const sameView = await ready('st-same');
        const same = paints(sameView);
        check(Object.keys(same).length === 5, 'st-same: expected 5 cells, got ' + JSON.stringify(same));
        for (const [k, p] of Object.entries(same))
            check(p.fill === p.stroke, 'st-same: cell ' + k + ' stroke should be its fill, got ' + JSON.stringify(p));
        check(same.b.fill !== same.d.fill, 'st-same: cells should differ, got ' + JSON.stringify(same));
        check(same.a.stroke === sameView.scale('stroke')(0) && same.e.stroke === sameView.scale('stroke')(3),
            'st-same: out-of-range strokes take the end colours, got ' + JSON.stringify(same));
        check(legends(sameView) === 1, 'st-same: one legend, got ' + legends(sameView));
        check(JSON.stringify(titles(sameView)) === '["W"]', 'st-same: legend title, got ' + JSON.stringify(titles(sameView)));

        const clip = paints(await ready('st-clip'));
        check(clip.a.stroke === 'red' && clip.a.fill === 'red', 'st-clip: lowclip on both, got ' + JSON.stringify(clip.a));
        check(clip.e.stroke === 'green' && clip.e.fill === 'green', 'st-clip: highclip on both, got ' + JSON.stringify(clip.e));
        check(!!clip.d && clip.d.stroke === 'grey' && clip.d.fill === 'grey', 'st-clip: nan_color on both, got ' + JSON.stringify(clip.d));
        check(clip.b.stroke === clip.b.fill && !['red', 'green', 'grey'].includes(clip.b.stroke),
            'st-clip: an in-range value keeps the scheme, got ' + JSON.stringify(clip.b));

        const aloneView = await ready('st-alone');
        const alone = paints(aloneView);
        const viridisAt = v => sameView.scale('stroke')(v);
        check(alone.b.stroke === viridisAt(0.5) && alone.c.stroke === viridisAt(1.5), 'st-alone: strokes take the scheme, got ' + JSON.stringify(alone));
        check(alone.b.fill === 'white', 'st-alone: the fixed fill stays, got ' + alone.b.fill);
        check(legends(aloneView) === 1, 'st-alone: one legend, got ' + legends(aloneView));

        const otherView = await ready('st-other');
        check(paints(otherView).a.stroke === viridisAt(3), 'st-other: another column takes the same scale, got ' + paints(otherView).a.stroke);
        check(JSON.stringify(titles(otherView)) === '["W, Other"]', 'st-other: one legend over the shared range, got ' + JSON.stringify(titles(otherView)));

        const catView = await ready('st-cat');
        const cat = paints(catView);
        check(cat.a.fill === 'blue' && cat.a.stroke === 'blue', 'st-cat: x is blue on both, got ' + JSON.stringify(cat.a));
        check(cat.b.fill === 'red' && cat.b.stroke === 'red', 'st-cat: y is red on both, got ' + JSON.stringify(cat.b));
        check(legends(catView) === 1, 'st-cat: one legend, got ' + legends(catView));

        // No `colorrange`: the frame plan fixes the data-driven domain of both scales.
        const seen = [];
        for (const i of [0, 1]) {
            await AoV.setFrame('st-frame', i);
            const view = await ready('st-frame');
            const shown = paints(view);
            check(Object.values(shown).length === 3, 'st-frame: frame ' + i + ' cells, got ' + JSON.stringify(shown));
            for (const [k, p] of Object.entries(shown))
                check(p.fill === p.stroke, 'st-frame: frame ' + i + ' cell ' + k + ', got ' + JSON.stringify(p));
            seen.push(JSON.stringify(view.scale('stroke').domain()));
            check(legends(view) === 1, 'st-frame: frame ' + i + ' one legend, got ' + legends(view));
        }
        check(seen[0] === seen[1] && seen[0] === '[0,6]', 'st-frame: one stroke domain across frames, got ' + JSON.stringify(seen));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-stroke-scale-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
