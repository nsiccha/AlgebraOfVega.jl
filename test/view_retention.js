// Vega views a plot element keeps alive (snag attachtouch-clos-f2d7a0dc,
// reporter Bruno:arv393). A plot element must hold no view but its current
// one: a re-embed (resize, picker, theme, update_spec) releases the view it
// replaces, and a plot disposed in place (AoV.dispose / disposeWithin, its
// element left in the page) holds none once its drawing is replaced by a
// static snapshot. The element listeners _attachTouch added once per element
// shared a scope with the first embed's touchstart handler, so every element
// kept its first view (data, dataflow, scenegraph) for as long as it stayed
// in the page: two views per live plot, one per released one.
//
// Views are counted through WeakRefs after forced collections (Chrome runs
// with --js-flags=--expose-gc). The driver holds a view only through a
// WeakRef: a local in a suspended async function would keep it alive.
(async function () {
    const failures = [], counts = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
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
    async function collect() { for (let i = 0; i < 8; i++) { gc(); await sleep(25); } }
    const alive = refs => refs.filter(r => r.deref() !== undefined).length;
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

        // A re-embed releases the view it replaces: each live plot holds one.
        for (const id of ids) AoV._reembeds[id]();
        const second = [];
        for (let i = 0; i < ids.length; i++) second.push(await ready(ids[i], first[i]));
        await collect();
        counts.replaced = alive(first);
        counts.current = alive(second);
        check(counts.current === ids.length, 're-embedded plots lost views: ' + counts.current + ' of ' + ids.length);
        // V8 can keep one most-recent view of a spec shape (a constant
        // residue, testing section of the AoV primer); one per element is the defect.
        check(counts.replaced <= 1, 're-embedded plot elements still hold their replaced views: ' +
            counts.replaced + ' of ' + ids.length);

        // Disposed in place: the registry lets go and the elements stay.
        const box = document.getElementById('retention-plots');
        AoV.disposeWithin(box);
        check(Object.keys(AoV.views).length === 0, 'disposeWithin left views registered');
        check(ids.every(id => document.getElementById(id).isConnected), 'disposeWithin removed a plot element');
        await collect();
        // Not asserted: a canvas left in the page keeps its own view through
        // Vega's canvas listeners, which View.finalize does not remove.
        counts.disposedCanvasKept = alive(first) + alive(second);
        // A static snapshot, as a report's plot release takes one: each canvas
        // is replaced by an image of its size, the plot element stays.
        box.querySelectorAll('canvas').forEach(canvas => {
            const img = document.createElement('img');
            img.width = canvas.clientWidth;
            img.height = canvas.clientHeight;
            canvas.replaceWith(img);
        });
        await collect();
        counts.snapshotReplaced = alive(first);
        counts.snapshotCurrent = alive(second);
        // Control: collections run and clear WeakRefs. This holds without the
        // fix too, so a red check above is not a collection that never ran.
        check(counts.snapshotCurrent <= 1, 'replacing the canvases released no current view: ' +
            counts.snapshotCurrent + ' of ' + ids.length);
        check(counts.snapshotReplaced + counts.snapshotCurrent <= 1,
            'plot elements disposed in place still hold views: ' + (counts.snapshotReplaced + counts.snapshotCurrent) +
            ' (first embeds ' + counts.snapshotReplaced + ', current ' + counts.snapshotCurrent + ')');
    } catch (err) {
        failures.push('driver error: ' + (err && err.stack || err));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-view-retention-results';
    pre.textContent = JSON.stringify({checks, failures, counts});
    document.body.appendChild(pre);
})();
