(async function () {
    const failures = [];
    const errors = [];
    const warnings = [];
    const originalError = console.error;
    const originalWarn = console.warn;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    console.warn = (...args) => { warnings.push(args.map(String).join(' ')); originalWarn(...args); };
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const fixture = window.AOV_FIXTURE;
    const send = name => (0, eval)(fixture.updates[name]);
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    async function settle(id) {
        for (let i = 0; i < 20; i++) await pause();
        return ready(id);
    }
    // Drawn path-mark items (one per datum) by mark type and scenario.
    function drawn(view) {
        const out = {};
        (function walk(item) {
            const type = item.mark?.marktype;
            if ((type === 'area' || type === 'line') && item.datum?.scenario !== undefined) {
                const k = type + ':' + item.datum.scenario;
                out[k] = (out[k] || 0) + 1;
            }
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const cells = view => {
        const out = [];
        (function walk(item) {
            if (item.mark?.role === 'scope' && item.mark?.name === 'cell') out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    };
    const rowsOf = (view, s) => view.data('source_0').filter(r => r.scenario === s);
    // Parameter names declared anywhere in a spec.
    function params(spec) {
        const names = [];
        (function walk(v) {
            if (Array.isArray(v)) return v.forEach(walk);
            if (!v || typeof v !== 'object') return;
            (Array.isArray(v.params) ? v.params : []).forEach(p => names.push(p.name));
            Object.keys(v).forEach(k => { if (k !== 'values') walk(v[k]); });
        })(spec);
        return names.sort();
    }
    const near = (a, b) => Math.abs(a - b) < 1e-9;

    try {
        // --- A raw-row plot (Band + Lines): one group's rows swapped in place.
        let id = 'rk-plain';
        let view = await ready(id);
        let d = drawn(view);
        check(d['area:A'] === 5 && d['area:B'] === 5 && d['line:A'] === 5 && d['line:B'] === 5, 'plain: initial bands');
        const plainA = rowsOf(view, 'A');
        send('plain_B');
        await view.runAsync();
        check(AoV.views[id] === view, 'plain replace: same view');
        check(view.data('source_0').length === 10, 'plain replace: 10 rows');
        check(rowsOf(view, 'A').every((r, i) => r === plainA[i]), 'plain replace: A tuples untouched');
        check(rowsOf(view, 'B').length === 5 && rowsOf(view, 'B').every(r => r.lower === 9 && r.upper === 11),
            'plain replace: B rows replaced');
        check(AoV._liveRows[id].source_0.length === 10, 'plain replace: kept for re-embeds');
        // A responsive re-embed compiles with the kept rows.
        AoV._embed(id, AoV._origSpecs[id], AoV._embedOpts[id], true);
        view = await ready(id, view);
        check(view.data('source_0').length === 10 && rowsOf(view, 'B').every(r => r.lower === 9) &&
            rowsOf(view, 'A').every(r => r.lower === -1), 'plain re-embed: replaced rows kept');

        // --- Sent before its plot embedded: applied once ready.
        id = 'rk-queued';
        view = await ready(id);
        check(view.data('source_0').length === 10, 'queued replace: 10 rows');
        check(rowsOf(view, 'B').every(r => r.lower === 9) && rowsOf(view, 'A').every(r => r.lower === -1),
            'queued replace: applied to B only');

        // --- Faceted coloured lineribbon: a new group gets its layers.
        id = 'rk-ribbon';
        view = await ready(id);
        check(cells(view).length === 2, 'ribbon: two panels');
        d = drawn(view);
        check(d['area:A'] === 10 && d['area:B'] === 10 && !d['area:C'], 'ribbon: initial groups');
        const paramsBefore = params(AoV._cur[id].spec);
        const ribbonA = rowsOf(view, 'A');
        send('ribbon_C1');
        let next = await ready(id, view);
        check(next !== view, 'ribbon new group: re-embedded');
        view = next;
        d = drawn(view);
        check(d['area:C'] === 10 && d['line:C'] === 10, 'ribbon new group: C drawn in both panels');
        check(d['area:A'] === 10 && d['area:B'] === 10, 'ribbon new group: A and B still drawn');
        check(view.scale('color').domain().join() === 'A,B,C', 'ribbon new group: legend lists C');
        check(JSON.stringify(params(AoV._cur[id].spec)) === JSON.stringify(paramsBefore),
            'ribbon new group: parameters not duplicated ' + params(AoV._cur[id].spec));
        const groups = (AoV._cur[id].spec.spec.layer || []).filter(l => l._lr_layer).map(l => l._lr_group);
        check(groups.join() === 'A,A,B,B,C,C', 'ribbon new group: layers in group order ' + groups);
        // A later stage of the same group: data swapped in place.
        const ribbonB = rowsOf(view, 'B');
        send('ribbon_C2');
        await view.runAsync();
        check(AoV.views[id] === view, 'ribbon next stage: same view');
        check(rowsOf(view, 'C').length === 10 && rowsOf(view, 'C').every(r => r.lower === 6),
            'ribbon next stage: C replaced');
        check(rowsOf(view, 'B').every((r, i) => r === ribbonB[i]), 'ribbon next stage: B tuples untouched');
        check(rowsOf(view, 'A').length === ribbonA.length && view.data('source_0').length === 30,
            'ribbon next stage: 30 rows');
        // A composite key replaces one panel of the group.
        send('ribbon_Cp1');
        await view.runAsync();
        const c = rowsOf(view, 'C');
        check(c.length === 10 && c.filter(r => r.panel === 'p1').every(r => r.lower === 7) &&
            c.filter(r => r.panel === 'p2').every(r => r.lower === 6), 'composite key: one panel replaced');
        check(drawn(view)['area:C'] === 10, 'composite key: C still drawn');

        // --- Empty coloured lineribbon: groups arrive one by one.
        id = 'rk-empty';
        view = await ready(id);
        check(Object.keys(drawn(view)).length === 0, 'empty: nothing drawn');
        check(AoV._cur[id].spec.layer.every(l => l._lr_proto), 'empty: template layers');
        const emptyParams = params(AoV._cur[id].spec);
        send('empty_A');
        view = await ready(id, view);
        d = drawn(view);
        check(d['area:A'] === 5 && d['line:A'] === 5, 'empty first group: A drawn');
        check(!AoV._cur[id].spec.layer.some(l => l._lr_proto), 'empty first group: template layers replaced');
        check(params(AoV._cur[id].spec).filter(n => n === 'grid').length ===
            emptyParams.filter(n => n === 'grid').length, 'empty first group: zoom binding kept');
        send('empty_B');
        view = await ready(id, view);
        d = drawn(view);
        check(d['area:A'] === 5 && d['area:B'] === 5, 'empty second group: A and B drawn');
        send('empty_A2');
        await view.runAsync();
        check(AoV.views[id] === view, 'empty next stage: same view');
        check(rowsOf(view, 'A').every(r => r.lower === 0) && rowsOf(view, 'B').every(r => r.lower === 2),
            'empty next stage: A replaced, B kept');
        // append_data brings a group too.
        send('empty_append_C');
        view = await ready(id, view);
        d = drawn(view);
        check(d['area:C'] === 5 && d['area:A'] === 5 && d['area:B'] === 5, 'append new group: drawn');
        // A re-facet onto the same colour field keeps the groups rows brought.
        AoV.remapEncoding(id, {color: 'scenario'});
        view = await ready(id, view);
        d = drawn(view);
        check(d['area:A'] === 5 && d['area:B'] === 5 && d['area:C'] === 5, 'remap after live groups: all drawn');
        check(view.scale('color').domain().join() === 'A,B,C', 'remap after live groups: legend');

        // --- A lowered dataset refuses raw rows.
        id = 'rk-interval';
        view = await ready(id);
        const intervalRows = AoV._plotData(id).length;
        const before = errors.length;
        send('interval_raw');
        await view.runAsync();
        check(errors.length === before + 1 && /replaceData/.test(errors[before] || '') &&
            /update_spec/.test(errors[before] || ''), 'lowered: refused with an update_spec pointer');
        check(AoV._plotData(id).length === intervalRows, 'lowered: data left unchanged');

        // --- A ribbon layered with other layers: a new group is not drawn, and said so.
        id = 'rk-layered';
        view = await ready(id);
        const warned = warnings.filter(w => /layered lineribbon/.test(w)).length;
        send('layered_C');
        await view.runAsync();
        const w = warnings.filter(w => /layered lineribbon/.test(w));
        check(w.length === warned + 1 && /group\(s\) C /.test(w[w.length - 1]) && /update_spec/.test(w[w.length - 1]),
            'layered ribbon new group: warned with an update_spec pointer');
        d = drawn(view);
        check(d['area:A'] === 5 && d['area:B'] === 5 && !d['area:C'], 'layered ribbon new group: A and B kept, C not drawn');
        check(AoV._plotData(id).length === 15, 'layered ribbon new group: rows kept');

        check(errors.length === 1, 'unexpected runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
        console.warn = originalWarn;
        ['rk-plain', 'rk-queued', 'rk-ribbon', 'rk-empty', 'rk-interval', 'rk-layered'].forEach(id => AoV.dispose(id));
    }
    const result = document.createElement('pre');
    result.id = 'aov-replace-data-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
