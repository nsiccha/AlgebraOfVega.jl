// Touch input in the browser. A finger has no hover, and Vega picks a canvas
// mark only on pointermove, which a tap never sends, so the runtime reads
// touches itself (`_attachTouch`): a tap on a data mark opens its tooltip
// above the finger and hovers its row (aov:hover, link groups) until a tap
// on empty plot space, a press outside the plot, a finger drag on the plot,
// a re-embed or the plot's removal; a long press on a mark is its click (one
// aov:click); a tap never clicks. Touches are sent as Chrome sends them
// (measured over CDP touch input): pointer events, then the touch event,
// and after a touchend nobody cancelled, the mouse events Chrome emulates
// and its click, ending with the mouseout it sends after a tap.
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
        e => events.push({type: e.type, target: e.target.id, datum: e.detail.datum, event: e.detail.event})));
    document.addEventListener('htmxo:link', e => links.push(e.detail));
    const take = () => events.splice(0);
    const show = got => JSON.stringify(got.map(e => [e.type, e.target, e.datum]));
    const kinds = got => got.map(e => e.type).join(',');

    // Scenegraph items matching `pred`, with their position in view coordinates.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds;
                out.push({item, x: dx + (b.x1 + b.x2) / 2, y: dy + (b.y1 + b.y2) / 2, top: dy + b.y1});
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
    const surface = id => document.querySelector('#' + id + ' canvas, #' + id + ' svg');
    // The client point of view coordinates (x, y): through the view origin
    // PLUS its padding, as Vega maps it (see test/mark_click.js).
    function client(id, at) {
        const view = AoV.views[id], rect = surface(id).getBoundingClientRect();
        const origin = view.origin(), pad = view.padding();
        return {x: rect.left + origin[0] + pad.left + at.x, y: rect.top + origin[1] + pad.top + at.y};
    }

    // A finger at client point p of plot `id`, targeting what is drawn there
    // (the canvas, or the SVG element under the point).
    let fingers = 0;
    function fingerDown(id, p, others) {
        const target = document.elementFromPoint(p.x, p.y);
        if (!surface(id).contains(target)) throw new Error(id + ': no plot under ' + JSON.stringify(p));
        const n = ++fingers, touch = new Touch({identifier: n, target, clientX: p.x, clientY: p.y});
        const pointer = {bubbles: true, cancelable: true, composed: true, clientX: p.x, clientY: p.y,
            pointerId: 100 + n, isPrimary: !others, pointerType: 'touch'};
        target.dispatchEvent(new PointerEvent('pointerover', pointer));
        target.dispatchEvent(new PointerEvent('pointerdown', pointer));
        target.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, cancelable: true, composed: true,
            touches: (others || []).map(f => f.touch).concat([touch]), changedTouches: [touch]}));
        return {id, target, touch, pointer, p, moved: false};
    }
    function fingerMove(f, p) {
        f.moved = true;
        const touch = new Touch({identifier: f.touch.identifier, target: f.target, clientX: p.x, clientY: p.y});
        f.target.dispatchEvent(new PointerEvent('pointermove', {...f.pointer, clientX: p.x, clientY: p.y}));
        f.target.dispatchEvent(new TouchEvent('touchmove', {bubbles: true, cancelable: true, composed: true,
            touches: [touch], changedTouches: [touch]}));
        f.target.dispatchEvent(new PointerEvent('pointercancel', {...f.pointer, clientX: p.x, clientY: p.y}));
    }
    // The finger lifts. `cancelable: false` is a touchend the page may not
    // cancel; the emulated click then carries no pointerType, as in a
    // browser whose click is a plain MouseEvent.
    function fingerUp(f, cancelable = true) {
        const plot = document.getElementById(f.id);
        f.target.dispatchEvent(new PointerEvent('pointerup', f.pointer));
        f.target.dispatchEvent(new PointerEvent('pointerout', f.pointer));
        [f.target, plot].forEach(el => el.dispatchEvent(new PointerEvent('pointerleave', {...f.pointer, bubbles: false})));
        const end = new TouchEvent('touchend', {bubbles: true, cancelable, composed: true,
            touches: [], changedTouches: [f.touch]});
        f.target.dispatchEvent(end);
        if (!end.defaultPrevented && !f.moved) {
            const mouse = {bubbles: true, cancelable: true, composed: true, clientX: f.p.x, clientY: f.p.y};
            ['mouseover', 'mousemove', 'mousedown', 'mouseup'].forEach(t => f.target.dispatchEvent(new MouseEvent(t, mouse)));
            f.target.dispatchEvent(cancelable ? new PointerEvent('click', {...mouse, pointerType: 'touch'}) : new MouseEvent('click', mouse));
            f.target.dispatchEvent(new MouseEvent('mouseout', mouse));
        }
        return end;
    }
    async function tap(id, at, cancelable = true) {
        const f = fingerDown(id, client(id, at));
        await sleep(60);
        const end = fingerUp(f, cancelable);
        await sleep(30);
        return {f, end};
    }
    // A mouse click as a pointer sends it (see test/mark_click.js).
    function mouseClick(id, at) {
        const p = client(id, at), target = surface(id);
        const opts = {bubbles: true, cancelable: true, clientX: p.x, clientY: p.y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        target.dispatchEvent(new PointerEvent('pointermove', opts));
        target.dispatchEvent(new PointerEvent('pointerdown', opts));
        target.dispatchEvent(new PointerEvent('pointerup', opts));
        target.dispatchEvent(new MouseEvent('click', opts));
    }
    // The tooltip shown, if any: its text and where it is.
    function tip() {
        const el = document.querySelector('.vg-tooltip');
        if (!el || !el.classList.contains('visible')) return null;
        const r = el.getBoundingClientRect();
        return {text: el.textContent, top: r.top, bottom: r.bottom, left: r.left, right: r.right};
    }
    const district = ags => item => item.mark.role === 'mark' && item.mark.marktype === 'shape' && item.datum && item.datum.AGS === ags;
    const bar = k => item => item.mark.role === 'mark' && item.mark.marktype === 'rect' && item.datum && item.datum.k === k;

    try {
        // --- A map (canvas) in a link group ---
        let view = await ready('tt-map');
        const d2 = one(view, 'district 01002', district('01002')), d3 = one(view, 'district 01003', district('01003'));
        const d1 = one(view, 'district 01001', district('01001'));
        // A tap hovers the district and leaves its tooltip open, above the
        // finger; the touchend is cancelled, so no click and no emulated
        // mouse events follow.
        links.length = 0;
        let {f, end} = await tap('tt-map', d2);
        let got = take();
        check(kinds(got) === 'aov:hover' && got[0].datum.AGS === '01002' && got[0].target === 'tt-map',
            'map tap: ' + show(got));
        check(got[0] && got[0].event instanceof TouchEvent, 'map tap: aov:hover detail.event is not the touch');
        check(end.defaultPrevented, 'map tap: the touchend of a tap on a mark is not cancelled');
        check(links.length === 1 && links[0].group === 'districts' && links[0].key === '01002',
            'map tap: link announcements ' + JSON.stringify(links.map(l => [l.group, l.key])));
        let t = tip();
        check(t && t.text.includes('01002'), 'map tap: tooltip ' + JSON.stringify(t));
        check(t && t.bottom <= f.p.y - AoV._TOUCH_TIP_GAP + 0.5 && t.left <= f.p.x && t.right >= f.p.x,
            'map tap: tooltip not above the finger at ' + JSON.stringify(f.p) + ': ' + JSON.stringify(t));
        await sleep(800);
        check(tip() && tip().text.includes('01002') && take().length === 0, 'map tap: the tooltip did not stay');

        // The page scrolls: the tooltip moves with the tapped spot. (Headless
        // virtual time skips the rendering step that fires `scroll`, so the
        // driver fires it as the browser does.)
        const before = tip();
        window.scrollBy(0, 30);
        document.dispatchEvent(new Event('scroll', {bubbles: true}));
        await sleep(30);
        const after = tip();
        check(after && before && window.scrollY === 30 && Math.abs(before.top - after.top - 30) < 1,
            'map scroll: tooltip at ' + JSON.stringify(before) + ' then ' + JSON.stringify(after) + ', scrollY ' + window.scrollY);
        window.scrollTo(0, 0);
        document.dispatchEvent(new Event('scroll', {bubbles: true}));
        await sleep(30);

        // A tap on the same district keeps it; a tap on another moves both.
        links.length = 0;
        await tap('tt-map', d2);
        got = take();
        check(got.length === 0 && tip() && tip().text.includes('01002'), 'map tap again: ' + show(got));
        await tap('tt-map', d3);
        got = take();
        check(kinds(got) === 'aov:hoverend,aov:hover' && got[0].datum.AGS === '01002' && got[1].datum.AGS === '01003',
            'map tap on another district: ' + show(got));
        check(tip() && tip().text.includes('01003'), 'map tap on another district: tooltip ' + JSON.stringify(tip()));
        check(JSON.stringify(links.map(l => l.key)) === '[null,"01003"]', 'map tap on another district: links ' + JSON.stringify(links.map(l => l.key)));

        // A press outside the plot closes it.
        links.length = 0;
        document.body.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, pointerType: 'touch', clientX: 5, clientY: 5}));
        got = take();
        check(kinds(got) === 'aov:hoverend' && got[0].datum.AGS === '01003' && !tip(), 'map press outside: ' + show(got));
        check(links.length === 1 && links[0].key === null, 'map press outside: links ' + JSON.stringify(links.map(l => l.key)));

        // A long press is the click: the tooltip and hover, then one
        // aov:click; the context menu over the mark and the click on release
        // are suppressed.
        f = fingerDown('tt-map', client('tt-map', d1));
        await sleep(AoV._TOUCH_HOLD_MS + 100);
        got = take();
        check(kinds(got) === 'aov:hover,aov:click' && got[1].datum.AGS === '01001' && got[1].target === 'tt-map',
            'map long press: ' + show(got));
        check(got[1] && got[1].event instanceof TouchEvent && got[1].event.type === 'touchstart',
            'map long press: aov:click detail.event is not the touchstart');
        let menu = new MouseEvent('contextmenu', {bubbles: true, cancelable: true, clientX: f.p.x, clientY: f.p.y});
        f.target.dispatchEvent(menu);
        check(menu.defaultPrevented, 'map long press: the context menu is not suppressed');
        end = fingerUp(f);
        await sleep(30);
        got = take();
        check(end.defaultPrevented && got.length === 0, 'map long press release: ' + show(got));
        check(tip() && tip().text.includes('01001'), 'map long press: tooltip ' + JSON.stringify(tip()));
        // A context menu opened on release (after the hold) is suppressed too.
        menu = new MouseEvent('contextmenu', {bubbles: true, cancelable: true});
        f.target.dispatchEvent(menu);
        check(menu.defaultPrevented, 'map long press: a context menu on release is not suppressed');

        // A browser that opens the context menu before the hold time (Android)
        // makes it the long press at once.
        f = fingerDown('tt-map', client('tt-map', d2));
        await sleep(100);
        menu = new MouseEvent('contextmenu', {bubbles: true, cancelable: true, clientX: f.p.x, clientY: f.p.y});
        f.target.dispatchEvent(menu);
        got = take();
        check(menu.defaultPrevented && kinds(got) === 'aov:hoverend,aov:hover,aov:click' && got[2].datum.AGS === '01002',
            'map context-menu long press: ' + show(got));
        await sleep(AoV._TOUCH_HOLD_MS);
        fingerUp(f);
        await sleep(30);
        check(take().length === 0, 'map context-menu long press: a second click');

        // A finger that moves (a scroll) presses nothing and closes the tooltip.
        f = fingerDown('tt-map', client('tt-map', d3));
        await sleep(50);
        fingerMove(f, {x: f.p.x, y: f.p.y - 40});
        end = fingerUp(f);
        await sleep(AoV._TOUCH_HOLD_MS + 100);
        got = take();
        check(kinds(got) === 'aov:hoverend' && got[0].datum.AGS === '01002' && !tip() && !end.defaultPrevented,
            'map drag: ' + show(got));
        // A second finger (a pinch) presses nothing.
        const first = fingerDown('tt-map', client('tt-map', d1));
        const second = fingerDown('tt-map', client('tt-map', d3), [first]);
        await sleep(AoV._TOUCH_HOLD_MS + 100);
        fingerUp(second);
        fingerUp(first);
        await sleep(30);
        check(take().length === 0 && !tip(), 'map pinch: ' + show(events));
        // A right click (no touch) keeps its context menu.
        menu = new MouseEvent('contextmenu', {bubbles: true, cancelable: true});
        surface('tt-map').dispatchEvent(menu);
        check(!menu.defaultPrevented, 'map right click: the context menu is suppressed');

        // Mouse input is unchanged, also right after touches.
        mouseClick('tt-map', d2);
        got = take();
        check(got.filter(e => e.type === 'aov:click').length === 1 && got.some(e => e.type === 'aov:hover' && e.datum.AGS === '01002'),
            'map mouse click after touches: ' + show(got));
        surface('tt-map').dispatchEvent(new PointerEvent('pointerout', {bubbles: true, pointerType: 'mouse'}));
        document.getElementById('tt-map').dispatchEvent(new PointerEvent('pointerleave', {pointerType: 'mouse'}));
        await sleep(10);
        take();

        // A re-embed closes the open tooltip (its item is gone); the new view taps.
        await tap('tt-map', d2);
        take();
        AoV._reembeds['tt-map']();
        view = await ready('tt-map', view);
        got = take();
        check(kinds(got) === 'aov:hoverend' && !tip(), 'map re-embed with an open tooltip: ' + show(got));
        await tap('tt-map', one(view, 'district 01003 after re-embed', district('01003')));
        got = take();
        check(kinds(got) === 'aov:hover' && got[0].datum.AGS === '01003' && tip(), 'map tap after re-embed: ' + show(got));

        // --- A scatter with the nearest-point overlay ---
        view = await ready('tt-scatter');
        const pb = one(view, 'point b', item => item.mark.role === 'mark' && item.mark.marktype === 'symbol' && item.datum && item.datum.g === 'b');
        // A tap on another plot closes the map's tooltip first.
        await tap('tt-scatter', {x: pb.x + 3, y: pb.y + 2});
        got = take();
        check(kinds(got) === 'aov:hoverend,aov:hover' && got[0].target === 'tt-map' && got[1].target === 'tt-scatter' &&
            got[1].datum.g === 'b' && got[1].datum.y === 4, 'scatter tap: ' + show(got));
        check(tip() && tip().text.includes('4'), 'scatter tap: tooltip ' + JSON.stringify(tip()));
        f = fingerDown('tt-scatter', client('tt-scatter', pb));
        await sleep(AoV._TOUCH_HOLD_MS + 100);
        fingerUp(f);
        await sleep(30);
        got = take();
        check(kinds(got) === 'aov:click' && got[0].datum.g === 'b', 'scatter long press: ' + show(got));

        // --- Bars: empty plot space closes ---
        view = await ready('tt-bars');
        const bb = one(view, 'bar b', bar('b'));
        await tap('tt-bars', bb);
        got = take();
        check(kinds(got) === 'aov:hoverend,aov:hover' && got[1].datum.k === 'b' && tip(), 'bars tap: ' + show(got));
        ({end} = await tap('tt-bars', {x: bb.x, y: 3}));
        got = take();
        check(kinds(got) === 'aov:hoverend' && got[0].datum.k === 'b' && !tip(), 'bars tap on empty space: ' + show(got));
        check(!end.defaultPrevented, 'bars tap on empty space: its touchend is cancelled');

        // --- SVG: Vega's own click after a tap names the mark ---
        const svgEl = document.createElement('div');
        svgEl.id = 'tt-svg';
        document.getElementById('tt-bars').after(svgEl);
        AoV.embed('tt-svg', JSON.parse(JSON.stringify(AoV._origSpecs['tt-bars'])), {actions: false, renderer: 'svg'});
        view = await ready('tt-svg');
        check(!!document.querySelector('#tt-svg svg'), 'svg: not drawn as SVG');
        const sb = one(view, 'svg bar c', bar('c'));
        await tap('tt-svg', sb);
        got = take();
        check(kinds(got) === 'aov:hover' && got[0].datum.k === 'c' && tip() && tip().text.includes('4'), 'svg tap: ' + show(got));
        // A touchend the page may not cancel: the emulated mouse events and
        // click (no pointerType) neither click nor end the hover. (Vega's SVG
        // handler hides its tooltip on their mouseout by itself.)
        await tap('tt-svg', sb, false);
        await sleep(300);
        got = take();
        check(got.length === 0 && AoV._hovers['tt-svg'] && AoV._hovers['tt-svg'].row.k === 'c',
            'svg tap with an uncancellable touchend: ' + show(got));

        // --- Removal: the plot's tooltip and hover go with it ---
        await tap('tt-bars', bb);
        take();
        check(tip() && AoV._hovers['tt-bars'], 'bars tap before removal: ' + JSON.stringify(tip()));
        document.getElementById('tt-bars').remove();
        await sleep(50);
        check(!tip(), 'bars removed with an open tooltip: the tooltip stayed ' + JSON.stringify(tip()));
        check(!AoV._touches['tt-bars'] && !AoV._hovers['tt-bars'], 'bars removed with an open tooltip: its touch or hover state stayed');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-touch-input-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
