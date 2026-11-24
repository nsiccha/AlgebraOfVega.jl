// "Show intervals" switch browser checks (todo `0no7hcn`): the button sits
// after a bare plot (after its Ribbons | Intervals switch) or in a captioned
// figure's action row, pressed while the intervals show; a click hides only
// the interval marks, without a re-embed, and the axes refit to the marks
// still drawn (an authored domain stays); the choice survives a re-embed, an
// in-place update_spec, the Ribbons | Intervals switch and a picker remap; a
// figure without interval marks has no button; a standalone to_html page has it.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const show = d => JSON.stringify(d.map(v => Math.round(+v * 100) / 100));
    async function ready(id, previous, win = window) {
        for (let i = 0; i < 400; i++) {
            const A = win.AoV, view = A && A.views[id];
            if (view && view !== previous && !A._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    async function settle(view) {
        for (let i = 0; i < 3; i++) { await pause(); await view.runAsync(); }
    }
    const button = (id, doc = document) => doc.querySelector('[data-aov-intervals-for="' + id + '"]');
    // Drawn items per mark type (data marks only).
    function counts(view) {
        const out = {rule: 0, symbol: 0, area: 0, line: 0};
        (function walk(item) {
            const m = item.mark;
            if (m && m.role === 'mark' && item.datum && out[m.marktype] !== undefined) out[m.marktype]++;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const domain = (view, ch) => view.scale(ch).domain().map(Number);
    async function toggle(id, win = window) {
        const view = win.AoV.views[id];
        button(id, win.document).click();
        await settle(view);
        return view;
    }

    try {
        const views = {};
        for (const id of ['iv-range', 'iv-caption', 'iv-de', 'iv-ribbon', 'iv-point', 'iv-limits', 'iv-picker', 'iv-none'])
            views[id] = await ready(id);

        // --- A faceted xgx-style figure: two Rangebars layers and the medians.
        let id = 'iv-range', view = views[id], b = button(id);
        check(!!b, id + ': no switch');
        const area = document.getElementById(id).closest('.aov-plot-area') || document.getElementById(id);
        check(b && b.parentElement.classList.contains('aov-intervals') && area.nextElementSibling === b.parentElement,
            id + ': the switch is not in a group right after the plot');
        check(b && b.textContent === 'Show intervals' && b.getAttribute('aria-pressed') === 'true',
            id + ': button ' + (b && b.textContent) + ' pressed=' + (b && b.getAttribute('aria-pressed')));
        const shown = counts(view), wide = domain(view, 'y');
        check(shown.rule > 0 && shown.symbol > 0, id + ': initial marks ' + JSON.stringify(shown));
        check(wide[0] <= -25 && wide[1] >= 30, id + ': the intervals do not set the y range ' + show(wide));
        await toggle(id);
        check(AoV.views[id] === view, id + ': hiding re-embedded the plot');
        let now = counts(view), y = domain(view, 'y');
        check(b.getAttribute('aria-pressed') === 'false', id + ' hidden: still pressed');
        check(now.rule === 0 && now.symbol === shown.symbol, id + ' hidden: marks ' + JSON.stringify(now));
        check(y[0] > -5 && y[1] < 15 && y[0] <= 1 && y[1] >= 8, id + ' hidden: y domain ' + show(y) + ' does not fit the medians 1..8');
        // A re-embed (resize, theme) keeps it hidden.
        AoV._reembeds[id]();
        view = views[id] = await ready(id, view);
        await settle(view);
        now = counts(view);
        check(now.rule === 0 && button(id).getAttribute('aria-pressed') === 'false', id + ' re-embed: ' + JSON.stringify(now));
        // An update_spec with new rows swaps them in place and keeps it hidden.
        const next = JSON.parse(JSON.stringify(AoV._origSpecs[id]));
        next.data.values = AoV._rowsFromColumns(next.data.values).map(r => r.m === undefined ? r : Object.assign({}, r, {m: r.m + 10}));
        AoV.updateSpec(id, next);
        await settle(view); await settle(view);
        check(AoV.views[id] === view, id + ' update: the view was replaced');
        now = counts(view); y = domain(view, 'y');
        check(now.rule === 0 && button(id).getAttribute('aria-pressed') === 'false', id + ' update: ' + JSON.stringify(now));
        check(y[0] > 5 && y[1] >= 18 && y[1] < 25, id + ' update: y domain ' + show(y) + ' does not fit the new medians 11..18');
        await toggle(id);
        now = counts(view); y = domain(view, 'y');
        check(now.rule === shown.rule && button(id).getAttribute('aria-pressed') === 'true', id + ' shown again: ' + JSON.stringify(now));
        check(y[0] <= -25 && y[1] >= 40, id + ' shown again: y domain ' + show(y));

        // --- In a captioned figure's action row, in English and German.
        id = 'iv-caption'; view = views[id]; b = button(id);
        check(b && b.closest('figure.captioned .caption-actions') && b.classList.contains('caption-action'),
            id + ': the switch is not in the action row');
        await toggle(id);
        check(counts(view).rule === 0 && b.getAttribute('aria-pressed') === 'false', id + ': not hidden');
        b = button('iv-de');
        check(b && b.textContent === 'Intervalle zeigen', 'iv-de: button text ' + (b && b.textContent));

        // --- A ribbon: both drawings, and its two switches in order.
        id = 'iv-ribbon'; view = views[id]; b = button(id);
        const rgroup = document.querySelector('[data-aov-ribbon-view-for="' + id + '"]');
        check(rgroup && b && rgroup.parentElement.nextElementSibling === b.parentElement,
            id + ': the intervals switch does not follow the Ribbons | Intervals switch');
        const rShown = counts(view), rWide = domain(view, 'y');
        check(rShown.rule > 0 && rShown.symbol > 0, id + ' intervals drawing: ' + JSON.stringify(rShown));
        await toggle(id);
        now = counts(view);
        check(now.rule === 0 && now.symbol === rShown.symbol, id + ' hidden: ' + JSON.stringify(now));
        check(domain(view, 'y')[1] - domain(view, 'y')[0] < rWide[1] - rWide[0], id + ' hidden: the y range did not shrink');
        AoV.setRibbonView(id, 'ribbons');
        view = views[id] = await ready(id, view);
        await settle(view);
        now = counts(view);
        check(now.area === 0 && now.line > 0 && button(id).getAttribute('aria-pressed') === 'false',
            id + ' ribbons drawing, hidden: ' + JSON.stringify(now));
        await toggle(id);
        now = counts(view);
        check(now.area > 0 && now.line > 0, id + ' ribbons drawing, shown: ' + JSON.stringify(now));

        // --- A horizontal pointinterval: the value axis is x.
        id = 'iv-point'; view = views[id];
        const pShown = counts(view), pWide = domain(view, 'x');
        await toggle(id);
        now = counts(view);
        check(now.rule === 0 && now.symbol === pShown.symbol && pShown.rule > 0, id + ': ' + JSON.stringify(pShown) + ' → ' + JSON.stringify(now));
        check(domain(view, 'x')[1] - domain(view, 'x')[0] < pWide[1] - pWide[0], id + ': the x range did not shrink ' + show(pWide) + ' → ' + show(domain(view, 'x')));

        // --- Axis limits stay.
        id = 'iv-limits'; view = views[id];
        await toggle(id);
        check(counts(view).rule === 0, id + ': not hidden');
        y = domain(view, 'y');
        check(y[0] === -40 && y[1] === 50, id + ': the authored y domain changed ' + show(y));

        // --- The picker keeps the choice across a remap.
        id = 'iv-picker'; view = views[id];
        await toggle(id);
        const before = view;
        AoV.remapEncoding(id, {color: 'k'});
        view = views[id] = await ready(id, before);
        await settle(view);
        now = counts(view);
        check(now.rule === 0 && now.symbol > 0 && button(id).getAttribute('aria-pressed') === 'false',
            id + ' remapped: ' + JSON.stringify(now));

        // --- No interval marks, no switch.
        check(!button('iv-none') && !document.querySelector('#iv-none ~ .aov-intervals'), 'iv-none: a switch was added');

        // --- A standalone to_html page has the switch.
        const frame = document.createElement('iframe');
        frame.style.width = '900px'; frame.style.height = '600px';
        frame.srcdoc = window.IV_STANDALONE;
        document.body.append(frame);
        let inner = null;
        for (let i = 0; i < 400 && !inner; i++) {
            await pause();
            const w = frame.contentWindow;
            inner = w && w.AoV && w.AoV.views && w.AoV.views['iv-standalone'] && !w.AoV._inFlight['iv-standalone'] ?
                w.AoV.views['iv-standalone'] : null;
        }
        check(!!inner, 'standalone: the plot did not embed');
        if (inner) {
            const sb = button('iv-standalone', frame.contentDocument);
            check(!!sb && sb.getAttribute('aria-pressed') === 'true', 'standalone: no pressed switch');
            if (sb) {
                await toggle('iv-standalone', frame.contentWindow);
                check(counts(inner).rule === 0, 'standalone: the intervals did not hide');
            }
        }
        frame.remove();
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-interval-switch-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
