// Map pan and zoom in the browser (Julia's `_add_map_zoom!`, the runtime's
// `_mapZoom`): a wheel zooms a map around the pointer, a drag pans it, two
// fingers pinch-zoom and pan it while one finger still scrolls the page, and
// every layer moves under the one projection. A reset button shows while the
// map is zoomed or moved; the zoom survives the runtime's re-embeds; marks are
// cut at the frame only once zoomed. Facet cells share the projection, each
// zoomed around the pointer in its own frame. Input is sent as a browser does:
// Vega reads a wheel on the item under the last pointer move.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const near = (a, b, tol) => Math.abs(a - b) <= (tol === undefined ? 0.5 : tol);
    const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms || 10));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    const clicks = [];
    document.addEventListener('aov:click', e => clicks.push(e.detail.id));

    // Scenegraph items matching `pred`, with their centre in view coordinates
    // and the facet cell (group) they are drawn in.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy, cell) {
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, cell, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2});
            }
            const group = item.mark && item.mark.marktype === 'group';
            const gx = group ? dx + (item.x || 0) : dx, gy = group ? dy + (item.y || 0) : dy;
            const inner = group && item.mark.name === 'cell' ? item : cell;
            (item.items || []).forEach(child => walk(child, gx, gy, inner));
        })(view.scenegraph().root, 0, 0, null);
        return out;
    }
    const symbols = view => items(view, it => it.mark.marktype === 'symbol' && it.datum && it.datum.name);
    const shapes = view => items(view, it => it.mark.marktype === 'shape' && it.datum && it.datum.k);
    const byName = (list, name) => list.find(s => s.item.datum.name === name);
    const zoomOf = view => view.signal('aov_zoom');
    const button = id => document.querySelector('#' + id + ' .aov-zoom-reset');
    function client(id, x, y) {
        const view = AoV.views[id], canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        return {canvas, clientX: rect.left + origin[0] + pad.left + x, clientY: rect.top + origin[1] + pad.top + y};
    }
    function move(id, x, y) {
        const c = client(id, x, y);
        const opts = {bubbles: true, cancelable: true, clientX: c.clientX, clientY: c.clientY,
            pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        c.canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        c.canvas.dispatchEvent(new MouseEvent('mousemove', opts));
        return c;
    }
    async function wheel(id, x, y, deltaY) {
        const c = move(id, x, y);
        const ev = new WheelEvent('wheel', {bubbles: true, cancelable: true, clientX: c.clientX, clientY: c.clientY,
            deltaY, deltaMode: 0});
        c.canvas.dispatchEvent(ev);
        // A cancel after dispatch returns comes too late for the browser.
        const cancelled = ev.defaultPrevented;
        await AoV.views[id].runAsync();
        return {ev, cancelled};
    }
    async function drag(id, x, y, dx, dy) {
        const c = move(id, x, y);
        const at = (i, n) => ({bubbles: true, cancelable: true, button: 0, buttons: 1,
            clientX: c.clientX + dx * i / n, clientY: c.clientY + dy * i / n});
        c.canvas.dispatchEvent(new MouseEvent('mousedown', at(0, 1)));
        for (let i = 1; i <= 5; i++) window.dispatchEvent(new MouseEvent('mousemove', at(i, 5)));
        window.dispatchEvent(new MouseEvent('mouseup', at(5, 5)));
        await AoV.views[id].runAsync();
    }
    // Touches at view coordinates; returns the touchmove events so their
    // cancellation can be read.
    async function touches(id, startPts, endPts) {
        const canvas = document.querySelector('#' + id + ' canvas');
        const mk = (pts) => pts.map((p, i) => {
            const c = client(id, p[0], p[1]);
            return new Touch({identifier: i + 1, target: canvas, clientX: c.clientX, clientY: c.clientY});
        });
        const fire = (type, list, changed) => {
            const ev = new TouchEvent(type, {bubbles: true, cancelable: true, composed: true,
                touches: type === 'touchend' ? [] : list, targetTouches: type === 'touchend' ? [] : list,
                changedTouches: changed});
            canvas.dispatchEvent(ev);
            // A cancel after dispatch returns comes too late for the browser.
            return {ev, cancelled: ev.defaultPrevented};
        };
        const start = mk(startPts);
        // Fingers land one by one, as they do.
        for (let i = 0; i < start.length; i++) fire('touchstart', start.slice(0, i + 1), [start[i]]);
        const moves = [];
        for (let s = 1; s <= 4; s++) {
            const pts = startPts.map((p, i) => [p[0] + (endPts[i][0] - p[0]) * s / 4, p[1] + (endPts[i][1] - p[1]) * s / 4]);
            const list = mk(pts);
            moves.push(fire('touchmove', list, list));
        }
        const last = mk(endPts);
        fire('touchend', last, last);
        await AoV.views[id].runAsync();
        return moves;
    }
    // Whether a mark of the view is cut at its frame right now.
    function clipped(view, marktype) {
        let any = false;
        (function walk(item) {
            if (item.mark && item.mark.marktype === marktype && item.mark.clip) any = true;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return any;
    }

    try {
        // ---- A layered map: polygons, two lon/lat points and their labels.
        let view = await ready('mz-map');
        check(JSON.stringify(zoomOf(view)) === JSON.stringify({k: 1, x: 0, y: 0}),
            'map: not at rest after embed: ' + JSON.stringify(zoomOf(view)));
        check(button('mz-map') && button('mz-map').hidden, 'map: no hidden reset button at rest');
        check(!clipped(view, 'shape') && !clipped(view, 'symbol'), 'map: marks are cut at rest');
        let a = byName(symbols(view), 'A'), b = byName(symbols(view), 'B');
        check(a && b, 'map: points A and B not found');
        const rest = {ax: a.x, ay: a.y, bx: b.x, by: b.y};

        // Wheel over A: A stays put, B moves away from it by the zoom factor,
        // and the polygons move with them.
        const shape0 = shapes(view).find(s => s.item.datum.k === 'c0_0');
        let ev = await wheel('mz-map', a.x, a.y, -300);
        let z = zoomOf(view);
        check(near(z.k, Math.pow(1.001, 300), 1e-6), 'map: wheel zoom ' + JSON.stringify(z));
        check(ev.cancelled, 'map: the wheel also scrolled the page');
        a = byName(symbols(view), 'A'); b = byName(symbols(view), 'B');
        check(near(a.x, rest.ax) && near(a.y, rest.ay), 'map: the point under the pointer moved ' +
            JSON.stringify([rest.ax, rest.ay, a.x, a.y]));
        check(near(b.x - a.x, z.k * (rest.bx - rest.ax), 1) && near(b.y - a.y, z.k * (rest.by - rest.ay), 1),
            'map: B is not k times as far from A');
        const shape1 = shapes(view).find(s => s.item.datum.k === 'c0_0');
        check(near(shape1.x - a.x, z.k * (shape0.x - rest.ax), 1.5), 'map: the polygons did not zoom with the points');
        check(button('mz-map') && !button('mz-map').hidden, 'map: reset button hidden while zoomed');
        check(clipped(view, 'shape') && clipped(view, 'symbol') && clipped(view, 'text'),
            'map: marks not cut at the frame once zoomed');
        check(clicks.length === 0, 'map: a wheel sent aov:click');

        // A drag pans by exactly the pointer's movement.
        const before = {x: a.x, y: a.y};
        await drag('mz-map', a.x + 20, a.y + 10, 30, -20);
        a = byName(symbols(view), 'A');
        check(near(a.x - before.x, 30) && near(a.y - before.y, -20), 'map: drag moved A by ' +
            JSON.stringify([a.x - before.x, a.y - before.y]));
        check(near(zoomOf(view).k, z.k, 1e-9), 'map: a drag changed the zoom');
        // After the button is up, moving the mouse pans nothing.
        move('mz-map', a.x + 60, a.y + 60);
        window.dispatchEvent(new MouseEvent('mousemove', {clientX: 5, clientY: 5}));
        await view.runAsync();
        const afterUp = byName(symbols(view), 'A');
        check(near(afterUp.x, a.x) && near(afterUp.y, a.y), 'map: a mouse move after the drag still panned');

        // A re-embed (as a theme change or resize runs it) keeps the zoom:
        // the new view starts where the old one was, with the button shown.
        const kept = zoomOf(view);
        AoV._reembeds['mz-map']();
        view = await ready('mz-map', view);
        check(JSON.stringify(zoomOf(view)) === JSON.stringify(kept), 'map: re-embed lost the zoom: ' +
            JSON.stringify([kept, zoomOf(view)]));
        a = byName(symbols(view), 'A');
        check(near(a.x, afterUp.x) && near(a.y, afterUp.y), 'map: re-embed moved A');
        check(button('mz-map') && !button('mz-map').hidden, 'map: reset button hidden after re-embed while zoomed');
        check(document.querySelectorAll('#mz-map .aov-zoom-reset').length === 1, 'map: re-embed left two reset buttons');

        // The button brings back the fitted view, and hides.
        button('mz-map').click();
        await view.runAsync();
        a = byName(symbols(view), 'A'); b = byName(symbols(view), 'B');
        check(JSON.stringify(zoomOf(view)) === JSON.stringify({k: 1, x: 0, y: 0}), 'map: reset left ' + JSON.stringify(zoomOf(view)));
        check(near(a.x, rest.ax) && near(a.y, rest.ay) && near(b.x, rest.bx) && near(b.y, rest.by), 'map: reset is not the fitted view');
        check(button('mz-map').hidden, 'map: reset button still shown at rest');
        check(!clipped(view, 'shape') && !clipped(view, 'text'), 'map: marks still cut after the reset');
        check(clicks.length === 0, 'map: the reset button sent aov:click');

        // Two fingers: spreading them from 40 px to 80 px apart around A
        // doubles the zoom and keeps A under their midpoint; the page's own
        // pinch zoom is held off (the moves are cancelled).
        let moves = await touches('mz-map', [[a.x - 20, a.y], [a.x + 20, a.y]], [[a.x - 40, a.y], [a.x + 40, a.y]]);
        z = zoomOf(view);
        check(near(z.k, 2, 1e-6), 'map: pinch zoom ' + JSON.stringify(z));
        check(moves.every(m => m.cancelled), 'map: a two-finger move also zoomed the page');
        let a2 = byName(symbols(view), 'A');
        check(near(a2.x, rest.ax) && near(a2.y, rest.ay), 'map: pinch moved the point under the midpoint');
        // Moving both fingers pans with them.
        moves = await touches('mz-map', [[a.x - 30, a.y], [a.x + 30, a.y]], [[a.x - 10, a.y + 25], [a.x + 50, a.y + 25]]);
        a2 = byName(symbols(view), 'A');
        check(near(zoomOf(view).k, 2, 1e-6) && near(a2.x - rest.ax, 20) && near(a2.y - rest.ay, 25),
            'map: two-finger pan ' + JSON.stringify([zoomOf(view), a2.x - rest.ax, a2.y - rest.ay]));
        // One finger leaves the map alone and the page free to scroll.
        const one = zoomOf(view);
        moves = await touches('mz-map', [[a.x, a.y]], [[a.x, a.y + 60]]);
        check(JSON.stringify(zoomOf(view)) === JSON.stringify(one), 'map: one finger changed the zoom');
        check(moves.every(m => !m.cancelled && !m.ev.defaultPrevented), 'map: a one-finger move was cancelled (page cannot scroll)');
        await AoV.resetZoom('mz-map');
        check(button('mz-map').hidden && JSON.stringify(zoomOf(view)) === JSON.stringify({k: 1, x: 0, y: 0}),
            'map: AoV.resetZoom did not bring back the fitted view');

        // A plain click on a polygon is still the region's aov:click.
        const cell = shapes(view).find(s => s.item.datum.k === 'c2_2');
        const cc = move('mz-map', cell.x, cell.y);
        const copts = {bubbles: true, cancelable: true, clientX: cc.clientX, clientY: cc.clientY, pointerId: 1,
            isPrimary: true, pointerType: 'mouse'};
        cc.canvas.dispatchEvent(new PointerEvent('pointerdown', copts));
        cc.canvas.dispatchEvent(new PointerEvent('pointerup', copts));
        cc.canvas.dispatchEvent(new MouseEvent('click', copts));
        check(clicks.length === 1 && clicks[0] === 'mz-map', 'map: a click on a region sent ' + JSON.stringify(clicks));

        // ---- A faceted map: the cells share the projection, and a wheel
        // zooms around the pointer in the cell it is over, also over a part
        // of the cell no polygon covers.
        view = await ready('mz-facet');
        const cells = shapes(view);
        const right = cells.filter(s => s.cell && s.cell.x > 0);
        check(right.length > 0, 'facet: no polygons in a second cell');
        const target = right.find(s => s.item.datum.k === 'c1_1'), other = right.find(s => s.item.datum.k === 'c4_4');
        const left = cells.find(s => s.cell && s.cell.x === 0 && s.item.datum.k === 'c1_1');
        await wheel('mz-facet', target.x, target.y, -400);
        z = zoomOf(view);
        const t2 = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c1_1');
        const o2 = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c4_4');
        const l2 = shapes(view).find(s => s.cell && s.cell.x === 0 && s.item.datum.k === 'c1_1');
        check(z.k > 1.4, 'facet: wheel did not zoom ' + JSON.stringify(z));
        check(near(t2.x, target.x, 1) && near(t2.y, target.y, 1), 'facet: the polygon under the pointer moved ' +
            JSON.stringify([target.x, target.y, t2.x, t2.y]));
        check(near(o2.x - t2.x, z.k * (other.x - target.x), 2), 'facet: the second cell did not zoom around the pointer');
        check(near(l2.x - left.x, t2.x - target.x, 1) && near(l2.y - left.y, t2.y - target.y, 1),
            'facet: the cells did not zoom alike');
        check(clipped(view, 'shape'), 'facet: polygons not cut at the cell frame once zoomed');
        // Over empty space of the second cell (its lower right corner).
        await AoV.resetZoom('mz-facet');
        const cellItem = target.cell, cw = cellItem.width, ch = cellItem.height;
        const ex = cellItem.x + cw - 3, ey = cellItem.y + ch - 3;
        const hit = shapes(view).some(s => s.cell === cellItem && Math.abs(s.x - ex) < 8 && Math.abs(s.y - ey) < 8);
        check(!hit, 'facet: the probe corner is not empty');
        const shapeNear = shapes(view).filter(s => s.cell === cellItem);
        const ref = shapeNear[0], refPos = {x: ref.x, y: ref.y};
        await wheel('mz-facet', ex, ey, -400);
        z = zoomOf(view);
        const ref2 = shapes(view).find(s => s.cell === cellItem && s.item.datum.k === ref.item.datum.k);
        // The corner is the zoom's centre, so the polygon moves away from it by k.
        check(near(ref2.x - ex, z.k * (refPos.x - ex), 2) && near(ref2.y - ey, z.k * (refPos.y - ey), 2),
            'facet: zoom over empty cell space was not centred on the pointer ' +
            JSON.stringify({z, ref: refPos, ref2: {x: ref2.x, y: ref2.y}, ex, ey}));

        // Two fingers over the second cell zoom around their midpoint there.
        await AoV.resetZoom('mz-facet');
        const tgt = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c1_1');
        const oth = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c4_4');
        moves = await touches('mz-facet', [[tgt.x - 15, tgt.y], [tgt.x + 15, tgt.y]], [[tgt.x - 30, tgt.y], [tgt.x + 30, tgt.y]]);
        z = zoomOf(view);
        const tgt2 = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c1_1');
        const oth2 = shapes(view).find(s => s.cell === target.cell && s.item.datum.k === 'c4_4');
        check(near(z.k, 2, 1e-6) && near(tgt2.x, tgt.x, 1) && near(tgt2.y, tgt.y, 1) &&
            near(oth2.x - tgt2.x, 2 * (oth.x - tgt.x), 2), 'facet: pinch in the second cell ' +
            JSON.stringify({z, tgt: [tgt.x, tgt.y], tgt2: [tgt2.x, tgt2.y]}));

        // ---- A map whose layers author `clip=true` (a framed map) stays cut
        // at its frame at rest too.
        view = await ready('mz-clip');
        check(clipped(view, 'shape'), 'authored clip: a framed map is uncut at rest');
        await wheel('mz-clip', 40, 40, -200);
        check(clipped(view, 'shape') && zoomOf(view).k > 1, 'authored clip: not cut while zoomed');

        // ---- Texts: a figure carrying German texts names its button so.
        view = await ready('mz-de');
        const w = await wheel('mz-de', 50, 30, -200);
        check(w.cancelled, 'texts: wheel not cancelled');
        check(button('mz-de') && button('mz-de').textContent === 'Zoom zurücksetzen' && !button('mz-de').hidden,
            'texts: German reset button ' + (button('mz-de') && button('mz-de').textContent));
        // Its colours are the page's, never a theme's primary blue.
        const bs = getComputedStyle(button('mz-de'));
        check(bs.backgroundColor === 'rgb(255, 255, 255)' && bs.color === 'rgb(0, 0, 0)',
            'texts: reset button colours ' + bs.backgroundColor + ' / ' + bs.color);

        // ---- Dispose leaves no reset button behind.
        AoV.dispose('mz-de');
        check(!document.querySelector('#mz-de .aov-zoom-reset'), 'dispose: the reset button stayed');

        // ---- An x/y plot keeps its own pan/zoom and gets no map zoom.
        view = await ready('mz-xy');
        check(!view.getState().signals.hasOwnProperty('aov_zoom'), 'x/y plot: has a map zoom');
        check(!button('mz-xy'), 'x/y plot: has a reset button');
    } catch (err) {
        failures.push('driver error: ' + (err && err.stack || err));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-map-zoom-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
