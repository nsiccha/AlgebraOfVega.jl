// geobox in the browser: each value row draws its key's longitude/latitude
// box as a rect, in place on the map (the 3 × 2 grid of test/geobox.jl), from
// an inline box table, a URL and `by_url`; beside polygons and lon/lat marks
// under one projection; with the own-colour seam stroke, one legend,
// tooltips, `aov:click`, highlight and hover links, the CSV rows, pan/zoom and its clip, facet
// panels and frames.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const near = (a, b, tol) => Math.abs(a - b) <= (tol === undefined ? 0.5 : tol);
    const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms || 10));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    const events = [], links = [];
    document.addEventListener('aov:click', e => events.push({target: e.target.id, detail: e.detail}));
    document.addEventListener('htmxo:link', e => links.push(e.detail));

    // Scenegraph items matching `pred`, with their box in view coordinates and
    // the facet panel (its year) that holds them.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy, panel) {
            if (item.mark && item.mark.marktype === 'group' && /cell/.test(item.mark.name || '') && item.datum)
                panel = String(item.datum.year);
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, panel, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2,
                    left: dx + item.x, right: dx + item.x + item.width,
                    top: dy + item.y, bottom: dy + item.y + item.height});
            }
            const group = item.mark && item.mark.marktype === 'group';
            const gx = group ? dx + (item.x || 0) : dx, gy = group ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy, panel));
        })(view.scenegraph().root, 0, 0, null);
        return out;
    }
    const rects = view => items(view, it => it.mark.marktype === 'rect' && it.datum && it.datum.cell);
    const byCell = list => Object.fromEntries(list.map(r => [r.item.datum.cell, r]));
    const clipped = view => {
        let any = false;
        (function walk(item) {
            if (item.mark && item.mark.marktype === 'rect' && item.mark.clip) any = true;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return any;
    };
    function client(id, x, y) {
        const view = AoV.views[id], canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        return {canvas, clientX: rect.left + origin[0] + pad.left + x, clientY: rect.top + origin[1] + pad.top + y};
    }
    function clickAt(id, x, y) {
        const c = client(id, x, y);
        const opts = {bubbles: true, cancelable: true, clientX: c.clientX, clientY: c.clientY,
            pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        events.length = 0;
        c.canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        c.canvas.dispatchEvent(new PointerEvent('pointerdown', opts));
        c.canvas.dispatchEvent(new PointerEvent('pointerup', opts));
        c.canvas.dispatchEvent(new MouseEvent('click', opts));
        return events.slice();
    }
    async function wheel(id, x, y, deltaY) {
        const c = client(id, x, y);
        const opts = {bubbles: true, cancelable: true, clientX: c.clientX, clientY: c.clientY,
            pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        c.canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        c.canvas.dispatchEvent(new MouseEvent('mousemove', opts));
        c.canvas.dispatchEvent(new WheelEvent('wheel', Object.assign({deltaY, deltaMode: 0}, opts)));
        await AoV.views[id].runAsync();
    }

    // The 3 × 2 grid in place: west to east with i, south to north with j,
    // each cell sharing its edges with its neighbours.
    function inPlace(id, cells, where) {
        const names = Object.keys(cells).sort();
        check(JSON.stringify(names) === '["c00","c01","c10","c11","c20","c21"]',
            id + where + ': cells ' + JSON.stringify(names));
        if (names.length !== 6) return;
        for (const j of [0, 1]) for (const i of [0, 1]) {
            const a = cells['c' + i + j], b = cells['c' + (i + 1) + j];
            check(near(a.right, b.left, 0.01) && near(a.top, b.top, 0.01) && near(a.bottom, b.bottom, 0.01),
                id + where + ': c' + i + j + ' and its east neighbour do not share an edge ' +
                JSON.stringify([a.right, b.left, a.top, b.top]));
        }
        for (const i of [0, 1, 2]) {
            const s = cells['c' + i + '0'], n = cells['c' + i + '1'];
            check(near(n.bottom, s.top, 0.01) && near(n.left, s.left, 0.01),
                id + where + ': c' + i + '1 is not just north of c' + i + '0 ' + JSON.stringify([n.bottom, s.top]));
        }
        // 0.1° of latitude at 54° spans 1/cos(54°) ≈ 1.70 times 0.1° of
        // longitude under Mercator.
        const c = cells.c00, ratio = (c.bottom - c.top) / (c.right - c.left);
        check(near(ratio, 1 / Math.cos(54.05 * Math.PI / 180), 0.02), id + where + ': cell aspect ' + ratio);
    }
    const positions = cells => Object.fromEntries(Object.entries(cells).map(([k, r]) => [k, [r.left, r.top, r.right, r.bottom]]));
    function samePositions(a, b, what) {
        const pa = positions(a), pb = positions(b);
        const same = Object.keys(pa).length === 6 && Object.keys(pa).every(k => pb[k] && pa[k].every((v, i) => near(v, pb[k][i], 0.01)));
        check(same, what + ': cells not where the reference draws them ' + JSON.stringify([pa, pb]));
    }

    try {
        // ---- Polygons, cells and lon/lat marks on one map.
        let view = await ready('gb-map');
        const map = byCell(rects(view));
        inPlace('gb-map', map, '');
        // The outline polygon covers exactly the grid: one fitted projection.
        const outline = items(view, it => it.mark.marktype === 'shape' && it.datum && it.datum.AGS)[0];
        check(outline && near(outline.item.bounds.x1, map.c00.left, 1) && near(outline.item.bounds.x2, map.c20.right, 1) &&
            near(outline.item.bounds.y1, map.c01.top, 1) && near(outline.item.bounds.y2, map.c00.bottom, 1),
            'gb-map: the outline polygon and the cells disagree ' + JSON.stringify([outline && outline.item.bounds, positions(map)]));
        // Site A (10.05°E, 54.05°N) stands in c10, B (10.15°E, 54.15°N) in c21.
        const sites = items(view, it => it.mark.marktype === 'symbol' && it.datum && 'lon' in it.datum);
        const inside = (p, c) => p.x > c.left && p.x < c.right && p.y > c.top && p.y < c.bottom;
        check(sites.length === 2 && inside(sites[0], map.c10) && inside(sites[1], map.c21),
            'gb-map: sites not inside their cells ' + JSON.stringify(sites.map(s => [s.x, s.y])));
        // Own-colour seams: each cell is stroked in its fill, six colours, one legend.
        const fills = Object.values(map).map(r => r.item.fill);
        check(new Set(fills).size === 6, 'gb-map: expected six fills, got ' + JSON.stringify(fills));
        check(Object.values(map).every(r => r.item.stroke === r.item.fill && r.item.strokeWidth === 0.7),
            'gb-map: a cell is not stroked in its own colour');
        const legends = items(view, it => it.mark.role === 'legend');
        check(legends.length === 1, 'gb-map: expected one legend, got ' + legends.length);
        // Tooltip: the key and the value under its title, never the box edges.
        const tip = map.c11.item.tooltip;
        // (Vega formats a tooltip's numbers as text.)
        check(tip && tip.cell === 'c11' && String(tip.Wert) === '5' && !Object.keys(tip).some(k => /__/.test(k)),
            'gb-map: tooltip ' + JSON.stringify(tip));
        // A click on a cell reports its row.
        const got = clickAt('gb-map', map.c11.x, map.c11.y);
        const d = got[0] && got[0].detail;
        check(got.length === 1 && d && d.id === 'gb-map' && d.datum.cell === 'c11' && d.datum.v === 5,
            'gb-map: click on c11 gave ' + JSON.stringify(got.map(e => e.detail && e.detail.datum)));
        // A highlight dims every other cell.
        const bright = r => r.item.opacity == null || r.item.opacity >= 1;
        AoV.highlight('gb-map', {cell: 'c11'});
        for (let i = 0; i < 100 && rects(view).every(bright); i++) await pause();
        check(rects(view).every(r => (r.item.datum.cell === 'c11') === bright(r)),
            'gb-map: highlight of c11 ' + JSON.stringify(rects(view).map(r => [r.item.datum.cell, r.item.opacity])));
        AoV.clearHighlight('gb-map');
        for (let i = 0; i < 100 && !rects(view).every(bright); i++) await pause();
        check(rects(view).every(bright), 'gb-map: cleared highlight left cells dimmed');
        // The CSV rows are the value rows as given, without the looked-up edges.
        const groups = AoV._plotGroups('gb-map') || [];
        check(groups.every(g => g.rows.every(r => !Object.keys(r).some(k => /^__(west|south|east|north)/.test(k)))),
            'gb-map: box edges leaked into the CSV rows');
        check(groups.some(g => g.rows.length === 6 && g.rows.every(r => JSON.stringify(Object.keys(r).sort()) === '["cell","v"]')),
            'gb-map: no CSV group holds the six value rows ' + JSON.stringify(groups.map(g => [g.label, g.rows.length])));

        // Zoom 2×-ish around c11: it stays under the pointer, every cell grows by
        // k, and the cells are cut at the frame only once zoomed.
        check(!clipped(view), 'gb-map: cells cut at rest');
        const rest = byCell(rects(view));
        await wheel('gb-map', rest.c11.x, rest.c11.y, -300);
        const k = view.signal('aov_zoom').k, zoomed = byCell(rects(view));
        check(near(k, Math.pow(1.001, 300), 1e-6), 'gb-map: zoom ' + JSON.stringify(view.signal('aov_zoom')));
        check(near(zoomed.c11.x, rest.c11.x, 0.5) && near(zoomed.c11.y, rest.c11.y, 0.5),
            'gb-map: the cell under the pointer moved');
        check(near(zoomed.c00.right - zoomed.c00.left, k * (rest.c00.right - rest.c00.left), 0.05),
            'gb-map: a cell did not grow with the zoom');
        check(clipped(view), 'gb-map: cells not cut at the frame once zoomed');
        AoV.resetZoom('gb-map');
        view = await ready('gb-map');
        await view.runAsync();
        samePositions(byCell(rects(view)), rest, 'gb-map after reset');

        // ---- A map of cells alone, its boxes from a URL: the same fit (the
        // grid is what the gb-map fit covers), and its own zoom clip.
        view = await ready('gb-url');
        const url = byCell(rects(view));
        inPlace('gb-url', url, '');
        samePositions(url, map, 'gb-url');
        check(view.signal('aov_zoom') && !clipped(view), 'gb-url: no map zoom, or cut at rest');
        await wheel('gb-url', url.c11.x, url.c11.y, -300);
        check(view.signal('aov_zoom').k > 1 && clipped(view), 'gb-url: a cells-only map is not cut at the frame once zoomed');
        AoV.resetZoom('gb-url');

        // ---- Value rows and boxes both from their addresses.
        view = await ready('gb-byurl');
        samePositions(byCell(rects(view)), map, 'gb-byurl');
        check(rects(view).every(r => r.item.fill === map[r.item.datum.cell].item.fill),
            'gb-byurl: fills differ from the inline map');

        // ---- Facets: each panel draws its year's rows in the same places.
        view = await ready('gb-facet');
        const all = rects(view);
        const panels = {};
        all.forEach(r => (panels[r.panel] = panels[r.panel] || []).push(r));
        check(JSON.stringify(Object.keys(panels).sort()) === '["2020","2021"]',
            'gb-facet: panels ' + JSON.stringify(Object.keys(panels)));
        for (const [year, list] of Object.entries(panels)) {
            const cells = byCell(list);
            inPlace('gb-facet', cells, ' ' + year);
            check(list.every(r => r.item.datum.year === year), 'gb-facet ' + year + ": a cell carries another year's row");
            const pts = items(view, it => it.mark.marktype === 'symbol' && it.datum && 'lon' in it.datum).filter(p => p.panel === year);
            check(pts.length === 2, 'gb-facet ' + year + ': expected 2 sites, got ' + pts.length);
        }
        if (panels['2020'] && panels['2021']) {
            const a = byCell(panels['2020']), b = byCell(panels['2021']);
            // c00 holds 1 in 2020 and c21 holds 1 in 2021: one colour scale.
            check(a.c00 && b.c21 && a.c00.item.fill === b.c21.item.fill, 'gb-facet: one value, two colours across panels');
            check(a.c00 && b.c00 && near(a.c00.item.x, b.c00.item.x, 0.01) && near(a.c00.item.y, b.c00.item.y, 0.01),
                'gb-facet: a cell sits elsewhere in the other panel');
        }

        // ---- Frames: one year's cells at a time, in the same places.
        view = await ready('gb-frame');
        let shown = rects(view);
        check(shown.length === 6 && shown.every(r => r.item.datum.year === '2020'),
            'gb-frame: first frame ' + JSON.stringify(shown.map(r => r.item.datum)));
        samePositions(byCell(shown), map, 'gb-frame 2020');
        AoV.setFrame('gb-frame', 1);
        await view.runAsync();
        shown = rects(view);
        check(shown.length === 6 && shown.every(r => r.item.datum.year === '2021'),
            'gb-frame: second frame ' + JSON.stringify(shown.map(r => r.item.datum)));
        samePositions(byCell(shown), map, 'gb-frame 2021');

        // ---- A link group keyed on the cell: hovering a cell announces its
        // key, and a key announced elsewhere (a table row) lights that cell.
        view = await ready('gb-link');
        const linked = byCell(rects(view));
        links.length = 0;
        const c = client('gb-link', linked.c20.x, linked.c20.y);
        const hoverOpts = {bubbles: true, cancelable: true, clientX: c.clientX, clientY: c.clientY,
            pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        c.canvas.dispatchEvent(new PointerEvent('pointermove', hoverOpts));
        c.canvas.dispatchEvent(new MouseEvent('mousemove', hoverOpts));
        for (let i = 0; i < 50 && !links.length; i++) await pause();
        check(links.some(l => l.group === 'cells' && l.key === 'c20'),
            'gb-link: hovering c20 announced ' + JSON.stringify(links.map(l => [l.group, l.key])));
        c.canvas.dispatchEvent(new PointerEvent('pointerout', {bubbles: true, pointerId: 1, pointerType: 'mouse'}));
        c.canvas.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
        document.getElementById('gb-link').dispatchEvent(new PointerEvent('pointerleave', {pointerId: 1, pointerType: 'mouse'}));
        for (let i = 0; i < 100 && !rects(view).every(bright); i++) await pause();
        document.dispatchEvent(new CustomEvent('htmxo:link', {detail: {group: 'cells', key: 'c01', source: null}}));
        for (let i = 0; i < 100 && rects(view).every(bright); i++) await pause();
        check(rects(view).every(r => (r.item.datum.cell === 'c01') === bright(r)),
            'gb-link: announced c01 lit ' + JSON.stringify(rects(view).map(r => [r.item.datum.cell, r.item.opacity])));
        document.dispatchEvent(new CustomEvent('htmxo:link', {detail: {group: 'cells', key: null, source: null}}));
        for (let i = 0; i < 100 && !rects(view).every(bright); i++) await pause();
        check(rects(view).every(bright), 'gb-link: a cleared link left cells dimmed');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-geobox-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
