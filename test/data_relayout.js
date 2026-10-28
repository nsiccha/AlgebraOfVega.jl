(async function () {
    const failures = [];
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
    // The canvas, the view origin, and the axis titles and labels drawn, with
    // their boxes in canvas pixels (scenegraph bounds are relative to the
    // enclosing group, which the view origin offsets).
    function layout(id) {
        const view = AoV.views[id];
        const canvas = document.getElementById(id).querySelector('canvas');
        const w = canvas.clientWidth, h = canvas.clientHeight, origin = view.origin();
        const texts = [];
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
            (item.items || []).forEach(c => walk(c, group ? x + (item.x || 0) : x, group ? y + (item.y || 0) : y));
        })(view.scenegraph().root, 0, 0);
        const outside = texts.filter(t => t.x1 < -0.5 || t.y1 < -0.5 || t.x2 > w + 0.5 || t.y2 > h + 0.5);
        return {w, h, origin, texts, outside: [...new Set(outside.map(t => t.role + ' ' + t.text))],
            titles: texts.filter(t => t.role === 'axis-title').map(t => t.text).sort(),
            labels: texts.filter(t => t.role === 'axis-label').length,
            rows: view.data('source_0').length};
    }
    const fixedWidth = ['explicit', 'swap', 'wider', 'update'];
    try {
        for (const c of fixture.cases) { await ready(c.id); await ready(c.id + '-full'); }
        for (const c of fixture.cases) {
            for (const step of c.steps) { (0, eval)(step); await pause(30); await ready(c.id); }
            await pause(300);
            await ready(c.id);
            const got = layout(c.id), want = layout(c.id + '-full');
            // The rows arrived, and the drawing has its titles and labels.
            check(got.rows === want.rows, c.id + ': rows ' + got.rows + ' ≠ ' + want.rows);
            check(JSON.stringify(got.titles) === JSON.stringify(['AUC', 'Dose (mg)']),
                c.id + ': axis titles ' + JSON.stringify(got.titles));
            check(got.labels > 4, c.id + ': ' + got.labels + ' axis labels');
            // Every one of them inside the canvas, as in the render of the same rows.
            check(got.outside.length === 0, c.id + ': outside the canvas ' + JSON.stringify(got.outside));
            check(want.outside.length === 0, c.id + '-full: outside the canvas ' + JSON.stringify(want.outside));
            check(got.h === want.h, c.id + ': canvas height ' + got.h + ' ≠ ' + want.h);
            if (fixedWidth.includes(c.id)) {
                // The same layout as the render, laid out in place.
                check(got.w === want.w && got.origin[0] === want.origin[0] && got.origin[1] === want.origin[1],
                    c.id + ': canvas ' + got.w + ' at ' + got.origin + ' ≠ ' + want.w + ' at ' + want.origin);
                check(AOV_EMBEDS[c.id] === 1, c.id + ': embedded ' + AOV_EMBEDS[c.id] + ' times');
            } else {
                // Sized to its 700 px column, as the render is.
                check(got.w <= 702 && Math.abs(got.w - want.w) <= 2,
                    c.id + ': canvas width ' + got.w + ', the render ' + want.w);
                check(got.origin[0] === want.origin[0], c.id + ': origin ' + got.origin + ' ≠ ' + want.origin);
            }
        }
        // The container-sized layered plot is corrected at most once per row.
        check(AOV_EMBEDS.layered <= 1 + fixture.cases.find(c => c.id === 'layered').steps.length,
            'layered: embedded ' + AOV_EMBEDS.layered + ' times');
        // Vega-Lite lays out an autosize-fit view itself: no correction re-embeds.
        check(AOV_EMBEDS.container === 1, 'container: embedded ' + AOV_EMBEDS.container + ' times');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-data-relayout-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
