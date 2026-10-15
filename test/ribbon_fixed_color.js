// Fixed-colour ribbon browser checks: a `visual(; color=…)` ribbon paints its
// bands and median line in that colour, `:ink` follows the page theme, and a
// channel-picker colour remap leaves fixed-colour layers alone.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const LIGHT = 'rgba(30,40,50,1)', DARK = 'rgba(200,210,220,1)';
    const plain = ['rf-ink', 'rf-black'];
    const pickers = ['rf-picker-ink', 'rf-picker-black', 'rf-concat-ink', 'rf-concat-black'];
    const ink = id => id.endsWith('-ink');
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function items(view, predicate) {
        const out = [];
        (function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const uniq = xs => [...new Set(xs)];
    const areaFills = view => uniq(items(view, i => i.mark?.marktype === 'area' && i.fill !== undefined).map(i => i.fill));
    const lineStrokes = view => uniq(items(view, i => i.mark?.marktype === 'line' && i.stroke !== undefined).map(i => i.stroke));
    const pointFills = view => uniq(items(view, i => i.mark?.marktype === 'symbol' && i.datum && i.datum.g !== undefined).map(i => i.fill));
    function ribbon(id, view, colour, label) {
        const areas = areaFills(view), lines = lineStrokes(view);
        check(areas.length === 1 && areas[0] === colour, label + ' ' + id + ': band fills ' + JSON.stringify(areas) + ', expected ' + colour);
        if (!id.startsWith('rf-picker') && !id.startsWith('rf-concat'))
            check(lines.length === 1 && lines[0] === colour, label + ' ' + id + ': median line ' + JSON.stringify(lines) + ', expected ' + colour);
    }

    try {
        const views = {};
        for (const id of [...plain, ...pickers]) views[id] = await ready(id);
        for (const id of [...plain, ...pickers]) ribbon(id, views[id], ink(id) ? LIGHT : 'black', 'light');

        // A picker colour remap recolours the scatter, not the fixed ribbon —
        // in a layered figure and in a per-column-scale (hconcat) figure.
        for (const id of pickers) {
            const before = views[id];
            check(pointFills(before).length === 1, id + ': scatter starts uncoloured ' + JSON.stringify(pointFills(before)));
            AoV.remapEncoding(id, {color: 'g'});
            const after = await ready(id, before);
            check(pointFills(after).length === 2, id + ': remap did not colour the scatter ' + JSON.stringify(pointFills(after)));
            ribbon(id, after, ink(id) ? LIGHT : 'black', 'after remap');
            views[id] = after;
        }

        // Dark page: ink follows it, a literal colour stays.
        const before = Object.assign({}, AoV.views);
        document.documentElement.setAttribute('data-theme', 'dark');
        for (const id of [...plain, ...pickers]) {
            const view = await ready(id, before[id]);
            ribbon(id, view, ink(id) ? DARK : 'black', 'dark');
        }
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-ribbon-color-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
