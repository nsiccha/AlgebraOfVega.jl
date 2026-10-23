(async function () {
    const failures = [];
    const errors = [];
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const fixture = window.AOV_FIXTURE;
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function items(view, predicate) {
        const out = [];
        (function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    // Page position of a scenegraph item: its x plus its groups' offsets.
    function pageX(item) {
        let x = item.x || 0;
        for (let g = item.mark && item.mark.group; g; g = g.mark && g.mark.group) x += g.x || 0;
        return x;
    }
    const areas = view => items(view, i => i.mark?.marktype === 'area');
    const rules = view => items(view, i => i.mark?.marktype === 'rule' && i.datum?.q025 !== undefined &&
        i.datum?.y === undefined);
    const observations = view => items(view, i => i.mark?.marktype === 'symbol' && i.datum?.y !== undefined);
    const cells = view => items(view, i => i.mark?.role === 'scope' && i.mark?.name === 'cell');
    const switches = id => [...document.querySelectorAll('[data-aov-ribbon-view-for="' + id + '"]')];
    const button = (id, v) => switches(id).find(b => b.dataset.view === v);
    const pressed = id => switches(id).filter(b => b.getAttribute('aria-pressed') === 'true').map(b => b.dataset.view);
    const drawsIntervals = view => rules(view).length > 0 && areas(view).length === 0;
    const drawsRibbons = view => areas(view).length > 0 && rules(view).length === 0;
    const layers = spec => (spec.spec ? spec.spec.layer : spec.layer) || [];
    const mean = xs => xs.reduce((a, b) => a + b, 0) / xs.length;

    try {
        // Captioned picker figure: overlapping groups start as intervals.
        const cap = 'ribbon-cap';
        let view = await ready(cap);
        const fig = document.getElementById(cap).closest('figure');
        const acts = fig.querySelector('.caption-actions');
        check(switches(cap).length === 2 && acts.children[0] === button(cap, 'ribbons') &&
            acts.children[1] === button(cap, 'intervals'), 'captioned: first two buttons of the action row');
        check(switches(cap).every(b => b.classList.contains('caption-action')), 'captioned: caption buttons');
        check(button(cap, 'ribbons').textContent === 'Ribbons' && button(cap, 'intervals').textContent === 'Intervals',
            'captioned: English labels');
        check(switches(cap).every(b => /Bands overlap \d+% of the y range; intervals above 10%/.test(b.title)),
            'captioned: overlap tooltip: ' + button(cap, 'ribbons').title);
        check(pressed(cap).join() === 'intervals', 'captioned: starts as intervals');
        check(drawsIntervals(view), 'captioned: draws point-intervals');
        // Dodged by colour around each dose slot; the observations sit on the slot's centre.
        const atDose = d => rules(view).filter(i => i.datum.dose === d && i.datum.study === 'S1');
        const xs = [...new Set(atDose(5).map(pageX).map(x => Math.round(x)))];
        check(xs.length === 3, 'captioned: three groups dodged at one dose: ' + xs);
        const obs = observations(view).filter(i => i.datum.dose === 5 && i.datum.study === 'S1');
        const centre = mean(xs);
        check(obs.length > 0 && obs.every(i => Math.abs(pageX(i) - centre) < 2),
            'captioned: observations on the slot centre');
        const slotXs = [5, 10, 20].map(d => Math.round(mean(atDose(d).map(pageX))));
        check(Math.abs((slotXs[1] - slotXs[0]) - (slotXs[2] - slotXs[1])) <= 1, 'captioned: evenly spaced slots');

        // The reader switches to ribbons.
        button(cap, 'ribbons').click();
        view = await ready(cap, view);
        check(drawsRibbons(view), 'switch: draws ribbons');
        check(pressed(cap).join() === 'ribbons', 'switch: Ribbons pressed');
        check(AoV._ribbonViews[cap].view === 'ribbons', 'switch: state');
        check(switches(cap).length === 2, 'switch: one pair after a re-embed');

        // The choice survives a resize, a theme switch, a re-facet and update_spec.
        check(AoV._resizeReembed(cap), 'resize: re-embedded');
        view = await ready(cap, view);
        check(drawsRibbons(view), 'resize: still ribbons');
        // A host-theme change re-embeds through the plot's re-embed, as
        // refreshTheme does (this page has no theme CSS to change).
        AoV._reembeds[cap]();
        view = await ready(cap, view);
        check(drawsRibbons(view), 'theme: still ribbons');

        const pin = document.querySelector('input[type=radio][name="aov-pin-' + cap + '"][value=color]');
        check(!!pin, 'picker: rendered');
        pin.click();
        const row = document.getElementById('aov-remap-row-' + cap);
        [...row.options].forEach(o => o.selected = o.value === 'group');
        row.dispatchEvent(new Event('change', {bubbles: true}));
        view = await ready(cap, view);
        check(cells(view).length === 3, 're-facet: group rows: ' + cells(view).length);
        check(drawsRibbons(view), 're-facet: still ribbons');
        check(pressed(cap).join() === 'ribbons', 're-facet: Ribbons still pressed');

        // Back to intervals under the re-facet: the dodge follows the colour.
        button(cap, 'intervals').click();
        view = await ready(cap, view);
        check(drawsIntervals(view) && cells(view).length === 3, 're-facet intervals: drawn per group row');
        const offsets = layers(AoV._cur[cap].spec).map(l => l.encoding && l.encoding.xOffset).filter(Boolean);
        const color = layers(AoV._cur[cap].spec).map(l => l.encoding && l.encoding.color).filter(Boolean)[0];
        check(offsets.length > 0 && color && offsets.every(o => o.field === color.field) && color.field !== 'group',
            're-facet intervals: dodged by the colour field: ' + JSON.stringify([offsets[0], color]));

        (0, eval)(fixture.updates.same);
        await pause();
        view = await ready(cap);
        for (let i = 0; i < 30; i++) await pause();
        view = await ready(cap);
        check(drawsIntervals(view) && pressed(cap).join() === 'intervals', 'update_spec: still intervals');
        check(cells(view).length === 3, 'update_spec: picker assignment kept');
        check(AoV._plotData(cap).some(r => r.med === fixture.updated_median), 'update_spec: new rows');

        // An uncaptioned plot: separated groups start as ribbons, the switch follows the plot.
        const plain = 'ribbon-plain';
        let pview = await ready(plain);
        const area = document.getElementById(plain).closest('.aov-plot-area');
        const group = area && area.nextElementSibling;
        check(group && group.classList.contains('aov-ribbon-view') && group.getAttribute('role') === 'group' &&
            group.getAttribute('aria-label') === 'Drawing' && switches(plain).every(b => b.parentElement === group),
            'plain: a named group right after the plot');
        check(pressed(plain).join() === 'ribbons' && drawsRibbons(pview), 'plain: starts as ribbons');
        check(/Bands overlap \d+% of the y range; intervals above 10%/.test(button(plain, 'intervals').title), 'plain: tooltip');
        button(plain, 'intervals').click();
        pview = await ready(plain, pview);
        check(drawsIntervals(pview) && pressed(plain).join() === 'intervals', 'plain: switched to intervals');
        check(AoV.setRibbonView(plain, 'ribbons') === true, 'setRibbonView: public');
        pview = await ready(plain, pview);
        check(drawsRibbons(pview), 'setRibbonView: ribbons again');
        check(AoV.setRibbonView(plain, 'bars') === false, 'setRibbonView: unknown view refused');

        // A log dose axis: the intervals keep true positions, dodged by colour
        // around each dose (positions read against the view's own x scale).
        const lg = 'ribbon-log';
        let lview = await ready(lg);
        const xScale = v => v.scale('x');
        check(pressed(lg).join() === 'intervals' && drawsIntervals(lview), 'log: starts as intervals');
        check(layers(AoV._cur[lg].spec).some(l => l.encoding && l.encoding.x && l.encoding.x.field === '__aov_x' &&
            l.encoding.x.type === 'quantitative' && l.encoding.x.scale && l.encoding.x.scale.type === 'log'),
            'log: intervals on the dodged log x');
        let sc = xScale(lview);
        check(sc && sc.type === 'log', 'log: a log x scale');
        const groupX = (v, d, g) => rules(v).filter(i => i.datum.dose === d && i.datum.study === 'S1' &&
            i.datum.group === g).map(i => i.x)[0];
        const g5 = ['A', 'B', 'C'].map(g => groupX(lview, 5, g));
        check(g5.every(x => x !== undefined) && g5[0] < g5[1] && g5[1] < g5[2], 'log: A, B, C left to right at 5: ' + g5);
        check(Math.abs(g5[1] - sc(5)) < 1, 'log: the middle group on the dose: ' + g5[1] + ' vs ' + sc(5));
        check(Math.abs(groupX(lview, 320, 'B') - sc(320)) < 1, 'log: the middle group on the dose at 320');
        check(g5[2] - g5[0] < 0.75 * (sc(10) - sc(5)), 'log: the dodge fits inside a doubling');
        const o5 = observations(lview).filter(i => i.datum.dose === 5);
        check(o5.length > 0 && o5.every(i => Math.abs(i.x - sc(5)) < 1), 'log: observations on the dose');
        // The picker moves the colour: the dodge follows the new colour.
        document.querySelector('input[type=radio][name="aov-pin-' + lg + '"][value=color]').click();
        const lrow = document.getElementById('aov-remap-row-' + lg);
        [...lrow.options].forEach(o => o.selected = o.value === 'group');
        lrow.dispatchEvent(new Event('change', {bubbles: true}));
        lview = await ready(lg, lview);
        sc = xScale(lview);
        const dx = AoV._cur[lg].spec._aov.dodgeX;
        check(dx && dx.by === 'study' && JSON.stringify(dx.domain) === '["S1","S2"]',
            'log re-facet: dodged by the new colour: ' + JSON.stringify(dx));
        const s5 = ['S1', 'S2'].map(s => rules(lview).filter(i => i.datum.dose === 5 && i.datum.group === 'A' &&
            i.datum.study === s).map(i => i.x)[0]);
        check(s5.every(x => x !== undefined) && s5[0] < s5[1] && Math.abs(mean(s5) - sc(5)) < 1,
            'log re-facet: two studies centred on the dose: ' + s5 + ' vs ' + (sc && sc(5)));
        check(cells(lview).length === 3 && drawsIntervals(lview), 'log re-facet: intervals per group row');
        button(lg, 'ribbons').click();
        lview = await ready(lg, lview);
        check(drawsRibbons(lview) && xScale(lview).type === 'log', 'log: the ribbons on the same log axis');

        // German texts.
        const de = 'ribbon-de';
        await ready(de);
        check(button(de, 'ribbons').textContent === 'Bänder' && button(de, 'intervals').textContent === 'Intervalle',
            'German: labels');
        check(/überlappen/.test(button(de, 'ribbons').title), 'German: tooltip');

        // A plot without a ribbon has no switch.
        await ready('ribbon-none');
        check(switches('ribbon-none').length === 0, 'no ribbon: no switch');

        check(errors.length === 0, 'unexpected runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
    }
    const result = document.createElement('pre');
    result.id = 'aov-ribbon-view-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
