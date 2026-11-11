// Heatmap cell browser checks: each drawn cell spans Makie's edges for its
// value (read back through the plot's scales), cells are coloured by their
// value and stroked in it so no page background shows between them, a
// highlight drops the dimmed cells' stroke, a faceted figure edges each
// panel's grid, `updateData` re-edges the new rows, and the dataset keeps the
// rows as given.
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
    // Each cell's box in view coordinates, cut to the frame of the group that
    // holds it (the plot, or a facet panel), as the mark's clip cuts it.
    function framedCells(view) {
        const out = [];
        (function walk(mark, ox, oy, frame) {
            (mark.items || []).forEach(it => {
                if (mark.marktype === 'rect' && mark.role === 'mark') {
                    out.push({x0: Math.max(ox + it.x, frame.x0), y0: Math.max(oy + it.y, frame.y0),
                        x1: Math.min(ox + it.x + it.width, frame.x1), y1: Math.min(oy + it.y + it.height, frame.y1), frame});
                } else if (mark.marktype === 'group') {
                    const gx = ox + (it.x || 0), gy = oy + (it.y || 0);
                    const f = it.width && it.height ? {x0: gx, y0: gy, x1: gx + it.width, y1: gy + it.height} : frame;
                    (it.items || []).forEach(m => walk(m, gx, gy, f));
                }
            });
        })(view.scenegraph().root, 0, 0, {x0: -Infinity, y0: -Infinity, x1: Infinity, y1: Infinity});
        return out;
    }
    // How much page background shows inside the cells, drawn at `scale` device
    // pixels per px on a transparent background: the worst pixel's share and
    // the share of pixels that are not opaque. Each panel is the union of its
    // cells, 2 device px in from its edges.
    async function background(view, scale) {
        const canvas = await view.toCanvas(scale), pad = view.padding();
        const ox = view._origin[0] + (pad.left || 0), oy = view._origin[1] + (pad.top || 0);
        const px = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
        const panels = new Map();
        framedCells(view).forEach(b => {
            const p = panels.get(b.frame) || {x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity};
            panels.set(b.frame, {x0: Math.min(p.x0, b.x0), y0: Math.min(p.y0, b.y0), x1: Math.max(p.x1, b.x1), y1: Math.max(p.y1, b.y1)});
        });
        let n = 0, open = 0, minAlpha = 255;
        panels.forEach(p => {
            for (let y = Math.ceil((p.y0 + oy) * scale) + 2; y < Math.floor((p.y1 + oy) * scale) - 2; y++)
                for (let x = Math.ceil((p.x0 + ox) * scale) + 2; x < Math.floor((p.x1 + ox) * scale) - 2; x++) {
                    const a = px[(y * canvas.width + x) * 4 + 3];
                    n++; if (a < 255) open++; if (a < minAlpha) minAlpha = a;
                }
        });
        return {pixels: n, worst: 1 - minAlpha / 255, share: open / Math.max(n, 1)};
    }
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
        // The value is in each cell's tooltip under its label, formatted by Vega ("−50").
        cells.forEach(c => check(c.tooltip && Number(String(c.tooltip['Field value']).replace('−', '-')) === c.datum.value,
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

        // Seamless cells (snag draw-a-numeric-h-450a4bc9): each cell is stroked
        // in its own colour, under the fill's one colour bar.
        cells.forEach(c => check(c.stroke === c.fill && c.strokeWidth === 1.5,
            'grid: cell ' + c.datum.east + ',' + c.datum.north + ' stroke ' + c.stroke + '/' + c.strokeWidth + ', fill ' + c.fill));
        let legends = 0;
        (function walk(node) {
            if (node.role === 'legend') legends += (node.items || []).length;
            (node.items || []).forEach(walk);
        })(grid.scenegraph().root);
        check(legends === 1, 'grid: expected one legend, got ' + legends);
        // No page background between cells, measured on a transparent background
        // at the device scales of an ordinary and a high-density screen. The
        // control is the same plot with `strokeWidth=0`, which must show the
        // seams (about a quarter of the background in the worst pixel).
        const control = await ready('bare');
        check(cellsOf(control).every(c => !c.stroke), 'bare: strokeWidth=0 still strokes its cells');
        for (const scale of [1, 2]) {
            const seams = await background(control, scale), stroked = await background(grid, scale);
            check(seams.pixels > 10000 && seams.worst > 0.15,
                'bare at scale ' + scale + ': the probe saw no seams without the stroke: ' + JSON.stringify(seams));
            check(stroked.pixels > 10000 && stroked.worst <= (scale === 1 ? 0.02 : 0),
                'grid at scale ' + scale + ': page background shows between cells: ' + JSON.stringify(stroked));
        }
        const facets = await background(await ready('panels'), 1);
        check(facets.pixels > 10000 && facets.worst <= 0.02, 'panels: page background shows between cells: ' + JSON.stringify(facets));

        // A highlight dims the other cells' fill and drops their stroke, whose
        // overlap with the neighbours would otherwise draw the lattice again.
        // An undimmed cell has no opacity of its own (null), which `< 1` would read as 0.
        const bright = c => c.opacity == null || c.opacity >= 1;
        AoV.highlight('grid', {east: 50, north: 50});
        for (let i = 0; i < 100 && cellsOf(grid).every(bright); i++) await pause();
        cellsOf(grid).forEach(c => {
            const lit = c.datum.east === 50 && c.datum.north === 50;
            check(lit ? c.strokeOpacity !== 0 && bright(c) : c.strokeOpacity === 0 && !bright(c),
                'grid: highlighted ' + lit + ' cell ' + c.datum.east + ',' + c.datum.north +
                ' has opacity ' + c.opacity + ', stroke opacity ' + c.strokeOpacity);
        });
        AoV.clearHighlight('grid');
        for (let i = 0; i < 100 && !cellsOf(grid).every(bright); i++) await pause();
        check(cellsOf(grid).every(c => c.strokeOpacity !== 0 && bright(c)),
            'grid: cleared highlight left cells dimmed or unstroked');

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
