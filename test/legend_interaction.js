// Run the lowered spec directly (standalone HTML) and through AoV (live plot).
// The direct path prevents runtime repair from masking a Julia lowering defect.
(async function () {
    const failures = [];
    let checks = 0;
    function check(ok, message) {
        checks++;
        if (!ok) failures.push(message);
    }
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    function marks(view) {
        const out = [];
        function walk(item) {
            if (item.datum && item.datum.group &&
                ['symbol', 'line', 'area', 'rule'].includes(item.mark?.marktype)) {
                out.push({group: item.datum.group, opacity: item.opacity,
                    type: item.mark.marktype});
            }
            (item.items || []).forEach(walk);
        }
        walk(view.scenegraph().root);
        return out;
    }
    async function click(container, view, label, shift = false) {
        const node = [...container.querySelectorAll('.role-legend-label text')]
            .find(node => node.textContent === label);
        check(!!node, container.id + ': missing legend label ' + label);
        if (node) {
            node.scrollIntoView({block: 'center'});
            const box = node.getBoundingClientRect();
            const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2);
            check(getComputedStyle(node).pointerEvents !== 'none' && hit === node,
                container.id + ': legend label cannot receive native pointer events');
            const symbol = container.querySelector('.role-legend-symbol path');
            check(symbol && getComputedStyle(symbol).pointerEvents !== 'none',
                container.id + ': legend symbol cannot receive native pointer events');
            node.dispatchEvent(new MouseEvent('click', {bubbles: true, shiftKey: shift}));
            await pause();
            await view.runAsync();
        }
    }
    async function clear(container, view) {
        container.querySelector('svg').dispatchEvent(new MouseEvent('click', {bubbles: true}));
        await pause();
        await view.runAsync();
    }
    for (const [mode, collection] of Object.entries({highlight: fixtures, filter: filterFixtures})) {
        for (const [name, spec] of Object.entries(collection)) {
            for (const path of mode === 'highlight' ? ['direct', 'runtime', 'caption'] : ['direct', 'runtime']) {
                const container = path === 'caption' ? document.getElementById([mode, name, path].join('-')) :
                    document.createElement('div');
                container.id = [mode, name, path].join('-');
                if (path !== 'caption') document.body.append(container);
                let view;
                try {
                    const options = {renderer: 'svg', actions: false};
                    if (path === 'direct') view = (await vegaEmbed(container, spec, options)).view;
                    else {
                        if (path === 'runtime') await AoV.embed(container.id, spec, options);
                        else for (let i = 0; i < 100 && !AoV.views[container.id]; i++) await pause();
                        view = AoV.views[container.id];
                    }
                    check(!!view, container.id + ': embed failed');
                    const before = marks(view);
                    check(before.some(m => m.group === 'A') && before.some(m => m.group === 'B'),
                        container.id + ': initial series missing');
                    await click(container, view, 'A');
                    const store = view.data('legend_selection_store');
                    check(store.some(tuple => tuple.values[0] === 'A'), container.id + ': selection unchanged');
                    const selected = marks(view);
                    check(selected.some(m => m.group === 'A'), container.id + ': A missing');
                    if (mode === 'highlight') {
                        const bs = selected.filter(m => m.group === 'B');
                        check(bs.length && bs.every(m => m.opacity <= 0.15), container.id + ': B not dimmed');
                        if (name === 'translucent') {
                            check(selected.some(m => m.group === 'A' && m.type === 'line' && m.opacity === 0.2),
                                container.id + ': selected line lost its opacity');
                            check(selected.some(m => m.group === 'B' && m.type === 'line' && Math.abs(m.opacity - 0.03) < 1e-8),
                                container.id + ': line did not dim proportionally');
                        }
                    } else {
                        check(!selected.some(m => m.group === 'B'), container.id + ': B not filtered');
                        const appearance = items => items.filter(m => m.group === 'A')
                            .map(m => JSON.stringify([m.type, m.opacity ?? 1])).sort().join(';');
                        check(appearance(selected) === appearance(before),
                            container.id + ': filtering changed selected mark opacity');
                    }
                    await click(container, view, 'B', true);
                    // A re-embed between the clicks replaces the view, so the
                    // checks below would read a stale one; name that cause.
                    if (path !== 'direct') {
                        check(AoV.views[container.id] === view,
                            container.id + ': view re-embedded mid-interaction');
                    }
                    const multi = view.data('legend_selection_store');
                    check(multi.some(t => t.values[0] === 'A') && multi.some(t => t.values[0] === 'B'),
                        container.id + ': shift selection failed');
                    await clear(container, view);
                    check(view.data('legend_selection_store').length === 0, container.id + ': clear failed');
                    check(marks(view).length === before.length, container.id + ': clear did not restore marks');
                    // The ordinary fixtures retain `other` in their rows. The
                    // analyses intentionally summarize it away, so it is not a
                    // valid remap target for their summarized data.
                    if (path === 'runtime' && !['interval', 'ribbon'].includes(name)) {
                        const old = view;
                        AoV.remapEncoding(container.id, {color: 'other'});
                        for (let i = 0; i < 100 && (!AoV.views[container.id] || AoV.views[container.id] === old); i++) {
                            await pause();
                        }
                        view = AoV.views[container.id];
                        check(view && view !== old, container.id + ': remap did not complete');
                        await click(container, view, 'C');
                        check(![...container.querySelectorAll('.role-legend-label text')]
                            .some(node => ['A', 'B'].includes(node.textContent)),
                            container.id + ': stale legend domain after remapping');
                        check(view.data('legend_selection_store').some(t =>
                            t.fields[0].field === 'other' && t.values[0] === 'C'), container.id + ': stale selection field');
                        AoV.remapEncoding(container.id, {color: null});
                        const previous = view;
                        for (let i = 0; i < 100 && (!AoV.views[container.id] || AoV.views[container.id] === previous); i++) {
                            await pause();
                        }
                        view = AoV.views[container.id];
                        check(view && view !== previous, container.id + ': removing color did not complete');
                        check(!Object.keys(view.getState().signals).some(k => k.startsWith('legend_selection')),
                            container.id + ': stale selection after removing color');
                    }
                } catch (error) {
                    failures.push(container.id + ': ' + error.stack);
                } finally {
                    if (path !== 'direct') AoV.dispose(container.id);
                    else view?.finalize();
                }
            }
        }
    }
    // The runtime re-derives legend selections after remaps/updates; it must
    // rebuild exactly what the Julia lowering emitted.
    const canon = value => JSON.stringify(value, (key, x) =>
        x && typeof x === 'object' && !Array.isArray(x) ?
            Object.fromEntries(Object.keys(x).sort().map(k => [k, x[k]])) : x);
    const lowered = Object.assign({independent: independentFixture},
        ...Object.entries(fixtures).map(([name, spec]) => ({[name]: spec})),
        ...Object.entries(mergedFixtures).map(([name, f]) => ({[name]: f.spec})));
    for (const [name, spec] of Object.entries(lowered)) {
        const copy = structuredClone(spec);
        AoV._refreshLegendSelections(copy);
        check(canon(copy) === canon(spec), name + ': runtime legend refresh differs from the Julia lowering');
    }
    // Layers colouring by different fields share Vega-Lite's merged colour
    // legend (snag `legend-selection-0bea9abd`): every entry highlights the
    // series coloured by it, whichever field that is. Lines colour by `group`.
    function series(view, pointField) {
        const out = [];
        function walk(item) {
            const type = item.mark?.marktype, d = item.datum;
            const value = !d ? undefined : type === 'line' ? d.group : type === 'symbol' ? d[pointField] : undefined;
            if (value !== undefined) out.push({value, type, opacity: item.opacity ?? 1});
            (item.items || []).forEach(walk);
        }
        walk(view.scenegraph().root);
        return out;
    }
    // `lit` maps a mark type to the values left undimmed (null: all of them).
    function expectLit(container, view, pointField, lit, label) {
        const marks = series(view, pointField);
        check(['A', 'B'].every(v => marks.some(m => m.type === 'line' && m.value === v)) &&
            ['C', 'D'].every(v => marks.some(m => m.type === 'symbol' && m.value === v)),
            container.id + ': ' + label + ': series missing');
        for (const m of marks) {
            const on = lit[m.type] === null || lit[m.type].includes(m.value);
            check(on ? m.opacity > 0.15 + 1e-9 : m.opacity <= 0.15 + 1e-9,
                container.id + ': ' + label + ': ' + m.type + ' ' + m.value + ' opacity ' + m.opacity);
        }
    }
    const both = values => ({line: values, symbol: values});
    async function mount(id, spec, path) {
        const container = path === 'caption' ? document.getElementById(id) : document.createElement('div');
        container.id = id;
        if (path !== 'caption') document.body.append(container);
        const options = {renderer: 'svg', actions: false};
        if (path === 'direct') return [container, (await vegaEmbed(container, spec, options)).view];
        if (path === 'runtime') await AoV.embed(container.id, spec, options);
        else for (let i = 0; i < 100 && !AoV.views[container.id]; i++) await pause();
        return [container, AoV.views[container.id]];
    }
    const release = (path, id, view) => path === 'direct' ? view?.finalize() : AoV.dispose(id);
    for (const [name, {spec, pointField}] of Object.entries(mergedFixtures)) {
        for (const path of ['direct', 'runtime', 'caption']) {
            const id = ['merged', name, path].join('-');
            let view;
            try {
                let container;
                [container, view] = await mount(id, spec, path);
                check(!!view, id + ': embed failed');
                expectLit(container, view, pointField, both(null), 'initial');
                await click(container, view, 'C');
                check(view.data('legend_selection_store').some(t => t.values[0] === 'C'),
                    id + ': second-field entry not stored');
                expectLit(container, view, pointField, both(['C']), 'click C');
                await click(container, view, 'A');
                expectLit(container, view, pointField, both(['A']), 'click A');
                await click(container, view, 'D', true);
                expectLit(container, view, pointField, both(['A', 'D']), 'shift-click D');
                await clear(container, view);
                expectLit(container, view, pointField, both(null), 'clear');
            } catch (error) {
                failures.push(id + ': ' + error.stack);
            } finally {
                release(path, id, view);
            }
        }
    }
    // Independent colour scales draw a legend each, listing only their own
    // field's entries, and keep one selection each.
    for (const path of ['direct', 'runtime']) {
        const id = ['independent', path].join('-');
        let view;
        try {
            let container;
            [container, view] = await mount(id, independentFixture, path);
            check(container.querySelectorAll('.role-legend').length === 2, id + ': expected two legends');
            await click(container, view, 'C');
            check(view.data('legend_selection_2_store').some(t => t.values[0] === 'C'),
                id + ': independent legend entry not stored');
            expectLit(container, view, 'kind', {line: null, symbol: ['C']}, 'click C');
            await clear(container, view);
            await click(container, view, 'A');
            expectLit(container, view, 'kind', {line: ['A'], symbol: null}, 'click A');
        } catch (error) {
            failures.push(id + ': ' + error.stack);
        } finally {
            release(path, id, view);
        }
    }
    const result = document.createElement('pre');
    result.id = 'aov-legend-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
