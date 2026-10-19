// Mark clicks in the browser: a click on a data mark dispatches one bubbling
// `aov:click` on the plot element carrying the mark's row, on every view the
// runtime embeds (first embed, resize re-embed, a same-id element swap).
// Legend, axis and empty-space clicks dispatch none, and the legend keeps
// its own highlight. Clicks are sent the way a pointer does: Vega reports a
// click on the item that was under the pointer at pointerdown.
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
    const events = [];
    document.addEventListener('aov:click', e => events.push({target: e.target.id, detail: e.detail}));

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
    // Click at view coordinates (x, y), as a pointer would. Vega maps a pointer
    // through the view origin PLUS its padding; `view.origin()` alone lands a
    // padding short, which misses a small mark such as a point.
    function clickAt(id, x, y) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, clientX: rect.left + origin[0] + pad.left + x,
            clientY: rect.top + origin[1] + pad.top + y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new PointerEvent('pointerdown', opts));
        canvas.dispatchEvent(new PointerEvent('pointerup', opts));
        canvas.dispatchEvent(new MouseEvent('click', opts));
    }
    // The events one click dispatched.
    function clicked(id, at) {
        events.length = 0;
        clickAt(id, at.x, at.y);
        return events.slice();
    }
    const isRow = (field, value) => item => item.mark.role === 'mark' && item.datum && item.datum[field] === value
        && item.mark.marktype !== 'path';

    try {
        // A scatter: AoV's nearest-point hover lays a Voronoi overlay over the
        // points, so the click lands on an overlay item whose datum is the
        // point's scenegraph item. The event carries the row itself.
        let view = await ready('mc-scatter');
        let got = clicked('mc-scatter', one(view, 'scatter point b', isRow('g', 'b')));
        check(got.length === 1, 'scatter: ' + got.length + ' events for one click');
        const b = got[0] && got[0].detail;
        check(got[0] && got[0].target === 'mc-scatter', 'scatter: event not dispatched on the plot element');
        check(b && b.id === 'mc-scatter' && b.datum.g === 'b' && b.datum.x === 2 && b.datum.y === 4,
            'scatter: wrong detail ' + JSON.stringify(b && {id: b.id, datum: b.datum}));
        check(b && b.event instanceof MouseEvent && b.event.type === 'click', 'scatter: detail.event is not the click');
        // The datum is a copy: changing it leaves the plot's data alone.
        if (b) b.datum.g = 'changed';
        check(view.data('source_0').some(row => row.g === 'b'), 'scatter: changing detail.datum changed the plot data');

        // Legend and axis clicks report nothing; the legend still highlights.
        const legend = one(view, 'legend entry c', item => item.mark.role === 'legend-symbol' && item.datum && item.datum.value === 'c');
        got = clicked('mc-scatter', legend);
        check(got.length === 0, 'scatter: a legend click dispatched ' + got.length + ' events');
        await pause();
        check(view.data('legend_selection_store').length === 1, 'scatter: the legend click no longer selects');
        const label = items(view, item => item.mark.role === 'axis-label')[0];
        got = label ? clicked('mc-scatter', label) : null;
        check(got && got.length === 0, 'scatter: an axis-label click dispatched ' + (got && got.length) + ' events');

        // A resize re-embed replaces the view; the new one reports clicks, once.
        // Point a sits on the plot's corner, and the click still reaches it.
        check(AoV._resizeReembed('mc-scatter'), 'scatter: not re-embedded on resize');
        view = await ready('mc-scatter', view);
        got = clicked('mc-scatter', one(view, 'scatter point a after re-embed', isRow('g', 'a')));
        check(got.length === 1 && got[0].detail.datum.g === 'a',
            'scatter after re-embed: ' + JSON.stringify(got.map(e => e.detail.datum)));

        // Lon/lat points drawn on a map: a point reports its own row, and the
        // open part of a district reports the district's row.
        view = await ready('mc-mappts');
        for (const name of ['kita-A', 'kita-B']) {
            got = clicked('mc-mappts', one(view, 'map point ' + name, item => isRow('name', name)(item) && item.mark.marktype === 'symbol'));
            check(got.length === 1 && got[0].detail.datum.name === name,
                'map point ' + name + ': ' + JSON.stringify(got.map(e => e.detail.datum)));
        }
        const district = one(view, 'district 01003', item => item.mark.marktype === 'shape' && item.datum.AGS === '01003');
        got = clicked('mc-mappts', district);
        check(got.length === 1 && got[0].detail.datum.AGS === '01003',
            'map district under no point: ' + JSON.stringify(got.map(e => e.detail.datum)));

        // A map region carries its table row (AoV's geoshape is table-driven).
        view = await ready('mc-map');
        got = clicked('mc-map', one(view, 'district 01002', item => item.mark.marktype === 'shape' && item.datum.AGS === '01002'));
        check(got.length === 1 && got[0].detail.datum.AGS === '01002' && got[0].detail.datum.effect === 0.1,
            'map: ' + JSON.stringify(got.map(e => ({AGS: e.detail.datum.AGS, effect: e.detail.datum.effect}))));

        // Bars: a bar reports its row; the empty plot area above them nothing.
        view = await ready('mc-bars');
        got = clicked('mc-bars', one(view, 'bar b', isRow('k', 'b')));
        check(got.length === 1 && got[0].detail.datum.k === 'b' && got[0].detail.datum.v === 2,
            'bars: ' + JSON.stringify(got.map(e => e.detail.datum)));
        const bar = one(view, 'bar a', isRow('k', 'a'));
        got = clicked('mc-bars', {x: bar.x, y: 3});
        check(got.length === 0, 'bars: a click on empty plot space dispatched ' + got.length + ' events');

        // Faceted bars: a bar reports its row with the facet field; the empty
        // part of a cell (a group, role "scope") reports nothing.
        view = await ready('mc-facet');
        const right = one(view, 'panel 2 bar b', item => isRow('k', 'b')(item) && item.datum.panel === '2');
        got = clicked('mc-facet', right);
        check(got.length === 1 && got[0].detail.datum.panel === '2' && got[0].detail.datum.v === 4,
            'facet: ' + JSON.stringify(got.map(e => e.detail.datum)));
        const short = one(view, 'panel 2 bar a', item => isRow('k', 'a')(item) && item.datum.panel === '2');
        got = clicked('mc-facet', {x: short.x, y: short.top - 5});
        check(short.top > 10 && got.length === 0,
            'facet: a click on empty cell space (bar top ' + short.top + ') dispatched ' + got.length + ' events');

        // An htmx-style swap: a new element with the same id and its own embed.
        // The old view is disposed and the new one reports each click once.
        const old = AoV.views['mc-bars'], spec = JSON.parse(JSON.stringify(AoV._origSpecs['mc-bars']));
        const fresh = document.createElement('div');
        fresh.id = 'mc-bars';
        document.getElementById('mc-bars').replaceWith(fresh);
        AoV.embed('mc-bars', spec, {actions: false});
        view = await ready('mc-bars', old);
        got = clicked('mc-bars', one(view, 'bar c after swap', isRow('k', 'c')));
        check(got.length === 1 && got[0].detail.datum.k === 'c' && got[0].target === 'mc-bars',
            'bars after swap: ' + JSON.stringify(got.map(e => e.detail.datum)));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-mark-click-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
