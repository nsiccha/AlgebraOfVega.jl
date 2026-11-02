// Layer transforms in the browser: each plot draws exactly the marks its
// `config(transform=…)` leaves, which a spec's text cannot show. Vega-Lite runs a
// parent's transform only on data a child inherits, so where a transform sits
// decides which rows it reaches.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // How many data marks of each kind the view drew. Axes and legends have roles
    // of their own, and a line's points are its items.
    function drawn(view) {
        const out = {};
        (function walk(item) {
            const mark = item.mark;
            if (mark && mark.role === 'mark' && mark.marktype !== 'group' && item.datum)
                out[mark.marktype] = (out[mark.marktype] || 0) + 1;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const expected = {
        // The geoshape keeps its polygon; 2 labels past x > 1, 1 past x > 2.
        'lt-map': {shape: 1, text: 3},
        // 2 points past the filter, every label.
        'lt-shared': {symbol: 2, text: 3},
        // 2 of the shared table's rows and 1 of the other table's.
        'lt-whole': {symbol: 3},
        // A calculate that names columns the rules' table lacks leaves them drawn.
        'lt-calculate': {symbol: 3, rule: 2},
        // A transform leaves the lookup in place, so the region is painted.
        'lt-geoshape': {shape: 1},
        // 2 points past the filter across both panels, every point of the line.
        'lt-facet': {symbol: 2, line: 3},
    };

    try {
        for (const [id, want] of Object.entries(expected)) {
            const got = drawn(await ready(id));
            check(JSON.stringify(Object.entries(want).sort()) === JSON.stringify(Object.entries(got).sort()),
                id + ': expected ' + JSON.stringify(want) + ', drew ' + JSON.stringify(got));
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-layer-transform-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
