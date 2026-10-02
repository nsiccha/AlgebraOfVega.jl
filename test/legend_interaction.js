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
            for (const path of ['direct', 'runtime']) {
                const container = document.createElement('div');
                container.id = [mode, name, path].join('-');
                document.body.append(container);
                let view;
                try {
                    const options = {renderer: 'svg', actions: false};
                    if (path === 'direct') view = (await vegaEmbed(container, spec, options)).view;
                    else {
                        await AoV.embed(container.id, spec, options);
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
                    if (path === 'runtime') AoV.dispose(container.id);
                    else view?.finalize();
                }
            }
        }
    }
    const result = document.createElement('pre');
    result.id = 'aov-legend-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
