(async function () {
    const failures = [], metrics = [];
    let checks = 0;
    const check = (ok, msg) => { checks++; if (!ok) failures.push(msg); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    const ids = ['canvas', 'svg'].flatMap(r => [2, 4, 6].flatMap(n =>
        [false, true].map(l => `fw-${n}-${l}-${r}`)));
    async function settle(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views[id] && !AoV._inFlight[id]) {
                await pause(80);
                if (!AoV._inFlight[id]) return;
            }
            await pause(10);
        }
        throw new Error(id + ': embed did not settle');
    }
    function inspect(id, label, fit = true) {
        const el = document.getElementById(id), view = AoV.views[id];
        const room = el.parentElement.clientWidth, width = el.querySelector('.marks').clientWidth;
        const n = id.startsWith('fw-2-') ? 2 : id.startsWith('fw-4-') ? 4 : 6;
        const panels = new Set(AoV._origSpecs[id].data.values.map(row => row.panel));
        const headings = [], legends = [], cells = [], strayAxes = [];
        const origin = view.origin()[0] + view.padding().left;
        function walk(mark, x, cell) {
            if (mark.marktype === 'group') {
                for (const item of mark.items || []) {
                    let current = cell;
                    if (mark.name === 'cell') { current = {xAxes: 0}; cells.push(current); }
                    if (mark.role === 'legend') legends.push(x + item.bounds.x2);
                    for (const child of item.items || []) walk(child, x + (item.x || 0), current);
                }
            } else if (mark.marktype === 'text') {
                for (const item of mark.items || []) if (mark.role === 'axis-title' && item.text === 'Dose (mg)') {
                    if (cell) cell.xAxes++; else strayAxes.push(item);
                }
                for (const item of mark.items || []) if (panels.has(item.text)) {
                    headings.push(item.text);
                    if (fit) check(x + item.bounds.x1 >= -2 && x + item.bounds.x2 <= room + 2,
                        label + ': full heading lies outside the frame: ' + item.text);
                }
            }
        }
        walk(view.scenegraph().root, origin, null);
        check(cells.length === n, label + ': expected ' + n + ' real panels, got ' + cells.length);
        check(cells.every(c => c.xAxes > 0), label + ': a panel has no x axis');
        check(strayAxes.length === 0, label + ': x axes outside occupied panels: ' + strayAxes.length);
        check(new Set(headings).size === n, label + ': missing full headings: ' + headings);
        const vg = AoV._results[id].vgSpec;
        const sharedX = vg.scales.find(s => s.name === 'x');
        check(sharedX?.type === 'log', label + ': shared log x scale lost');
        // The interval drawing pads its domain for dodged points. Axis
        // resolution must leave the one shared scale's definition unchanged.
        const reference = structuredClone(AoV._results[id].spec);
        reference.resolve.axis.x = 'shared';
        const originalX = vegaLite.compile(reference).spec.scales.find(s => s.name === 'x');
        check(JSON.stringify(sharedX) === JSON.stringify(originalX), label + ': shared dose scale changed');
        if (fit) {
            check(width <= room, label + ': ' + width + 'px exceeds ' + room + 'px');
            check(el.scrollWidth <= el.clientWidth, label + ': plot scrolls');
            check(el.parentElement.scrollWidth <= room, label + ': frame scrolls');
            check(legends.every(right => right <= room + 2), label + ': legend outside frame');
            check(AoV._computedWidths[id].width >= 100, label + ': plot area below readable minimum');
        }
        metrics.push({id, label, width, room, cells: cells.length, columns: AoV._computedWidths[id]?.nCols});
    }
    try {
        for (const id of ids.concat(['fw-explicit', 'fw-fixed'])) await settle(id);
        ids.forEach(id => inspect(id, 'initial ' + id));
        for (const id of ['fw-4-true-canvas', 'fw-6-true-svg']) {
            const h = wrapFits[id];
            check(h.some((p, i) => i && p.cols < h[i - 1].cols), id + ': never reflowed after shrinking');
            check(h.length <= 12, id + ': too many correction renders: ' + JSON.stringify(h));
            check(h.every((p, i) => !i || p.cols < h[i - 1].cols ||
                (p.cols === h[i - 1].cols && p.width < h[i - 1].width)), id + ': fit oscillated');
        }
        inspect('fw-explicit', 'explicit count', false);
        inspect('fw-fixed', 'authored width and count', false);
        check(AoV._computedWidths['fw-explicit'].nCols === 4, 'explicit column count changed');
        check(!AoV._computedWidths['fw-fixed'], 'authored geometry was fitted');

        const id = 'fw-6-true-svg';
        for (const theme of ['dark', 'light']) {
            document.documentElement.dataset.theme = theme;
            AoV.refreshTheme(); await settle(id); inspect(id, theme);
        }
        for (const drawing of ['ribbons', 'intervals']) {
            document.querySelector(`[data-aov-ribbon-view-for="${id}"][data-view="${drawing}"]`).click();
            await settle(id); inspect(id, drawing);
        }
        for (const room of [720, 1600, 1040]) {
            document.getElementById('column-' + id).style.width = room + 'px';
            AoV._resizeReembed(id); await settle(id); inspect(id, 'resize ' + room);
        }
        const previous = wrapFits[id].length, last = JSON.stringify(wrapFits[id].at(-1));
        AoV._resizeReembed(id); await settle(id);
        check(wrapFits[id].length === previous + 1 && JSON.stringify(wrapFits[id].at(-1)) === last,
            'unchanged width lost its settled columns or restarted correction');
    } catch (error) { failures.push(error.stack || String(error)); }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-wrap-results';
    result.textContent = JSON.stringify({checks, failures, metrics});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
