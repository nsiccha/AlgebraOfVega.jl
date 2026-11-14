// A palette entry `:ink` (`scales(Color=(; palette=[:ink, …]))`) draws its
// category in the page's text colour: the scale range, the marks and the
// legend symbol, in light and dark, through a picker remap, both drawings of a
// ribbon and a theme switch. A literal `#333` in a palette stays `#333`, and an
// `aov-ink` colour the spec sets stays put (snag `give-one-categor-f6fa34be`).
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const LIGHT = 'rgba(30,40,50,1)', DARK = 'rgba(200,210,220,1)', RED = '#e03131';
    const ids = ['ink-lines', 'ink-literal', 'ink-pinned', 'ink-layered', 'ink-picker', 'ink-ribbon'];
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
    const paint = i => (i.fill != null && i.fill !== 'transparent' ? i.fill : i.stroke);
    // The paints of the data marks of `type`, per value of `field`.
    function paints(view, type, field) {
        const by = {};
        items(view, i => i.mark?.marktype === type && i.mark?.role === 'mark' && i.datum && i.datum[field] !== undefined)
            .forEach(i => { (by[i.datum[field]] = by[i.datum[field]] || new Set()).add(paint(i)); });
        return Object.fromEntries(Object.entries(by).map(([k, s]) => [k, [...s].sort().join('|')]));
    }
    // Legend entries in order: [label, symbol paint].
    function legend(view) {
        const labels = items(view, i => i.mark?.role === 'legend-label').map(i => i.text);
        const symbols = items(view, i => i.mark?.role === 'legend-symbol').map(paint);
        return labels.map((l, k) => [l, symbols[k]]);
    }
    // Equal as JSON, object keys in any order.
    const canon = x => Array.isArray(x) ? x.map(canon) : x && typeof x === 'object' ?
        Object.fromEntries(Object.keys(x).sort().map(k => [k, canon(x[k])])) : x;
    const same = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));
    function series(view, type, ink, label, field = 's') {
        const got = paints(view, type, field);
        check(same(got, {reference: ink, other: RED}), label + ' ' + type + ': ' + JSON.stringify(got) + ', ink ' + ink);
    }
    function scaleRange(view, ink, label) {
        const range = view.scale('color').range();
        check(same(range, [ink, RED]), label + ': colour range ' + JSON.stringify(range));
    }
    function key(view, ink, label) {
        const got = legend(view);
        check(same(got, [['reference', ink], ['other', RED]]), label + ': legend ' + JSON.stringify(got));
    }
    function all(views, ink, label) {
        // The reported figure.
        scaleRange(views['ink-lines'], ink, label + ' lines');
        series(views['ink-lines'], 'line', ink, label + ' lines');
        key(views['ink-lines'], ink, label + ' lines');
        // A literal #333 is the author's colour, in every theme.
        series(views['ink-literal'], 'line', '#333', label + ' literal');
        key(views['ink-literal'], '#333', label + ' literal');
        // A spec that set its own ink keeps it.
        series(views['ink-pinned'], 'line', '#123456', label + ' pinned');
        key(views['ink-pinned'], '#123456', label + ' pinned');
        // Every layer.
        series(views['ink-layered'], 'line', ink, label + ' layered');
        series(views['ink-layered'], 'symbol', ink, label + ' layered');
        key(views['ink-layered'], ink, label + ' layered');
    }
    async function switchTheme(dark) {
        const before = {};
        ids.forEach(id => { before[id] = AoV.views[id]; });
        if (dark) document.documentElement.setAttribute('data-theme', 'dark');
        else document.documentElement.removeAttribute('data-theme');
        const after = {};
        for (const id of ids) after[id] = await ready(id, before[id]);
        for (let i = 0; i < 60; i++) await pause();
        ids.forEach(id => { after[id] = AoV.views[id]; });
        return after;
    }
    async function ribbonView(id, which) {
        const before = AoV.views[id];
        check(AoV.setRibbonView(id, which), id + ': no ' + which + ' drawing');
        return await ready(id, before);
    }

    try {
        let views = {};
        for (const id of ids) views[id] = await ready(id);

        // Light page.
        all(views, LIGHT, 'light');
        series(views['ink-picker'], 'line', LIGHT, 'light picker');
        series(views['ink-ribbon'], 'line', LIGHT, 'light ribbon');
        series(views['ink-ribbon'], 'area', LIGHT, 'light ribbon');
        key(views['ink-ribbon'], LIGHT, 'light ribbon');
        // The stored spec keeps AoV's #333: the swap is per embed.
        const stored = JSON.stringify(AoV._cur['ink-lines'].spec);
        check(stored.includes('["#333","#e03131"]') && !stored.includes(LIGHT), 'stored spec took the host ink');

        // A picker remap away from the authored field and back.
        let before = AoV.views['ink-picker'];
        AoV.remapEncoding('ink-picker', {color: 'g'});
        views['ink-picker'] = await ready('ink-picker', before);
        const g = paints(views['ink-picker'], 'line', 'g');
        check(!Object.values(g).includes(LIGHT), 'light picker remap: the other field took the ink ' + JSON.stringify(g));

        // Dark page.
        views = await switchTheme(true);
        all(views, DARK, 'dark');
        before = AoV.views['ink-picker'];
        AoV.remapEncoding('ink-picker', {color: 's'});
        views['ink-picker'] = await ready('ink-picker', before);
        series(views['ink-picker'], 'line', DARK, 'dark picker back');
        key(views['ink-picker'], DARK, 'dark picker back');
        // The ribbon's other drawing: point-intervals take the palette too.
        series(views['ink-ribbon'], 'area', DARK, 'dark ribbon');
        views['ink-ribbon'] = await ribbonView('ink-ribbon', 'intervals');
        series(views['ink-ribbon'], 'rule', DARK, 'dark intervals');
        key(views['ink-ribbon'], DARK, 'dark intervals');

        // An SVG export draws the ink on the dark background.
        const svg = await (await fetch(await AoV.plotImageURL('ink-lines', 'svg'))).text();
        check(svg.includes('rgb(20,24,31)') && svg.includes('stroke="' + DARK + '"'),
            'dark svg export lacks the host ink line: ' + svg.slice(0, 300));

        // And back.
        views = await switchTheme(false);
        all(views, LIGHT, 'back to light');
        series(views['ink-ribbon'], 'rule', LIGHT, 'back to light intervals');
        views['ink-ribbon'] = await ribbonView('ink-ribbon', 'ribbons');
        series(views['ink-ribbon'], 'line', LIGHT, 'back to light ribbon');
        series(views['ink-picker'], 'line', LIGHT, 'back to light picker');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-palette-ink-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
