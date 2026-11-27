// The readout in the browser: a rule at the nearest x under the pointer and
// one box listing every series' value there, its link-group behaviour when
// the link key is the x field, and link groups keyed by dates (the key as
// Julia writes it, not Vega's epoch milliseconds). Pointers are sent the way
// a browser does: pointermove and mousemove at view coordinates.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const settle = async () => { await pause(); await pause(); await pause(); };
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    const links = [];
    document.addEventListener('htmxo:link', e => links.push(e.detail));

    // Scenegraph items matching `pred`, with their position in view
    // coordinates: a line or area point's own x and y (its bounds span the
    // whole path), the centre of any other item.
    function items(view, pred) {
        const out = [];
        (function walk(item, dx, dy) {
            if (item.mark && pred(item)) {
                const b = item.bounds, path = ['line', 'area', 'trail'].includes(item.mark.marktype);
                out.push({item, x: dx + (path ? item.x : (b.x1 + b.x2) / 2), y: dy + (path ? item.y : (b.y1 + b.y2) / 2)});
            }
            const gx = item.mark && item.mark.marktype === 'group' ? dx + (item.x || 0) : dx;
            const gy = item.mark && item.mark.marktype === 'group' ? dy + (item.y || 0) : dy;
            (item.items || []).forEach(child => walk(child, gx, gy));
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const mark = (type, field, value) => it => it.mark.role === 'mark' && it.mark.marktype === type &&
        it.datum && +it.datum[field] === +value;
    // A pointer at view coordinates: through the view origin plus its padding.
    function pointerAt(id, x, y) {
        const view = AoV.views[id];
        const canvas = document.querySelector('#' + id + ' canvas');
        const rect = canvas.getBoundingClientRect(), origin = view.origin(), pad = view.padding();
        const opts = {bubbles: true, cancelable: true, clientX: rect.left + origin[0] + pad.left + x,
            clientY: rect.top + origin[1] + pad.top + y, pointerId: 1, isPrimary: true, pointerType: 'mouse'};
        canvas.dispatchEvent(new PointerEvent('pointermove', opts));
        canvas.dispatchEvent(new MouseEvent('mousemove', opts));
    }
    function leave(id) {
        const canvas = document.querySelector('#' + id + ' canvas');
        canvas.dispatchEvent(new PointerEvent('pointerout', {bubbles: true, pointerId: 1, pointerType: 'mouse'}));
        document.getElementById(id).dispatchEvent(new PointerEvent('pointerleave', {pointerId: 1, pointerType: 'mouse'}));
    }
    // The box a plot shows: its lines, or null when hidden.
    function box(id) {
        const b = document.querySelector('#' + id + ' .aov-readout');
        return b && b.style.display !== 'none' ? b.innerText.split('\n').map(s => s.trim()).filter(Boolean) : null;
    }
    function ruleLeft(id) {
        const r = document.querySelector('#' + id + ' .aov-readout-rule');
        return r && r.style.display !== 'none' ? r.getBoundingClientRect().left : null;
    }
    const announce = (group, key) => document.dispatchEvent(new CustomEvent('htmxo:link',
        {detail: {group, key, keys: key === null ? [] : [key], source: null}}));
    const opacityOf = (view, type, field, value) => {
        const found = items(view, mark(type, field, value));
        return found.length ? Math.round((found[0].item.opacity === undefined ? 1 : found[0].item.opacity) * 1000) / 1000 : null;
    };
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const t = h => +new Date(2026, 2, 15, h);   // Vega reads `2026-03-15T0h:00:00` as local time

    try {
        let view = await ready('ro-series');
        await ready('ro-facet');
        await ready('ro-off');
        await ready('ro-bars');
        await ready('ro-dates');

        // --- plans ---
        check(!!(AoV._readouts['ro-series'] && AoV._readouts['ro-series'].plan), 'ro-series has no readout plan');
        check(!(AoV._readouts['ro-off'] && AoV._readouts['ro-off'].plan), 'readout=false still planned a readout');
        check(!!(AoV._readouts['ro-bars'] && AoV._readouts['ro-bars'].plan), 'readout=true gave bars no readout');
        check(!(AoV._readouts['ro-dates'] && AoV._readouts['ro-dates'].plan), 'a scatter got a readout by default');

        // --- the box and rule at the nearest x ---
        const at1 = items(view, mark('line', 't', t(1)))[0];
        check(!!at1, 'no line item at 01:00');
        links.length = 0;
        pointerAt('ro-series', at1.x + 3, 20);
        await settle();
        const got = box('ro-series');
        check(same(got, ['2026-03-15 01:00', 'A: 11.0 (9.0–13.0)', 'B: 21.0 (19.0–23.0)', 'Level (cm): 16.25']),
            'box at 01:00: ' + JSON.stringify(got));
        const canvas = document.querySelector('#ro-series canvas');
        const vx = canvas.getBoundingClientRect().left + view.origin()[0] + view.padding().left + at1.x;
        check(Math.abs(ruleLeft('ro-series') - vx) < 1.5, 'rule at ' + ruleLeft('ro-series') + ', the 01:00 line point at ' + vx);
        // The x is announced as Julia writes the DateTime, not Vega's epoch ms.
        check(same(links.map(l => l.keys), [['2026-03-15T01:00:00']]),
            'announced ' + JSON.stringify(links.map(l => l.keys)));
        // The mark tooltip stands down while the box shows.
        const tip = document.getElementById('vg-tooltip-element');
        check(!tip || tip.style.visibility === 'hidden', 'tooltip visible beside the readout');
        // Nearest x: a pointer just right of 02:00 reads 02:00.
        const at2 = items(view, mark('line', 't', t(2)))[0];
        pointerAt('ro-series', at2.x + 4, 60);
        await settle();
        check(same(box('ro-series') && box('ro-series')[0], '2026-03-15 02:00'), 'nearest x: ' + JSON.stringify(box('ro-series')));
        links.length = 0;
        leave('ro-series');
        await settle();
        check(box('ro-series') === null && ruleLeft('ro-series') === null, 'box kept after the pointer left');
        check(same(links.map(l => l.keys), [[]]), 'leaving announced ' + JSON.stringify(links.map(l => l.keys)));
        check(!tip || tip.style.visibility === '', 'tooltip still hidden after the readout ended');

        // --- another member announces one x: the readout shows it, nothing dims ---
        const lineBefore = opacityOf(view, 'line', 't', t(3));
        announce('hours', '2026-03-15T03:00:00');
        await settle();
        check(same(box('ro-series') && box('ro-series')[0], '2026-03-15 03:00'),
            'announced 03:00, box ' + JSON.stringify(box('ro-series')));
        check(opacityOf(view, 'line', 't', t(3)) === lineBefore, 'a line dimmed for an announced x');
        check(opacityOf(view, 'symbol', 't', t(0)) === opacityOf(view, 'symbol', 't', t(3)),
            'points dimmed for an announced x');
        announce('hours', null);
        await settle();
        check(box('ro-series') === null, 'box kept after the announcement ended');

        // --- readout=false: no box ---
        const off = AoV.views['ro-off'];
        const offAt = items(off, mark('line', 't', t(1)))[0];
        pointerAt('ro-off', offAt.x, 20);
        await settle();
        check(box('ro-off') === null, 'readout=false showed ' + JSON.stringify(box('ro-off')));
        leave('ro-off');

        // --- readout=true on bars over time ---
        const bars = AoV.views['ro-bars'];
        const bar = items(bars, mark('rect', 't', t(2)))[0];
        pointerAt('ro-bars', bar.x, bar.y);
        await settle();
        check(same(box('ro-bars'), ['2026-03-15 02:00', 'Rain (mm/h): 1.5']), 'bars box: ' + JSON.stringify(box('ro-bars')));
        leave('ro-bars');

        // --- facets: the panel under the pointer ---
        const facet = AoV.views['ro-facet'];
        const q3 = items(facet, it => it.mark.role === 'mark' && it.mark.marktype === 'line' &&
            it.datum && it.datum.g === 'q' && it.datum.x === 3)[0];
        check(!!q3, 'no q-panel line item at x = 3');
        pointerAt('ro-facet', q3.x + 2, q3.y);
        await settle();
        check(same(box('ro-facet'), ['x: 3', 'v: 30']), 'facet box: ' + JSON.stringify(box('ro-facet')));
        leave('ro-facet');

        // --- a link group keyed by a Date ---
        const dates = AoV.views['ro-dates'];
        const before = opacityOf(dates, 'symbol', 'v', 2);
        announce('days', '2026-03-02');
        await settle();
        check(opacityOf(dates, 'symbol', 'v', 2) === before && opacityOf(dates, 'symbol', 'v', 1) < before,
            'Date key: point opacities ' + JSON.stringify([opacityOf(dates, 'symbol', 'v', 1), opacityOf(dates, 'symbol', 'v', 2)]));
        announce('days', null);
        await settle();
        links.length = 0;
        const p3 = items(dates, mark('symbol', 'v', 3))[0];
        pointerAt('ro-dates', p3.x, p3.y);
        await settle();
        check(links.some(l => same(l.keys, ['2026-03-03'])), 'Date key announced ' + JSON.stringify(links.map(l => l.keys)));
        leave('ro-dates');

        // --- a re-embed keeps the readout working ---
        AoV.embed('ro-series', JSON.parse(JSON.stringify(AoV._origSpecs['ro-series'])));
        view = await ready('ro-series', view);
        const again = items(view, mark('line', 't', t(1)))[0];
        pointerAt('ro-series', again.x, 20);
        await settle();
        check(same(box('ro-series') && box('ro-series')[0], '2026-03-15 01:00'),
            'after a re-embed: ' + JSON.stringify(box('ro-series')));
        leave('ro-series');

        // --- a wash: `visual(Band; inspectable=false)` from 0 to the line ---
        // The band is left out of the readout, so the line reads as a line,
        // to four significant digits, not as `0.41 (0.00–0.41)`.
        const readAt = async (id, x) => {
            const v = await ready(id);
            const it = items(v, mark('line', 'hour', x))[0];
            if (!it) return 'no line item at hour ' + x;
            pointerAt(id, it.x + 3, it.y);
            await settle();
            const got = box(id);
            leave(id);
            await settle();
            return got;
        };
        let got2 = await readAt('ro-wash', 11);
        check(same(got2, ['Hour: 11', 'Added dose rate: 0.4096']), 'wash under a line: ' + JSON.stringify(got2));
        got2 = await readAt('ro-wash-label', 11);
        check(same(got2, ['Hour: 11', 'Added dose rate: 0.4096']), 'unlabelled wash, labelled line: ' + JSON.stringify(got2));
        // An inspectable Band under a line of the same name is that line's interval.
        got2 = await readAt('ro-band', 11);
        check(same(got2, ['Hour: 11', 'Added dose rate: 0.41 (0.00–0.41)']), 'inspectable band: ' + JSON.stringify(got2));
        // The wash as a stacked panel under bars: one box, the bars' value and the line's.
        got2 = await readAt('ro-wash-stack', 11);
        check(same(got2, ['Hour: 11', 'Rain (mm/h): 0', 'Added dose rate: 0.4096']), 'stacked wash: ' + JSON.stringify(got2));
        check(document.querySelectorAll('#ro-wash-stack .aov-readout-panel').length === 0,
            'a stack of single uncoloured series got panel headings');

        // --- a stack whose panels share a colour field: each panel's own
        // series, under its y title; the uncoloured panel below unheaded ---
        const scen = await ready('ro-stack-scenarios');
        const expected = ['Day: 2', 'Plasma (ng/mL)', 'S1: 120 (60–240)', 'S2: 1,200 (900–1,500)',
            'PBMC (%)', 'S1: −49.8 (−53.5 – −46.5)', 'S2: −40.0 (−44.0 – −36.0)',
            'CSF (%)', 'S1: −50.2 (−53.3 – −45.1)', 'S2: −30 (−35 – −25)', 'Dose (mg): 100'];
        const lines2 = items(scen, mark('line', 'day', 2));
        check(lines2.length >= 4, 'stack: ' + lines2.length + ' line items at day 2');
        // From the top panel and from the bottom one: the same box.
        for (const it of [lines2[0], lines2[lines2.length - 1]].filter(Boolean)) {
            pointerAt('ro-stack-scenarios', it.x + 3, it.y);
            await settle();
            const got = box('ro-stack-scenarios');
            check(same(got, expected), 'stack at y ' + Math.round(it.y) + ': ' + JSON.stringify(got));
        }
        const heads = [...document.querySelectorAll('#ro-stack-scenarios .aov-readout-panel')].map(h => h.textContent);
        check(same(heads, ['Plasma (ng/mL)', 'PBMC (%)', 'CSF (%)']), 'panel headings ' + JSON.stringify(heads));
        // Headed rows are indented; the uncoloured panel's row, named by its title, is not.
        const rows = [...document.querySelectorAll('#ro-stack-scenarios .aov-readout > div')]
            .filter(r => !r.classList.contains('aov-readout-panel')).slice(1);
        const indents = rows.map(r => [r.textContent.split(':')[0], r.style.paddingLeft]);
        check(same(indents, [['S1', '0.9em'], ['S2', '0.9em'], ['S1', '0.9em'], ['S2', '0.9em'],
            ['S1', '0.9em'], ['S2', '0.9em'], ['Dose (mg)', '']]), 'indents ' + JSON.stringify(indents));
        leave('ro-stack-scenarios');
        await settle();

        // --- each layer's own series (snag `embedded-hand-wr-eae60371`) ---
        // The pointer just beside a line's point at `x` (`dx` px off it).
        const readLine = async (id, field, x, dx) => {
            const v = await ready(id);
            const it = items(v, mark('line', field, x))[0];
            if (!it) return 'no line item at ' + field + ' ' + x;
            pointerAt(id, it.x + dx, it.y);
            await settle();
            const got = box(id);
            leave(id);
            await settle();
            return got;
        };
        // Layers coloured by a constant (`color.datum`) are named by their
        // legend entry: the rule's interval goes with the binned mean's point
        // of the same entry, never with the fitted line under the same y title.
        let got3 = await readLine('ro-datum', 'x', 1, 3);
        check(same(got3, ['Start: 1', 'Binned mean (± 2 SE): 20.4 (17.3–23.4)', 'Fit: 19.85']),
            'datum-named layers: ' + JSON.stringify(got3));
        // Unnamed layers of one y title that draw different columns are two
        // rows, here named by their tooltip titles; the interval goes with
        // the value layer drawn next after it.
        got3 = await readLine('ro-nodatum', 'x', 1, 3);
        check(same(got3, ['Start: 1', 'Mean change (nats): 20.4 (17.3–23.4)', 'Fitted change (nats): 19.85']),
            'one y title, two columns: ' + JSON.stringify(got3));
        // A line with a point overlay is read, and an area titled only by
        // `axis.title` is that line's interval.
        got3 = await readLine('ro-overlay', 'x', 3, -3);
        check(same(got3, ['Iteration: 3', 'Log density (nats): 241 (−1,209 – 698)']),
            'line with points over an area: ' + JSON.stringify(got3));
        got3 = await readLine('ro-scatterlines', 'hour', 11, 3);
        check(same(got3, ['Hour: 11', 'Added dose rate: 0.4096']), 'ScatterLines: ' + JSON.stringify(got3));
        // The same shapes from the algebra: a Band, the points and a step
        // line under one label; the auto tooltips share it, so both rows
        // keep it.
        got3 = await readLine('ro-shared', 'x', 1, 3);
        check(same(got3, ['Start: 1', 'Change: 20.4 (17.3–23.4)', 'Change: 19.85']),
            'algebra layers of one label: ' + JSON.stringify(got3));
        // `color=direct("Model")` is a constant colour too: its legend entry names it.
        got3 = await readLine('ro-direct', 'hour', 11, 3);
        check(same(got3, ['Hour: 11', 'Model: 0.4096']), 'direct colour: ' + JSON.stringify(got3));

        // A figure whose only line is passive gets no readout.
        await ready('ro-passive');
        check(!(AoV._readouts['ro-passive'] && AoV._readouts['ro-passive'].plan), 'a passive line got a readout');
        const pl = items(AoV.views['ro-passive'], mark('line', 'hour', 11))[0];
        if (pl) { pointerAt('ro-passive', pl.x, pl.y); await settle(); }
        check(!!pl && box('ro-passive') === null, 'passive line: ' + JSON.stringify(pl ? box('ro-passive') : 'no item'));
        if (pl) leave('ro-passive');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-readout-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
