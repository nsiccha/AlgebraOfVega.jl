// Geoshape browser checks: an unfaceted choropleth fills each district once,
// and a `col=`/`row=`/`layout=` faceted one draws one map per level, each
// filled from that level's own table rows.
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
    // Drawn polygons grouped by the facet cell that holds them.
    function cells(view) {
        const out = {};
        (function walk(item, cell) {
            if (item.mark?.marktype === 'group' && /cell/.test(item.mark.name || ''))
                cell = String(item.datum?.year);
            if (item.mark?.marktype === 'shape' && item.datum)
                (out[cell ?? '(single view)'] = out[cell ?? '(single view)'] || []).push(item);
            (item.items || []).forEach(child => walk(child, cell));
        })(view.scenegraph().root, null);
        return out;
    }
    // A geoshape item carries its geometry as `shape` (a path generator), not `path`.
    const filled = item => typeof item.fill === 'string' && item.fill !== 'transparent' && !!(item.shape || item.path);
    // The fixture's squares stand west to east in AGS order. A ring d3 read as
    // the globe minus its square would put every district on the same box.
    const westToEast = drawn => {
        const x = ags => drawn.find(s => s.datum.AGS === ags)?.bounds.x1;
        return x('01001') < x('01002') && x('01002') < x('01003');
    };

    try {
        const plain = cells(await ready('geo-plain'));
        check(Object.keys(plain).length === 1, 'geo-plain: expected one view, got ' + JSON.stringify(Object.keys(plain)));
        const shapes = Object.values(plain)[0] || [];
        check(shapes.length === 3 && shapes.every(filled), 'geo-plain: expected 3 filled districts, got ' + shapes.length);
        check(new Set(shapes.map(s => s.fill)).size === 3, 'geo-plain: districts should differ in fill');
        check(westToEast(shapes), 'geo-plain: districts are not drawn west to east in their own places');

        for (const id of ['geo-col', 'geo-row', 'geo-layout']) {
            const byCell = cells(await ready(id));
            check(JSON.stringify(Object.keys(byCell).sort()) === '["2020","2021"]',
                id + ': expected one panel per year, got ' + JSON.stringify(Object.keys(byCell)));
            for (const [year, panel] of Object.entries(byCell)) {
                check(panel.length === 3 && panel.every(filled), id + ' ' + year + ': expected 3 filled districts, got ' + panel.length);
                check(panel.every(s => s.datum.year === year), id + ' ' + year + ': a polygon carries another year\'s row');
                check(new Set(panel.map(s => s.datum.AGS)).size === 3, id + ' ' + year + ': districts repeat or are missing');
                check(westToEast(panel), id + ' ' + year + ': districts are not drawn west to east in their own places');
            }
            const fills = year => (byCell[year] || []).map(s => s.datum.AGS + '=' + s.fill).sort().join(',');
            check(fills('2020') !== fills('2021'), id + ': both panels show the same fills');
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-geoshape-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
