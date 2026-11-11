// Tooltip label browser checks (snag `hover-a-cell-of-a723ea83`): hovering a
// heatmap cell of the reporter's figure shows a tooltip whose rows are named
// by the mapping labels, read from the page the way the reporter read it
// (`#vg-tooltip-element td, th`), and so does a station point beside the cells;
// every drawn cell carries those names; and the picker's colour remap names the
// new colour row by its picker label.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // Scenegraph items matching `pred`, with their centre in view coordinates
    // (as test/pointer_through.js finds them).
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2});
            }
            const gx = item.mark && item.mark.marktype === 'group' ? dx + (item.x || 0) : dx;
            const gy = item.mark && item.mark.marktype === 'group' ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy));
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const surface = id => document.querySelector('#' + id + ' canvas, #' + id + ' svg');
    function hoverAt(id, at) {
        const view = AoV.views[id], rect = surface(id).getBoundingClientRect();
        const origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: 'mouse',
            clientX: rect.left + origin[0] + pad.left + at.x, clientY: rect.top + origin[1] + pad.top + at.y};
        surface(id).dispatchEvent(new PointerEvent('pointermove', opts));
        surface(id).dispatchEvent(new MouseEvent('mousemove', opts));
    }
    function leave(id) {
        const opts = {bubbles: true, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        surface(id).dispatchEvent(new PointerEvent('pointerout', opts));
        surface(id).dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
    }
    // The shown tooltip's cells, read as the reporter read them, once it shows.
    async function shownCells() {
        for (let i = 0; i < 50; i++) {
            const el = document.getElementById('vg-tooltip-element');
            if (el && el.classList.contains('visible'))
                return [...document.querySelectorAll('#vg-tooltip-element td, #vg-tooltip-element th')].map(e => e.textContent);
            await sleep(10);
        }
        return null;
    }
    const keysOf = cells => cells.filter((_, i) => i % 2 === 0);
    const cellKeys = ['East (km)', 'North (km)', 'Field value', 'time', 'panel'];
    const stationKeys = ['East (km)', 'North (km)', 'time', 'panel'];
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

    try {
        const maps = await ready('maps');
        const isCell = it => it.mark.marktype === 'rect' && it.mark.role === 'mark' && it.datum && 'value' in it.datum;
        const isStation = it => it.mark.marktype === 'symbol' && it.mark.role === 'mark' && it.datum && !('value' in it.datum);
        const cells = items(maps, isCell), stations = items(maps, isStation);
        check(cells.length === 400, 'maps: expected 400 cells, got ' + cells.length);
        // Every drawn cell's tooltip is keyed by the labels: what vega-tooltip lists.
        check(cells.every(c => same(Object.keys(c.item.tooltip || {}), cellKeys)),
            'maps: a cell tooltip is keyed ' + JSON.stringify(cells.map(c => Object.keys(c.item.tooltip || {})).find(k => !same(k, cellKeys))));

        // A real hover on a cell away from the stations, as the reporter did.
        const cell = cells.find(c => c.item.datum.east === 55 && c.item.datum.north === 5 &&
            c.item.datum.time === 'Time 1' && c.item.datum.panel === 'Generating field');
        check(!!cell, 'maps: no cell at east 55, north 5 in the first panel');
        if (cell) {
            hoverAt('maps', cell);
            const shown = await shownCells();
            check(shown !== null, 'maps: hovering the cell shows no tooltip');
            if (shown) {
                check(same(keysOf(shown), cellKeys), 'maps: the hovered cell shows ' + JSON.stringify(shown));
                check(shown[1] === '55' && shown[3] === '5' && shown[7] === 'Time 1' && shown[9] === 'Generating field',
                    'maps: the hovered cell shows other values ' + JSON.stringify(shown));
            }
            leave('maps');
            await sleep(30);
        }
        // And a station: the points beside the cells name their rows the same way.
        check(stations.length === 8, 'maps: expected 8 stations, got ' + stations.length);
        if (stations.length) {
            hoverAt('maps', stations[0]);
            const shown = await shownCells();
            check(shown !== null && same(keysOf(shown), stationKeys), 'maps: the hovered station shows ' + JSON.stringify(shown));
            leave('maps');
            await sleep(30);
        }

        // The picker moves another field to colour: its row takes the picker's label.
        await ready('pick');
        const remapped = AoV._remappedSpec('pick', {color: 'h', _comboTitles: {g: 'Arm', h: 'Phase'}});
        const tip = (remapped.layer ? remapped.layer[0] : remapped).encoding.tooltip;
        check(tip.some(t => t.field === 'h' && t.title === 'Phase'), 'pick: the remapped colour row is ' + JSON.stringify(tip));
        check(!tip.some(t => t.field === 'g'), 'pick: the old colour row stayed: ' + JSON.stringify(tip));
        check(tip.some(t => t.field === 'x' && t.title === 'Dose (mg)'), 'pick: the x row lost its label: ' + JSON.stringify(tip));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-tooltip-labels-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
