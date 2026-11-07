// A layer drawn with `visual(...; inspectable=false)` lets the pointer through:
// a mouse click, a hover with its tooltip, a touch tap and a link-group
// announcement over a region name report the district beneath it. The same
// map without it (`pt-control`) is the positive control that the aim lands on
// the name. Also: a scatter whose legend selection makes Vega-Lite mark the
// label interactive, a re-embed, the SVG renderer, and the bare `to_html(spec)`
// embed outside the runtime.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    const events = [], links = [];
    ['aov:click', 'aov:hover', 'aov:hoverend'].forEach(name => document.addEventListener(name,
        e => events.push({type: e.type, target: e.target.id, datum: e.detail.datum})));
    document.addEventListener('htmxo:link', e => links.push(e.detail));
    const take = () => events.splice(0);
    const show = got => JSON.stringify(got.map(e => [e.type, e.target, e.datum]));

    // Scenegraph items matching `pred`, with their position in view coordinates.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2,
                    x1: dx + b.x1, x2: dx + b.x2, y1: dy + b.y1, y2: dy + b.y2});
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
    // The scenegraph's marks (not items) of one marktype.
    function marks(view, type) {
        const out = [];
        (function walk(node) {
            if (node.marktype === type && out.indexOf(node) === -1) out.push(node);
            (node.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const surface = id => document.querySelector('#' + id + ' canvas, #' + id + ' svg');
    // The client point of view coordinates (x, y): through the view origin
    // PLUS its padding, as Vega maps it (see test/mark_click.js).
    function client(id, at, view) {
        view = view || AoV.views[id];
        const rect = surface(id).getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        return {x: rect.left + origin[0] + pad.left + at.x, y: rect.top + origin[1] + pad.top + at.y};
    }
    function mouse(id, at) {
        const p = client(id, at);
        return {bubbles: true, cancelable: true, clientX: p.x, clientY: p.y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
    }
    function clickAt(id, at) {
        const opts = mouse(id, at), target = surface(id);
        target.dispatchEvent(new PointerEvent('pointermove', opts));
        target.dispatchEvent(new PointerEvent('pointerdown', opts));
        target.dispatchEvent(new PointerEvent('pointerup', opts));
        target.dispatchEvent(new MouseEvent('click', opts));
    }
    function hoverAt(id, at) {
        const opts = mouse(id, at), target = surface(id);
        target.dispatchEvent(new PointerEvent('pointermove', opts));
        target.dispatchEvent(new MouseEvent('mousemove', opts));
    }
    function leave(id) {
        const target = surface(id), opts = {bubbles: true, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        target.dispatchEvent(new PointerEvent('pointerout', opts));
        target.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}));
        document.getElementById(id).dispatchEvent(new PointerEvent('pointerleave', {...opts, bubbles: false}));
    }
    // A finger tap, in Chrome's order (see test/touch_input.js); the runtime
    // cancels the touchend of a tap on a mark.
    async function tap(id, at) {
        const p = client(id, at), target = document.elementFromPoint(p.x, p.y);
        if (!surface(id).contains(target)) throw new Error(id + ': no plot under ' + JSON.stringify(p));
        const touch = new Touch({identifier: 7, target, clientX: p.x, clientY: p.y});
        const pointer = {bubbles: true, cancelable: true, composed: true, clientX: p.x, clientY: p.y,
            pointerId: 107, isPrimary: true, pointerType: 'touch'};
        target.dispatchEvent(new PointerEvent('pointerover', pointer));
        target.dispatchEvent(new PointerEvent('pointerdown', pointer));
        target.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, cancelable: true, composed: true,
            touches: [touch], changedTouches: [touch]}));
        await sleep(60);
        target.dispatchEvent(new PointerEvent('pointerup', pointer));
        target.dispatchEvent(new PointerEvent('pointerout', pointer));
        [target, document.getElementById(id)].forEach(el => el.dispatchEvent(new PointerEvent('pointerleave', {...pointer, bubbles: false})));
        target.dispatchEvent(new TouchEvent('touchend', {bubbles: true, cancelable: true, composed: true,
            touches: [], changedTouches: [touch]}));
        await sleep(30);
    }
    function tip() {
        const el = document.querySelector('.vg-tooltip');
        return el && el.classList.contains('visible') ? el.textContent : null;
    }
    const isText = item => item.mark.role === 'mark' && item.mark.marktype === 'text';
    // The ink of the name (the halo is drawn under it, white).
    const ink = item => isText(item) && item.fill !== 'white';
    const district = ags => item => item.mark.role === 'mark' && item.mark.marktype === 'shape' && item.datum && item.datum.AGS === ags;

    try {
        // --- The control: the same map with names that take the pointer ---
        let view = await ready('pt-control');
        const cname = one(view, 'control name', ink);
        check(cname.item.mark.interactive !== false, 'control: the name is not interactive');
        take();
        clickAt('pt-control', cname);
        let got = take().filter(e => e.type === 'aov:click');
        check(got.length === 1 && got[0].datum.name === 'Mitte',
            'control: a click on the name did not report the name (aim check): ' + show(got));
        hoverAt('pt-control', cname);
        await sleep(20);
        check((tip() || '').indexOf('Mitte') !== -1, 'control: hovering the name shows ' + JSON.stringify(tip()));
        leave('pt-control');
        await sleep(20);

        // --- The map: both name layers let the pointer through ---
        view = await ready('pt-map');
        const texts = marks(view, 'text').filter(m => m.role === 'mark');
        check(texts.length === 2 && texts.every(m => m.interactive === false),
            'map: name marks interactive: ' + JSON.stringify(texts.map(m => m.interactive)));
        check(marks(view, 'shape').every(m => m.interactive !== false), 'map: the districts lost the pointer');
        const name = one(view, 'map name', ink), d2 = one(view, 'district 01002', district('01002'));
        check(name.x > d2.x1 && name.x < d2.x2 && name.y > d2.y1 && name.y < d2.y2,
            'map: the name is not over district 01002');
        take();
        clickAt('pt-map', name);
        got = take();
        const clicks = got.filter(e => e.type === 'aov:click');
        check(clicks.length === 1 && clicks[0].datum.AGS === '01002' && clicks[0].target === 'pt-map',
            'map: a click on the name reported ' + show(got));
        check(!got.some(e => e.datum && e.datum.name), 'map: an event reported the name: ' + show(got));
        leave('pt-map');
        await sleep(20);

        take();
        links.length = 0;
        hoverAt('pt-map', name);
        await sleep(20);
        got = take();
        check(got.length >= 1 && got.every(e => e.type === 'aov:hover' && e.datum.AGS === '01002'),
            'map: hovering the name reported ' + show(got));
        const shown = tip() || '';
        check(shown.indexOf('01002') !== -1 && shown.indexOf('Mitte') === -1,
            'map: hovering the name shows the tooltip ' + JSON.stringify(shown));
        check(links.some(l => l.group === 'pt' && l.key === '01002'),
            'map: the link group heard ' + JSON.stringify(links.map(l => [l.group, l.key])));
        leave('pt-map');
        await sleep(20);

        take();
        await tap('pt-map', name);
        got = take();
        check(got.some(e => e.type === 'aov:hover' && e.datum.AGS === '01002') && !got.some(e => e.datum && e.datum.name),
            'map: a tap on the name reported ' + show(got));
        check((tip() || '').indexOf('01002') !== -1, 'map: a tap on the name shows ' + JSON.stringify(tip()));
        // A tap on empty space closes the tap's tooltip and hover.
        document.body.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, pointerType: 'mouse'}));
        await sleep(20);

        // A re-embed (as a theme switch or a resize does) compiles the spec
        // again: still through.
        AoV._reembeds['pt-map']();
        view = await ready('pt-map', view);
        const again = one(view, 'map name after re-embed', ink);
        take();
        clickAt('pt-map', again);
        got = take().filter(e => e.type === 'aov:click');
        check(got.length === 1 && got[0].datum.AGS === '01002', 'map after re-embed: ' + show(got));

        // --- A scatter: its legend selection makes Vega-Lite mark every layer
        // with a tooltip interactive, the label included ---
        view = await ready('pt-scatter');
        const label = one(view, 'scatter label', isText);
        check(label.item.mark.interactive === false, 'scatter: the label is interactive');
        const b = one(view, 'point b', item => item.mark.role === 'mark' && item.mark.marktype === 'symbol' && item.datum && item.datum.g === 'b');
        check(b.x > label.x1 && b.x < label.x2 && b.y > label.y1 && b.y < label.y2,
            'scatter: point b is not under the label');
        take();
        clickAt('pt-scatter', b);
        got = take().filter(e => e.type === 'aov:click');
        check(got.length === 1 && got[0].datum.g === 'b', 'scatter: a click on the label reported ' + show(got));
        const entry = one(view, 'legend entry c', item => item.mark.role === 'legend-symbol' && item.datum && item.datum.value === 'c');
        clickAt('pt-scatter', entry);
        await sleep(20);
        check(view.data('legend_selection_store').length === 1, 'scatter: the legend no longer selects');
        leave('pt-scatter');

        // --- The SVG renderer: the browser's own hit test passes the name ---
        AoV.embed('pt-svg', JSON.parse(JSON.stringify(AoV._origSpecs['pt-map'])), {actions: false, renderer: 'svg'});
        view = await ready('pt-svg');
        const sname = one(view, 'svg name', ink);
        const p = client('pt-svg', sname, view);
        const hit = document.elementFromPoint(p.x, p.y);
        const datum = hit && hit.__data__ && hit.__data__.datum;
        check(!!hit && !hit.closest('.mark-text') && datum && datum.AGS === '01002',
            'svg: the element under the name is ' + (hit && hit.outerHTML.slice(0, 80)));
        check(Array.from(document.querySelectorAll('#pt-svg .mark-text')).every(g => getComputedStyle(g).pointerEvents === 'none'),
            'svg: a name group takes pointer events');

        // --- The bare `to_html(spec)` embed, outside the runtime ---
        let bare = null;
        for (let i = 0; i < 500 && !bare; i++) { bare = window.__ptViews['#pt-bare']; if (!bare) await sleep(10); }
        check(!!bare, 'bare: no view');
        if (bare) {
            const bt = marks(bare, 'text').filter(m => m.role === 'mark');
            check(bt.length === 2 && bt.every(m => m.interactive === false),
                'bare: name marks interactive: ' + JSON.stringify(bt.map(m => m.interactive)));
            check(marks(bare, 'shape').every(m => m.interactive !== false), 'bare: the districts lost the pointer');
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-pointer-through-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
