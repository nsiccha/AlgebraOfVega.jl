// Click selections in the browser (snag `click-a-map-key-a85f71a9`): a click
// on a map cell selects its key for the group, and the charts that follow
// the group draw only that key's rows, refitting their axes; a per-key
// address is fetched once per key; Shift-click adds a key, a click on blank
// space keeps the selection, a long press selects, `AoV.select` from script
// selects and clears; the map outlines its selected cells; the selection is
// in the page address, survives re-embeds, reaches a chart embedded later
// and the CSV rows; a page opened with `?cells=C` starts at C.
(async function () {
    const F = window.AOV_FIXTURE;
    const mode = new URLSearchParams(location.search).get('mode') || 'clicks';
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    async function until(what, pred) {
        for (let i = 0; i < 500; i++) {
            if (pred()) return true;
            await sleep(10);
        }
        failures.push('timed out waiting for ' + what);
        return false;
    }
    const selects = [];
    document.addEventListener('aov:select', e => selects.push(e.detail));
    const clicks = [];
    document.addEventListener('aov:click', e => clicks.push(e.detail));

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
    const cellItem = (view, k) => {
        const found = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'shape' && it.datum && it.datum.cell === k);
        if (found.length !== 1) throw new Error('map: expected one cell ' + k + ', found ' + found.length);
        return found[0];
    };
    // The observed dots a chart draws, as the sorted cells they belong to.
    const dots = id => items(AoV.views[id], it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
        it.datum && 'observed' in it.datum).map(d => d.item.datum.cell).sort();
    const shownCells = id => Array.from(new Set(dots(id))).join(',');
    const surface = id => document.querySelector('#' + id + ' canvas, #' + id + ' svg');
    function client(id, at) {
        const view = AoV.views[id], rect = surface(id).getBoundingClientRect();
        const origin = view.origin(), pad = view.padding();
        return {x: rect.left + origin[0] + pad.left + at.x, y: rect.top + origin[1] + pad.top + at.y};
    }
    function clickAt(id, at, shiftKey) {
        const p = client(id, at), target = surface(id);
        const opts = {bubbles: true, cancelable: true, clientX: p.x, clientY: p.y, pointerId: 1, isPrimary: true,
            pointerType: 'mouse', shiftKey: !!shiftKey};
        target.dispatchEvent(new PointerEvent('pointermove', opts));
        target.dispatchEvent(new PointerEvent('pointerdown', opts));
        target.dispatchEvent(new PointerEvent('pointerup', opts));
        target.dispatchEvent(new MouseEvent('click', opts));
    }
    // A long press, as touch input sends it (see test/touch_input.js).
    async function longPress(id, at) {
        const p = client(id, at), target = document.elementFromPoint(p.x, p.y);
        const touch = new Touch({identifier: 7, target, clientX: p.x, clientY: p.y});
        const pointer = {bubbles: true, cancelable: true, composed: true, clientX: p.x, clientY: p.y,
            pointerId: 107, isPrimary: true, pointerType: 'touch'};
        target.dispatchEvent(new PointerEvent('pointerover', pointer));
        target.dispatchEvent(new PointerEvent('pointerdown', pointer));
        target.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, cancelable: true, composed: true,
            touches: [touch], changedTouches: [touch]}));
        await sleep(AoV._TOUCH_HOLD_MS + 100);
        target.dispatchEvent(new PointerEvent('pointerup', pointer));
        target.dispatchEvent(new TouchEvent('touchend', {bubbles: true, cancelable: true, composed: true,
            touches: [], changedTouches: [touch]}));
        await sleep(30);
    }
    const fetches = k => performance.getEntriesByType('resource').filter(e => e.name.endsWith('/cells/' + k + '.json')).length;
    const hint = id => document.querySelector('.aov-select-hint[data-aov-hint-for="' + id + '"]');
    const address = () => new URLSearchParams(location.search).getAll('cells').join(',');
    const ink = () => getComputedStyle(document.getElementById('sl-map')).color;
    // Which cells the map outlines: drawn in the text colour, painted last.
    function outlined() {
        const view = AoV.views['sl-map'];
        return ['A', 'B', 'C'].filter(k => {
            const it = cellItem(view, k).item;
            return it.stroke === ink() && it.zindex === 1;
        }).join(',');
    }
    const yDomain = id => JSON.stringify(AoV.views[id].scale('y').domain());

    try {
        await ready('sl-map'); await ready('sl-month'); await ready('sl-keyed');
        await sleep(50);
        if (mode === 'address') {
            // The page opened at ?cells=C: the group starts at C everywhere.
            check(JSON.stringify(AoV.selected('cells')) === '["C"]', 'address: selected ' + JSON.stringify(AoV.selected('cells')));
            check(shownCells('sl-month') === 'C', 'address: sl-month shows ' + shownCells('sl-month'));
            await until('sl-keyed to show C', () => shownCells('sl-keyed') === 'C');
            check(shownCells('sl-keyed') === 'C' && dots('sl-keyed').length === 12, 'address: sl-keyed shows ' + dots('sl-keyed'));
            check(fetches('C') === 1 && fetches('A') === 0, 'address: fetched C ' + fetches('C') + 'x, A ' + fetches('A') + 'x');
            check(outlined() === 'C', 'address: the map outlines ' + outlined());
            check(!hint('sl-keyed'), 'address: sl-keyed still shows its hint');
        } else {
            const map = AoV.views['sl-map'];
            // Before any click: the group starts at the month chart's `initial`
            // A, which the keyed chart (no `initial` of its own) follows too:
            // its page carried no rows, so it fetches A's.
            check(JSON.stringify(AoV.selected('cells')) === '["A"]', 'start: selected ' + JSON.stringify(AoV.selected('cells')));
            check(shownCells('sl-month') === 'A' && dots('sl-month').length === 12, 'start: sl-month shows ' + dots('sl-month'));
            await until('sl-keyed to show A', () => shownCells('sl-keyed') === 'A');
            check(dots('sl-keyed').length === 12 && fetches('A') === 1, 'start: sl-keyed draws ' + dots('sl-keyed').length + ' dots, fetched A ' + fetches('A') + 'x');
            check(!hint('sl-month') && !hint('sl-keyed'), 'start: a chart shows its hint with A selected');
            check(outlined() === 'A', 'start: the map outlines ' + outlined());
            check(address() === '', 'start: the address names ' + address() + ' before any click');
            const domainA = yDomain('sl-month');

            // A click on cell B.
            clickAt('sl-map', cellItem(map, 'B'));
            await sleep(20);
            check(clicks.length === 1 && clicks[0].datum.cell === 'B', 'click B: aov:click ' + JSON.stringify(clicks.map(c => c.datum.cell)));
            check(selects.length === 1 && JSON.stringify(selects[0].keys) === '["B"]' && selects[0].group === 'cells' &&
                selects[0].source === document.getElementById('sl-map'), 'click B: aov:select ' + JSON.stringify(selects.map(s => s.keys)));
            check(shownCells('sl-month') === 'B' && dots('sl-month').length === 12, 'click B: sl-month shows ' + dots('sl-month'));
            check(yDomain('sl-month') !== domainA, 'click B: sl-month kept the y domain ' + domainA + ' of A');
            await until('sl-keyed to show B', () => shownCells('sl-keyed') === 'B');
            check(dots('sl-keyed').length === 12, 'click B: sl-keyed draws ' + dots('sl-keyed').length + ' dots');
            check(!hint('sl-keyed'), 'click B: sl-keyed still shows its hint');
            check(fetches('B') === 1 && fetches('C') === 0, 'click B: fetched B ' + fetches('B') + 'x, C ' + fetches('C') + 'x');
            check(address() === 'B', 'click B: the address names ' + address());
            check(outlined() === 'B', 'click B: the map outlines ' + outlined());

            // Shift-click adds C.
            clickAt('sl-map', cellItem(map, 'C'), true);
            await sleep(20);
            check(JSON.stringify(AoV.selected('cells')) === '["B","C"]', 'shift C: selected ' + JSON.stringify(AoV.selected('cells')));
            check(shownCells('sl-month') === 'B,C' && dots('sl-month').length === 24, 'shift C: sl-month shows ' + shownCells('sl-month'));
            await until('sl-keyed to show B and C', () => shownCells('sl-keyed') === 'B,C');
            check(dots('sl-keyed').length === 24 && fetches('C') === 1 && fetches('B') === 1,
                'shift C: sl-keyed draws ' + dots('sl-keyed').length + ', fetched B ' + fetches('B') + 'x, C ' + fetches('C') + 'x');
            check(address() === 'B,C' && outlined() === 'B,C', 'shift C: address ' + address() + ', outlined ' + outlined());

            // A click on blank map space keeps the selection.
            const n = selects.length;
            const all = ['A', 'B', 'C'].map(k => cellItem(map, k));
            const blank = {x: all[1].x, y: Math.max(2, Math.min.apply(null, all.map(c => c.item.bounds.y1)) - 10)};
            clickAt('sl-map', blank);
            await sleep(20);
            check(selects.length === n && JSON.stringify(AoV.selected('cells')) === '["B","C"]',
                'blank click: selected ' + JSON.stringify(AoV.selected('cells')) + ' after ' + (selects.length - n) + ' aov:select');

            // A plain click on B replaces the selection; its rows are not fetched again.
            clickAt('sl-map', cellItem(map, 'B'));
            await until('sl-keyed to show B again', () => shownCells('sl-keyed') === 'B');
            check(shownCells('sl-month') === 'B' && fetches('B') === 1, 'click B again: sl-month ' + shownCells('sl-month') + ', fetched B ' + fetches('B') + 'x');

            // The CSV and data pane give the rows the chart draws.
            const groups = AoV._plotGroups('sl-month');
            const csvCells = Array.from(new Set([].concat.apply([], groups.map(g => g.rows.map(r => r.cell))))).sort().join(',');
            check(csvCells === 'B', 'csv: sl-month rows of cells ' + csvCells);
            const keyedCsv = Array.from(new Set([].concat.apply([], AoV._plotGroups('sl-keyed').map(g => g.rows.map(r => r.cell))))).join(',');
            check(keyedCsv === 'B', 'csv: sl-keyed rows of cells ' + keyedCsv);

            // Re-embeds (a theme change, a resize) keep the selection.
            let prev = AoV.views['sl-month'];
            AoV._reembeds['sl-month']();
            await ready('sl-month', prev);
            check(shownCells('sl-month') === 'B', 'resize: sl-month shows ' + shownCells('sl-month'));
            prev = AoV.views['sl-keyed'];
            AoV._reembeds['sl-keyed']();
            await ready('sl-keyed', prev);
            await sleep(30);
            check(shownCells('sl-keyed') === 'B' && dots('sl-keyed').length === 12, 'resize: sl-keyed shows ' + dots('sl-keyed'));
            prev = AoV.views['sl-map'];
            AoV._reembeds['sl-map']();
            await ready('sl-map', prev);
            check(outlined() === 'B', 'resize: the map outlines ' + outlined());

            // A chart embedded later shows the group's selection.
            const late = document.createElement('div');
            late.id = 'sl-late';
            document.body.appendChild(late);
            AoV.embed('sl-late', F.late);
            await ready('sl-late');
            check(shownCells('sl-late') === 'B', 'late: sl-late shows ' + shownCells('sl-late'));

            // A long press selects, as a click does.
            await longPress('sl-map', cellItem(AoV.views['sl-map'], 'C'));
            check(JSON.stringify(AoV.selected('cells')) === '["C"]', 'long press C: selected ' + JSON.stringify(AoV.selected('cells')));
            check(shownCells('sl-month') === 'C' && shownCells('sl-late') === 'C', 'long press C: sl-month ' + shownCells('sl-month') + ', sl-late ' + shownCells('sl-late'));

            // Page script: select from a table, then clear.
            AoV.select('cells', ['A']);
            await until('sl-keyed to show A', () => shownCells('sl-keyed') === 'A');
            check(shownCells('sl-month') === 'A' && fetches('A') === 1 && outlined() === 'A' && address() === 'A',
                'script A: sl-month ' + shownCells('sl-month') + ', fetched A ' + fetches('A') + 'x, outlined ' + outlined() + ', address ' + address());
            check(selects[selects.length - 1].source === null, 'script A: aov:select source is not null');
            AoV.select('cells', []);
            await sleep(30);
            check(dots('sl-month').length === 0 && dots('sl-keyed').length === 0, 'clear: drawn dots ' + dots('sl-month').length + ', ' + dots('sl-keyed').length);
            check(hint('sl-month') && hint('sl-keyed'), 'clear: a chart shows no hint');
            check(outlined() === '' && address() === '', 'clear: outlined ' + outlined() + ', address ' + address());
            check(JSON.stringify(AoV.selected('cells')) === '[]', 'clear: selected ' + JSON.stringify(AoV.selected('cells')));

            // A saved card opens at the keys shown and carries their rows.
            AoV.select('cells', ['C']);
            await until('sl-keyed to show C', () => shownCells('sl-keyed') === 'C');
            const script = await AoV._preloadScript('sl-keyed');
            check(script.indexOf('"cells/C.json"') !== -1 && script.indexOf('AoV._selections["cells"]') !== -1 &&
                script.indexOf('"keys":["C"]') !== -1, 'saved card: preload ' + script.slice(0, 160));
            check(!/<\/script/i.test(script.slice(0, -'<\/script>'.length)), 'saved card: the preload spells a closing script tag');
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const out = document.createElement('pre');
    out.id = 'aov-select-results';
    out.textContent = JSON.stringify({mode, checks, failures});
    document.body.appendChild(out);
})();
