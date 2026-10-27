// Cell charts in the browser: the cells of a column share one scale (equal
// values draw equal bars in every row), a column with unlinked y axes fits
// each cell to its own rows, the cells show no axes or legend and the AoV
// tooltip, cells far below the viewport are drawn while the browser is idle
// (printing takes the rest at once), each cell's view holds only its own
// rows, a cell that leaves the page releases its view, and every chart of a
// column starts at the same x whatever its total's width (each total sits
// in a slot as wide as the column's widest: snag cell-charts-tota-b5b30921).
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms || 10));
    const cellsIn = sel => Array.from(document.querySelectorAll(sel + ' .aov-cell'));
    // Drawn: the cell's view exists and its bars are in the page (one SVG path per bar).
    const isDrawn = el => !!(AoV._cellViews && AoV._cellViews.has(el) && el.querySelectorAll('svg path').length >= 3);
    async function drawn(els, what) {
        for (let i = 0; i < 500; i++) {
            if (els.every(isDrawn)) return els.map(el => AoV._cellViews.get(el).view);
            await pause();
        }
        throw new Error(what + ': ' + els.filter(el => !isDrawn(el)).length + ' of ' + els.length + ' cells not drawn');
    }
    // A cell's bars: category → pixel height.
    function bars(view) {
        const out = {};
        (function walk(item) {
            if (item.mark && item.mark.marktype === 'rect' && item.mark.role === 'mark' && item.datum)
                out[item.datum.klasse] = item.height;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    function roles(view) {
        const out = new Set();
        (function walk(item) {
            if (item.mark) out.add(item.mark.role);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const near = (a, b) => Math.abs(a - b) < 0.5;
    // Each cell column of a table (its cells' column id): where its charts
    // start, where its totals' texts end, the totals' text widths, and the
    // room left before the widest total's text in its slot.
    function columns(sel) {
        const byId = {};
        document.querySelectorAll(sel + ' td.aov-cells').forEach(td => {
            const id = td.querySelector('.aov-cell').getAttribute('data-aov-cells');
            (byId[id] = byId[id] || []).push(td);
        });
        return Object.keys(byId).map(id => {
            const tds = byId[id], totals = tds.map(td => td.querySelector('.aov-cell-total'));
            const text = totals.map(t => { const r = document.createRange(); r.selectNodeContents(t); return r.getBoundingClientRect(); });
            return {id, texts: totals.map(t => t.textContent),
                chartX: tds.map(td => td.querySelector('.aov-cell').getBoundingClientRect().left),
                textRight: text.map(r => r.right), textWidth: text.map(r => r.width),
                slack: Math.min(...totals.map((t, i) => text[i].left - t.getBoundingClientRect().left))};
        });
    }
    const spread = xs => Math.max(...xs) - Math.min(...xs);
    const isAligned = c => spread(c.chartX) < 0.5 && spread(c.textRight) < 0.5 && c.slack > -0.5 && c.slack < 1;
    // Every chart of a column starts at one x, the totals are right-aligned
    // against them, and the slot is as wide as the widest total, no wider.
    async function aligned(sel, what) {
        let cols = [];
        for (let i = 0; i < 100; i++) {
            cols = columns(sel);
            if (cols.length && cols.every(isAligned)) break;
            await pause();
        }
        check(cols.length > 0, what + ': no cell columns');
        cols.forEach(c => check(isAligned(c), what + ', column ' + c.id + ': ' + JSON.stringify(c)));
        return cols;
    }
    try {
        // Near the viewport: every cell of both columns is drawn.
        const shared = await drawn(cellsIn('#near'), 'shared column');
        const own = await drawn(cellsIn('#own-table'), 'own-axis column');
        const ys = shared.map(v => JSON.stringify(v.scale('y').domain()));
        check(new Set(ys).size === 1 && shared[0].scale('y').domain()[1] >= 9,
            'shared y domains: ' + ys.join(' '));
        const xs = shared.map(v => JSON.stringify(v.scale('x').domain()));
        check(new Set(xs).size === 1 && xs[0] === JSON.stringify(['200–499', '500–999', '1000–2499']),
            'shared x domains: ' + xs.join(' '));
        // Rows 11001, 11002, 11003: n = 3 and 9 in the first class, all zero in the last row.
        const b1 = bars(shared[0]), b2 = bars(shared[1]), b3 = bars(shared[2]);
        check(b1['200–499'] > 0 && near(b2['200–499'], 3 * b1['200–499']),
            'bars on one scale: ' + JSON.stringify([b1, b2]));
        check(Object.keys(b3).length === 3 && Object.values(b3).every(h => near(h, 0)),
            'a row of zeros draws flat bars: ' + JSON.stringify(b3));
        const svg = cellsIn('#near')[0].querySelector('svg');
        check(svg && +svg.getAttribute('width') === 120 && +svg.getAttribute('height') === 24,
            'cell size: ' + (svg && svg.getAttribute('width') + 'x' + svg.getAttribute('height')));
        const r = roles(shared[0]);
        check(!r.has('axis') && !r.has('legend') && !r.has('axis-domain'), 'chrome drawn: ' + Array.from(r).join(','));
        // Unlinked y: each cell fits its own rows.
        const own1 = own[0].scale('y').domain()[1], own2 = own[1].scale('y').domain()[1];
        check(own1 < own2 && own2 >= 9, 'own y domains: ' + own1 + ' ' + own2);
        check(JSON.stringify(own[0].scale('x').domain()) === xs[0], 'own x domain stays shared');

        // Totals of different widths ("8,3 Tsd. m²", "380 Tsd. m²", "1,2 Mio. m²"):
        // each column's charts still start at one x (snag cell-charts-tota-b5b30921).
        await aligned('#near', 'near table');
        const area = await aligned('#area-table', 'area table');
        const geschoss = area.find(c => c.texts.some(t => t.indexOf('m²') !== -1));
        check(geschoss && spread(geschoss.textWidth) > 5, 'area totals of different widths: ' + JSON.stringify(geschoss));
        // A table laid out only later (a closed tab opened) gets its slots then.
        // Its totals' ResizeObserver measures it; headless virtual time
        // delivers no ResizeObserver notification after load (test/fit_width.js),
        // so the driver measures as the observer does.
        document.getElementById('hidden-table').style.display = '';
        AoV._cellAlignSoon();
        await aligned('#hidden-table', 'table shown later');

        // The tooltip every AoV plot shows, one handler for every cell.
        const handler = await AoV._cellTip;
        check(typeof handler === 'function' && shared.every(v => v.tooltip() === handler),
            'cells take the AoV tooltip');

        // Far below the viewport: drawn while the browser is idle, on the
        // scale of its column (the first column again, and one of its own).
        const far = await drawn(cellsIn('#far-table'), 'far cells');
        check(JSON.stringify(far[1].scale('y').domain()) === ys[0], 'far cells share the column scale');
        const late = await drawn(cellsIn('#late-table'), 'late cells');
        check(new Set(late.map(v => JSON.stringify(v.scale('y').domain()))).size === 1, 'late cells share their scale');
        // Each cell's view holds only its own rows.
        check(far.every(v => v.data('source_0').length === 3), 'cell rows: ' + far.map(v => v.data('source_0').length));

        // A cell added after load and printed at once is taken off the idle queue by printing.
        const row = document.getElementById('row-11002-1').cloneNode(true);
        row.id = 'row-added';
        const added = row.querySelector('.aov-cell');
        added.innerHTML = '';
        row.querySelectorAll('script').forEach(sc => sc.remove());
        // Its total is wider than the column's others: the column's slot grows.
        row.querySelector('.aov-cell-total').textContent = '12.345';
        document.getElementById('late-table').querySelector('tbody').appendChild(row);
        AoV.cell(added);
        window.dispatchEvent(new Event('beforeprint'));
        check(!AoV._cellPending.has(added), 'printing left a cell undrawn');
        const [a] = await drawn([added], 'added cell');
        check(near(bars(a)['200–499'], b2['200–499']), 'added cell draws its row: ' + JSON.stringify(bars(a)));
        await aligned('#late-table', 'row with a wider total added');

        // The row with a column's widest total leaves: the slot shrinks to the next widest.
        const widest = geschoss.textWidth.indexOf(Math.max(...geschoss.textWidth));
        document.querySelectorAll('#area-table td.aov-cells .aov-cell[data-aov-cells="' + geschoss.id + '"]')[widest]
            .closest('tr').remove();
        await pause(50);
        const after = (await aligned('#area-table', 'widest row removed')).find(c => c.id === geschoss.id);
        check(after && after.texts.length === geschoss.texts.length - 1, 'widest row removed: ' + JSON.stringify(after));

        // A row removed from the table releases its cell's view.
        const gone = cellsIn('#near')[0];
        document.getElementById('row-11001-1').remove();
        await pause(50);
        check(!AoV._cellViews.has(gone), 'a removed cell kept its view');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-cells-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
