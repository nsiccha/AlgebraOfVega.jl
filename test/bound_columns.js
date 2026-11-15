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
    const PLOTS = {'bound-plain': 'source_0', 'bound-obs': 'aov_bound', 'bound-facet': 'source_0', 'bound-picker': 'source_0',
        'bound-rule': 'source_0'};
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
    // What the page asks the server once the inputs change: every request its
    // own code makes (htmx's XHR, a fetch), recorded as it is made, and every
    // network resource entry that started after `t0`. A resource entry is
    // added asynchronously (after its body has arrived), so the entry count
    // alone missed a request read just before the check (measured), and
    // could count an asset the page started before the inputs changed whose
    // entry landed late (the likely source of the 2 counted on GitHub's
    // Ubuntu runners). `blob:` entries (the browser module) are no requests.
    const pageRequests = [];
    let watching = false;
    const realFetch = window.fetch;
    window.fetch = function (input) {
        if (watching) pageRequests.push('fetch ' + String(input && input.url || input));
        return realFetch.apply(this, arguments);
    };
    const realOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
        if (watching) pageRequests.push('xhr ' + method + ' ' + url);
        return realOpen.apply(this, arguments);
    };
    const requestsSince = t0 => pageRequests.concat(performance.getEntriesByType('resource')
        .filter(e => /^https?:/.test(e.name) && e.startTime >= t0).map(e => 'resource ' + e.name));
    // A plot that does not follow ends the run, so the report is written
    // within the page's time budget.
    // The rule plot draws two tables of `line`: its wide columns (`source_0`)
    // and the one-row `mid` (`aov_bound`), each followed.
    const zOf = () => { const r = rows('bound-rule'); return r ? r.map(d => d.z).join(',') : null; };
    const midOf = () => { const r = rows('bound-rule', 'aov_bound'); return r && r.length === 1 ? r[0].mid : null; };
    async function allFollow(a, b, stage) {
        const want = ys(a, b);
        for (const id of Object.keys(PLOTS)) {
            const ok = await until(() => drawn(id) && yOf(id) === want, stage + ': ' + id + ' shows y = ' + want);
            check(ok, stage + ': ' + id + ' follows the inputs (y = ' + yOf(id) + ')');
            if (!ok) throw new Error(stage + ': stopped at ' + id);
        }
        const z = ys(a, b + 1), mid = b + 1.5 * a;
        const ok = await until(() => zOf() === z && midOf() === mid, stage + ': bound-rule shows z = ' + z + ', mid = ' + mid);
        check(ok, stage + ': bound-rule follows both tables (z = ' + zOf() + ', mid = ' + midOf() + ')');
        if (!ok) throw new Error(stage + ': stopped at bound-rule');
    }
    // The texts of a plot's legend entries.
    const legendLabels = id => {
        const out = [];
        (function walk(node) {
            if (!node) return;
            if (node.marktype && node.role === 'legend-label') (node.items || []).forEach(i => out.push(i.text));
            (node.items || []).forEach(walk);
        })(AoV.views[id] && AoV.views[id].scenegraph().root);
        return out;
    };

    try {
        if (!await until(() => Object.keys(PLOTS).every(drawn), 'the plots draw')) throw new Error('the plots did not draw');
        // The server's rows, marked as bound on each plot's area.
        await allFollow(2, 1, 'first render');
        for (const id of Object.keys(PLOTS)) {
            const area = document.querySelector('[data-aov-bound-for="' + id + '"]');
            check(!!area && area.classList.contains('aov-plot-area'), id + ': its plot area names it');
            const marker = area && JSON.parse(area.getAttribute('data-htmxo-bound-columns'));
            check(!!marker && marker.dataset === PLOTS[id] && marker.path[0] === 'line',
                id + ': the marker names its dataset (' + JSON.stringify(marker) + ')');
        }
        // The rule plot's second table rides an empty marker inside its area.
        const ruleMarker = document.querySelector('span[hidden][data-aov-bound-for="bound-rule"]');
        const ruleSpec = ruleMarker && JSON.parse(ruleMarker.getAttribute('data-htmxo-bound-columns'));
        check(!!ruleSpec && ruleSpec.dataset === 'aov_bound' && ruleSpec.columns.join(',') === 'mid' &&
            !!ruleMarker.closest('[data-aov-bound-for="bound-rule"].aov-plot-area'),
            'bound-rule: the marker of its one-row table (' + JSON.stringify(ruleSpec) + ')');
        // Its labelled layers each have a legend entry.
        check(['Line', 'Above', 'Middle'].every(t => legendLabels('bound-rule').includes(t)),
            'bound-rule: a legend entry per labelled layer (' + legendLabels('bound-rule').join(', ') + ')');
        // The observations beside the bound line stay as they are throughout.
        const obs = () => yOf('bound-obs', 'source_0');
        check(obs() === '1,4,6', 'the observations are drawn (' + obs() + ')');

        const before = performance.now();
        watching = true;
        const views = Object.fromEntries(Object.keys(PLOTS).map(id => [id, AoV.views[id]]));
        type('a', '3');
        await allFollow(3, 1, 'a = 3');
        type('b', '4');
        await allFollow(3, 4, 'a = 3, b = 4');
        check(obs() === '1,4,6', 'the observations stay (' + obs() + ')');
        // New rows go into the views in place.
        check(AoV.views['bound-plain'] === views['bound-plain'], 'the plain plot keeps its view');
        check(AoV.views['bound-rule'] === views['bound-rule'], 'the rule plot keeps its view');
        check(['Line', 'Above', 'Middle'].every(t => legendLabels('bound-rule').includes(t)),
            'bound-rule: its legend stays (' + legendLabels('bound-rule').join(', ') + ')');

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

        await pause(500);  // late resource entries land
        const asked = requestsSince(before);
        check(asked.length === 0, 'no request while the inputs changed (' + asked.join(', ') + ')');
        check(uncaught.length === 0, 'no uncaught error: ' + uncaught.join(' | '));
        check(!errors.some(e => /AoV\./.test(e)), 'no AoV console error: ' + errors.join(' | '));
    } catch (err) {
        failures.push('driver: ' + (err && err.stack || err));
    }
    document.getElementById('aov-bound-results').textContent = JSON.stringify({checks, failures});
});
