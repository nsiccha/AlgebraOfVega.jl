// Pan/zoom clip in the browser (snag `text-marks-above-6e3d5a0b`): AoV's
// automatic pan/zoom no longer cuts marks at the plot frame before the reader
// zooms. At rest, labels placed above the frame are drawn and Vega reserves
// room for them (the view origin moves down); after a wheel zoom the marks are
// cut at the frame along the zoomed axes only, and a double-click reset draws
// them whole again. A layer that authors `clip: true` stays cut. Checked on
// `vdraw` plots and on the bare `to_html(spec)` embed.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(get, what) {
        for (let i = 0; i < 500; i++) {
            const view = get();
            if (view) return view;
            await wait(10);
        }
        throw new Error(what + ': embed did not complete');
    }
    const runtimeView = id => ready(() => !AoV._inFlight[id] && AoV.views[id], id);
    const bareView = id => ready(() => window.aovBareViews && window.aovBareViews[id], id);

    // The data marks (Vega-Lite names them `…marks`) with the offset of their group.
    function dataMarks(view) {
        const out = [];
        (function walk(mark, dx, dy) {
            if (mark.marktype === 'group') {
                (mark.items || []).forEach(g => (g.items || []).forEach(m => walk(m, dx + (g.x || 0), dy + (g.y || 0))));
            } else if (/marks$/.test(mark.name || '')) out.push({mark, dx, dy});
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const clipKind = c => typeof c === 'function' ? 'path' : c === true ? 'frame' : c === false || c === undefined ? 'none' : String(c);
    const clips = view => dataMarks(view).map(({mark}) => clipKind(mark.clip));
    // The view-coordinate boxes of the text items reading one of `texts`.
    function textBoxes(view, texts) {
        const out = [];
        dataMarks(view).forEach(({mark, dx, dy}) => {
            if (mark.marktype !== 'text') return;
            (mark.items || []).forEach(it => {
                if (texts.indexOf(it.text) === -1) return;
                const b = it.bounds;
                out.push({text: it.text, x1: dx + b.x1, y1: dy + b.y1, x2: dx + b.x2, y2: dy + b.y2, mark});
            });
        });
        return out;
    }
    function itemCenter(view, marktype) {
        const found = dataMarks(view).find(({mark}) => mark.marktype === marktype && (mark.items || []).length);
        const it = found.mark.items[0], b = it.bounds;
        return {x: found.dx + (b.x1 + b.x2) / 2, y: found.dy + (b.y1 + b.y2) / 2};
    }
    // Pixels of the drawn canvas inside a view-coordinate box matching `pred`.
    // A box above or left of the canvas is not drawn: 0.
    function ink(el, view, box, pred) {
        const canvas = el.querySelector('canvas'), k = canvas.width / canvas.clientWidth;
        const o = view.origin(), p = view.padding();
        const x0 = Math.floor((box.x1 + o[0] + p.left) * k), y0 = Math.floor((box.y1 + o[1] + p.top) * k);
        const w = Math.ceil((box.x2 - box.x1) * k), h = Math.ceil((box.y2 - box.y1) * k);
        if (x0 < 0 || y0 < 0 || w <= 0 || h <= 0) return 0;
        const d = canvas.getContext('2d').getImageData(x0, y0, w, h).data;
        let n = 0;
        for (let i = 0; i < d.length; i += 4) if (pred(d[i], d[i + 1], d[i + 2], d[i + 3])) n++;
        return n;
    }
    const dark = (r, g, b, a) => a > 100 && r < 128 && g < 128 && b < 128;
    const blue = (r, g, b, a) => a > 100 && b > 120 && r < 120;
    function pointer(el, view, at) {
        const canvas = el.querySelector('canvas'), r = canvas.getBoundingClientRect();
        const o = view.origin(), p = view.padding();
        const opts = {bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, pointerType: 'mouse',
            clientX: r.left + o[0] + p.left + at.x, clientY: r.top + o[1] + p.top + at.y};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        return {canvas, opts};
    }
    async function zoom(el, view, at) {
        const {canvas, opts} = pointer(el, view, at);
        canvas.dispatchEvent(new WheelEvent('wheel', Object.assign({deltaY: -200, deltaMode: 0}, opts)));
        await wait(300);
    }
    async function reset(el, view, at) {
        const {canvas, opts} = pointer(el, view, at);
        canvas.dispatchEvent(new MouseEvent('dblclick', opts));
        await wait(300);
    }
    // The reader has zoomed while the `grid` selection holds a domain (what
    // the zoomed scale reads); a facet's store stays empty.
    const zoomed = view => { const g = view.signal('grid') || {}; return Object.keys(g).some(k => Array.isArray(g[k])); };
    const labelsInk = (el, view, texts) => textBoxes(view, texts).map(b => ink(el, view, b, dark));

    // The reporter's schedule figure: only x zooms.
    async function schedule(id, view, el) {
        const labels = ['M 1', 'M 2'];
        check(view.origin()[1] > 0, id + ': room above the frame at rest (origin ' + view.origin() + ')');
        check(clips(view).every(c => c === 'none'), id + ': marks unclipped at rest: ' + clips(view));
        const restInk = labelsInk(el, view, labels);
        check(restInk.length === 2 && restInk.every(n => n > 0), id + ': labels drawn above the frame at rest: ' + restInk);
        check(!zoomed(view), id + ': nothing zoomed at rest');
        const at = itemCenter(view, 'rect');
        const before = view.scale('x').domain().slice();
        await zoom(el, view, at);
        const after = view.scale('x').domain();
        check(zoomed(view) && after[1] - after[0] < before[1] - before[0],
            id + ': the wheel zoomed x: ' + before + ' -> ' + after);
        check(clips(view).every(c => c === 'path'), id + ': x-only clip once zoomed: ' + clips(view));
        const zoomInk = labelsInk(el, view, labels);
        check(zoomInk.length === 2 && zoomInk.every(n => n > 0), id + ': labels above the frame stay while x is zoomed: ' + zoomInk);
        // Row c's bar runs past the zoomed domain's right end: cut at the frame.
        const w = view.width();
        const cBar = dataMarks(view).find(({mark}) => mark.marktype === 'rect').mark.items
            .find(it => it.datum && it.datum.row === 'c');
        check(!!cBar && cBar.x + cBar.width > w + 3, id + ': the zoomed bar of row c reaches past the frame in data');
        if (cBar) {
            const y = cBar.y + cBar.height / 2;
            check(ink(el, view, {x1: w + 1, x2: w + 4, y1: y - 1, y2: y + 1}, blue) === 0,
                id + ': the bar is cut at the right frame edge');
            check(ink(el, view, {x1: w - 4, x2: w - 1, y1: y - 1, y2: y + 1}, blue) > 0,
                id + ': control: the bar is drawn inside the frame');
        }
        await reset(el, view, at);
        check(!zoomed(view), id + ': double-click resets the zoom');
        check(clips(view).every(c => c === 'none'), id + ': marks unclipped again after the reset: ' + clips(view));
    }

    try {
        const g = await runtimeView('pz-gantt');
        await schedule('pz-gantt', g, document.getElementById('pz-gantt'));

        const padded = await runtimeView('pz-padded');
        check(padded.padding().top === 24, 'pz-padded: authored padding kept');
        const paddedInk = labelsInk(document.getElementById('pz-padded'), padded, ['M 1', 'M 2']);
        check(paddedInk.length === 2 && paddedInk.every(n => n > 0), 'pz-padded: labels drawn: ' + paddedInk);

        // Both axes zoom: the whole frame cuts once zoomed.
        const s = await runtimeView('pz-scatter'), sel = document.getElementById('pz-scatter');
        check(s.origin()[1] > 0, 'pz-scatter: room above the frame at rest');
        check(clips(s).every(c => c === 'none'), 'pz-scatter: unclipped at rest: ' + clips(s));
        const top = labelsInk(sel, s, ['top']);
        check(top.length === 1 && top[0] > 0, 'pz-scatter: label above the frame drawn at rest: ' + top);
        await zoom(sel, s, itemCenter(s, 'symbol'));
        check(zoomed(s), 'pz-scatter: zoomed');
        check(clips(s).every(c => c === 'frame'), 'pz-scatter: whole-frame clip once both axes zoom: ' + clips(s));
        const topZoomed = labelsInk(sel, s, ['top']);
        check(topZoomed.length === 1 && topZoomed[0] === 0, 'pz-scatter: label outside the zoomed frame cut: ' + topZoomed);

        // An authored clip=true is kept.
        const own = await runtimeView('pz-own'), oel = document.getElementById('pz-own');
        const ownText = dataMarks(own).filter(({mark}) => mark.marktype === 'text').map(({mark}) => clipKind(mark.clip));
        const ownRest = dataMarks(own).filter(({mark}) => mark.marktype !== 'text').map(({mark}) => clipKind(mark.clip));
        check(ownText.length === 1 && ownText[0] === 'frame', 'pz-own: the authored clip stays: ' + ownText);
        check(ownRest.length === 2 && ownRest.every(c => c === 'none'), 'pz-own: other layers unclipped at rest: ' + ownRest);
        const ownInk = labelsInk(oel, own, ['M 1', 'M 2']);
        check(ownInk.every(n => n === 0), 'pz-own: its labels stay cut: ' + ownInk);

        // Facet cells: the clip follows the cell's size signal.
        const f = await runtimeView('pz-facet'), fel = document.getElementById('pz-facet');
        const fLabels = textBoxes(f, ['F 1', 'F 2']);
        check(fLabels.length === 2 && fLabels.every(b => clipKind(b.mark.clip) === 'none'), 'pz-facet: labels unclipped at rest');
        check(fLabels.every(b => b.y2 < 0), 'pz-facet: the labels lie above their cells');
        check(f.origin()[1] > 0, 'pz-facet: room above the cells at rest');
        await zoom(fel, f, itemCenter(f, 'rect'));
        check(zoomed(f), 'pz-facet: zoomed');
        check(clips(f).every(c => c === 'path'), 'pz-facet: x-only clip in every cell once zoomed: ' + clips(f));

        // The bare `to_html(spec)` embed draws the same.
        const b = await bareView('pz-bare'), bel = document.getElementById('pz-bare');
        check(b.origin()[1] > 0, 'pz-bare: room above the frame at rest');
        check(clips(b).every(c => c === 'none'), 'pz-bare: unclipped at rest: ' + clips(b));
        const bareInk = labelsInk(bel, b, ['M 1', 'M 2']);
        check(bareInk.length === 2 && bareInk.every(n => n > 0), 'pz-bare: labels drawn at rest: ' + bareInk);
        await zoom(bel, b, itemCenter(b, 'rect'));
        check(zoomed(b) && clips(b).every(c => c === 'path'), 'pz-bare: x-only clip once zoomed: ' + clips(b));
    } catch (e) {
        failures.push('driver error: ' + (e && e.stack || e));
    }

    const pre = document.createElement('pre');
    pre.id = 'aov-pan-zoom-clip-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
