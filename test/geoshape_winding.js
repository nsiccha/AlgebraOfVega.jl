// Winding browser checks (snag `a-choropleth-of-89e8fdc1`): GeoJSON wound
// counter-clockwise (RFC 7946) draws each district as its own polygon, inline
// and fetched from a URL, in the same place as clockwise (d3-wound) geometry,
// also under the frame player; and the runtime's rewind gives what Julia's does.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const fixture = window.AOV_FIXTURE;
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function shapes(view) {
        const out = [];
        (function walk(item) {
            if (item.mark?.marktype === 'shape' && item.datum) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const box = s => [s.bounds.x1, s.bounds.y1, s.bounds.x2, s.bounds.y2].map(v => Math.round(v));

    try {
        // Districts 01001–01003 stand side by side, west to east.
        const placed = {};
        for (const id of fixture.plots) {
            const drawn = shapes(await ready(id));
            check(drawn.length === 3, id + ': expected 3 districts, got ' + drawn.length);
            const byAgs = {};
            drawn.forEach(s => { byAgs[s.datum.AGS] = box(s); });
            placed[id] = byAgs;
            const xs = ['01001', '01002', '01003'].map(a => byAgs[a] && byAgs[a][0]);
            check(xs[0] < xs[1] && xs[1] < xs[2], id + ': districts are not west to east: ' + JSON.stringify(byAgs));
            const w = fixture.width;
            check(Object.values(byAgs).every(b => b[2] - b[0] < w / 2),
                id + ': a district spans the plot (drawn as the globe minus it): ' + JSON.stringify(byAgs));
        }
        const [ref, ...rest] = fixture.plots.filter(id => !/frame/.test(id));
        for (const id of rest)
            check(JSON.stringify(placed[id]) === JSON.stringify(placed[ref]),
                id + ': districts not where ' + ref + ' draws them: ' + JSON.stringify(placed[id]) + ' vs ' + JSON.stringify(placed[ref]));

        // The runtime's rewind and Julia's agree, case by case.
        fixture.cases.forEach((c, i) => {
            const got = JSON.parse(JSON.stringify(c.input));
            const changed = AoV._rewindGeoJSON(got);
            check(JSON.stringify(got) === JSON.stringify(c.expected),
                'case ' + i + ': runtime rewind ' + JSON.stringify(got) + ' differs from Julia ' + JSON.stringify(c.expected));
            check(changed === (JSON.stringify(c.input) !== JSON.stringify(c.expected)),
                'case ' + i + ': runtime reported changed=' + changed);
        });
        // Text that is not GeoJSON comes back byte for byte.
        const csv = 'name,type\na,"Polygon"\n';
        check(AoV._rewindLoaded(csv) === csv, 'a CSV naming "Polygon" was altered');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-geoshape-winding-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
