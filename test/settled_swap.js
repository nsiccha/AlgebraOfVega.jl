// A figure swapped in by htmx under the id of the one it replaces, checked
// against the freshly loaded page: the map's reset button over the map's
// top-left corner, vega-embed's actions menu laid out, a single view's width
// cap in force. See test/settled_swap.jl.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const near = (a, b, tol) => Math.abs(a - b) <= (tol === undefined ? 1.5 : tol);
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms || 10));
    const uncaught = [];
    window.addEventListener('error', e => uncaught.push(String(e.message)));
    const IDS = ['ss-map', 'ss-act', 'ss-cap'];
    let settles = 0;
    document.addEventListener('htmx:afterSettle', () => { settles++; });

    // Every plot drawn anew in the element that now carries its id.
    async function drawn(previous, stage) {
        for (let i = 0; i < 600; i++) {
            if (IDS.every(id => {
                const view = AoV.views[id], el = document.getElementById(id);
                return view && view !== previous[id] && !AoV._inFlight[id] && el && el.contains(view.container());
            })) return Object.fromEntries(IDS.map(id => [id, AoV.views[id]]));
            await pause(25);
        }
        throw new Error(stage + ': the plots did not draw');
    }

    async function inspect(stage) {
        // The map: zoomed, its reset button sits over the drawing's top-left
        // corner, inside the plot's own box.
        const el = document.getElementById('ss-map'), view = AoV.views['ss-map'];
        const canvas = el.querySelector('canvas.marks');
        check(el.classList.contains('vega-embed'), stage + ': the map element has vega-embed\'s class (' + el.className + ')');
        check(getComputedStyle(el).position !== 'static', stage + ': the map element is the reset button\'s positioned box');
        view.signal('aov_zoom', {k: 2, x: -40, y: -30});
        await view.runAsync();
        const buttons = el.querySelectorAll('.aov-zoom-reset'), b = buttons[0];
        check(buttons.length === 1, stage + ': the map has one reset button (' + buttons.length + ')');
        check(!!b && !b.hidden, stage + ': the zoomed map shows its reset button');
        if (b && canvas) {
            const br = b.getBoundingClientRect(), cr = canvas.getBoundingClientRect();
            const o = view.origin(), pad = view.padding();
            const x = cr.left + o[0] + pad.left + 6, y = cr.top + o[1] + pad.top + 6;
            check(near(br.left, x) && near(br.top, y), stage + ': the reset button sits over the map\'s top-left corner ' +
                '(button at ' + [br.left, br.top].map(Math.round) + ', expected ' + [x, y].map(Math.round) + ')');
            check(br.top >= cr.top && br.bottom <= cr.bottom && br.left >= cr.left && br.right <= cr.right,
                stage + ': the reset button lies inside the drawing');
            b.click();
            await view.runAsync();
            const z = view.signal('aov_zoom');
            check(z.k === 1 && z.x === 0 && z.y === 0 && b.hidden, stage + ': the reset button brings back the fitted view');
        } else {
            check(false, stage + ': no drawing or no button to measure');
        }
        // vega-embed's actions menu: its stylesheet lays it out through the
        // element's classes.
        const act = document.getElementById('ss-act'), summary = act.querySelector('details > summary');
        check(act.classList.contains('vega-embed') && act.classList.contains('has-actions'),
            stage + ': the actions plot has vega-embed\'s classes (' + act.className + ')');
        check(!!summary && getComputedStyle(summary).position === 'absolute',
            stage + ': the actions menu button floats at the plot\'s corner');
        check(getComputedStyle(act).paddingRight === '38px', stage + ': the actions plot keeps room for its menu button');
        // A single view's width and its cap, written by the runtime.
        const cap = document.getElementById('ss-cap');
        check(cap.style.width === '100%', stage + ': the capped view fills its container (style width "' + cap.style.width + '")');
        check(getComputedStyle(cap).maxWidth === '300px', stage + ': the capped view keeps its 300 px cap (' +
            getComputedStyle(cap).maxWidth + ')');
        check(cap.getBoundingClientRect().width <= 300.5, stage + ': the capped view is at most 300 px wide (' +
            Math.round(cap.getBoundingClientRect().width) + ' px)');
    }

    async function swap(html, settleDelay, previous, stage) {
        const before = settles;
        let settledFirst = null;
        htmx.swap(document.getElementById('ss-target'), html, {swapStyle: 'innerHTML', settleDelay: settleDelay});
        const views = await drawn(previous, stage);
        settledFirst = settles > before;
        for (let i = 0; i < 400 && settles === before; i++) await pause(25);
        check(settles > before, stage + ': htmx settled the swap');
        await pause(300);
        return {views, settledFirst};
    }

    try {
        const fresh = await drawn({}, 'fresh page');
        await pause(300);
        await inspect('fresh page');

        // The order the reporter measured: every embed has finished when
        // htmx puts the served class and style back.
        const late = await swap(window.AOV_LEVELS.level2, 1500, fresh, 'settle after the embeds');
        check(late.settledFirst === false, 'settle after the embeds: the embeds finished before the settle');
        await inspect('settle after the embeds');

        // htmx's default settle delay.
        await swap(window.AOV_LEVELS.level1, 20, late.views, 'default settle');
        await inspect('default settle');
    } catch (err) {
        failures.push('driver error: ' + (err && err.stack || err));
    }
    if (uncaught.length) failures.push('uncaught errors: ' + uncaught.join(' | '));
    document.getElementById('aov-settle-results').textContent = JSON.stringify({checks, failures});
})();
