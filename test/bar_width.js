// Bar width browser checks (snag draw-hourly-amou-2b963e4e): bars on a
// numeric or time axis are drawn Makie's width, `width * (1 - gap)` in data
// units with `width` the smallest step between positions, centred on their
// position; they keep that width in data units at another plot width, after
// `updateData` brings rows at another step, in a `vconcat` panel and stacked
// by colour; the readout and its link group read a bar's own position; and
// the dataset keeps the rows as given (what a CSV download reads).
(async function () {
    const failures = [], measured = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const warnings = [];
    const warn = console.warn.bind(console), error = console.error.bind(console);
    console.warn = function () { warnings.push(Array.from(arguments).join(' ')); warn.apply(null, arguments); };
    console.error = function () { warnings.push(Array.from(arguments).join(' ')); error.apply(null, arguments); };
    async function ready(id) {
        for (let i = 0; i < 400; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // The drawn bars with the x scale of the group that holds them, in view
    // coordinates (a `vconcat` panel is a group of its own).
    function barsOf(view) {
        const out = [];
        (function walk(mark, ox, oy) {
            (mark.items || []).forEach(it => {
                if (mark.marktype === 'rect' && mark.role === 'mark' && /marks$/.test(mark.name || '')) {
                    out.push({item: it, x0: ox + it.x, x1: ox + it.x + it.width, y0: oy + it.y, y1: oy + it.y + it.height, ox});
                } else if (mark.marktype === 'group') {
                    (it.items || []).forEach(m => walk(m, ox + (it.x || 0), oy + (it.y || 0)));
                }
            });
        })(view.scenegraph().root, 0, 0);
        return out;
    }
    const position = (d, field) => {
        const v = d[field];
        return v instanceof Date ? +v : typeof v === 'string' ? +new Date(v) : v;
    };
    // Every bar is `share` of `step` data units wide, centred on its position.
    function widths(id, view, field, step, share, count, scaleName) {
        const bars = barsOf(view), xs = view.scale(scaleName || 'x');
        check(bars.length === count, id + ': expected ' + count + ' bars, got ' + bars.length);
        const unit = Math.abs(xs(step) - xs(0));
        const px = unit * share;
        bars.forEach(b => {
            const d = b.item.datum, c = position(d, field), mid = (b.x0 + b.x1) / 2 - b.ox;
            check(Math.abs((b.x1 - b.x0) - px) <= 0.01,
                id + ': bar at ' + d[field] + ' is ' + (b.x1 - b.x0).toFixed(2) + ' px wide, expected ' + px.toFixed(2));
            check(Math.abs(mid - xs(c)) <= 0.01,
                id + ': bar at ' + d[field] + ' is centred at ' + mid.toFixed(2) + ', its position is at ' + xs(c).toFixed(2));
        });
        measured[id] = {bars: bars.length, step_px: +unit.toFixed(2), bar_px: +px.toFixed(2),
            drawn_px: bars.slice(0, 3).map(b => +(b.x1 - b.x0).toFixed(2))};
        return {bars, unit, px};
    }

    try {
        // The reporter's figure, 48 hours at 900 px: each bar 0.8 h wide, so
        // twelve hours of rain read as one block with a small gap between bars.
        const hours = await ready('hours');
        const wide = widths('hours', hours, 'hour', 1, 0.8, 48);
        check(wide.unit > 15, 'hours: an hour is only ' + wide.unit + ' px');
        check(wide.px > 12, 'hours: bars are only ' + wide.px.toFixed(2) + ' px wide');
        // The outer bars lie inside the plot (`nice=false` ends the axis at their edges).
        const xs = hours.scale('x'), [r0, r1] = xs.range();
        const ends = wide.bars.map(b => [b.x0 - b.ox, b.x1 - b.ox]).flat();
        check(Math.min.apply(null, ends) >= r0 - 0.01 && Math.max.apply(null, ends) <= r1 + 0.01,
            'hours: bars reach past the plot area ' + JSON.stringify([Math.min.apply(null, ends), Math.max.apply(null, ends), r0, r1]));
        // The rows stay as given.
        const raw = hours.data('source_0');
        check(raw.length === 48 && raw.every(r => Object.keys(r).sort().join() === 'fall,hour'),
            'hours: source rows carry computed fields: ' + JSON.stringify(Object.keys(raw[0] || {})));

        // Half the plot width: the bars keep their width in hours.
        const narrow = widths('narrow', await ready('narrow'), 'hour', 1, 0.8, 48);
        check(Math.abs(narrow.px / wide.px - narrow.unit / wide.unit) < 1e-6 && narrow.unit < 0.7 * wide.unit,
            'narrow: bar width did not follow the plot width: ' + narrow.px + ' vs ' + wide.px);
        // An authored width and gap.
        widths('authored', await ready('authored'), 'hour', 1, 0.5 * 0.9, 48);

        // Hourly bars on a time axis.
        widths('timed', await ready('timed'), 't', 3600e3, 0.8, 6);

        // A `vconcat` panel under a level line: the same bars.
        const stacked = await ready('stacked');
        const panelBars = barsOf(stacked);
        check(panelBars.length === 48, 'stacked: expected 48 bars, got ' + panelBars.length);
        let scaleName = null;
        ['x', 'concat_1_x', 'concat_0_x'].forEach(n => { try { if (!scaleName && stacked.scale(n)) scaleName = n; } catch (e) {} });
        check(scaleName !== null, 'stacked: no x scale found');
        if (scaleName) widths('stacked', stacked, 'hour', 1, 0.8, 48, scaleName);

        // Colour groups at one hour stack, each bar the full width.
        const colours = await ready('colours');
        const cb = widths('colours', colours, 'hour', 1, 0.8, 12);
        const byHour = {};
        cb.bars.forEach(b => (byHour[b.item.datum.hour] = byHour[b.item.datum.hour] || []).push(b));
        Object.keys(byHour).forEach(h => {
            const g = byHour[h].sort((a, b) => a.y0 - b.y0);
            check(g.length === 2 && Math.abs(g[0].y1 - g[1].y0) <= 0.01,
                'colours: the two bars at hour ' + h + ' do not stack: ' + JSON.stringify(g.map(b => [b.y0, b.y1])));
        });

        // New rows at half-hour steps: the bars follow the new step.
        await ready('update');
        AoV.updateData('update', window.AOV_UPDATE_ROWS);
        for (let i = 0; i < 200 && barsOf(AoV.views.update).length !== window.AOV_UPDATE_ROWS.length; i++) await pause();
        widths('update', AoV.views.update, 'hour', 0.5, 0.8, window.AOV_UPDATE_ROWS.length);

        // The readout reads a bar's own hour at its middle.
        const rv = await ready('readout');
        const st = AoV._readouts.readout;
        const plan = st && st.plan;
        check(!!plan && plan.x === 'hour', 'readout: plan reads ' + (plan && plan.x));
        if (plan) {
            const scope = AoV._readoutScopes(rv, plan)[0];
            const items = scope ? AoV._readoutItems(plan, scope) : [];
            const rb = barsOf(rv);
            check(items.length === 48, 'readout: ' + items.length + ' items');
            items.forEach(c => {
                const b = rb.find(b => b.item === c.item);
                check(c.value === c.datum.hour && b && Math.abs(c.x - (b.x0 + b.x1) / 2) <= 0.01,
                    'readout: item at ' + c.datum.hour + ' reads ' + c.value + ' at ' + c.x);
            });
            check(AoV._readoutOwnsLink('readout'), 'readout: the link keyed by hour is not the readout\'s');
        }

        // The reporter's captioned figure (`with_plot_caption`, 1500 px column).
        const cap = widths('washout-rain', await ready('washout-rain'), 'hour', 1, 0.8, 48);
        check(cap.px > 20, 'washout-rain: bars are only ' + cap.px.toFixed(2) + ' px wide');

        const vega = warnings.filter(w => !/favicon/.test(w));
        check(vega.length === 0, 'console warnings: ' + JSON.stringify(vega));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-bar-width-results';
    pre.textContent = JSON.stringify({checks, failures, measured});
    document.body.appendChild(pre);
})();
