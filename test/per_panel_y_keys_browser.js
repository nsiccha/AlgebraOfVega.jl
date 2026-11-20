// Per-panel Y domain and clamp, in the browser (snag `per-panel-y-doma-41192758`):
// Bruno web-sim's Exposure by dose draws Cmax, AUC₂₄ and Ctrough on log y axes,
// Ctrough's cut at 0.3 with its lower values drawn at the axis edge. In a
// row stack and a wrapped concat, the Ctrough panel's compiled scale has the
// authored domain and clamps, the other panels fit their own domains and do
// not clamp, every band and line of the Ctrough panel lies inside its plot
// area (unclamped, its 1e-12 values would fall far below it), some of it on
// the bottom edge, and the interval drawing keeps all of this. No console
// error or warning is logged.
(async function () {
    const failures = [], samples = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const PANELS = window.AOV_PANELS;
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // The y scale of panel `k`, or null.
    function yScale(view, k) {
        try { return view.scale('concat_' + k + '_y') || null; } catch (e) { return null; }
    }
    // Every mark item of panel `k` whose marktype is in `types`, with its y
    // extent in the panel's own coordinates.
    function panelItems(view, k, types) {
        const out = [], prefix = 'concat_' + k + '_';
        (function walk(item) {
            const m = item.mark;
            if (m && types.includes(m.marktype) && (m.name || '').startsWith(prefix) && m.role === 'mark' &&
                    item.datum && item.datum.panel === PANELS[k]) {
                // The geometry, not the stroke-padded bounds: a clamped rule or
                // point centred on the edge reaches past it by its stroke.
                const ys = [item.y, item.y2].filter(v => typeof v === 'number' && isFinite(v));
                out.push({mark: m.marktype, ys});
            }
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const near = (a, b) => Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(b));
    function checkPanels(id, view, what, kinds) {
        for (let k = 0; k < PANELS.length; k++) {
            const s = yScale(view, k);
            check(!!s, id + ' ' + what + ': no y scale for panel ' + k);
            if (!s) continue;
            check(s.type === 'log', id + ' ' + what + ': panel ' + k + ' y type ' + s.type);
            const dom = s.domain(), cut = k === 2;
            samples[id + ' ' + what + ' domain ' + k] = dom;
            if (cut) {
                check(near(dom[0], 0.3) && near(dom[1], 3e5), id + ' ' + what + ': Ctrough domain ' + JSON.stringify(dom));
                check(s.clamp() === true, id + ' ' + what + ': Ctrough does not clamp');
            } else {
                check(!near(dom[0], 0.3), id + ' ' + what + ': panel ' + k + ' took the cut domain ' + JSON.stringify(dom));
                check(s.clamp() === false, id + ' ' + what + ': panel ' + k + ' clamps');
            }
        }
        // The Ctrough panel's marks stay inside its plot area, some on its edge.
        const s = yScale(view, 2);
        if (!s) return;
        const [r0, r1] = s.range(), lo = Math.min(r0, r1), hi = Math.max(r0, r1);
        const its = panelItems(view, 2, kinds);
        const ys = its.flatMap(i => i.ys);
        samples[id + ' ' + what + ' Ctrough marks'] = [its.length, Math.min(...ys), Math.max(...ys), lo, hi];
        check(its.length > 0, id + ' ' + what + ': no Ctrough marks');
        check(ys.every(y => y >= lo - 1 && y <= hi + 1), id + ' ' + what + ': Ctrough marks outside its plot area ' +
            JSON.stringify([Math.min(...ys), Math.max(...ys), lo, hi]));
        check(ys.some(y => Math.abs(y - hi) <= 1), id + ' ' + what + ': nothing drawn at the bottom edge');
    }

    try {
        let view = await ready('pk-row');
        checkPanels('pk-row', view, 'ribbons', ['area', 'line']);
        AoV.setRibbonView('pk-row', 'intervals');
        view = await ready('pk-row', view);
        checkPanels('pk-row', view, 'intervals', ['rule']);
        const wrap = await ready('pk-wrap');
        checkPanels('pk-wrap', wrap, 'ribbons', ['area', 'line']);

        samples.errors = window.AOV_ERRORS.slice();
        check(window.AOV_ERRORS.length === 0, 'console errors or warnings: ' + JSON.stringify(window.AOV_ERRORS));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-per-panel-y-keys-results';
    pre.textContent = JSON.stringify({checks, failures, samples});
    document.body.appendChild(pre);
})();
