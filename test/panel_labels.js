// Per-panel axis titles in the browser (snag `facet-panels-can-13c4e53c`):
// each panel of Bruno web-sim's dose figure draws its own quantity as its y
// title, in both drawings of the Ribbons | Intervals switch; the readout names
// the panel's series by it; a hovered mark's tooltip names its estimate and
// value rows by it, read from the page as a reader sees them
// (`#vg-tooltip-element td, th`); and a picker remap that takes the panels
// away gives the axes their mapping's title back.
(async function () {
    const failures = [], samples = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    const QUANTITY = window.AOV_PANELS, PANELS = Object.keys(QUANTITY);
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
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
    const axisTitles = view => items(view, it => it.mark.role === 'axis-title').map(t => t.item.text).filter(Boolean).sort();
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
    const keysOf = cells => cells.filter((_, i) => i % 2 === 0);
    function box(id) {
        const b = document.querySelector('#' + id + ' .aov-readout');
        return b && b.style.display !== 'none' ? b.innerText.split('\n').map(s => s.trim()).filter(Boolean) : null;
    }
    const quantities = Object.values(QUANTITY).sort();

    try {
        // The y titles: each panel's quantity, never the mapping's "Median".
        let view = await ready('pl-readout');
        let titles = axisTitles(view);
        check(quantities.every(q => titles.includes(q)), 'readout figure: axis titles ' + JSON.stringify(titles));
        check(!titles.includes('Median'), 'readout figure: an axis still reads Median: ' + JSON.stringify(titles));

        // The readout over each panel names the panel's series by its quantity.
        for (const p of PANELS) {
            const line = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'line' &&
                it.datum && it.datum.panel === p && +it.datum.dose === 10 && it.datum.line === undefined)[0];
            check(!!line, 'readout figure: no median line point at 10 mg in ' + p);
            if (!line) continue;
            pointerAt('pl-readout', line);
            await sleep(30);
            const lines = box('pl-readout');
            samples['readout ' + p] = lines;
            check(!!lines && lines.some(l => l.includes(QUANTITY[p])), p + ': the readout reads ' + JSON.stringify(lines));
            check(!!lines && !lines.some(l => l.includes('Median')), p + ': the readout still names Median: ' + JSON.stringify(lines));
            leave('pl-readout');
            await sleep(30);
        }

        // The other drawing keeps the panel titles.
        AoV.setRibbonView('pl-readout', 'intervals');
        await sleep(50);
        view = await ready('pl-readout');
        titles = axisTitles(view);
        samples['intervals drawing axis titles'] = titles;
        check(quantities.every(q => titles.includes(q)) && !titles.includes('Median'),
            'intervals drawing: axis titles ' + JSON.stringify(titles));

        // A hovered median point's estimate row, and an observation's value row,
        // name the panel's quantity.
        view = await ready('pl-tip');
        for (const p of PANELS) {
            const median = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
                it.datum && it.datum.panel === p && +it.datum.dose === 30 && it.datum.__aov_estimate !== undefined)[0];
            check(!!median, 'tooltip figure: no median point at 30 mg in ' + p);
            if (median) {
                pointerAt('pl-tip', median);
                const shown = await shownCells();
                samples['median tooltip ' + p] = shown;
                const keys = shown ? keysOf(shown) : null;
                // `bands=` with `probs=` but no `point=` names the median column (aov-use §8).
                check(!!keys && keys.includes(QUANTITY[p] + ': q50 (95% interval)'),
                    p + ': the median point shows ' + JSON.stringify(shown));
                check(!!keys && !keys.some(k => k.startsWith('Median')), p + ': a row still reads Median: ' + JSON.stringify(shown));
                leave('pl-tip');
                await sleep(30);
            }
            const observed = items(view, it => it.mark.role === 'mark' && it.mark.marktype === 'symbol' &&
                it.datum && it.datum.panel === p && it.datum.obs !== undefined)[0];
            check(!!observed, 'tooltip figure: no observation in ' + p);
            if (observed) {
                pointerAt('pl-tip', observed);
                const shown = await shownCells();
                samples['observation tooltip ' + p] = shown;
                const keys = shown ? keysOf(shown) : null;
                check(!!keys && keys.includes(QUANTITY[p]) && !keys.includes('Observed'),
                    p + ': the observation shows ' + JSON.stringify(shown));
                leave('pl-tip');
                await sleep(30);
            }
        }

        // A remap that keeps the panels keeps the titles; one that takes them
        // away, or moves the axis to another field, gives the mapping's back.
        const orig = AoV._origSpecs['pl-tip'];
        const exprs = s => { const out = []; AoV._eachEncoding(s, 'y', e => { if (e.axis && e.axis.title && e.axis.title.expr) out.push(e); }); return out; };
        const kept = AoV._fitPanelLabels(JSON.parse(JSON.stringify(orig)));
        check(exprs(kept).length > 0 && !!AoV._panelLabelsOf(kept), 'remap: an unchanged facet lost its panel titles');
        const flat = JSON.parse(JSON.stringify(orig));
        delete flat.facet;
        AoV._fitPanelLabels(flat);
        check(exprs(flat).length === 0 && !AoV._panelLabelsOf(flat), 'remap: an unfaceted spec kept panel titles');
        const moved = JSON.parse(JSON.stringify(orig));
        AoV._eachEncoding(moved, 'y', e => { if (e.field === 'obs') e.field = 'other'; });
        AoV._fitPanelLabels(moved);
        check(exprs(moved).length === 0, 'remap: an axis moved to another field kept panel titles');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-panel-labels-results';
    pre.textContent = JSON.stringify({checks, failures, samples});
    document.body.appendChild(pre);
})();
