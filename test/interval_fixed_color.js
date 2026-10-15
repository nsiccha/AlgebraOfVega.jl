// Fixed-colour interval browser checks: a `visual(; color=…)` interval paints
// its rules (and dotinterval's dots) in that colour while the median point stays
// white, `:ink` follows the page theme, and a channel-picker colour remap leaves
// the fixed-colour interval alone.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const LIGHT = 'rgba(30,40,50,1)', DARK = 'rgba(200,210,220,1)';
    const plain = ['iv-point-ink', 'iv-point-black', 'iv-bands-black', 'iv-gradient-ink',
        'iv-gradient-black', 'iv-dot-ink', 'iv-dot-black'];
    const pickers = ['iv-picker-ink', 'iv-picker-black'];
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
    // Data marks only: axis ticks, grid lines and domains are rules too.
    const dataItems = (view, type) => items(view, i => i.mark?.marktype === type && i.mark.role === 'mark');
    const ruleStrokes = view => uniq(dataItems(view, 'rule').filter(i => i.stroke !== undefined).map(i => i.stroke));
    const symbols = view => dataItems(view, 'symbol').filter(i => i.fill !== undefined && i.datum);
    // Median points carry the dark ring; dotinterval dots and picker scatters
    // (the rows with `h`) are the rest.
    const isMedian = i => i.stroke === '#333';
    const medianFills = view => uniq(symbols(view).filter(isMedian).map(i => i.fill));
    const dotFills = view => uniq(symbols(view).filter(i => !isMedian(i) && i.datum.h === undefined).map(i => i.fill));
    const scatterFills = view => uniq(symbols(view).filter(i => !isMedian(i) && i.datum.h !== undefined).map(i => i.fill));
    function interval(id, view, colour, label) {
        const rules = ruleStrokes(view);
        check(rules.length === 1 && rules[0] === colour, label + ' ' + id + ': rule strokes ' + JSON.stringify(rules) + ', expected ' + colour);
        const medians = medianFills(view);
        check(medians.length === 1 && medians[0] === 'white', label + ' ' + id + ': median fills ' + JSON.stringify(medians));
        if (id.startsWith('iv-dot')) {
            const dots = dotFills(view);
            check(dots.length === 1 && dots[0] === colour, label + ' ' + id + ': dot fills ' + JSON.stringify(dots) + ', expected ' + colour);
        }
    }

    try {
        const views = {};
        for (const id of [...plain, ...pickers]) views[id] = await ready(id);
        for (const id of [...plain, ...pickers]) interval(id, views[id], ink(id) ? LIGHT : 'black', 'light');

        // A picker colour remap recolours the scatter, not the fixed interval.
        for (const id of pickers) {
            const before = views[id];
            check(scatterFills(before).length === 1, id + ': scatter starts uncoloured ' + JSON.stringify(scatterFills(before)));
            AoV.remapEncoding(id, {color: 'h'});
            const after = await ready(id, before);
            check(scatterFills(after).length === 2, id + ': remap did not colour the scatter ' + JSON.stringify(scatterFills(after)));
            interval(id, after, ink(id) ? LIGHT : 'black', 'after remap');
            views[id] = after;
        }

        // Dark page: ink follows it, a literal colour stays.
        const before = Object.assign({}, AoV.views);
        document.documentElement.setAttribute('data-theme', 'dark');
        for (const id of [...plain, ...pickers]) {
            const view = await ready(id, before[id]);
            interval(id, view, ink(id) ? DARK : 'black', 'dark');
        }
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-interval-color-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
