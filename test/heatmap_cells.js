// Heatmap cell browser checks: each drawn cell spans Makie's edges for its
// value (read back through the plot's scales), cells are coloured by their
// value, a faceted figure edges each panel's grid, `updateData` re-edges the
// new rows, and the dataset keeps the rows as given.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 400; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // The drawn cells: the data rects (role "mark"), not legends or backgrounds.
    function cellsOf(view) {
        const out = [];
        (function walk(node) {
            if (node.marktype === 'rect' && node.role === 'mark') (node.items || []).forEach(i => out.push(i));
            (node.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const close = (a, b) => Math.abs(a - b) <= 1e-6 * Math.max(1, Math.abs(b));
    // Each cell's edges in data units against Makie's edges for its x and y.
    function edged(id, view, xEdges, yEdges, count) {
        const cells = cellsOf(view), xs = view.scale('x'), ys = view.scale('y');
        check(cells.length === count, id + ': expected ' + count + ' cells, got ' + cells.length);
        cells.forEach(c => {
            const d = c.datum, ex = xEdges[d.east], ey = yEdges[d.north];
            const x0 = xs.invert(c.x), x1 = xs.invert(c.x + c.width);
            const y1 = ys.invert(c.y), y0 = ys.invert(c.y + c.height);
            check(ex && close(x0, ex[0]) && close(x1, ex[1]),
                id + ': cell at east=' + d.east + ' spans x ' + [x0, x1] + ', expected ' + ex);
            check(ey && close(y0, ey[0]) && close(y1, ey[1]),
                id + ': cell at north=' + d.north + ' spans y ' + [y0, y1] + ', expected ' + ey);
        });
        return cells;
    }

    try {
        const grid = await ready('grid');
        const step = {0: [-25, 25], 50: [25, 75], 100: [75, 125]};
        const cells = edged('grid', grid, step, step, 9);
        // Coloured by value: one fill per distinct value, never Vega's default blue.
        const fillOf = {};
        cells.forEach(c => {
            const v = c.datum.value;
            check(fillOf[v] === undefined || fillOf[v] === c.fill, 'grid: value ' + v + ' drawn in two colours');
            fillOf[v] = c.fill;
        });
        const fills = new Set(Object.values(fillOf));
        check(fills.size === 5, 'grid: 5 values need 5 fills, got ' + JSON.stringify(fillOf));
        check(!fills.has('#4c78a8'), 'grid: a cell is drawn in the default blue');
        // The value is in each cell's tooltip, formatted by Vega ("−50").
        cells.forEach(c => check(c.tooltip && Number(String(c.tooltip.value).replace('−', '-')) === c.datum.value,
            'grid: tooltip lacks the value: ' + JSON.stringify(c.tooltip)));
        // A colour scale and its legend.
        let gradient = false;
        (function walk(node) {
            if (node.role === 'legend-gradient' || node.role === 'legend-band') gradient = true;
            (node.items || []).forEach(walk);
        })(grid.scenegraph().root);
        check(gradient, 'grid: no colour legend');
        // The rows stay as given: what a CSV download reads.
        const raw = grid.data('source_0');
        check(raw.length === 9 && raw.every(r => Object.keys(r).sort().join() === 'east,north,value'),
            'grid: source rows carry computed fields: ' + JSON.stringify(Object.keys(raw[0] || {})));

        edged('uneven', await ready('uneven'), {0: [-5, 5], 10: [5, 25], 40: [25, 55]},
            {0: [-0.5, 0.5], 1: [0.5, 1.5]}, 6);
        edged('single', await ready('single'), {5: [4.5, 5.5]}, {5: [4.5, 5.5]}, 1);
        // Two panels of nine cells each, beside the station points.
        edged('panels', await ready('panels'), step, step, 18);

        // Raw rows replace raw rows: the cells follow the new grid.
        const update = await ready('update');
        AoV.updateData('update', window.AOV_UPDATE_ROWS);
        for (let i = 0; i < 100 && cellsOf(AoV.views.update).length !== 6; i++) await pause();
        const after = {0: [-10, 10], 20: [10, 30], 40: [30, 50]};
        edged('update', AoV.views.update, after, {0: [-10, 10], 20: [10, 30]}, 6);
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-heatmap-cells-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
