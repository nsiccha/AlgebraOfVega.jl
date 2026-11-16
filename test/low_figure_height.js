(async function () {
    const failures = [];
    const errors = [];
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms || 10));
    const fixture = window.AOV_FIXTURE;
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // The canvas, and the axis titles and labels drawn, with their boxes in
    // canvas pixels (scenegraph bounds are relative to the enclosing group,
    // which the view origin offsets).
    function layout(id) {
        const view = AoV.views[id];
        const canvas = document.getElementById(id).querySelector('canvas');
        const w = canvas.clientWidth, h = canvas.clientHeight, origin = view.origin();
        // Every item of a mark is visited, and each reaches its siblings
        // through `item.mark`: a set counts each bar once.
        const texts = [], bars = new Set();
        (function walk(item, x, y) {
            const mark = item.mark;
            const group = mark && mark.marktype === 'group';
            if (mark && (mark.role === 'axis-title' || mark.role === 'axis-label')) {
                (mark.items || []).forEach(t => {
                    if (t.text === '' || t.opacity === 0) return;
                    texts.push({role: mark.role, text: String(t.text),
                        x1: origin[0] + x + t.bounds.x1, x2: origin[0] + x + t.bounds.x2,
                        y1: origin[1] + y + t.bounds.y1, y2: origin[1] + y + t.bounds.y2});
                });
            }
            if (mark && mark.marktype === 'rect' && mark.role === 'mark') {
                (mark.items || []).forEach(r => bars.add(r));
            }
            (item.items || []).forEach(c => walk(c, group ? x + (item.x || 0) : x, group ? y + (item.y || 0) : y));
        })(view.scenegraph().root, 0, 0);
        const outside = texts.filter(t => t.x1 < -0.5 || t.y1 < -0.5 || t.x2 > w + 0.5 || t.y2 > h + 0.5);
        return {w, h, plot: view.height(), bars: [...bars].map(r => r.bounds.y2 - r.bounds.y1), outside: [...new Set(outside.map(t => t.role + ' ' + t.text))],
            titles: texts.filter(t => t.role === 'axis-title').map(t => t.text)};
    }
    // The plot keeps its authored plot area, draws its bars at full height,
    // spans its 900 px column and holds every axis text inside its canvas.
    function verify(p, label) {
        const got = layout(p.id);
        if (p.height !== null) {
            check(got.plot === p.height, label + ': plot area ' + got.plot + ' px, not ' + p.height);
            check(got.h > p.height, label + ': canvas ' + got.h + ' px holds no axis below a ' + p.height + ' px plot');
        }
        check(got.outside.length === 0, label + ': outside the canvas ' + JSON.stringify(got.outside));
        check(got.titles.length === 2, label + ': axis titles ' + JSON.stringify(got.titles));
        check(got.w >= 870 && got.w <= 902, label + ': canvas width ' + got.w + ' in a 900 px column');
        const tall = fixture.bars[p.id];
        if (tall) {
            const full = got.bars.filter(b => b >= got.plot - 1 && b > 0).length;
            check(full === tall, label + ': ' + full + ' bars at the full plot height, not ' + tall);
        }
        return got;
    }
    try {
        for (const p of fixture.plots) await ready(p.id);
        await pause(300);
        for (const p of fixture.plots) {
            verify(p, p.id);
            // Each layout pass (a data change, a resize) leaves the plot area as it is.
            for (let i = 1; i <= 3; i++) {
                AoV._runRelayout(AoV.views[p.id]);
                await pause(30);
                verify(p, p.id + ' after relayout ' + i);
            }
        }
        // Rows replaced in the browser: one more layout pass, in place.
        const update = fixture.plots.find(p => p.id === 'low-update');
        (0, eval)(fixture.update);
        await pause(300);
        await ready('low-update');
        check(AoV.views['low-update'].data('source_0').some(r => r.fall === 4), 'low-update: the new rows did not arrive');
        verify(update, 'low-update after update_data');
        check(AOV_EMBEDS['low-update'] === 1, 'low-update: embedded ' + AOV_EMBEDS['low-update'] + ' times');
        // One mark layer or two: the same default plot area.
        const a = AoV.views['low-default'].height(), b = AoV.views['low-default-layered'].height();
        check(a === b && a > 0, 'default height: single ' + a + ' px, layered ' + b + ' px');
        check(errors.length === 0, 'console errors: ' + errors.join('; '));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    } finally {
        console.error = originalError;
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-low-figure-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
