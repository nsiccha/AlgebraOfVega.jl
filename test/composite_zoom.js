// Composite-layer zoom browser checks (snag `drew-a-faceted-f-c1afd58d`): a
// faceted figure whose first layer is a `Rangebars` (Vega-Lite's composite
// `errorbar`) and the same figure unfaceted embed with no console warning
// ("Selection not supported for errorbar yet." before), carry the automatic
// `grid` zoom, and a wheel over a panel zooms it: the error bars, drawn by
// the composite layer, follow the zoomed scales with the points.
(async function () {
    const failures = [], samples = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // Data items of `marktype`, with their bounds in view coordinates.
    function items(view, marktype) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && item.mark.marktype === marktype && item.mark.role === 'mark' && item.datum) {
                const b = item.bounds;
                out.push({x1: dx + b.x1, x2: dx + b.x2, y1: dy + b.y1, y2: dy + b.y2});
            }
            const group = item.mark && item.mark.marktype === 'group';
            const gx = group ? dx + (item.x || 0) : dx, gy = group ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy));
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const length = rules => rules.reduce((s, r) => s + (r.y2 - r.y1), 0);
    const hasSignal = (view, name) => { try { view.signal(name); return true; } catch (e) { return false; } };
    const zoomed = view => {
        const g = hasSignal(view, 'grid') && view.signal('grid') || {};
        return Object.keys(g).some(k => Array.isArray(g[k]));
    };
    async function wheel(id, view, at) {
        const canvas = document.querySelector('#' + id + ' canvas'), r = canvas.getBoundingClientRect();
        const o = view.origin(), p = view.padding();
        const opts = {bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: 'mouse',
            clientX: r.left + o[0] + p.left + at.x, clientY: r.top + o[1] + p.top + at.y};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new MouseEvent('mousemove', opts));
        canvas.dispatchEvent(new WheelEvent('wheel', Object.assign({deltaY: -300, deltaMode: 0}, opts)));
        await sleep(300);
        await view.runAsync();
    }
    try {
        for (const id of ['cz-facet', 'cz-plain']) {
            const view = await ready(id);
            await view.runAsync();
            check(hasSignal(view, 'grid'), id + ': the automatic zoom selection is in the view');
            check(!zoomed(view), id + ': nothing zoomed at rest');
            const rules = items(view, 'rule'), points = items(view, 'symbol');
            check(rules.length >= 12 && points.length >= 12,
                id + ': error bars and points drawn: ' + rules.length + ' rules, ' + points.length + ' points');
            const before = length(rules);
            const pt = points[0];
            await wheel(id, view, {x: (pt.x1 + pt.x2) / 2, y: (pt.y1 + pt.y2) / 2});
            const after = length(items(view, 'rule'));
            check(zoomed(view), id + ': the wheel set the zoom selection');
            check(after > before * 1.05, id + ': the error bars grew with the zoom: ' + before.toFixed(1) +
                ' -> ' + after.toFixed(1));
            samples[id] = {rules: rules.length, points: points.length, before, after};
        }
        samples.errors = window.AOV_ERRORS.slice();
        check(!window.AOV_ERRORS.some(e => /Selection not supported/.test(e)),
            'a selection was put on a composite mark: ' + JSON.stringify(window.AOV_ERRORS));
        check(window.AOV_ERRORS.length === 0, 'console errors or warnings: ' + JSON.stringify(window.AOV_ERRORS));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-composite-zoom-results';
    pre.textContent = JSON.stringify({checks, failures, samples});
    document.body.appendChild(pre);
})();
