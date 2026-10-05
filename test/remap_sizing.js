(async function () {
    const failures = [];
    const errors = [];
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id, previous) {
        for (let i = 0; i < 200; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function items(view, predicate) {
        const out = [];
        function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        }
        walk(view.scenegraph().root);
        return out;
    }
    function verify(id, view, count, cells) {
        const marks = items(view, i => i.mark?.marktype === 'symbol' && i.datum?.category);
        check(marks.length === count, id + ': expected ' + count + ' points, got ' + marks.length);
        check(marks.every(i => Number.isFinite(i.x) && Number.isFinite(i.y)), id + ': invalid positions');
        const panels = items(view, i => i.mark?.role === 'scope' && i.mark?.name === 'cell');
        if (cells) {
            check(panels.length === cells, id + ': wrong facet count ' + panels.length);
            check(panels.every(i => i.height === 140), id + ': cell height changed');
        } else {
            // Native autosize:"fit" includes the axes in the authored height;
            // the data rectangle can be smaller than that outer budget.
            check(AoV._results[id].spec.height === 140, id + ': authored flat height lost');
        }
        const svg = document.getElementById(id).querySelector('svg');
        check(svg && +svg.getAttribute('width') > 100 && +svg.getAttribute('height') > 100,
            id + ': rendered view collapsed');
        return marks;
    }
    try {
        const id = 'sizing-picker';
        let view = await ready(id);
        verify(id, view, 6, 2);
        const original = JSON.stringify(AoV._origSpecs[id]);
        const old = view;
        document.querySelector('input[type=radio][value=color]').click();
        const row = document.getElementById('aov-remap-row-' + id);
        [...row.options].forEach(o => o.selected = o.value === 'family');
        row.dispatchEvent(new Event('change', {bubbles: true}));
        view = await ready(id, old);
        const marks = verify(id, view, 6, 6);
        check(new Set(marks.map(i => i.datum.family + '/' + i.datum.metric)).size === 6,
            id + ': fixed metric columns or family rows lost');
        check(JSON.stringify(AoV._origSpecs[id]) === original, id + ': original spec mutated');
        const emitted = AoV._results[id].spec;
        check(emitted.resolve.scale.x === 'independent' && emitted.resolve.scale.y === 'independent',
            id + ': independent axes lost');
        check(emitted.spec.encoding.x.scale.type === 'log', id + ': log scale lost');
        const rows = AoV._plotData(id).map(r => ({...r}));
        const extra = ['P', 'Q'].map(metric =>
            ({value:6, category:'D', family:'F4', group:'G4', metric}));
        AoV.updateData(id, rows.concat(extra));
        await view.runAsync();
        verify(id, view, 8, 8);
        const beforeAppend = AoV._plotData(id).length;
        AoV.appendData(id, [{value:7, category:'E', family:'F4', group:'G4', metric:'P'}]);
        await view.runAsync();
        verify(id, view, 9, 8);
        check(AoV._plotData(id).length === beforeAppend + 1, id + ': append lost rows');
        const updated = view;
        [...row.options].forEach(o => o.selected = false);
        row.dispatchEvent(new Event('change', {bubbles: true}));
        view = await ready(id, updated);
        verify(id, view, 9, 2);
        check(AoV._plotData(id).length === 9, id + ': re-faceting lost streamed rows');

        for (const id of ['sizing-single', 'sizing-layered']) {
            let view = await ready(id);
            const height = view.height();
            verify(id, view, 6, 0);
            AoV.remapEncoding(id, {row:'family'});
            view = await ready(id, view);
            verify(id, view, 6, 3);
            AoV.remapEncoding(id, {row:null});
            view = await ready(id, view);
            verify(id, view, 6, 0);
            check(view.height() === height, id + ': rendered height changed after round trip');
        }
        view = await ready('sizing-faceted-layered');
        verify('sizing-faceted-layered', view, 6, 2);
        AoV.remapEncoding('sizing-faceted-layered', {row:null, column:null});
        view = await ready('sizing-faceted-layered', view);
        verify('sizing-faceted-layered', view, 6, 0);
        check(errors.length === 0, 'runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
        ['sizing-picker', 'sizing-single', 'sizing-layered', 'sizing-faceted-layered']
            .forEach(id => AoV.dispose(id));
    }
    const result = document.createElement('pre');
    result.id = 'aov-remap-sizing-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
