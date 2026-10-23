// Plots in a tabset panel that was hidden when they embedded. The page opens
// with `?tab=hidden`, so the tabset's restore script shows that panel after its
// plots embedded into it: each embedded into a container that offered no
// width. Once the panel shows, they fill it — a plain single view too, which
// no ResizeObserver watched before — and a plot re-embedded while hidden (a
// theme change, `update_spec`) re-sizes when the panel shows again at the
// width it had before.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    const el = id => document.getElementById(id);
    const canvasWidth = id => el(id).querySelector('canvas.marks').clientWidth;
    const offered = id => el(id).parentElement.clientWidth;
    const panels = Array.from(document.querySelectorAll('.tabset > .tab-panel'));
    const show = name => panels.forEach(p => p.classList.toggle('u-hidden', p !== el(name).closest('.tab-panel')));
    // What the ResizeObserver does when the panel's layout changes, called the
    // way it calls it: headless virtual time delivers its notifications after
    // load unreliably (fit_width.js). Synchronous, so it runs before an
    // observer notification for the same change can.
    function observe(id) {
        const before = AoV.views[id];
        const resized = AoV._measurableAgain(id, el(id)) && AoV._resizeReembed(id);
        return {resized, done: resized ? ready(id, before) : Promise.resolve()};
    }
    async function observed(id) {
        const o = observe(id);
        await o.done;
        return o.resized;
    }

    try {
        for (const id of ['hp-shown', 'hp-layered', 'hp-single', 'hp-wrap']) await ready(id);
        // The shown-on-load panel's ResizeObserver re-sizes its plots; let it settle.
        await pause(600);
        check(!el('hp-layered').closest('.tab-panel').classList.contains('u-hidden'),
            'the ?tab=hidden panel is not shown');
        for (const id of ['hp-layered', 'hp-single']) {
            const w = canvasWidth(id), budget = offered(id);
            check(w > budget - 40 && w <= budget + 2, id + ' is ' + w + 'px wide in a ' + budget + 'px panel');
            check(!AoV._unmeasured[id], id + ' still waits for a width');
        }
        check(!AoV._unmeasured['hp-shown'], 'the default panel\'s plot waits for a width');

        // Hidden again, re-embedded there, then shown at the width it had.
        show('hp-shown');
        for (const id of ['hp-layered', 'hp-single']) {
            const before = AoV.views[id];
            AoV._reembeds[id]();
            await ready(id, before);
            check(AoV._unmeasured[id] === true, id + ' re-embedded while hidden is not marked unmeasured');
        }
        check(!(await observed('hp-shown')), 'the shown plot re-embeds on an unchanged container');
        show('hp-layered');
        check(AoV.views['hp-layered'].width() === 400,
            'hp-layered hidden width ' + AoV.views['hp-layered'].width() + ', expected its 400px fallback');
        check(canvasWidth('hp-single') === 0, 'hp-single hidden width ' + canvasWidth('hp-single'));
        const shown = ['hp-layered', 'hp-single'].map(id => [id, observe(id)]);
        for (const [id, o] of shown) {
            check(o.resized, id + ' did not re-size when its panel was shown');
            await o.done;
            const w = canvasWidth(id), budget = offered(id);
            check(w > budget - 40 && w <= budget + 2, id + ' is ' + w + 'px wide in a ' + budget + 'px panel after showing again');
            check(!AoV._unmeasured[id], id + ' still waits for a width after showing again');
            check(!(await observed(id)), id + ' re-sizes again with no change');
        }

        // A container that shrink-wraps the plot still offers no width when
        // shown: the plot keeps its fallback and nothing re-embeds in a loop.
        check(AoV._unmeasured['hp-wrap'] === true, 'shrink-wrapped plot is not marked unmeasured');
        check(!(await observed('hp-wrap')), 'shrink-wrapped plot re-embeds although its container offers no width');
        check(AoV.views['hp-wrap'].width() === 400, 'shrink-wrapped plot width ' + AoV.views['hp-wrap'].width());
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-hidden-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
