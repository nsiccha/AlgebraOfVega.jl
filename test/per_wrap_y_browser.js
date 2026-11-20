// Per-panel Y scale browser checks on a wrapped `layout=` facet (todo
// `0svhytl`, snag `per-panel-y-scal-81725851`): Bruno web-sim's Exposure by
// dose, wrapped, draws Cmax and AUC₂₄ on log y axes and Ctrough on a linear
// one, as one figure: its panels fit the container and re-wrap when it
// resizes, every panel draws its own x axis on the shared x scale, both
// drawings of the Ribbons | Intervals switch keep each panel's scale, the
// readout follows the hovered panel and reaches a linked plot, a tooltip
// names its panel, a rule without the wrap field reaches every panel, and the
// channel picker remaps colour in every panel. No console error or warning is
// logged.
(async function () {
    const failures = [], samples = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const PANELS = window.AOV_PANELS, LOG = window.AOV_LOG;
    const expected = PANELS.map(p => LOG.includes(p) ? 'log' : 'linear');
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // The view once its post-paint fit corrections are done: unchanged for 150 ms.
    async function settled(id, previous) {
        let view = await ready(id, previous);
        for (let i = 0; i < 100; i++) {
            await sleep(150);
            const now = AoV.views[id];
            if (now === view && !AoV._inFlight[id]) return view;
            view = await ready(id, view);
        }
        throw new Error(id + ': the fit corrections did not settle');
    }
    // Scenegraph items matching `pred`, at a line or area point's own x and y,
    // else their centre, in view coordinates.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds, path = ['line', 'area', 'trail'].includes(item.mark.marktype);
                out.push({item, x: dx + (path ? item.x : (b.x1 + b.x2) / 2), y: dy + (path ? item.y : (b.y1 + b.y2) / 2)});
            }
            const gx = item.mark && item.mark.marktype === 'group' ? dx + (item.x || 0) : dx;
            const gy = item.mark && item.mark.marktype === 'group' ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy));
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const axisTitles = view => items(view, it => it.mark.role === 'axis-title').map(t => t.item.text).filter(Boolean);
    const surface = id => document.querySelector('#' + id + ' canvas, #' + id + ' svg');
    function pointerAt(id, at) {
        const view = AoV.views[id], rect = surface(id).getBoundingClientRect();
        const origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: 'mouse',
            clientX: rect.left + origin[0] + pad.left + at.x, clientY: rect.top + origin[1] + pad.top + at.y};
        surface(id).dispatchEvent(new PointerEvent('pointermove', opts));
        surface(id).dispatchEvent(new MouseEvent('mousemove', opts));
    }
    function leave(id) {
        surface(id).dispatchEvent(new PointerEvent('pointerout', {bubbles: true, pointerId: 1, pointerType: 'mouse'}));
        surface(id).dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
        document.getElementById(id).dispatchEvent(new PointerEvent('pointerleave', {pointerId: 1, pointerType: 'mouse'}));
    }
    async function shownCells() {
        for (let i = 0; i < 50; i++) {
            const el = document.getElementById('vg-tooltip-element');
            if (el && el.classList.contains('visible'))
                return [...document.querySelectorAll('#vg-tooltip-element td, #vg-tooltip-element th')].map(e => e.textContent);
            await sleep(10);
        }
        return null;
    }
    function box(id) {
        const b = document.querySelector('#' + id + ' .aov-readout');
        return b && b.style.display !== 'none' ? b.innerText.split('\n').map(s => s.trim()).filter(Boolean) : null;
    }
    // The y scale type of each panel, in panel order.
    function yTypes(view) {
        const out = [];
        for (let k = 0; k < 10; k++) {
            let s = null;
            try { s = view.scale('concat_' + k + '_y'); } catch (e) { /* no such panel */ }
            if (!s) break;
            out.push(s.type);
        }
        return out;
    }
    // The panels' plot areas in view coordinates, in panel order.
    function panelBoxes(view) {
        const frame = view.scenegraph().root.items[0], out = [];
        (frame.items || []).forEach(m => {
            if (m.marktype === 'group' && /^concat_\d+_group$/.test(m.name || '')) (m.items || []).forEach(g =>
                out.push({x: Math.round(g.x || 0), y: Math.round(g.y || 0), width: Math.round(g.width || 0),
                    height: Math.round(g.height || 0)}));
        });
        return out;
    }
    // How the panels are laid out: panels per row and rows.
    function grid(view) {
        const boxes = panelBoxes(view);
        const rows = [...new Set(boxes.map(b => b.y))];
        return {cols: boxes.filter(b => b.y === boxes[0].y).length, rows: rows.length, boxes};
    }
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    // The column count the runtime wrapped the panels into.
    const columns = id => (AoV._computedWidths[id] || {}).nCols;
    // Fits its container, with one width for every panel.
    function fits(id, view, label) {
        const el = document.getElementById(id), drawing = surface(id), g = grid(view);
        samples[label + ' widths'] = [drawing.clientWidth, el.clientWidth, columns(id), g.cols, g.rows];
        check(drawing.clientWidth <= el.clientWidth + 1 && drawing.clientWidth > 0.75 * el.clientWidth,
            label + ': drawing ' + drawing.clientWidth + ' px in a ' + el.clientWidth + ' px container');
        check(new Set(g.boxes.map(b => b.width)).size === 1, label + ': panel widths ' + JSON.stringify(g.boxes));
        check(g.cols === columns(id), label + ': ' + g.cols + ' panels to a row, sized for ' + columns(id));
        return g;
    }

    try {
        // Both embeds of the exposure figure: captioned, and a bare `vdraw`.
        for (const id of ['pw-caption', 'pw-bare']) {
            const view = await settled(id);
            const types = yTypes(view);
            samples[id + ' y types'] = types;
            check(same(types, expected), id + ': y scale types ' + JSON.stringify(types));
            let x = null;
            try { x = view.scale('x'); } catch (e) { /* none */ }
            check(!!x && x.type === 'log', id + ': no shared log x scale');
            const titles = axisTitles(view);
            samples[id + ' axis titles'] = titles;
            check(PANELS.every(p => titles.includes(p)), id + ': axis titles ' + JSON.stringify(titles));
            check(!titles.includes('Exposure'), id + ': an axis still reads the mapping title');
            check(titles.filter(t => t === 'Dose (mg)').length === PANELS.length, id + ': x title drawn ' +
                titles.filter(t => t === 'Dose (mg)').length + ' times, expected under every panel');
            fits(id, view, id);
        }
        // Three panels to a row in the wide caption, two in the 700 px column.
        check(grid(AoV.views['pw-caption']).cols === 3, 'pw-caption: ' + grid(AoV.views['pw-caption']).cols + ' panels to a row');
        check(grid(AoV.views['pw-bare']).cols === 2 && grid(AoV.views['pw-bare']).rows === 2,
            'pw-bare: grid ' + JSON.stringify(grid(AoV.views['pw-bare'])));


        const id = 'pw-caption';
        let view = await ready(id);
        check(!!document.querySelector('[data-aov-ribbon-view-for="' + id + '"]'), 'no Ribbons | Intervals switch');
        check(Object.keys(view.getState().signals).some(k => k.startsWith('legend_selection')), 'no legend selection');

        // The readout at 40 mg in the AUC₂₄ panel lists that panel's series
        // only, and the linked plot shows its readout at 40 mg too.
        const median = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'line' &&
            it.datum && it.datum.panel === PANELS[1] && +it.datum.dose === 40)[0];
        check(!!median, 'no median line point at 40 mg in ' + PANELS[1]);
        if (median) {
            pointerAt(id, median);
            await sleep(40);
            const lines = box(id);
            samples.readout = lines;
            check(!!lines && lines[0] === 'Dose (mg): 40', 'readout heading ' + JSON.stringify(lines));
            check(!!lines && lines.filter(l => /^(5th|50th|95th): /.test(l)).length === 3, 'readout series ' + JSON.stringify(lines));
            check(!!lines && !lines.some(l => PANELS.includes(l) || l === 'Exposure'),
                'readout names a panel heading ' + JSON.stringify(lines));
            // The AUC₂₄ panel's own median (20 × 40 × 0.6² = 288), not Cmax's (144).
            check(!!lines && lines.some(l => l.startsWith('50th: 288 ')), 'readout reads another panel ' + JSON.stringify(lines));
            const linked = box('pw-bare');
            samples['linked readout'] = linked;
            check(!!linked && linked[0] === 'Dose (mg): 40' && linked.filter(l => /^(5th|50th|95th): /.test(l)).length === 3,
                'linked readout ' + JSON.stringify(linked));
            leave(id);
            await sleep(30);
            check(box(id) === null && box('pw-bare') === null, 'readouts stay after the pointer left');
        }

        // The interval drawing keeps each panel's scale type and title, and a
        // median point's tooltip names its panel.
        AoV.setRibbonView(id, 'intervals');
        view = await settled(id, view);
        const itypes = yTypes(view);
        samples['intervals y types'] = itypes;
        check(same(itypes, expected), 'intervals drawing: y types ' + JSON.stringify(itypes));
        const ititles = axisTitles(view);
        check(PANELS.every(p => ititles.includes(p)), 'intervals drawing: axis titles ' + JSON.stringify(ititles));
        fits(id, view, 'intervals drawing');
        for (const p of PANELS) {
            const pt = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
                it.datum && it.datum.panel === p && +it.datum.dose === 80 && it.datum.__aov_estimate !== undefined)[0];
            check(!!pt, 'intervals drawing: no median point at 80 mg in ' + p);
            if (!pt) continue;
            pointerAt(id, pt);
            const shown = await shownCells();
            samples['tooltip ' + p] = shown;
            check(!!shown && shown.some(c => c === p + ': median (95% interval)'), p + ': tooltip ' + JSON.stringify(shown));
            leave(id);
            await sleep(30);
        }
        AoV.setRibbonView(id, 'ribbons');
        view = await settled(id, view);
        check(same(yTypes(view), expected), 'back to ribbons: y types ' + JSON.stringify(yTypes(view)));

        // A rule whose rows lack the wrap field reaches every panel.
        view = await ready('pw-rule');
        const rules = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'rule' && it.datum && +it.datum.dose === 20);
        check(rules.length === PANELS.length, 'pw-rule: ' + rules.length + ' rules, expected one per panel');
        check(same(yTypes(view), expected), 'pw-rule: y types ' + JSON.stringify(yTypes(view)));

        // The picker remaps colour in every panel and keeps each panel's
        // scale and title; the wrap it is keyed by stays.
        const pk = 'pw-picker';
        view = await settled(pk);
        const fills = v => [...new Set(items(v, it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
            it.datum && it.datum.panel !== undefined).map(i => i.item.fill))];
        check(fills(view).length === 3, pk + ': starts with 3 percentile colours ' + JSON.stringify(fills(view)));
        check(grid(view).cols === columns(pk), pk + ': grid ' + JSON.stringify(grid(view)));
        AoV.remapEncoding(pk, {color: ''});
        view = await settled(pk, view);
        check(fills(view).length === 1, pk + ': colour cleared, fills ' + JSON.stringify(fills(view)));
        check(same(yTypes(view), expected), pk + ': colour cleared, y types ' + JSON.stringify(yTypes(view)));
        let ptitles = axisTitles(view);
        check(PANELS.every(p => ptitles.includes(p)), pk + ': colour cleared, axis titles ' + JSON.stringify(ptitles));
        check(grid(view).rows === Math.ceil(PANELS.length / columns(pk)), pk + ': colour cleared, grid ' +
            JSON.stringify(grid(view)));
        AoV.remapEncoding(pk, {color: 'percentile'});
        view = await settled(pk, view);
        check(fills(view).length === 3, pk + ': colour restored, fills ' + JSON.stringify(fills(view)));
        check(same(yTypes(view), expected), pk + ': colour restored, y types ' + JSON.stringify(yTypes(view)));
        check(!!AoV._panelLabelsOf(AoV._cur[pk].spec), pk + ': the remap dropped the panel titles record');

        // The panels re-wrap when the container resizes. Last: the resize
        // observer's own (debounced) re-embed of the resized plot would
        // otherwise land in the middle of the readout checks above.
        const bareBox = document.getElementById('pw-bare-box');
        for (const [w, cols] of [[1100, 3], [380, 1], [700, 2]]) {
            const before = AoV.views['pw-bare'];
            bareBox.style.width = w + 'px';
            AoV._resizeReembed('pw-bare');
            const view = await settled('pw-bare', before);
            const g = fits('pw-bare', view, 'pw-bare at ' + w + ' px');
            check(g.cols === cols && g.rows === Math.ceil(PANELS.length / cols),
                'pw-bare at ' + w + ' px: grid ' + JSON.stringify([g.cols, g.rows]) + ', expected ' + cols + ' to a row');
            check(same(yTypes(view), expected), 'pw-bare at ' + w + ' px: y types ' + JSON.stringify(yTypes(view)));
        }

        samples.errors = window.AOV_ERRORS.slice();
        check(window.AOV_ERRORS.length === 0, 'console errors or warnings: ' + JSON.stringify(window.AOV_ERRORS));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-per-wrap-y-results';
    pre.textContent = JSON.stringify({checks, failures, samples});
    document.body.appendChild(pre);
})();
