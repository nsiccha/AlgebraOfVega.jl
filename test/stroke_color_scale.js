// A mapped stroke under `scales(Color=…)`, in the browser: each cell's stroke is
// the colour of its fill, clip and NaN colours included; the two channels draw
// one legend, a colour bar on a continuous colour; a stroke alone takes the
// scale; frames and data changes keep fill and stroke together; and a legend
// click on a categorical colour still selects.
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
    // Which parts a view's legends draw: a colour bar or discrete symbols.
    function parts(view) {
        const roles = new Set();
        (function walk(item) {
            if (item.mark?.role) roles.add(item.mark.role);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return {bar: roles.has('legend-gradient'), symbols: roles.has('legend-symbol')};
    }
    const oneBar = (view, id) => {
        check(legends(view) === 1, id + ': one legend, got ' + JSON.stringify(titles(view)));
        const p = parts(view);
        check(p.bar && !p.symbols, id + ': the legend is a colour bar, got ' + JSON.stringify(p));
    };
    const samePaint = (shown, id) => {
        const cells = Object.entries(shown);
        check(cells.length > 0, id + ': no cells drawn');
        for (const [k, p] of cells)
            check(!!p.stroke && p.fill === p.stroke, id + ': cell ' + k + ' stroke should be its fill, got ' + JSON.stringify(p));
    };

    try {
        const sameView = await ready('st-same');
        const same = paints(sameView);
        check(Object.keys(same).length === 5, 'st-same: expected 5 cells, got ' + JSON.stringify(same));
        samePaint(same, 'st-same');
        check(same.b.fill !== same.d.fill, 'st-same: cells should differ, got ' + JSON.stringify(same));
        check(same.a.stroke === sameView.scale('stroke')(0) && same.e.stroke === sameView.scale('stroke')(3),
            'st-same: out-of-range strokes take the end colours, got ' + JSON.stringify(same));
        oneBar(sameView, 'st-same');
        check(JSON.stringify(titles(sameView)) === '["W"]', 'st-same: legend title, got ' + JSON.stringify(titles(sameView)));
        check(JSON.stringify(sameView.scale('stroke').domain()) === '[0,3]', 'st-same: the stroke keeps the range, got ' + JSON.stringify(sameView.scale('stroke').domain()));

        const clipView = await ready('st-clip');
        oneBar(clipView, 'st-clip');
        const clip = paints(clipView);
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
        oneBar(aloneView, 'st-alone');

        const otherView = await ready('st-other');
        check(paints(otherView).a.stroke === viridisAt(3), 'st-other: another column takes the same scale, got ' + paints(otherView).a.stroke);
        check(JSON.stringify(titles(otherView)) === '["W, Other"]', 'st-other: one legend over the shared range, got ' + JSON.stringify(titles(otherView)));

        const catView = await ready('st-cat');
        const cat = paints(catView);
        check(cat.a.fill === 'blue' && cat.a.stroke === 'blue', 'st-cat: x is blue on both, got ' + JSON.stringify(cat.a));
        check(cat.b.fill === 'red' && cat.b.stroke === 'red', 'st-cat: y is red on both, got ' + JSON.stringify(cat.b));
        check(legends(catView) === 1, 'st-cat: one legend, got ' + JSON.stringify(titles(catView)));
        check(parts(catView).symbols && !parts(catView).bar, 'st-cat: categories draw symbols, got ' + JSON.stringify(parts(catView)));
        // A legend click selects through the merged legend, as on a fill-only map.
        const catBox = document.getElementById('st-cat');
        const label = [...catBox.querySelectorAll('.role-legend-label text')].find(n => n.textContent === 'y');
        check(!!label, 'st-cat: legend label y');
        label.dispatchEvent(new MouseEvent('click', {bubbles: true}));
        await pause();
        await catView.runAsync();
        check(catView.data('legend_selection_store').some(t => t.values[0] === 'y'), 'st-cat: the click selects y');
        const dimmed = {};
        (function walk(item) {
            if (item.mark?.marktype === 'shape' && item.datum?.k !== undefined) dimmed[item.datum.k] = item.opacity;
            (item.items || []).forEach(walk);
        })(catView.scenegraph().root);
        check(dimmed.a <= 0.15 && dimmed.b > 0.15, 'st-cat: x dims and y stays, got ' + JSON.stringify(dimmed));

        // No `colorrange`: the frame plan fixes the data-driven domain of both scales.
        for (const [id, domain] of [['st-frame', '[0,6]'], ['st-frame-fixed', '[0,3]']]) {
            const seen = [];
            for (const i of [0, 1]) {
                await AoV.setFrame(id, i);
                const view = await ready(id);
                const shown = paints(view);
                check(Object.values(shown).length === 3, id + ': frame ' + i + ' cells, got ' + JSON.stringify(shown));
                samePaint(shown, id + ' frame ' + i);
                seen.push(JSON.stringify(view.scale('stroke').domain()));
                oneBar(view, id + ' frame ' + i);
            }
            check(seen[0] === seen[1] && seen[0] === domain, id + ': one stroke domain across frames, got ' + JSON.stringify(seen));
        }

        // No `Color` scale at all, and a log colour: one colour bar, same paint.
        const plainView = await ready('st-plain');
        samePaint(paints(plainView), 'st-plain');
        oneBar(plainView, 'st-plain');
        check(JSON.stringify(plainView.scale('stroke').domain()) === '[10,50]', 'st-plain: the stroke range is the data range, got ' + JSON.stringify(plainView.scale('stroke').domain()));
        const logView = await ready('st-log');
        samePaint(paints(logView), 'st-log');
        oneBar(logView, 'st-log');
        check(/log/.test(logView.scale('stroke').type), 'st-log: a log stroke scale, got ' + logView.scale('stroke').type);

        // New rows move the range from the data on both channels.
        AoV.updateData('st-plain', [{k: 'a', v: 1, w: 100, g: 'x'}, {k: 'b', v: 2, w: 900, g: 'y'}, {k: 'c', v: 3, w: 400, g: 'x'}]);
        for (let i = 0; i < 300 && JSON.stringify(AoV.views['st-plain'].scale('stroke').domain()) !== '[100,900]'; i++) await pause();
        const updatedView = await ready('st-plain');
        await updatedView.runAsync();
        check(JSON.stringify(updatedView.scale('stroke').domain()) === '[100,900]', 'st-plain update: stroke range follows the rows, got ' + JSON.stringify(updatedView.scale('stroke').domain()));
        samePaint(paints(updatedView), 'st-plain update');
        oneBar(updatedView, 'st-plain update');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-stroke-scale-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
