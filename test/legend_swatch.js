// Colour legend swatch browser checks (snag `color-legend-swa-8625457a`): a
// coloured ribbon's legend draws each swatch like its median line, a
// full-strength stroke; a legend click keeps the chosen entry at full strength
// and dims the others; and the channel picker keeps that look on the colour it
// moves in, onto another field or onto an uncoloured ribbon.
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
    function swatches(view) {
        const out = [];
        (function walk(item) {
            if (item.mark && item.mark.role === 'legend-symbol' && item.datum)
                out.push({value: item.datum.value, shape: item.shape, opacity: item.opacity,
                    width: item.strokeWidth});
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    function lineLook(id, view, values, label) {
        const s = swatches(view);
        check(JSON.stringify(s.map(x => x.value)) === JSON.stringify(values),
            label + ' ' + id + ': entries ' + JSON.stringify(s.map(x => x.value)) + ', expected ' + JSON.stringify(values));
        check(s.length && s.every(x => x.shape === 'stroke' && x.width === 2),
            label + ' ' + id + ': swatches not drawn like the line ' + JSON.stringify(s));
        check(s.length && s.every(x => x.opacity === 1),
            label + ' ' + id + ': swatches not at full strength ' + JSON.stringify(s));
    }
    async function click(id, view, label) {
        const container = document.getElementById(id);
        const node = [...container.querySelectorAll('.role-legend-label text')]
            .find(n => n.textContent === label);
        check(!!node, id + ': missing legend label ' + label);
        if (!node) return;
        node.dispatchEvent(new MouseEvent('click', {bubbles: true}));
        await pause();
        await view.runAsync();
    }
    async function remap(id, views, field) {
        const before = views[id];
        AoV.remapEncoding(id, {color: field});
        views[id] = await ready(id, before);
        return views[id];
    }

    try {
        const views = {};
        for (const id of ['ls-ribbon', 'ls-composed', 'ls-picker', 'ls-plain-picker']) views[id] = await ready(id);
        lineLook('ls-ribbon', views['ls-ribbon'], ['a', 'b', 'c'], 'initial');
        lineLook('ls-composed', views['ls-composed'], ['a', 'b', 'c'], 'initial');
        lineLook('ls-picker', views['ls-picker'], ['a', 'b', 'c'], 'initial');
        check(swatches(views['ls-plain-picker']).length === 0,
            'ls-plain-picker: an uncoloured ribbon drew a colour legend');

        // A click keeps the chosen entry at full strength and dims the others
        // (before, the chosen entry stayed at the band's 0.2 and the others
        // rose to 0.35).
        await click('ls-ribbon', views['ls-ribbon'], 'b');
        const picked = swatches(views['ls-ribbon']);
        check(picked.find(x => x.value === 'b')?.opacity === 1,
            'ls-ribbon: the clicked entry is not at full strength ' + JSON.stringify(picked));
        check(picked.filter(x => x.value !== 'b').every(x => x.opacity < 0.5),
            'ls-ribbon: the other entries are not dimmed ' + JSON.stringify(picked));

        // The picker: another field, back to the authored one, and a colour
        // moved onto an uncoloured ribbon.
        lineLook('ls-picker', await remap('ls-picker', views, 'h'), ['u', 'v'], 'remapped to h');
        lineLook('ls-picker', await remap('ls-picker', views, 'g'), ['a', 'b', 'c'], 'back to g');
        lineLook('ls-plain-picker', await remap('ls-plain-picker', views, 'g'), ['a', 'b', 'c'], 'coloured by the picker');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-legend-swatch-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
