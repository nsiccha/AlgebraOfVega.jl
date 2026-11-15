// A static export of an HTMXObjects semantic page whose result draws AoV plots
// from `bound(line; columns)`: the browser computes `line` from the inputs and
// each plot follows, with no request. See test/bound_columns.jl.
window.addEventListener('load', async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms || 25));
    const uncaught = [];
    window.addEventListener('error', e => uncaught.push(String(e.message)));
    const errors = [];
    const consoleError = console.error;
    console.error = function () { errors.push(Array.from(arguments).map(String).join(' ')); return consoleError.apply(console, arguments); };
    const PLOTS = {'bound-plain': 'source_0', 'bound-obs': 'aov_bound', 'bound-facet': 'source_0', 'bound-picker': 'source_0'};
    const ys = (a, b) => [0, 1, 2, 3].map(x => a * x + b).join(',');

    async function until(test, label) {
        for (let i = 0; i < 400; i++) {
            if (test()) return true;
            await pause(25);
        }
        failures.push('timeout: ' + label);
        return false;
    }
    // Every plot drawn in the element that carries its id, with its rows.
    const drawn = id => {
        const view = AoV.views[id], el = document.getElementById(id);
        return !!view && !AoV._inFlight[id] && !!el && el.contains(view.container());
    };
    const rows = (id, name) => {
        try { return AoV.views[id].data(name || PLOTS[id]); } catch (e) { return null; }
    };
    const yOf = (id, name) => { const r = rows(id, name); return r ? r.map(d => d.y).join(',') : null; };
    const control = name => document.querySelector('input[name="' + name + '"]');
    function type(name, value) {
        const c = control(name);
        c.value = value;
        c.dispatchEvent(new Event('change', {bubbles: true}));
    }
    const choose = (name, value) => document.querySelector('input[name="' + name + '"][value="' + value + '"]').click();
    const requests = () => performance.getEntriesByType('resource').length;
    async function allFollow(a, b, stage) {
        const want = ys(a, b);
        for (const id of Object.keys(PLOTS)) {
            const ok = await until(() => drawn(id) && yOf(id) === want, stage + ': ' + id + ' shows y = ' + want + ' (' + yOf(id) + ')');
            check(ok, stage + ': ' + id + ' follows the inputs');
        }
    }

    try {
        await until(() => Object.keys(PLOTS).every(drawn), 'the plots draw');
        // The server's rows, marked as bound on each plot's area.
        await allFollow(2, 1, 'first render');
        for (const id of Object.keys(PLOTS)) {
            const area = document.querySelector('[data-aov-bound-for="' + id + '"]');
            check(!!area && area.classList.contains('aov-plot-area'), id + ': its plot area names it');
            const marker = area && JSON.parse(area.getAttribute('data-htmxo-bound-columns'));
            check(!!marker && marker.dataset === PLOTS[id] && marker.path[0] === 'line',
                id + ': the marker names its dataset (' + JSON.stringify(marker) + ')');
        }
        // The observations beside the bound line stay as they are throughout.
        const obs = () => yOf('bound-obs', 'source_0');
        check(obs() === '1,4,6', 'the observations are drawn (' + obs() + ')');

        const before = requests();
        const views = Object.fromEntries(Object.keys(PLOTS).map(id => [id, AoV.views[id]]));
        type('a', '3');
        await allFollow(3, 1, 'a = 3');
        type('b', '4');
        await allFollow(3, 4, 'a = 3, b = 4');
        check(obs() === '1,4,6', 'the observations stay (' + obs() + ')');
        // New rows go into the views in place.
        check(AoV.views['bound-plain'] === views['bound-plain'], 'the plain plot keeps its view');

        // The picker moves the group from colour to the panels: the browser's
        // rows stay.
        const color = document.getElementById('aov-remap-color-bound-picker');
        check(!!color, 'the picker has its colour control');
        if (color) {
            Array.from(color.options).forEach(o => { o.selected = false; });
            color.value = '';
            color.dispatchEvent(new Event('change', {bubbles: true}));
            const faceted = () => { const c = AoV._cur['bound-picker']; return !!c && JSON.stringify(c.spec).indexOf('"row"') !== -1; };
            check(await until(() => faceted() && drawn('bound-picker'), 'the picker re-facets by group'),
                'the picker re-facets by group');
            check(yOf('bound-picker') === ys(3, 4), 'the re-faceted picker keeps the browser\'s rows (' + yOf('bound-picker') + ')');
        }

        // Another mark is another view of the result (a finite input): its
        // plot is drawn from the export's rows and follows the browser's.
        choose('mark', 'point');
        check(await until(() => drawn('bound-plain') && AoV.views['bound-plain'] !== views['bound-plain'],
            'the point view draws'), 'the point view draws its plot');
        const symbols = () => { try { return AoV.views['bound-plain'].scenegraph().root.items[0].items.some(function walk(g) {
            return g.marktype === 'symbol' || (g.items || []).some(walk); }); } catch (e) { return false; } };
        check(symbols(), 'the point view draws points');
        await allFollow(3, 4, 'point view');
        type('b', '2');
        await allFollow(3, 2, 'point view, b = 2');
        choose('mark', 'line');
        await allFollow(3, 2, 'line view again');

        check(requests() === before, 'no request while the inputs changed (' + (requests() - before) + ')');
        check(uncaught.length === 0, 'no uncaught error: ' + uncaught.join(' | '));
        check(!errors.some(e => /AoV\./.test(e)), 'no AoV console error: ' + errors.join(' | '));
    } catch (err) {
        failures.push('driver: ' + (err && err.stack || err));
    }
    document.getElementById('aov-bound-results').textContent = JSON.stringify({checks, failures});
});
