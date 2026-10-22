// Hover linking in the browser. A plot reports the data mark under the
// pointer as `aov:hover` / `aov:hoverend` on its element, on every view the
// runtime embeds; `AoV.highlight(id, match)` dims the marks whose rows do not
// match, in place and across re-embeds; and plots that join a link group
// (`config(link=(; group, key))`) announce hovered keys as `htmxo:link` events
// on `document` and highlight the keys other members announce. Pointers are
// sent the way a browser does: pointermove and mousemove for each position.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    const hovers = [], links = [];
    ['aov:hover', 'aov:hoverend'].forEach(name => document.addEventListener(name,
        e => hovers.push({type: e.type, target: e.target.id, detail: e.detail})));
    document.addEventListener('htmxo:link', e => links.push(e.detail));

    // Scenegraph items matching `pred`, with their position in view coordinates.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2, left: dx + b.x1, top: dy + b.y1});
            }
            const gx = item.mark && item.mark.marktype === 'group' ? dx + (item.x || 0) : dx;
            const gy = item.mark && item.mark.marktype === 'group' ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy));
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    function one(view, what, pred) {
        const found = items(view, pred);
        if (found.length !== 1) throw new Error(what + ': expected one scenegraph item, found ' + found.length);
        return found[0];
    }
    const symbol = (field, value) => item => item.mark.role === 'mark' && item.mark.marktype === 'symbol' &&
        item.datum && item.datum[field] === value;
    // The opacity each data mark of a kind is drawn with, by its row's `field`.
    function opacities(id, marktype, field) {
        const out = {};
        items(AoV.views[id], item => item.mark.role === 'mark' && item.mark.marktype === marktype &&
            item.datum && item.datum[field] !== undefined).forEach(({item}) => {
            out[item.datum[field]] = Math.round((item.opacity === undefined ? 1 : item.opacity) * 1000) / 1000;
        });
        return out;
    }
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    // A pointer at view coordinates (x, y): through the view origin PLUS its
    // padding, as Vega maps it (see test/mark_click.js).
    function pointerAt(id, x, y) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, clientX: rect.left + origin[0] + pad.left + x,
            clientY: rect.top + origin[1] + pad.top + y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new MouseEvent('mousemove', opts));
    }
    // A click as a pointer sends it (see test/mark_click.js).
    function clickAt(id, at) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, clientX: rect.left + origin[0] + pad.left + at.x,
            clientY: rect.top + origin[1] + pad.top + at.y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new PointerEvent('pointerdown', opts));
        canvas.dispatchEvent(new PointerEvent('pointerup', opts));
        canvas.dispatchEvent(new MouseEvent('click', opts));
    }
    // The pointer leaves the plot: the canvas loses it, then the element.
    function leave(id) {
        const canvas = document.querySelector('#' + id + ' canvas');
        canvas.dispatchEvent(new PointerEvent('pointerout', {bubbles: true, pointerId: 1, pointerType: 'mouse'}));
        canvas.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
        document.getElementById(id).dispatchEvent(new PointerEvent('pointerleave', {pointerId: 1, pointerType: 'mouse'}));
    }
    // The events a pointer action sent, after Vega's mouseout/mouseover pair settles.
    async function during(fn) {
        hovers.length = 0;
        links.length = 0;
        fn();
        await Promise.resolve();
        await pause();
        return {hovers: hovers.slice(), links: links.slice()};
    }
    const summary = got => got.hovers.map(e => e.type + ':' + e.target + ':' + (e.detail.datum.kenn || e.detail.datum.k));
    const announce = (group, key) => document.dispatchEvent(new CustomEvent('htmxo:link',
        {detail: {group, key, source: null}}));
    const settle = async () => { await pause(); await pause(); };

    try {
        // --- aov:hover / aov:hoverend ---
        let view = await ready('hh-scatter');
        await ready('hh-map');
        await ready('hh-lines');
        await ready('hh-plain');
        await ready('hh-bars');
        await ready('hh-other');
        const plainBefore = opacities('hh-plain', 'symbol', 'kenn');
        // The highlight machinery leaves an unhighlighted plot's look alone:
        // Vega-Lite's own 0.7 opacity on scatter points.
        check(same(plainBefore, {a: 0.7, b: 0.7, c: 0.7}), 'plain: unhighlighted opacities ' + JSON.stringify(plainBefore));

        const b = one(view, 'scatter point b', symbol('kenn', 'b'));
        let got = await during(() => pointerAt('hh-scatter', b.x, b.y));
        check(same(summary(got), ['aov:hover:hh-scatter:b']), 'scatter hover b: ' + JSON.stringify(summary(got)));
        const detail = got.hovers[0] && got.hovers[0].detail;
        check(detail && detail.id === 'hh-scatter' && detail.datum.x === 2 && detail.event instanceof MouseEvent,
            'scatter hover b: detail ' + JSON.stringify(detail && {id: detail.id, datum: detail.datum}));
        // The datum is a copy.
        if (detail) detail.datum.kenn = 'changed';
        check(view.data('source_0').some(row => row.kenn === 'b'), 'scatter: changing detail.datum changed the plot data');
        // The link announcement carries the key as a string and the plot as source.
        check(got.links.length === 1 && got.links[0].group === 'probes' && got.links[0].key === 'b' &&
            got.links[0].source === document.getElementById('hh-scatter'),
            'scatter hover b: announcements ' + JSON.stringify(got.links.map(l => [l.group, l.key])));
        // Moving within the same mark sends nothing.
        got = await during(() => pointerAt('hh-scatter', b.x + 1, b.y));
        check(got.hovers.length === 0 && got.links.length === 0, 'scatter: moving on b sent ' + JSON.stringify(summary(got)));
        // Linked members show b; the hovered plot itself is not dimmed.
        await settle();
        check(same(opacities('hh-map', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.105}),
            'map while b is hovered: ' + JSON.stringify(opacities('hh-map', 'symbol', 'kenn')));
        check(same(opacities('hh-scatter', 'symbol', 'kenn'), {a: 1, b: 1, c: 1}),
            'scatter dimmed itself: ' + JSON.stringify(opacities('hh-scatter', 'symbol', 'kenn')));
        // The other group heard nothing it acts on.
        check(same(opacities('hh-other', 'symbol', 'kenn'), plainBefore),
            'other group reacted: ' + JSON.stringify(opacities('hh-other', 'symbol', 'kenn')));

        // From b to c: b's hoverend, then c's hover, and the matching announcements.
        const c = one(view, 'scatter point c', symbol('kenn', 'c'));
        got = await during(() => pointerAt('hh-scatter', c.x, c.y));
        check(same(summary(got), ['aov:hoverend:hh-scatter:b', 'aov:hover:hh-scatter:c']),
            'scatter b → c: ' + JSON.stringify(summary(got)));
        check(same(got.links.map(l => l.key), [null, 'c']), 'scatter b → c announced ' + JSON.stringify(got.links.map(l => l.key)));
        await settle();
        check(same(opacities('hh-map', 'symbol', 'kenn'), {a: 0.105, b: 0.105, c: 0.7}),
            'map while c is hovered: ' + JSON.stringify(opacities('hh-map', 'symbol', 'kenn')));
        // Leaving the plot ends the hover once, and clears the group.
        got = await during(() => leave('hh-scatter'));
        check(same(summary(got), ['aov:hoverend:hh-scatter:c']), 'scatter leave: ' + JSON.stringify(summary(got)));
        check(same(got.links.map(l => l.key), [null]), 'scatter leave announced ' + JSON.stringify(got.links.map(l => l.key)));
        await settle();
        check(same(opacities('hh-map', 'symbol', 'kenn'), {a: 0.7, b: 0.7, c: 0.7}),
            'map after the hover ended: ' + JSON.stringify(opacities('hh-map', 'symbol', 'kenn')));

        // Bars: a bar is a mark; the empty space above it is none, so moving
        // there ends the hover. An unlinked plot announces nothing.
        view = AoV.views['hh-bars'];
        const bar = one(view, 'bar b', item => item.mark.role === 'mark' && item.datum && item.datum.k === 'b');
        got = await during(() => pointerAt('hh-bars', bar.x, bar.y));
        check(same(summary(got), ['aov:hover:hh-bars:b']) && got.links.length === 0,
            'bars hover b: ' + JSON.stringify(summary(got)) + ' ' + got.links.length + ' announcements');
        got = await during(() => pointerAt('hh-bars', bar.x, 3));
        check(same(summary(got), ['aov:hoverend:hh-bars:b']), 'bars b → empty space: ' + JSON.stringify(summary(got)));

        // A legend is no mark: hovering it sends nothing.
        view = AoV.views['hh-scatter'];
        const entry = one(view, 'legend entry q', item => item.mark.role === 'legend-symbol' && item.datum && item.datum.value === 'q');
        got = await during(() => pointerAt('hh-scatter', entry.x, entry.y));
        check(got.hovers.length === 0, 'scatter: hovering a legend entry sent ' + JSON.stringify(summary(got)));
        leave('hh-scatter');

        // --- AoV.highlight ---
        AoV.highlight('hh-plain', {kenn: ['a', 'c']});
        await settle();
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.7, b: 0.105, c: 0.7}),
            'plain highlight a, c: ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));
        const plainView = AoV.views['hh-plain'];
        AoV.highlight('hh-plain', d => d.x >= 2);
        await settle();
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.7}),
            'plain highlight by function: ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));
        // Several fields must all match; values compare as strings.
        AoV.highlight('hh-plain', {kenn: 'b', x: '2'});
        await settle();
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.105}),
            'plain highlight kenn b, x "2": ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));
        // In place: the view was not replaced.
        check(AoV.views['hh-plain'] === plainView, 'plain: highlighting re-embedded the plot');
        // A re-embed (as a resize or theme switch runs it) shows the highlight
        // from its first frame.
        AoV._reembeds['hh-plain']();
        await ready('hh-plain', plainView);
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.105}),
            'plain after re-embed: ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));
        // update_spec with new rows: the new rows are tested too.
        const spec = JSON.parse(JSON.stringify(AoV._origSpecs['hh-plain']));
        const values = spec.data && spec.data.values ||
            spec.datasets && spec.datasets[Object.keys(spec.datasets)[0]];
        values.push({x: 2.5, y: 6, kenn: 'd'});
        AoV.updateSpec('hh-plain', spec);
        await pause();
        await ready('hh-plain');
        await settle();
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.105, d: 0.105}),
            'plain after update_spec: ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));
        AoV.clearHighlight('hh-plain');
        await settle();
        check(same(opacities('hh-plain', 'symbol', 'kenn'), {a: 0.7, b: 0.7, c: 0.7, d: 0.7}),
            'plain cleared: ' + JSON.stringify(opacities('hh-plain', 'symbol', 'kenn')));

        // --- Link group members ---
        // A table announces b: the map dims its other probes but not its
        // districts (they have no kenn); the lines dim the other series.
        const districts = () => opacities('hh-map', 'shape', 'AGS');
        const districtsBefore = districts();
        announce('probes', 'b');
        await settle();
        check(same(opacities('hh-map', 'symbol', 'kenn'), {a: 0.105, b: 0.7, c: 0.105}),
            'map on table b: ' + JSON.stringify(opacities('hh-map', 'symbol', 'kenn')));
        check(same(districts(), districtsBefore), 'map districts changed: ' + JSON.stringify(districts()));
        check(same(opacities('hh-lines', 'line', 'kenn'), {a: 0.15, b: 1, c: 0.15}),
            'lines on table b: ' + JSON.stringify(opacities('hh-lines', 'line', 'kenn')));
        check(same(opacities('hh-scatter', 'symbol', 'kenn'), {a: 0.15, b: 1, c: 0.15}),
            'scatter on table b: ' + JSON.stringify(opacities('hh-scatter', 'symbol', 'kenn')));
        check(same(opacities('hh-other', 'symbol', 'kenn'), plainBefore), 'other group on table b changed');
        // A legend selection and a highlight combine: a mark stays bright
        // only if it passes both (a is outside legend entry q, c outside the
        // highlight).
        view = AoV.views['hh-scatter'];
        AoV.highlight('hh-scatter', {kenn: ['a', 'b']});
        await settle();
        check(same(opacities('hh-scatter', 'symbol', 'kenn'), {a: 1, b: 1, c: 0.15}),
            'scatter highlight a, b: ' + JSON.stringify(opacities('hh-scatter', 'symbol', 'kenn')));
        clickAt('hh-scatter', one(view, 'legend entry q', item => item.mark.role === 'legend-symbol' &&
            item.datum && item.datum.value === 'q'));
        await settle();
        check(view.data('legend_selection_store').length === 1, 'scatter: the legend click did not select');
        check(same(opacities('hh-scatter', 'symbol', 'kenn'), {a: 0.15, b: 1, c: 0.15}),
            'scatter: legend q with highlight a, b: ' + JSON.stringify(opacities('hh-scatter', 'symbol', 'kenn')));
        // A remap there and back (a new view, so no legend selection) keeps
        // the link and the highlight.
        AoV.remapEncoding('hh-scatter', {row: 'g'});
        view = await ready('hh-scatter', view);
        AoV.remapEncoding('hh-scatter', {row: ''});
        view = await ready('hh-scatter', view);
        await settle();
        check(AoV._link('hh-scatter') && AoV._link('hh-scatter').key === 'kenn', 'scatter lost its link on remap');
        check(same(opacities('hh-scatter', 'symbol', 'kenn'), {a: 1, b: 1, c: 0.15}),
            'scatter after remap: ' + JSON.stringify(opacities('hh-scatter', 'symbol', 'kenn')));
        // Null clears every member.
        announce('probes', null);
        await settle();
        check(same(opacities('hh-map', 'symbol', 'kenn'), {a: 0.7, b: 0.7, c: 0.7}) &&
            same(opacities('hh-lines', 'line', 'kenn'), {a: 1, b: 1, c: 1}),
            'members after null: ' + JSON.stringify([opacities('hh-map', 'symbol', 'kenn'), opacities('hh-lines', 'line', 'kenn')]));

        // A linked plot swapped in while its group shows a key shows it too,
        // and a hover on the replaced element ends with the swap.
        view = AoV.views['hh-map'];
        const probe = one(view, 'map probe a', symbol('kenn', 'a'));
        got = await during(() => pointerAt('hh-map', probe.x, probe.y));
        check(same(summary(got), ['aov:hover:hh-map:a']) && same(got.links.map(l => l.key), ['a']),
            'map hover a: ' + JSON.stringify(summary(got)) + ' ' + JSON.stringify(got.links.map(l => l.key)));
        const lines = AoV.views['hh-lines'], lineSpec = JSON.parse(JSON.stringify(AoV._origSpecs['hh-lines']));
        const fresh = document.createElement('div');
        fresh.id = 'hh-lines';
        document.getElementById('hh-lines').replaceWith(fresh);
        AoV.embed('hh-lines', lineSpec, {actions: false});
        await ready('hh-lines', lines);
        await settle();
        check(same(opacities('hh-lines', 'line', 'kenn'), {a: 1, b: 0.15, c: 0.15}),
            'swapped-in lines while a is hovered: ' + JSON.stringify(opacities('hh-lines', 'line', 'kenn')));
        // Removing the hovered plot ends its hover and clears the group.
        const mapEl = document.getElementById('hh-map');
        got = await during(() => mapEl.remove());
        await settle();
        check(got.links.some(l => l.key === null && l.source === mapEl),
            'removing the hovered map announced ' + JSON.stringify(got.links.map(l => l.key)));
        check(same(opacities('hh-lines', 'line', 'kenn'), {a: 1, b: 1, c: 1}),
            'lines after the hovered map left: ' + JSON.stringify(opacities('hh-lines', 'line', 'kenn')));
        check(!AoV._hovers['hh-map'] && !AoV._highlights['hh-map'], 'map state kept after removal');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-hover-highlight-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
