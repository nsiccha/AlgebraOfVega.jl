// Map browser checks: marks summed onto a geoshape stand at their
// longitude/latitude, so each site's symbol lies inside the polygon of the
// district (AGS) it belongs to — unfaceted, and in every panel of a
// `col=` faceted map.
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
    // Drawn polygons and symbols, grouped by the facet cell that holds them.
    function cells(view) {
        const out = {};
        const get = cell => (out[cell] = out[cell] || {shapes: [], symbols: []});
        (function walk(item, cell) {
            if (item.mark?.marktype === 'group' && /cell/.test(item.mark.name || ''))
                cell = String(item.datum?.year);
            const key = cell ?? '(single view)';
            if (item.mark?.marktype === 'shape' && item.datum) get(key).shapes.push(item);
            if (item.mark?.marktype === 'symbol' && item.datum && 'lon' in item.datum) get(key).symbols.push(item);
            (item.items || []).forEach(child => walk(child, cell));
        })(view.scenegraph().root, null);
        return out;
    }
    const inside = (sym, shape) => {
        const b = shape.bounds;
        return b && sym.x >= b.x1 && sym.x <= b.x2 && sym.y >= b.y1 && sym.y <= b.y2;
    };
    function standInside(id, cell, panel) {
        check(panel.shapes.length === 3, id + ' ' + cell + ': expected 3 districts, got ' + panel.shapes.length);
        check(panel.symbols.length === 4, id + ' ' + cell + ': expected 4 sites, got ' + panel.symbols.length);
        for (const sym of panel.symbols) {
            const home = panel.shapes.find(s => s.datum.AGS === sym.datum.AGS);
            check(!!home && inside(sym, home), id + ' ' + cell + ': site ' + sym.datum.name + ' at (' +
                sym.x + ', ' + sym.y + ') is not inside district ' + sym.datum.AGS + ' ' + JSON.stringify(home?.bounds));
        }
    }

    try {
        const plain = cells(await ready('geo-points'));
        check(Object.keys(plain).length === 1, 'geo-points: expected one view, got ' + JSON.stringify(Object.keys(plain)));
        for (const [cell, panel] of Object.entries(plain)) standInside('geo-points', cell, panel);

        const byCell = cells(await ready('geo-points-col'));
        check(JSON.stringify(Object.keys(byCell).sort()) === '["2020","2021"]',
            'geo-points-col: expected one panel per year, got ' + JSON.stringify(Object.keys(byCell)));
        for (const [year, panel] of Object.entries(byCell)) {
            standInside('geo-points-col', year, panel);
            check(panel.shapes.every(s => s.datum.year === year) && panel.symbols.every(s => s.datum.year === year),
                'geo-points-col ' + year + ': a mark carries another year\'s row');
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-geoshape-points-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
