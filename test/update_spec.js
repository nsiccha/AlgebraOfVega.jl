(async function () {
    const failures = [];
    const errors = [];
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
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
    function items(view, predicate) {
        const out = [];
        (function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const medians = view => items(view, i => i.mark?.marktype === 'symbol' && i.datum?.__point__ !== undefined);
    const rules = view => items(view, i => i.mark?.marktype === 'rule' && i.datum?.lo_0_95_ !== undefined);
    const cells = view => items(view, i => i.mark?.role === 'scope' && i.mark?.name === 'cell');
    const placed = list => list.every(i => Number.isFinite(i.x) && Number.isFinite(i.y));
    function intervalsMatch(id, expected, label) {
        const rows = AoV._plotData(id).filter(r => r.lo_0_95_ !== undefined);
        check(rows.length === expected.length, label + ': ' + rows.length + ' interval rows, expected ' + expected.length);
        const want = new Map(expected.map(([m, t, lo]) => [m + '|' + t, lo]));
        check(rows.every(r => Math.abs(want.get(r.model + '|' + r.metric) - r.lo_0_95_) < 1e-9),
            label + ': interval bounds are not the re-lowered summary');
    }
    const pretty = () => document.getElementById('refresh-interval-pretty');

    try {
        const id = 'refresh-interval';
        let view = await ready(id);
        check(cells(view).length === 2, 'initial: metric columns');
        check(medians(view).length === 6 && placed(medians(view)), 'initial: medians drawn');
        check(rules(view).length === 18, 'initial: interval rules drawn');
        const initialRows = AoV._plotData(id).length;
        check(AoV._plotData(id).some(r => r.__src), 'initial: merged dataset');

        // The captioned summary pane renders once opened.
        const details = pretty().closest('details');
        details.open = true;
        AoV._lazyRenderDataView(details, 'pretty');
        const prettyBefore = pretty().textContent;
        check(pretty().dataset.aovRendered === '1' && prettyBefore.length > 0, 'pretty summary rendered');

        // Raw rows into the lowered dataset: refused, the figure keeps drawing.
        const errorsBefore = errors.length;
        send('raw');
        await view.runAsync();
        check(errors.length === errorsBefore + 1 && /update_spec/.test(errors[errors.length - 1] || ''),
            'raw update_data: refused with an update_spec pointer');
        check(/lo_0_95_|__src|__point__/.test(errors[errors.length - 1] || ''), 'raw update_data: names the missing fields');
        check(AoV.views[id] === view && AoV._plotData(id).length === initialRows, 'raw update_data: data left unchanged');
        check(medians(view).length === 6 && rules(view).length === 18, 'raw update_data: figure still drawn');

        // The reader re-facets: Family onto rows.
        document.querySelector('input[type=radio][name="aov-pin-' + id + '"][value=color]').click();
        const row = document.getElementById('aov-remap-row-' + id);
        [...row.options].forEach(o => o.selected = o.value === 'family');
        row.dispatchEvent(new Event('change', {bubbles: true}));
        view = await ready(id, view);
        check(cells(view).length === 4, 'picker: family rows x metric columns');
        check(medians(view).length === 6, 'picker: medians drawn');

        // Same-shape refresh: data swapped into the live view, picker kept.
        const remapped = view;
        send('same');
        view = await settle(id);
        check(view === remapped, 'same-shape update_spec: swapped in place (no re-embed)');
        check(cells(view).length === 4, 'same-shape update_spec: picker rows kept');
        check(medians(view).length === 6 && placed(medians(view)), 'same-shape update_spec: medians drawn');
        check(rules(view).length === 18, 'same-shape update_spec: interval rules drawn');
        intervalsMatch(id, fixture.expected.same, 'same-shape update_spec');
        check(JSON.stringify(AoV._cur[id].spec).includes(String(fixture.expected.same[0][2])),
            'same-shape update_spec: resize re-embeds read the new data');
        check(AoV._origSpecs[id] && !AoV._origSpecs[id].facet?.row,
            'same-shape update_spec: stored original stays unremapped');
        check(pretty().dataset.aovRendered === '1' && pretty().textContent !== prettyBefore,
            'same-shape update_spec: open summary pane re-rendered');

        // A new metric adds a facet column: structural, so it re-embeds in place.
        send('grow');
        view = await ready(id, view);
        check(cells(view).length === 6, 'structural update_spec: picker rows x three metric columns');
        check(medians(view).length === 9 && placed(medians(view)), 'structural update_spec: medians drawn');
        check(rules(view).length === 27, 'structural update_spec: interval rules drawn');
        check([...row.selectedOptions].map(o => o.value).join() === 'family', 'structural update_spec: picker DOM kept');
        check(pretty().textContent.includes('hessian'), 'structural update_spec: summary pane shows the new metric');

        // ...after which a same-shape refresh is in place again.
        const grown = view;
        send('grow_same');
        view = await settle(id);
        check(view === grown, 'post-structural update_spec: swapped in place');
        check(cells(view).length === 6 && medians(view).length === 9 && rules(view).length === 27,
            'post-structural update_spec: figure drawn');
        intervalsMatch(id, fixture.expected.grow_same, 'post-structural update_spec');

        // Re-faceting after refreshes builds from the refreshed data.
        [...row.options].forEach(o => o.selected = false);
        row.dispatchEvent(new Event('change', {bubbles: true}));
        view = await ready(id, view);
        check(cells(view).length === 3, 'picker after refresh: metric columns only');
        intervalsMatch(id, fixture.expected.grow_same, 'picker after refresh');

        // Plain plots keep accepting raw rows.
        const pid = 'refresh-plain';
        let plain = await ready(pid);
        const points = v => items(v, i => i.mark?.marktype === 'symbol' && i.datum?.y !== undefined);
        check(points(plain).length === 3, 'plain: initial points');
        send('plain_update');
        await plain.runAsync();
        check(points(plain).length === 2, 'plain update_data: applied');
        send('plain_append_uncolored');
        await plain.runAsync();
        check(points(plain).length === 3, 'plain append_data without colour: applied');
        const errorsPlain = errors.length;
        send('plain_append_unplaced');
        await plain.runAsync();
        check(errors.length === errorsPlain + 1 && /lack x/.test(errors[errors.length - 1] || ''),
            'plain append_data without x: refused');
        check(points(plain).length === 3, 'plain append_data without x: data left unchanged');
        send('plain_spec');
        const before = plain;
        plain = await settle(pid);
        check(plain === before, 'plain update_spec: swapped in place');
        check(points(plain).length === 4, 'plain update_spec: new rows replace the appended ones');

        // A refresh for a plot whose element was just removed (not yet swept)
        // is dropped, not re-dispatched forever.
        const holder = document.getElementById(pid).parentElement;
        const node = holder.removeChild(document.getElementById(pid));
        let threw = null;
        try { send('plain_spec'); } catch (e) { threw = e; }
        check(threw === null, 'update_spec on a removed plot: ' + threw);
        holder.appendChild(node);

        check(errors.length === 2, 'unexpected runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
        ['refresh-interval', 'refresh-plain'].forEach(id => AoV.dispose(id));
    }
    const result = document.createElement('pre');
    result.id = 'aov-update-spec-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
