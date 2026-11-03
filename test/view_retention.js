// Vega views a plot element keeps alive (snags attachtouch-clos-f2d7a0dc and
// dispose-in-place-cbce89a5, reporter Bruno:arv393). A plot element must hold
// no view but its current one: a re-embed (resize, picker, theme, update_spec)
// releases the view it replaces, and a plot disposed in place (AoV.dispose /
// disposeWithin, its element left in the page) holds none.
// - The element listeners _attachTouch added once per element shared a scope
//   with the first embed's touchstart handler, so every element kept its first
//   view (data, dataflow, scenegraph) for as long as it stayed in the page.
// - Vega's View.finalize leaves the canvas handler's listeners on the canvas,
//   the svg handler's listeners and every svg node's `__data__` item, and
//   vega-embed's finalize leaves the actions menu's export links: each holds
//   the view. dispose swaps the drawing for a static copy and drops the menu.
//
// The page sets window.AOV_RETENTION_CASE = {renderer, actions}. Views are
// counted through WeakRefs after forced collections (Chrome runs with
// --js-flags=--expose-gc). The driver holds a view or a drawing only through a
// WeakRef: a local in a suspended async function would keep it alive.
(async function () {
    const CASE = window.AOV_RETENTION_CASE || {renderer: 'canvas', actions: false};
    const failures = [], counts = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(CASE.renderer + '/' + (CASE.actions ? 'menu' : 'no menu') + ': ' + message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    // Every view any embed creates, the ones superseded or disposed in
    // flight included (they are never registered). Set up before the plots'
    // embeds run: they wait for the parsed page.
    const created = [];
    const initialize = vega.View.prototype.initialize;
    vega.View.prototype.initialize = function () {
        created.push(new WeakRef(this));
        return initialize.apply(this, arguments);
    };
    // The id's registered view once it is not `previous` (a WeakRef) and no
    // embed of the id is in flight, as a WeakRef.
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== (previous && previous.deref()) && !AoV._inFlight[id]) return new WeakRef(view);
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    async function settled(id) {
        for (let i = 0; i < 500 && AoV._inFlight[id]; i++) await sleep(10);
        if (AoV._inFlight[id]) throw new Error(id + ': embed did not settle');
        await sleep(50);
    }
    async function collect() { for (let i = 0; i < 8; i++) { gc(); await sleep(25); } }
    const alive = refs => refs.filter(r => r.deref() !== undefined).length;
    const drawingOf = id => document.getElementById(id).querySelector('canvas.marks, svg.marks');
    // What the drawing shows: a canvas's pixels, an svg's markup.
    const picture = node => !node ? null : node.localName === 'canvas' ? node.toDataURL() :
        new XMLSerializer().serializeToString(node);
    // Whether the drawing shows any mark: a canvas with an opaque pixel, an
    // svg with a path.
    function painted(node) {
        if (!node) return false;
        if (node.localName !== 'canvas') return !!node.querySelector('path');
        if (!node.width || !node.height) return false;
        const d = node.getContext('2d').getImageData(0, 0, node.width, node.height).data;
        for (let i = 3; i < d.length; i += 4) if (d[i]) return true;
        return false;
    }
    try {
        if (typeof gc !== 'function') throw new Error('gc() is not exposed: run Chrome with --js-flags=--expose-gc');
        const ids = ['vr-1', 'vr-2', 'vr-3', 'vr-4'];
        check(ids.every(id => document.getElementById(id)), 'a plot element is missing');
        const first = [];
        for (const id of ids) first.push(await ready(id, null));
        await collect();
        counts.live = alive(first);
        // Control: WeakRefs to the views of live plots stay set.
        check(counts.live === ids.length, 'live plots lost views: ' + counts.live + ' of ' + ids.length);

        const box = document.getElementById('retention-plots');
        check(ids.every(id => drawingOf(id) && drawingOf(id).localName === (CASE.renderer === 'svg' ? 'svg' : 'canvas')),
            'a plot is not drawn with the ' + CASE.renderer + ' renderer');
        counts.menusBefore = box.querySelectorAll('.vega-actions').length;
        check(counts.menusBefore === (CASE.actions ? ids.length : 0), 'actions menus before dispose: ' + counts.menusBefore);

        // Disposed while an embed is in flight: the embed's view is finalized
        // when it resolves, and its drawing is released as dispose releases
        // one. Done before the other plots re-embed, so that this view is not
        // the most recent one (the residue below).
        const inflight = ids[ids.length - 1], others = ids.slice(0, -1);
        const createdBefore = created.length;
        AoV._reembeds[inflight]();
        check(AoV._inFlight[inflight] > 0, 'the in-flight case started no embed');
        AoV.dispose(inflight);
        await settled(inflight);
        check(created.length === createdBefore + 1, 'the in-flight embed created ' + (created.length - createdBefore) + ' views');
        const inflightView = created[created.length - 1];
        check(painted(drawingOf(inflight)), 'a plot disposed in flight shows no drawing');

        // A re-embed releases the view it replaces: each live plot holds one.
        for (const id of others) AoV._reembeds[id]();
        const second = [];
        for (let i = 0; i < others.length; i++) second.push(await ready(others[i], first[i]));
        await collect();
        counts.replaced = alive(first);
        counts.current = alive(second);
        counts.inflight = alive([inflightView]);
        check(counts.current === others.length, 're-embedded plots lost views: ' + counts.current + ' of ' + others.length);
        // V8 can keep one most-recent view of a spec shape (a constant
        // residue, testing section of the AoV primer); one per element is the
        // defect. This is also the control that collections run and clear
        // WeakRefs (4 live views become at most 1), so a red check below is
        // not a collection that never ran.
        check(counts.replaced <= 1, 're-embedded plot elements still hold their replaced views: ' +
            counts.replaced + ' of ' + ids.length);
        check(counts.inflight === 0, 'a plot disposed while its embed was in flight keeps that embed\'s view');

        // Disposed in place: the registry lets go and the elements stay.
        const pictures = {}, drawings = {};
        ids.forEach(id => { pictures[id] = picture(drawingOf(id)); drawings[id] = new WeakRef(drawingOf(id)); });
        AoV.disposeWithin(box);
        check(Object.keys(AoV.views).length === 0, 'disposeWithin left views registered');
        check(ids.every(id => document.getElementById(id).isConnected), 'disposeWithin removed a plot element');
        // The last frame stays: a copy that shows the same picture.
        check(ids.every(id => drawingOf(id) && picture(drawingOf(id)) === pictures[id]),
            'a disposed plot does not show its last frame unchanged');
        check(ids.slice(0, -1).every(id => drawingOf(id) !== drawings[id].deref()),
            'a plot disposed in place kept its Vega drawing node');
        counts.menusAfter = box.querySelectorAll('.vega-actions').length;
        check(counts.menusAfter === 0, 'disposed plots kept ' + counts.menusAfter + ' actions menus');
        await collect();
        counts.disposedInPlace = alive(created);
        // V8's one-view residue, as above; one per plot is the defect.
        check(counts.disposedInPlace <= 1, 'plots disposed in place still hold views: ' + counts.disposedInPlace +
            ' of ' + created.length + ' created (first embeds ' + alive(first) + ', current ' + alive(second) + ')');
        counts.created = created.length;
    } catch (err) {
        failures.push('driver error: ' + (err && err.stack || err));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-view-retention-results';
    pre.textContent = JSON.stringify({checks, failures, counts});
    document.body.appendChild(pre);
})();
