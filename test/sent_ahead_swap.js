// A captioned figure replaced under the same plot id: a part sent ahead and
// replaced out of band, then the finished answer that replaces the parts. See
// test/sent_ahead_swap.jl.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    const uncaught = [];
    window.addEventListener('error', e => uncaught.push(String(e.message)));
    async function until(ready, what) {
        for (let i = 0; i < 400; i++) {
            if (ready()) return true;
            await pause(25);
        }
        failures.push(what + ': timed out');
        return false;
    }
    const ID = 'dr-plot', SEL = '[data-aov-ribbon-view-for="' + ID + '"]';
    // How many elements carried the id when each embed of it started.
    const sharing = [];
    const embed = AoV.embed;
    AoV.embed = function (id) {
        if (id === ID) sharing.push(document.querySelectorAll('[id="' + ID + '"]').length);
        return embed.apply(this, arguments);
    };
    const shown = () => document.getElementById(ID);
    const view = () => AoV.views[ID];
    const ownView = () => !!view() && !!shown() && shown().contains(view().container());
    const figButtons = () => shown() ? shown().closest('figure').querySelectorAll(SEL) : [];
    // The figure in `el` is complete: its own live view, the switch beside it,
    // the runtime's record on it, and a drawing that fits its column.
    async function complete(stage, previous) {
        await until(() => ownView() && view() !== previous, stage + ': a new view draws in the shown element');
        await pause(600);   // the fit correction re-embeds once
        const el = shown(), area = el && el.closest('.aov-plot-area');
        const canvas = el && el.querySelector('canvas.marks');
        check(document.querySelectorAll('[id="' + ID + '"]').length === 1, stage + ': one element has the id');
        check(ownView(), stage + ': the plot has a view, drawn in the shown element');
        check(AoV._els[ID] === el, stage + ': the runtime records the shown element');
        const buttons = figButtons();
        check(buttons.length === 2, stage + ': the shown figure has the Ribbons | Intervals switch (' +
            buttons.length + ' buttons; ' + document.querySelectorAll(SEL).length + ' in the page)');
        check(document.querySelectorAll(SEL).length === buttons.length, stage + ': no other switch for the plot');
        check(Array.from(buttons).filter(b => b.getAttribute('aria-pressed') === 'true').length === 1,
            stage + ': one drawing is pressed');
        check(!!canvas && !!area && canvas.clientWidth <= area.clientWidth + 2,
            stage + ': the drawing fits its column (' + (canvas && canvas.clientWidth) + ' px in ' +
            (area && area.clientWidth) + ' px)');
        return view();
    }

    const inner = document.querySelector('.treebar-poller-inner');
    // Part 1 opens the region above the polling inner.
    window.htmxoSentAhead.land(inner, 1, window.AOV_PARTS.part1);
    const v1 = await complete('first part', undefined);
    check(!!document.querySelector('.htmxo-sent-ahead #' + ID), 'first part: the figure is in the sent-ahead region');

    // Part 2 replaces part 1 out of band: htmx inserts it before the old one
    // and runs its script while both are in the page.
    window.htmxoSentAhead.land(inner, 2, window.AOV_PARTS.part2);
    const v2 = await complete('second part', v1);
    check(sharing[1] === 2, 'second part: its embed ran while the old figure was in the page (' + sharing[1] + ')');

    // The finished answer, as Treebars swaps a pushed or polled answer in:
    // it replaces the polling inner below the region, which HTMXObjects
    // removes once the swap has happened.
    htmx.swap(inner, window.AOV_PARTS.final, {swapStyle: 'outerHTML', settleDelay: 20},
        {select: '.treebar-terminal-content', contextElement: inner});
    const v3 = await complete('finished answer', v2);
    check(sharing[2] === 2, 'finished answer: its embed ran while the parts were in the page (' + sharing[2] + ')');
    check(document.querySelectorAll('.htmxo-sent-ahead').length === 0, 'finished answer: the parts are gone');
    check(!!document.querySelector('.treebar-terminal-content #' + ID), 'finished answer: the figure is the answer\'s');

    // The switch works: the other drawing draws in the same element.
    const other = Array.from(figButtons()).find(b => b.getAttribute('aria-pressed') !== 'true');
    if (other) {
        other.click();
        await until(() => ownView() && view() !== v3, 'switch: the other drawing draws');
        check(AoV._ribbonViews[ID] && AoV._ribbonViews[ID].view === other.dataset.view, 'switch: the plot shows ' +
            (other && other.dataset.view));
        check(other.getAttribute('aria-pressed') === 'true', 'switch: its button is pressed');
    } else {
        check(false, 'switch: no unpressed button to click');
    }
    check(uncaught.length === 0, 'uncaught errors: ' + uncaught.join(' | '));
    return {checks, failures};
})().catch(e => ({checks: 0, failures: [String(e && e.stack || e)]})).then(report => {
    document.getElementById('aov-ahead-results').textContent = JSON.stringify(report);
});
