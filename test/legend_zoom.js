// config(legend_zoom=true) browser checks (todo `0b9v7xy`): selecting colour
// legend entries zooms each panel's x and y axes to the selected entries'
// marks, with a 5 % margin; the uncoloured identity line does not hold the
// range and is cut at the frame; shift-click adds entries; a click on blank
// plot space brings back the full view, as does a double-click reset; the
// reader's own zoom is replaced by a new selection; a panel without selected
// marks keeps its range; shared scales take the extent over every panel; the
// picker's colour remap and an in-place data update keep working; a figure
// without the setting only dims. A click inside the plot area clears only on
// blank space, on facet panels and tooltip scatters too, and leaves a
// selection of several entries whole otherwise (snag
// `legend-zoom-blan-90471a09`).
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const near = (a, b, tol = 1e-6) => Math.abs(a - b) <= tol * Math.max(1, Math.abs(b));
    const nearDomain = (d, want) => d.length === 2 && near(+d[0], want[0]) && near(+d[1], want[1]);
    const show = d => JSON.stringify(d.map(v => Math.round(+v * 1000) / 1000));
    async function ready(id, previous) {
        for (let i = 0; i < 400; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    async function settle(view) {
        for (let i = 0; i < 3; i++) { await pause(); await view.runAsync(); }
    }
    async function click(id, label, shift = false) {
        const view = AoV.views[id];
        const node = [...document.getElementById(id).querySelectorAll('.role-legend-label text')]
            .find(n => n.textContent === label);
        check(!!node, id + ': missing legend label ' + label);
        if (!node) return;
        node.dispatchEvent(new MouseEvent('click', {bubbles: true, shiftKey: shift}));
        await settle(view);
    }
    // A click on blank plot space, as a reader clears the selection: each
    // click is a press and a release in place.
    async function clear(id, events = ['click']) {
        const view = AoV.views[id];
        const svg = document.getElementById(id).querySelector('svg');
        const opts = {bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        for (const type of events) {
            if (type === 'click') {
                svg.dispatchEvent(new PointerEvent('pointerdown', opts));
                svg.dispatchEvent(new PointerEvent('pointerup', opts));
            }
            svg.dispatchEvent(new MouseEvent(type, opts));
        }
        await settle(view);
    }
    // A pan on a canvas plot: a press at `from`, the pointer moving to `to`
    // and the release there (view coordinates), as `mark_click.js` drags;
    // Vega follows the release with a click.
    async function drag(id, from, to) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const at = (p, buttons) => ({bubbles: true, cancelable: true, buttons, pointerId: 1, isPrimary: true,
            pointerType: 'mouse', clientX: rect.left + origin[0] + pad.left + p.x, clientY: rect.top + origin[1] + pad.top + p.y});
        canvas.dispatchEvent(new PointerEvent('pointermove', at(from, 0)));
        canvas.dispatchEvent(new PointerEvent('pointerdown', at(from, 1)));
        for (let i = 1; i <= 8; i++) {
            canvas.dispatchEvent(new PointerEvent('pointermove',
                at({x: from.x + (to.x - from.x) * i / 8, y: from.y + (to.y - from.y) * i / 8}, 1)));
            await view.runAsync();
        }
        canvas.dispatchEvent(new PointerEvent('pointerup', at(to, 0)));
        canvas.dispatchEvent(new MouseEvent('click', at(to, 0)));
        await settle(view);
    }
    // On a canvas plot: the page position of a scenegraph item's bounds, and
    // a press and release in place at view coordinates (x, y), as a reader
    // clicks (`mark_click.js` clickAt). `hits[id]` records what Vega picked.
    const hits = {};
    function viewBounds(item) {
        let x = 0, y = 0, g = item.mark && item.mark.group;
        while (g) { x += g.x || 0; y += g.y || 0; g = g.mark && g.mark.group; }
        return {x1: item.bounds.x1 + x, y1: item.bounds.y1 + y, x2: item.bounds.x2 + x, y2: item.bounds.y2 + y};
    }
    function sceneItems(view, pred) {
        const out = [];
        (function walk(item) { if (pred(item)) out.push(item); (item.items || []).forEach(walk); })(view.scenegraph().root);
        return out;
    }
    async function clickAt(id, x, y, shift = false) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, shiftKey: shift, pointerId: 1, isPrimary: true, pointerType: 'mouse',
            clientX: rect.left + origin[0] + pad.left + x, clientY: rect.top + origin[1] + pad.top + y};
        hits[id] = undefined;
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new PointerEvent('pointerdown', Object.assign({}, opts, {buttons: 1})));
        canvas.dispatchEvent(new PointerEvent('pointerup', opts));
        canvas.dispatchEvent(new MouseEvent('click', opts));
        await settle(view);
    }
    async function canvasLegend(id, label, shift = false) {
        const view = AoV.views[id];
        const item = sceneItems(view, i => i.mark && i.mark.role === 'legend-label' && i.text === label)[0];
        check(!!item, id + ': missing legend label ' + label);
        if (!item) return;
        const b = viewBounds(item);
        await clickAt(id, (b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2, shift);
    }
    const selected = view => [...new Set(view.data('legend_selection_store').map(t => t.values[0]))].sort();
    const domain = (view, ch) => view.scale(ch).domain();
    const zoomValue = view => view.signal('aov_legend_zoom');
    // Every drawn point with its group, its panel and its position inside
    // that panel's frame.
    function points(view) {
        const out = [];
        (function walk(item) {
            if (item.mark && item.mark.marktype === 'symbol' && item.datum && item.datum.g !== undefined &&
                /layer_0_marks$/.test(item.mark.name || '')) {
                const cell = item.mark.group;
                out.push({g: item.datum.g, h: item.datum.h, panel: cell && cell.datum ? cell.datum.kind : undefined,
                    x: item.x, y: item.y, w: cell ? cell.width : view.width(), hgt: cell ? cell.height : view.height()});
            }
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    // The identity line's marks: whether each is cut at the frame now.
    function lineClips(view) {
        const out = [];
        (function walk(item) {
            if (item.marktype === 'line' && /layer_1_marks$/.test(item.name || '')) out.push(item.clip === true);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    // The selected points of each panel fill its frame up to the 5 % margin
    // (on a span of 1.1) along both axes.
    const EDGE = 0.05 / 1.1;
    function fills(id, pts, label) {
        const byPanel = {};
        pts.forEach(p => { (byPanel[p.panel] = byPanel[p.panel] || []).push(p); });
        Object.keys(byPanel).forEach(panel => {
            const ps = byPanel[panel], w = ps[0].w, h = ps[0].hgt;
            const xs = ps.map(p => p.x), ys = ps.map(p => p.y);
            const ok = near(Math.min(...xs), w * EDGE, 1.5 / w) && near(Math.max(...xs), w * (1 - EDGE), 1.5 / w) &&
                near(Math.min(...ys), h * EDGE, 1.5 / h) && near(Math.max(...ys), h * (1 - EDGE), 1.5 / h);
            check(ok, id + ' ' + label + ' panel ' + panel + ': selected marks do not fill the frame: x ' +
                show([Math.min(...xs), Math.max(...xs)]) + ' of ' + w + ', y ' + show([Math.min(...ys), Math.max(...ys)]) + ' of ' + h);
        });
    }

    try {
        const views = {};
        for (const id of ['lz-plain', 'lz-canvas', 'lz-off', 'lz-limits', 'lz-facet', 'lz-shared', 'lz-picker', 'lz-caption',
            'lz-facet-canvas', 'lz-scatter-canvas', 'lz-off-facet-canvas'])
            views[id] = await ready(id);

        // --- One view: zoom, add, add the outlier's group, clear. ---
        let id = 'lz-plain', view = views[id];
        const fullX = domain(view, 'x').slice(), fullY = domain(view, 'y').slice();
        check(+fullY[1] >= 60, id + ': the outlier is outside the initial y domain ' + show(fullY));
        check(zoomValue(view) === null, id + ': zoomed before any selection');
        check(lineClips(view).every(c => !c), id + ': the identity line is cut before any zoom');
        await click(id, 'A');
        check(nearDomain(domain(view, 'y'), [0.8, 5.2]), id + ' A: y domain ' + show(domain(view, 'y')) + ', expected [0.8, 5.2]');
        check(nearDomain(domain(view, 'x'), [0.8, 5.2]), id + ' A: x domain ' + show(domain(view, 'x')) + ', expected [0.8, 5.2]');
        fills(id, points(view).filter(p => p.g === 'A'), 'A');
        check(points(view).some(p => p.g === 'B' && p.y < 0), id + ' A: the outlier is not above the frame');
        check(lineClips(view).length && lineClips(view).every(c => c), id + ' A: the identity line is not cut at the frame');
        // The selection still dims the other groups.
        check(view.data('legend_selection_store').length === 1, id + ' A: selection store');
        await click(id, 'C', true);
        check(nearDomain(domain(view, 'y'), [0.7, 7.3]), id + ' A+C: y domain ' + show(domain(view, 'y')) + ', expected [0.7, 7.3]');
        check(nearDomain(domain(view, 'x'), [0.8, 5.2]), id + ' A+C: x domain ' + show(domain(view, 'x')));
        await click(id, 'B', true);
        check(nearDomain(domain(view, 'y'), [1 - 2.95, 60 + 2.95]), id + ' A+B+C: y domain ' + show(domain(view, 'y')) + ', expected the outlier inside');
        await clear(id);
        check(view.data('legend_selection_store').length === 0, id + ' clear: the selection stayed');
        check(zoomValue(view) === null, id + ' clear: still zoomed');
        check(nearDomain(domain(view, 'y'), fullY.map(Number)) && nearDomain(domain(view, 'x'), fullX.map(Number)),
            id + ' clear: domains ' + show(domain(view, 'x')) + ' ' + show(domain(view, 'y')) + ' are not the full ' + show(fullX) + ' ' + show(fullY));
        check(lineClips(view).every(c => !c), id + ' clear: the identity line is still cut');

        // A new selection replaces the reader's own zoom; a wheel zoom after
        // it starts from the zoomed view; a double-click resets everything.
        view.signal('grid_x', [2, 3]).signal('grid_y', [2, 3]);
        await settle(view);
        check(nearDomain(domain(view, 'x'), [2, 3]), id + ' reader zoom: x domain ' + show(domain(view, 'x')));
        await click(id, 'A');
        check(nearDomain(domain(view, 'x'), [0.8, 5.2]) && nearDomain(domain(view, 'y'), [0.8, 5.2]),
            id + ' A after a reader zoom: domains ' + show(domain(view, 'x')) + ' ' + show(domain(view, 'y')));
        check(view.signal('grid_x') == null && view.signal('grid_y') == null, id + ' A after a reader zoom: the reader zoom stayed');
        view.signal('grid_x', [1, 2]).signal('grid_y', [1, 2]);
        await settle(view);
        check(nearDomain(domain(view, 'y'), [1, 2]), id + ' a reader zoom while legend-zoomed wins: ' + show(domain(view, 'y')));
        await clear(id, ['click', 'click', 'dblclick']);
        check(zoomValue(view) === null && nearDomain(domain(view, 'y'), fullY.map(Number)) && nearDomain(domain(view, 'x'), fullX.map(Number)),
            id + ' double-click: domains ' + show(domain(view, 'x')) + ' ' + show(domain(view, 'y')) + ' are not the full view');

        // An in-place data update re-fits an active zoom to the new rows.
        await click(id, 'A');
        const before = view;
        const next = JSON.parse(JSON.stringify(AoV._origSpecs[id]));
        (function walk(node) {
            if (!node || typeof node !== 'object') return;
            if (node.data && node.data.values) {
                node.data.values = AoV._rowsFromColumns(node.data.values).map(r =>
                    r.g === 'A' ? Object.assign({}, r, {y: r.y * 2}) : r);
            }
            ['layer', 'hconcat', 'vconcat', 'concat'].forEach(k => (node[k] || []).forEach(walk));
            if (node.spec) walk(node.spec);
        })(next);
        AoV.updateSpec(id, next);
        await settle(view);
        await settle(view);
        check(AoV.views[id] === before, id + ' update: the view was replaced (the selection would be lost)');
        check(nearDomain(domain(view, 'y'), [1.6, 10.4]), id + ' update: y domain ' + show(domain(view, 'y')) + ', expected [1.6, 10.4]');
        await clear(id);

        // --- A pan while legend-zoomed moves the zoomed view, and the click
        // Vega sends with the release keeps the selection. ---
        id = 'lz-canvas'; view = views[id];
        view.signal('legend_selection_g_legend', 'A');
        await settle(view);
        check(view.data('legend_selection_store').length === 1 && nearDomain(domain(view, 'x'), [0.8, 5.2]),
            id + ' A: x domain ' + show(domain(view, 'x')));
        await drag(id, {x: 6, y: 6}, {x: 46, y: 36});
        const panned = domain(view, 'x').slice();
        check(view.data('legend_selection_store').length === 1, id + ' pan: the selection was cleared');
        check(!nearDomain(panned, [0.8, 5.2]) && near(panned[1] - panned[0], 4.4, 1e-3),
            id + ' pan: x domain ' + show(panned) + ' did not move by the drag, at the zoomed span 4.4');

        // --- A click inside the plot area (snag `legend-zoom-blan-90471a09`):
        // Vega-Lite took a click on a facet panel (a group with a datum) or on
        // a tooltip scatter's nearest-point overlay for a click on a mark and
        // set the selection to the last clicked entry again: nothing cleared,
        // and A + B shrank to B. Now blank space clears, and a click on a
        // point, a pan or Shift with a click leave A + B whole. ---
        for (id of ['lz-facet-canvas', 'lz-scatter-canvas', 'lz-off-facet-canvas']) {
            view = views[id];
            const zoomed = id !== 'lz-off-facet-canvas', overlay = id === 'lz-scatter-canvas';
            view.addEventListener('click', (event, item) => { hits[id] = item || null; });
            const symbols = () => sceneItems(view, i => i.mark && i.mark.marktype === 'symbol' && i.mark.role === 'mark' &&
                i.datum && i.datum.g !== undefined);
            const at = () => symbols().map(i => [i.x, i.y].map(Math.round).join(',')).join(' ');
            const start = at();
            // The first panel's frame in view coordinates, and the spot in it
            // farthest from every point.
            const cell = sceneItems(view, i => i.mark && i.mark.marktype === 'group' && i.mark.name === 'cell')[0];
            check(overlay === !cell, id + ': ' + (cell ? 'a facet cell' : 'no facet cell'));
            let fx = 0, fy = 0, fw = view.width(), fh = view.height();
            if (cell) {
                // The cell's own origin, not its bounds: those take in its axes.
                let g = cell.mark.group;
                fx = cell.x; fy = cell.y; fw = cell.width; fh = cell.height;
                while (g) { fx += g.x || 0; fy += g.y || 0; g = g.mark && g.mark.group; }
            }
            // In the view as it is drawn now: the points move with a zoom.
            function blankSpot(label) {
                let best = null;
                const pts = symbols().map(viewBounds);
                for (let u = 0.05; u < 0.96; u += 0.05) for (let v = 0.05; v < 0.96; v += 0.05) {
                    const x = fx + fw * u, y = fy + fh * v;
                    const d = Math.min(...pts.map(b => Math.hypot(Math.min(Math.max(x, b.x1), b.x2) - x, Math.min(Math.max(y, b.y1), b.y2) - y)));
                    if (!best || d > best.d) best = {x, y, d};
                }
                check(best.d > 8, id + ' ' + label + ': no blank spot in the plot area');
                return best;
            }
            const pick = () => hits[id] ? (hits[id].isVoronoi ? 'overlay' : hits[id].mark.marktype + ':' + hits[id].mark.role) : 'nothing';
            async function selectAB(label) {
                await canvasLegend(id, 'A');
                await canvasLegend(id, 'B', true);
                check(JSON.stringify(selected(view)) === '["A","B"]', id + ' ' + label + ': A + B selected ' + JSON.stringify(selected(view)));
            }
            await selectAB('blank');
            check(!zoomed || zoomValue(view) !== null, id + ': A + B did not zoom');
            let blank = blankSpot('blank click');
            await clickAt(id, blank.x, blank.y);
            check(pick() === (overlay ? 'overlay' : 'group:scope'), id + ' blank click picked ' + pick());
            check(selected(view).length === 0, id + ' blank click: the selection stayed ' + JSON.stringify(selected(view)));
            check(!zoomed || zoomValue(view) === null, id + ' blank click: still zoomed');
            check(at() === start, id + ' blank click: the points did not return to the full view');
            // A click on an unselected C point's own shape.
            await selectAB('point');
            const zoom = JSON.stringify(zoomed ? zoomValue(view) : null);
            const c = symbols().find(i => i.datum.g === 'C');
            const cb = viewBounds(c);
            await clickAt(id, (cb.x1 + cb.x2) / 2, (cb.y1 + cb.y2) / 2);
            check(pick() === (overlay ? 'overlay' : 'symbol:mark'), id + ' point click picked ' + pick());
            check(JSON.stringify(selected(view)) === '["A","B"]', id + ' point click: the selection became ' + JSON.stringify(selected(view)));
            check(JSON.stringify(zoomed ? zoomValue(view) : null) === zoom, id + ' point click: the zoom changed');
            // Shift with a click on blank space, then a pan from blank space.
            blank = blankSpot('shift-click');
            await clickAt(id, blank.x, blank.y, true);
            check(JSON.stringify(selected(view)) === '["A","B"]', id + ' shift-click on blank space: the selection became ' + JSON.stringify(selected(view)));
            await drag(id, {x: blank.x, y: blank.y}, {x: blank.x + 30, y: blank.y + 12});
            check(JSON.stringify(selected(view)) === '["A","B"]', id + ' pan: the selection became ' + JSON.stringify(selected(view)));
            blank = blankSpot('blank click after a pan');
            await clickAt(id, blank.x, blank.y);
            check(selected(view).length === 0, id + ' blank click after a pan: the selection stayed ' + JSON.stringify(selected(view)));
        }

        // --- Without the setting a selection only dims. ---
        id = 'lz-off'; view = views[id];
        const offY = domain(view, 'y').slice();
        await click(id, 'A');
        check(view.data('legend_selection_store').length === 1, id + ': selection store');
        check(nearDomain(domain(view, 'y'), offY.map(Number)), id + ': the y domain changed without legend_zoom ' + show(domain(view, 'y')));
        let threw = false;
        try { view.signal('aov_legend_zoom'); } catch (e) { threw = true; }
        check(threw, id + ': the zoom signal is defined without legend_zoom');
        check(points(view).filter(p => p.g === 'B').every(p => p.y >= 0), id + ': the outlier left the frame');

        // --- An authored domain (axis limits) is kept; the other axis zooms. ---
        id = 'lz-limits'; view = views[id];
        check(nearDomain(domain(view, 'y'), [-5, 70]), id + ': authored y domain ' + show(domain(view, 'y')));
        await click(id, 'A');
        check(nearDomain(domain(view, 'y'), [-5, 70]), id + ' A: the authored y domain changed ' + show(domain(view, 'y')));
        check(nearDomain(domain(view, 'x'), [0.8, 5.2]), id + ' A: x domain ' + show(domain(view, 'x')));
        await clear(id);

        // --- Faceted, independent scales: each panel zooms to its own marks. ---
        for (id of ['lz-facet', 'lz-caption']) {
            view = views[id];
            const start = points(view);
            await click(id, 'A');
            const pts = points(view);
            const panels = new Set(pts.filter(p => p.g === 'A').map(p => p.panel));
            check(panels.size === 2, id + ' A: panels ' + JSON.stringify([...panels]));
            fills(id, pts.filter(p => p.g === 'A'), 'A');
            check(pts.some(p => p.g === 'B' && p.panel === 'P' && p.y < 0), id + ' A: the outlier is not above panel P');
            check(lineClips(view).length && lineClips(view).every(c => c), id + ' A: the identity line is not cut at the frame');
            const z = zoomValue(view);
            check(z && Object.keys(z).some(k => /\|P$/.test(k)) && Object.keys(z).some(k => /\|Q$/.test(k)),
                id + ' A: zoom keys ' + JSON.stringify(z && Object.keys(z)));
            // C is drawn in panel P only: Q keeps its full range.
            await click(id, 'C');
            const c = points(view);
            fills(id, c.filter(p => p.g === 'C'), 'C');
            const qNow = c.filter(p => p.panel === 'Q'), qStart = start.filter(p => p.panel === 'Q');
            check(qNow.length && qNow.every((p, i) => Math.abs(p.x - qStart[i].x) < 0.5 && Math.abs(p.y - qStart[i].y) < 0.5),
                id + ' C: panel Q, which has no C, did not keep its full range');
            await clear(id);
            const back = points(view);
            check(back.every((p, i) => Math.abs(p.x - start[i].x) < 0.5 && Math.abs(p.y - start[i].y) < 0.5),
                id + ' clear: the panels did not return to their full range');
        }

        // --- The saved "⬇ HTML" card zooms too: the runtime it carries does it.
        let saved = null;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = function (page) { saved = page; };
        try { await AoV.downloadPlotHtml('lz-caption', 'lz-caption'); } finally { AoV._triggerDownload = trigger; }
        check(!!saved, 'lz-caption: nothing saved');
        if (saved) {
            const frame = document.createElement('iframe');
            frame.style.width = '900px'; frame.style.height = '600px';
            frame.srcdoc = saved;
            document.body.append(frame);
            let inner = null;
            for (let i = 0; i < 400 && !inner; i++) {
                await pause();
                const w = frame.contentWindow;
                inner = w && w.AoV && w.AoV.views && w.AoV.views['lz-caption'] && !w.AoV._inFlight['lz-caption'] ?
                    w.AoV.views['lz-caption'] : null;
            }
            check(!!inner, 'saved card: the plot did not embed');
            if (inner) {
                inner.signal('legend_selection_g_legend', 'A');
                await settle(inner);
                const z = inner.signal('aov_legend_zoom');
                check(z && Object.keys(z).some(k => /\|P$/.test(k)) && Object.keys(z).some(k => /\|Q$/.test(k)),
                    'saved card A: zoom keys ' + JSON.stringify(z && Object.keys(z)));
                fills('saved card', points(inner).filter(p => p.g === 'A'), 'A');
            }
            frame.remove();
        }

        // --- Faceted, shared scales: every panel takes the shared extent. ---
        id = 'lz-shared'; view = views[id];
        await click(id, 'A');
        // A spans x 1..50 and y 1..50 over both panels (Q is scaled by 10).
        check(nearDomain(domain(view, 'y'), [1 - 2.45, 50 + 2.45]), id + ' A: shared y domain ' + show(domain(view, 'y')));
        check(nearDomain(domain(view, 'x'), [1 - 2.45, 50 + 2.45]), id + ' A: shared x domain ' + show(domain(view, 'x')));
        await clear(id);

        // --- The picker: the zoom follows the colour it moves in. ---
        id = 'lz-picker';
        const old = views[id];
        AoV.remapEncoding(id, {color: 'h'});
        view = views[id] = await ready(id, old);
        await click(id, 'u');
        // u is every odd x (1, 3, 5) of every group, the outlier (x 3, y 60) too.
        check(nearDomain(domain(view, 'x'), [0.8, 5.2]), id + ' u: x domain ' + show(domain(view, 'x')));
        check(nearDomain(domain(view, 'y'), [1 - 2.95, 60 + 2.95]), id + ' u: y domain ' + show(domain(view, 'y')));
        await click(id, 'v');
        // v is x 2 and 4: y from 2 (A) to 4 + 2 (C).
        check(nearDomain(domain(view, 'x'), [1.9, 4.1]) && nearDomain(domain(view, 'y'), [1.8, 6.2]),
            id + ' v: domains ' + show(domain(view, 'x')) + ' ' + show(domain(view, 'y')));
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-legend-zoom-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
