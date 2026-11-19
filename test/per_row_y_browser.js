// Per-row Y scale browser checks (snag `per-panel-y-scal-81725851`): Bruno
// web-sim's Exposure by dose, a row per quantity, draws Cmax and AUC₂₄ on log
// y axes and Ctrough on a linear one, as one figure: its panels line up and fit
// the container, the x axis is labelled once, both drawings of the Ribbons |
// Intervals switch keep each panel's scale, the readout lists every panel's
// series under its title, a tooltip names its panel, a rule without the row
// field reaches every panel, and the channel picker remaps colour in every
// panel. No console error or warning is logged.
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
    // The y scale type of each stacked panel, top to bottom.
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
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

    try {
        // Both embeds of the exposure figure: captioned, and a bare `vdraw`.
        for (const id of ['pr-caption', 'pr-bare']) {
            const view = await ready(id);
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
            check(titles.filter(t => t === 'Dose (mg)').length === 1, id + ': x title drawn ' +
                titles.filter(t => t === 'Dose (mg)').length + ' times');
            const el = document.getElementById(id), drawing = surface(id);
            samples[id + ' widths'] = [drawing.clientWidth, el.clientWidth];
            check(drawing.clientWidth <= el.clientWidth + 1 && drawing.clientWidth > 0.8 * el.clientWidth,
                id + ': drawing ' + drawing.clientWidth + ' px in a ' + el.clientWidth + ' px container');
            // Every panel's plot area starts at the same x and is as wide.
            const groups = items(view, it => it.mark.marktype === 'group' && /^concat_\d+_group$/.test(it.mark.name || ''));
            const xs = groups.map(g => Math.round(g.item.x)), ws = groups.map(g => Math.round(g.item.width));
            check(groups.length === PANELS.length && new Set(xs).size === 1 && new Set(ws).size === 1,
                id + ': panels not aligned ' + JSON.stringify([xs, ws]));
        }

        const id = 'pr-caption';
        let view = await ready(id);
        check(!!document.querySelector('[data-aov-ribbon-view-for="' + id + '"]'), 'no Ribbons | Intervals switch');
        check(Object.keys(view.getState().signals).some(k => k.startsWith('legend_selection')), 'no legend selection');

        // The readout at 40 mg lists every panel's series under its title.
        const median = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'line' &&
            it.datum && it.datum.panel === PANELS[0] && +it.datum.dose === 40)[0];
        check(!!median, 'no median line point at 40 mg in ' + PANELS[0]);
        if (median) {
            pointerAt(id, median);
            await sleep(40);
            const lines = box(id);
            samples.readout = lines;
            check(!!lines && same(lines.filter(l => PANELS.includes(l)), PANELS), 'readout headings ' + JSON.stringify(lines));
            check(!!lines && lines.filter(l => /^(5th|50th|95th): /.test(l)).length === 9, 'readout series ' + JSON.stringify(lines));
            check(!!lines && !lines.includes('Exposure'), 'readout names the mapping title ' + JSON.stringify(lines));
            leave(id);
            await sleep(30);
        }

        // The interval drawing keeps each panel's scale type and title, and a
        // median point's tooltip names its panel.
        AoV.setRibbonView(id, 'intervals');
        view = await ready(id, view);
        const itypes = yTypes(view);
        samples['intervals y types'] = itypes;
        check(same(itypes, expected), 'intervals drawing: y types ' + JSON.stringify(itypes));
        const ititles = axisTitles(view);
        check(PANELS.every(p => ititles.includes(p)), 'intervals drawing: axis titles ' + JSON.stringify(ititles));
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
        view = await ready(id, view);
        check(same(yTypes(view), expected), 'back to ribbons: y types ' + JSON.stringify(yTypes(view)));

        // A rule whose rows lack the row field reaches every panel.
        view = await ready('pr-rule');
        const rules = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'rule' && it.datum && +it.datum.dose === 20);
        check(rules.length === PANELS.length, 'pr-rule: ' + rules.length + ' rules, expected one per panel');
        check(same(yTypes(view), expected), 'pr-rule: y types ' + JSON.stringify(yTypes(view)));

        // The picker remaps colour in every panel and keeps each panel's
        // scale and title; the row it is keyed by stays.
        const pk = 'pr-picker';
        view = await ready(pk);
        const fills = v => [...new Set(items(v, it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
            it.datum && it.datum.panel !== undefined).map(i => i.item.fill))];
        check(fills(view).length === 3, pk + ': starts with 3 percentile colours ' + JSON.stringify(fills(view)));
        AoV.remapEncoding(pk, {color: ''});
        view = await ready(pk, view);
        check(fills(view).length === 1, pk + ': colour cleared, fills ' + JSON.stringify(fills(view)));
        check(same(yTypes(view), expected), pk + ': colour cleared, y types ' + JSON.stringify(yTypes(view)));
        let ptitles = axisTitles(view);
        check(PANELS.every(p => ptitles.includes(p)), pk + ': colour cleared, axis titles ' + JSON.stringify(ptitles));
        AoV.remapEncoding(pk, {color: 'percentile'});
        view = await ready(pk, view);
        check(fills(view).length === 3, pk + ': colour restored, fills ' + JSON.stringify(fills(view)));
        check(same(yTypes(view), expected), pk + ': colour restored, y types ' + JSON.stringify(yTypes(view)));
        check(!!AoV._panelLabelsOf(AoV._cur[pk].spec), pk + ': the remap dropped the panel titles record');
        check(same(yTypes(view), expected), pk + ': y types ' + JSON.stringify(yTypes(view)));

        samples.errors = window.AOV_ERRORS.slice();
        check(window.AOV_ERRORS.length === 0, 'console errors or warnings: ' + JSON.stringify(window.AOV_ERRORS));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-per-row-y-results';
    pre.textContent = JSON.stringify({checks, failures, samples});
    document.body.appendChild(pre);
})();
