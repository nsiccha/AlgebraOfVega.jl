// A figure whose axis lists its tick values, swapped in under the same plot
// id with other rows and another tick list, keeps its view and draws the new
// ticks. See test/axis_values_swap.jl.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    const uncaught = [];
    window.addEventListener('error', e => uncaught.push(String(e.message)));
    const logged = [];
    const consoleError = console.error;
    console.error = function () { logged.push(Array.prototype.map.call(arguments, String).join(' ')); return consoleError.apply(console, arguments); };
    async function until(ready, what) {
        for (let i = 0; i < 400; i++) {
            if (ready()) return true;
            await pause(25);
        }
        failures.push(what + ': timed out');
        return false;
    }
    const FIX = window.AOV_FIXTURES, TICKS = window.AOV_TICKS;
    const swap = (target, html) => htmx.swap(target, html, {swapStyle: 'innerHTML', settleDelay: 20},
        {contextElement: target});
    const answer = (fixture, note) => '<div class="answer"><p class="note">' + note + '</p>' + fixture + '</div>';
    const shown = id => document.getElementById(id);
    const view = id => AoV.views[id];
    const ownView = id => !!view(id) && !!shown(id) && shown(id).contains(view(id).container());

    // The label values of every bottom axis the view draws (each wrapped
    // panel has its own), as sorted lists of numbers. Hidden labels count:
    // what matters is which ticks the axis has.
    function bottomTicks(id) {
        const out = [];
        (function walk(item) {
            if (!item) return;
            if (item.marktype === 'group' && item.role === 'axis') {
                (item.items || []).forEach(axis => {
                    if (axis.orient !== 'bottom') return;
                    let values = [];
                    (function labels(it) {
                        if (!it) return;
                        if (it.role === 'axis-label') (it.items || []).forEach(l => values.push(+l.datum.value));
                        (it.items || []).forEach(labels);
                    })(axis);
                    if (values.length) out.push(values.sort((a, b) => a - b));
                });
                return;
            }
            (item.items || []).forEach(walk);
        })(view(id) && view(id).scenegraph().root);
        return out;
    }
    const want = key => TICKS[key].map(v => typeof v === 'string' ? new Date(v).getTime() : v).sort((a, b) => a - b);
    function ticksAre(id, key, stage) {
        const got = bottomTicks(id), w = JSON.stringify(want(key));
        check(got.length > 0, stage + ': the plot draws a bottom axis with labels');
        check(got.every(t => JSON.stringify(t) === w),
            stage + ': every bottom axis shows the ticks ' + w + ' (got ' + JSON.stringify(got) + ')');
    }

    async function settled(id, stage) {
        await until(() => ownView(id) && !AoV._inFlight[id] && !(AoV._adopting || {})[id], stage + ': the figure settles');
        await pause(600);   // a fit correction re-embeds once
        check(document.querySelectorAll('[id="' + id + '"]').length === 1, stage + ': one element has the id');
        check(ownView(id), stage + ': the plot has a view, drawn in the shown element');
        return {view: view(id), el: shown(id)};
    }
    async function kept(id, stage, before, note) {
        const now = await settled(id, stage);
        check(now.view === before.view, stage + ': the view is kept (no new embed)');
        check(now.el === before.el, stage + ': the plot element is kept');
        if (note) {
            const a = now.el && now.el.closest('.answer');
            check(!!a && a.querySelector('.note').textContent === note, stage + ': the plot sits in the new answer');
        }
        return now;
    }

    // --- Bruno's Dose–response figure ---
    const ID = 'dr-plot', SEL = '[data-aov-ribbon-view-for="' + ID + '"]';
    const result = document.getElementById('result');
    swap(result, answer(FIX.a, 'Dose 60 mg'));
    let state = await settled(ID, 'first render');
    ticksAre(ID, 'a', 'first render');
    // The reader picks the other drawing (as on the reporter's page).
    const buttons = () => shown(ID) ? shown(ID).closest('figure').querySelectorAll(SEL) : [];
    const started = AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view;
    const other = Array.from(buttons()).find(b => b.dataset.view !== started);
    check(!!started && !!other, 'first render: a Ribbons | Intervals switch');
    const chosen = other && other.dataset.view;
    if (other) other.click();
    await until(() => AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view === chosen && ownView(ID) &&
        view(ID) !== state.view, 'switch: the other drawing draws');
    state = await settled(ID, 'reader\'s drawing');
    ticksAre(ID, 'a', 'reader\'s drawing');

    // The marked dose moves off the ladder: one tick more.
    swap(result, answer(FIX.b, 'Dose 85 mg'));
    state = await kept(ID, 'marker off the ladder', state, 'Dose 85 mg');
    ticksAre(ID, 'b', 'marker off the ladder');
    check(AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view === chosen, 'marker off the ladder: the reader\'s drawing is kept');
    // The same figure again: rows and ticks unchanged.
    swap(result, answer(FIX.b_again, 'Dose 85 mg again'));
    state = await kept(ID, 'same ticks', state, 'Dose 85 mg again');
    ticksAre(ID, 'b', 'same ticks');
    // Back onto the ladder: one tick fewer.
    swap(result, answer(FIX.back, 'Dose 40 mg'));
    state = await kept(ID, 'marker on the ladder', state, 'Dose 40 mg');
    ticksAre(ID, 'back', 'marker on the ladder');

    // update_spec with another marked dose, into the shown plot.
    swap(document.getElementById('sink'), FIX.update_c);
    await until(() => JSON.stringify(bottomTicks(ID)[0] || []) === JSON.stringify(want('c')), 'update_spec: the new ticks draw');
    state = await kept(ID, 'update_spec', state, null);
    ticksAre(ID, 'c', 'update_spec');

    // A re-embed (as a resize or a theme switch does) draws the current
    // spec: the ticks the last update brought stay.
    const before = view(ID);
    AoV._reembeds[ID]();
    await until(() => ownView(ID) && view(ID) !== before && !AoV._inFlight[ID], 're-embed: a new view');
    state = await settled(ID, 're-embed');
    ticksAre(ID, 'c', 're-embed');

    // Control: a changed axis title is structural and embeds afresh.
    swap(result, answer(FIX.title, 'Other title'));
    const now = await settled(ID, 'changed title');
    check(now.view !== state.view && now.el !== state.el, 'changed title: a new embed in the new element');
    ticksAre(ID, 'c', 'changed title');

    // --- A temporal axis listing hours ---
    const time = document.getElementById('time');
    swap(time, answer(FIX.time_a, 'Hours a'));
    let tstate = await settled('time-plot', 'time: first render');
    ticksAre('time-plot', 'time_a', 'time: first render');
    swap(time, answer(FIX.time_b, 'Hours b'));
    tstate = await kept('time-plot', 'time: other hours', tstate, 'Hours b');
    ticksAre('time-plot', 'time_b', 'time: other hours');

    // --- A wrapped facet with a per-panel Y scale type: one view per panel ---
    const panels = document.getElementById('panels');
    swap(panels, answer(FIX.panel_a, 'Panels 60 mg'));
    let pstate = await settled('panel-plot', 'panels: first render');
    ticksAre('panel-plot', 'a', 'panels: first render');
    check(bottomTicks('panel-plot').length >= 3, 'panels: each panel draws its own x axis (' +
        bottomTicks('panel-plot').length + ')');
    swap(panels, answer(FIX.panel_b, 'Panels 85 mg'));
    pstate = await kept('panel-plot', 'panels: marker off the ladder', pstate, 'Panels 85 mg');
    ticksAre('panel-plot', 'b', 'panels: marker off the ladder');

    check(uncaught.length === 0, 'uncaught errors: ' + uncaught.join(' | '));
    check(logged.length === 0, 'console errors: ' + logged.join(' | '));
    return {checks, failures};
})().catch(e => ({checks: 0, failures: [String(e && e.stack || e)]})).then(report => {
    document.getElementById('aov-axis-values-results').textContent = JSON.stringify(report);
});
