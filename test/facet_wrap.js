// Auto-wrapped `layout=` facets (17 panels) in 1450px containers: the runtime puts
// as many panels in a row as fit, the rendered grid stays inside the container,
// a narrower container re-wraps, and an authored `columns` is left alone.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // Lets a post-embed correction re-embed settle.
    async function settle() { await pause(600); }
    // The facet cells Vega laid out: distinct x and y offsets of the cell groups.
    function grid(view) {
        const xs = new Set(), ys = new Set();
        (function walk(item, ox, oy) {
            for (const it of (item.items || [])) {
                const x = ox + (it.x || 0), y = oy + (it.y || 0);
                if (it.mark && it.mark.marktype === 'group' && it.mark.name === 'cell') {
                    xs.add(Math.round(x)); ys.add(Math.round(y));
                }
                walk(it, it.marktype === 'group' || (it.mark && it.mark.marktype === 'group') ? x : ox,
                    it.marktype === 'group' || (it.mark && it.mark.marktype === 'group') ? y : oy);
            }
        })(view.scenegraph().root, 0, 0);
        return {cols: xs.size, rows: ys.size};
    }
    const canvasWidth = id => document.querySelector('#' + id + ' canvas').clientWidth;
    const info = id => (AoV._computedWidths || {})[id];

    try {
        const ids = ['fwr-sized', 'fwr-fit', 'fwr-plain', 'fwr-explicit', 'fwr-indep'];
        for (const id of ids) await ready(id);
        await settle();

        // Authored 170px panels: about seven fit in 1450px (196px each), in three rows.
        for (const id of ['fwr-sized', 'fwr-plain']) {
            const g = grid(AoV.views[id]);
            check(info(id) && info(id).kind === 'wrap', id + ': not wrapped by the runtime: ' + JSON.stringify(info(id)));
            check(g.cols >= 6 && g.cols <= 7, id + ': ' + g.cols + ' panels per row (expected 6-7)');
            check(g.rows === Math.ceil(17 / g.cols), id + ': ' + g.rows + ' rows for ' + g.cols + ' columns');
            check(canvasWidth(id) <= 1452, id + ': rendered ' + canvasWidth(id) + 'px in a 1450px container');
            check(canvasWidth(id) > 1100, id + ': rendered only ' + canvasWidth(id) + 'px of 1450px');
            check(AoV._origSpecs[id].columns === 4, id + ': the spec lost its static count');
        }
        // Container-sized: 200px default panels decide the count, then the cells
        // stretch to fill the row.
        const fitGrid = grid(AoV.views['fwr-fit']);
        check(fitGrid.cols >= 5 && fitGrid.cols <= 6, 'fwr-fit: ' + fitGrid.cols + ' panels per row (expected 5-6)');
        check(canvasWidth('fwr-fit') <= 1452 && canvasWidth('fwr-fit') > 1250,
            'fwr-fit: rendered ' + canvasWidth('fwr-fit') + 'px, not filling 1450px');
        // An authored count stays: three columns, never sized by the runtime.
        const explicitGrid = grid(AoV.views['fwr-explicit']);
        check(explicitGrid.cols === 3 && explicitGrid.rows === 6, 'fwr-explicit: grid ' + JSON.stringify(explicitGrid));
        check(!info('fwr-explicit'), 'fwr-explicit: the runtime re-wrapped an authored count');
        // Independent y axes give every panel its own axis: the first paint
        // overshoots the estimate and the correction drops columns once.
        const corr = (AoV._corrections || {})['fwr-indep'];
        check(corr && corr.cols >= 1, 'fwr-indep: no column correction: ' + JSON.stringify(corr));
        check(canvasWidth('fwr-indep') <= 1452, 'fwr-indep: rendered ' + canvasWidth('fwr-indep') + 'px in 1450px');

        // A narrower container re-wraps the sized plot; a few px less does not
        // (same count, so no re-embed and the legend selection would survive).
        // Headless virtual time delivers no ResizeObserver notification after
        // load, so call `_resizeReembed` the way the observer does.
        const before = AoV.views['fwr-sized'];
        document.getElementById('wrap-fwr-sized').style.width = '800px';
        check(AoV._resizeReembed('fwr-sized') === true, 'fwr-sized: did not re-wrap at 800px');
        await ready('fwr-sized', before);
        await settle();
        const narrow = grid(AoV.views['fwr-sized']);
        check(narrow.cols >= 3 && narrow.cols <= 4, 'fwr-sized at 800px: ' + narrow.cols + ' panels per row');
        check(canvasWidth('fwr-sized') <= 802, 'fwr-sized at 800px: rendered ' + canvasWidth('fwr-sized') + 'px');
        document.getElementById('wrap-fwr-sized').style.width = '795px';
        check(AoV._resizeReembed('fwr-sized') === false, 'fwr-sized: re-embedded for an unchanged count');
        const explicitView = AoV.views['fwr-explicit'];
        document.getElementById('wrap-fwr-explicit').style.width = '800px';
        check(AoV._resizeReembed('fwr-explicit') === false, 'fwr-explicit: re-embedded on resize');
        check(AoV.views['fwr-explicit'] === explicitView, 'fwr-explicit: view replaced on resize');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-facet-wrap-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
