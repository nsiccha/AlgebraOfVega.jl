// Per-column Y scale browser checks: `col=`-only and row × column figures
// embed with one Y scale type per column, a reference layer without the
// column field reaches every column, and the figures stay valid through
// channel-picker remaps — colour, and a row facet added or cleared.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function items(view, predicate) {
        const out = [];
        (function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const uniq = xs => [...new Set(xs)];
    const points = view => items(view, i => i.mark?.marktype === 'symbol' && i.datum && i.datum.p !== undefined);
    const rowLabels = view => uniq(items(view, i => i.mark?.marktype === 'text' && /^R[12]$/.test(i.text)).map(i => i.text)).sort();
    const hlines = view => items(view, i => i.mark?.marktype === 'rule' && i.datum && i.datum.y0 !== undefined);
    function perColumn(marks) {
        const counts = {};
        marks.forEach(i => { counts[i.datum.p] = (counts[i.datum.p] || 0) + 1; });
        return JSON.stringify(Object.keys(counts).sort().map(k => [k, counts[k]]));
    }
    function figure(id, view, label) {
        // hconcat child 0 is P1 (log), child 1 is P2 (linear).
        const types = ['concat_0_y', 'concat_1_y'].map(n => { try { return view.scale(n).type; } catch (e) { return null; } });
        check(types[0] === 'log' && types[1] === 'linear',
            label + ' ' + id + ': y scale types ' + JSON.stringify(types) + ', expected ["log","linear"]');
        check(points(view).length === 12, label + ' ' + id + ': ' + points(view).length + ' points, expected 12');
    }
    async function remap(id, mapping, previous) {
        AoV.remapEncoding(id, mapping);
        return ready(id, previous);
    }

    try {
        const ids = ['pc-single', 'pc-layered', 'pc-positional', 'pc-picker'];
        let view;
        for (const id of ids) {
            view = await ready(id);
            figure(id, view, 'embed');
            check(rowLabels(view).length === 0, id + ': unexpected row headers ' + JSON.stringify(rowLabels(view)));
        }
        // The positional-Scales figure keeps its colour and its legend selection.
        view = AoV.views['pc-positional'];
        check(uniq(points(view).map(i => i.fill)).length === 2,
            'pc-positional: scatter fills ' + JSON.stringify(uniq(points(view).map(i => i.fill))));
        check(Object.keys(view.getState().signals).some(k => k.startsWith('legend_selection')),
            'pc-positional: no legend selection signal');

        // Picker remaps re-lower the figure to valid specs.
        const id = 'pc-picker';
        view = AoV.views[id];
        check(uniq(points(view).map(i => i.fill)).length === 1, id + ': scatter starts uncoloured');
        view = await remap(id, {color: 'g'}, view);
        figure(id, view, 'colour remap');
        check(uniq(points(view).map(i => i.fill)).length === 2,
            id + ': colour remap did not colour the scatter ' + JSON.stringify(uniq(points(view).map(i => i.fill))));
        view = await remap(id, {row: 'r'}, view);
        figure(id, view, 'row remap');
        check(JSON.stringify(rowLabels(view)) === '["R1","R2"]', id + ': row remap headers ' + JSON.stringify(rowLabels(view)));
        view = await remap(id, {row: ''}, view);
        figure(id, view, 'row cleared');
        check(rowLabels(view).length === 0, id + ': cleared row still shows headers ' + JSON.stringify(rowLabels(view)));

        // A reference line without either facet field reaches every cell:
        // one per (row, column) cell, as in the plain facet form.
        view = await ready('pc-colonly-ref');
        figure('pc-colonly-ref', view, 'embed');
        check(perColumn(hlines(view)) === '[["P1",1],["P2",1]]',
            'pc-colonly-ref: hlines per column ' + perColumn(hlines(view)));
        view = await ready('pc-rowcol-ref');
        figure('pc-rowcol-ref', view, 'embed');
        check(JSON.stringify(rowLabels(view)) === '["R1","R2"]', 'pc-rowcol-ref: row headers ' + JSON.stringify(rowLabels(view)));
        check(hlines(view).length === 4, 'pc-rowcol-ref: ' + hlines(view).length + ' hlines, expected 4');
        check(perColumn(hlines(view)) === '[["P1",2],["P2",2]]',
            'pc-rowcol-ref: hlines per column ' + perColumn(hlines(view)));

        // An authored row × column picker figure clears and restores its row
        // facet; each step re-embeds a valid spec.
        const rc = 'pc-rowcol-picker';
        view = await ready(rc);
        figure(rc, view, 'embed');
        check(JSON.stringify(rowLabels(view)) === '["R1","R2"]', rc + ': row headers ' + JSON.stringify(rowLabels(view)));
        view = await remap(rc, {row: ''}, view);
        figure(rc, view, 'row cleared');
        check(rowLabels(view).length === 0, rc + ': cleared row still shows headers ' + JSON.stringify(rowLabels(view)));
        view = await remap(rc, {row: 'r'}, view);
        figure(rc, view, 'row restored');
        check(JSON.stringify(rowLabels(view)) === '["R1","R2"]', rc + ': restored row headers ' + JSON.stringify(rowLabels(view)));
        view = await remap(rc, {color: 'g'}, view);
        figure(rc, view, 'colour remap');
        check(uniq(points(view).map(i => i.fill)).length === 2,
            rc + ': colour remap did not colour the scatter ' + JSON.stringify(uniq(points(view).map(i => i.fill))));
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-per-column-y-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
