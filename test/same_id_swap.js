// A captioned figure that a swap replaces with one of the same structure under
// the same plot id keeps its drawing, view and reader state. See
// test/same_id_swap.jl.
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
    const FIX = window.AOV_FIXTURES;
    const ID = 'dr-plot', SEL = '[data-aov-ribbon-view-for="' + ID + '"]';
    const result = document.getElementById('result');
    const shown = () => document.getElementById(ID);
    const view = () => AoV.views[ID];
    const ownView = () => !!view() && !!shown() && shown().contains(view().container());
    const figButtons = () => shown() ? shown().closest('figure').querySelectorAll(SEL) : [];
    // The largest median the view draws (each fixture scales the same rows),
    // over the datasets its compiled spec names.
    const drawnMax = () => {
        const v = view(), cur = AoV._cur[ID];
        let max = -Infinity;
        if (!v || !cur) return max;
        vegaLite.compile(JSON.parse(JSON.stringify(cur.spec))).spec.data.forEach(d => {
            let rows = [];
            try { rows = v.data(d.name) || []; } catch (e) { return; }
            rows.forEach(r => { if (r && typeof r.q50 === 'number' && r.q50 > max) max = r.q50; });
        });
        return max;
    };
    const MAX = window.AOV_MAX;
    const near = (got, want) => Math.abs(got - want) <= 1e-9 * Math.abs(want);
    let chosen = null;
    const swap = (target, html, style) => htmx.swap(target, html, {swapStyle: style || 'innerHTML', settleDelay: 20},
        {contextElement: target});
    const result_of = (fixture, note) => '<div class="answer"><p class="note">' + note + '</p>' + fixture +
        '<table class="answer-table"><tr><td>' + note + '</td></tr></table></div>';

    // The figure in the page is complete: its own settled view, drawn in the
    // shown element, the switch beside it, a drawing that fits its column.
    async function settled(stage) {
        await until(() => ownView() && !AoV._inFlight[ID] && !(AoV._adopting || {})[ID], stage + ': the figure settles');
        await pause(600);   // a fit correction re-embeds once
        const el = shown(), area = el && el.closest('.aov-plot-area');
        const canvas = el && el.querySelector('canvas.marks');
        check(document.querySelectorAll('[id="' + ID + '"]').length === 1, stage + ': one element has the id');
        check(ownView(), stage + ': the plot has a view, drawn in the shown element');
        check(AoV._els[ID] === el, stage + ': the runtime records the shown element');
        const buttons = figButtons();
        check(buttons.length === 2, stage + ': the shown figure has the Ribbons | Intervals switch (' +
            buttons.length + ' buttons; ' + document.querySelectorAll(SEL).length + ' in the page)');
        check(document.querySelectorAll(SEL).length === buttons.length, stage + ': no other switch for the plot');
        const pressed = Array.from(buttons).filter(b => b.getAttribute('aria-pressed') === 'true');
        check(pressed.length === 1 && AoV._ribbonViews[ID] && pressed[0].dataset.view === AoV._ribbonViews[ID].view,
            stage + ': the pressed button names the drawing shown');
        check(!!canvas && !!area && canvas.clientWidth <= area.clientWidth + 2,
            stage + ': the drawing fits its column (' + (canvas && canvas.clientWidth) + ' px in ' +
            (area && area.clientWidth) + ' px)');
        return {view: view(), el: el};
    }
    // Plot state kept across a swap: the same element and view, now in the
    // new figure, drawing the new rows, with the reader's ribbon choice.
    async function kept(stage, before, key, note) {
        const now = await settled(stage);
        check(now.view === before.view, stage + ': the view is kept (no new embed)');
        check(now.el === before.el, stage + ': the plot element is kept');
        const answer = now.el && now.el.closest('.answer');
        check(!!answer && answer.querySelector('.note').textContent === note,
            stage + ': the plot sits in the new answer (' + note + ')');
        const want = MAX[key], got = drawnMax();
        check(near(got, want), stage + ': the view draws the new rows (max ' + got +
            ', sent ' + want + ')');
        check(AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view === chosen,
            stage + ': the reader\'s drawing (' + chosen + ') is kept');
        return now;
    }

    // First render.
    swap(result, result_of(FIX.a, 'Dose 60 mg'));
    let state = await settled('first render');
    check(near(drawnMax(), MAX.a), 'first render: the view draws the rows');
    // The reader picks the other drawing.
    const started = AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view;
    const other = Array.from(figButtons()).find(b => b.dataset.view !== started);
    check(!!started && !!other, 'first render: a switch with another drawing (' + started + ')');
    chosen = other && other.dataset.view;
    if (other) other.click();
    await until(() => AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view === chosen && ownView() &&
        view() !== state.view, 'switch: the other drawing draws');
    state = await settled('reader\'s drawing');

    // A control's refresh: the answer replaces the shown result (htmx 2
    // inserts it and runs its scripts before it removes the old one).
    swap(result, result_of(FIX.b, 'Dose 80 mg'));
    check(!!(AoV._adopting || {})[ID], 'refresh: the new figure waits for the swap to end');
    state = await kept('refresh', state, 'b', 'Dose 80 mg');
    check(!result.querySelector('.answer .note') || result.textContent.indexOf('Dose 60 mg') === -1,
        'refresh: the old answer is gone');

    // Parts sent ahead (HTMXObjects' sent_ahead_script): the first moves its
    // region into the live target, removing the shown result before its
    // figure's script runs; the second replaces the first out of band.
    const reporter = document.createElement('div');
    reporter.className = 'htmxo-live-reporter';
    reporter.innerHTML = '<div class="treebar-poller"><div class="treebar-poller-inner">running</div></div>';
    result.after(reporter);
    reporter.__htmxoLiveTarget = result;
    const inner = reporter.querySelector('.treebar-poller-inner');
    window.htmxoSentAhead.land(inner, 1, '<div id="dr-ahead">' + result_of(FIX.c, 'Part 1') + '</div>');
    state = await kept('first part', state, 'c', 'Part 1');
    check(!!result.querySelector('.htmxo-sent-ahead #' + ID), 'first part: the plot is in the parts region');
    window.htmxoSentAhead.land(inner, 2, '<div id="dr-ahead" hx-swap-oob="true">' + result_of(FIX.d, 'Part 2') + '</div>');
    state = await kept('second part', state, 'd', 'Part 2');
    // The finished answer replaces the parts (live_refresh_script's swap).
    reporter.remove();
    swap(result, result_of(FIX.b, 'Answer'));
    state = await kept('finished answer', state, 'b', 'Answer');
    check(!result.querySelector('.htmxo-sent-ahead'), 'finished answer: the parts are gone');

    // The whole result swapped out by outerHTML.
    const holder = result.querySelector('.answer');
    swap(holder, result_of(FIX.c, 'Outer'), 'outerHTML');
    state = await kept('outerHTML', state, 'c', 'Outer');

    // An update_spec script right after the figure in the same answer: the
    // figure shows its rows.
    swap(result, result_of(FIX.a + FIX.update_b, 'Updated'));
    state = await kept('update_spec in the answer', state, 'update_b', 'Updated');

    // An app that disposes what htmx cleans up: the old plot is gone before
    // the swap ends, so the new figure draws its own.
    const disposeOnCleanup = e => AoV.disposeWithin(e.target);
    document.addEventListener('htmx:beforeCleanupElement', disposeOnCleanup);
    swap(result, result_of(FIX.c, 'Disposed'));
    let now = await settled('disposed on cleanup');
    document.removeEventListener('htmx:beforeCleanupElement', disposeOnCleanup);
    check(now.view !== state.view && now.el !== state.el, 'disposed on cleanup: a new embed in the new element');
    check(near(drawnMax(), MAX.c), 'disposed on cleanup: the new figure draws its rows');
    state = now;

    // A changed structure (no colour) embeds afresh, as before.
    swap(result, result_of(FIX.nocolor, 'No colour'));
    now = await settled('changed structure');
    check(now.view !== state.view && now.el !== state.el, 'changed structure: a new embed in the new element');
    state = now;

    // A second figure under the id, beside the first: not a replacement. It
    // embeds on its own; the first stays in the page.
    const second = document.createElement('div');
    second.id = 'second';
    result.after(second);
    swap(second, result_of(FIX.nocolor, 'Second'));
    await until(() => AoV._els[ID] && AoV._els[ID] !== state.el && view() && view() !== state.view &&
        !AoV._inFlight[ID], 'second figure: it embeds');
    check(AoV._els[ID] && second.contains(AoV._els[ID]), 'second figure: the runtime records the second element');
    check(state.el.isConnected && result.contains(state.el), 'second figure: the first stays in the page');
    check(!(AoV._adopting || {})[ID], 'second figure: nothing waits');

    check(uncaught.length === 0, 'uncaught errors: ' + uncaught.join(' | '));
    check(logged.length === 0, 'console errors: ' + logged.join(' | '));
    return {checks, failures};
})().catch(e => ({checks: 0, failures: [String(e && e.stack || e)]})).then(report => {
    document.getElementById('aov-same-id-results').textContent = JSON.stringify(report);
});
