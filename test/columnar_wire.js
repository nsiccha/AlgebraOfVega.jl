(async function () {
    const failures = [];
    const errors = [];
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const fixture = window.AOV_FIXTURE;
    const send = name => (0, eval)(fixture.updates[name]);
    async function settle(id) {
        for (let i = 0; i < 300; i++) {
            await pause();
            if (AoV.views[id] && !AoV._inFlight[id] && !(AoV._pending[id] || []).length) break;
        }
        for (let i = 0; i < 20; i++) await pause();
        if (!AoV.views[id]) throw new Error(id + ': embed did not complete');
    }
    // Rows equal value by value: the same keys (`exactKeys`) or at least the
    // expected ones (a live view's tuples), and Object.is on every value, so
    // -0 versus 0 and 1 versus "1" differ.
    function sameRows(got, want, label, exactKeys) {
        check(got.length === want.length, label + ': ' + got.length + ' rows, expected ' + want.length);
        let bad = null;
        for (let i = 0; i < Math.min(got.length, want.length) && bad === null; i++) {
            const g = got[i], w = want[i], wk = Object.keys(w).sort();
            if (exactKeys && Object.keys(g).sort().join('\u0000') !== wk.join('\u0000'))
                bad = i + ': keys ' + Object.keys(g).sort() + ' vs ' + wk;
            for (const k of wk) {
                if (bad !== null) break;
                if (!Object.is(g[k], w[k])) bad = i + '.' + k + ': ' + JSON.stringify(g[k]) + ' vs ' + JSON.stringify(w[k]);
            }
        }
        check(bad === null, label + ': row ' + bad);
    }

    try {
        // Every case expands to exactly the rows its row-wise JSON parses to.
        Object.keys(fixture.wire).forEach(function(k) {
            const wire = JSON.parse(fixture.wire[k]);
            check(AoV._isColumns(wire), k + ': sent column by column');
            sameRows(AoV._rowsFromColumns(wire), JSON.parse(fixture.reference[k]), k, true);
        });
        const rows = [{a: 1}];
        check(AoV._rowsFromColumns(rows) === rows, 'a row array passes through');
        let threw = null;
        try { AoV._rowsFromColumns({n: 1, columns: {x: {foo: 1}}}); } catch (e) { threw = e; }
        check(threw && /unknown encoding/.test(threw.message), 'an unknown column encoding throws');

        // An embedded dataset reaches the view as rows.
        await settle('emb');
        sameRows(AoV._plotData('emb'), JSON.parse(fixture.expected.embedded), 'embedded', false);
        check(Array.isArray(AoV._origSpecs['emb'].data.values), 'embedded: stored spec holds rows');

        // Streaming into a typed-empty plot: append, sliding window, replace.
        await settle('live');
        send('append');
        await settle('live');
        sameRows(AoV._plotData('live'), JSON.parse(fixture.expected.append), 'append', false);
        send('append_window');
        await settle('live');
        sameRows(AoV._plotData('live'), JSON.parse(fixture.expected.long).slice(-500), 'append max_rows', false);
        send('update');
        await settle('live');
        sameRows(AoV._plotData('live'), JSON.parse(fixture.expected.long), 'update_data', false);
        check(AoV._liveRows['live'].source_0.length === JSON.parse(fixture.expected.long).length,
            'update_data: live rows kept as rows for re-embeds');

        // update_spec with only new data swaps the rows into the same view.
        const before = AoV.views['emb'];
        send('spec');
        await settle('emb');
        check(AoV.views['emb'] === before, 'update_spec: swapped in place');
        sameRows(AoV._plotData('emb'), JSON.parse(fixture.expected.spec), 'update_spec', false);

        check(errors.length === 0, 'unexpected runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
        ['live', 'emb'].forEach(id => AoV.dispose(id));
    }
    const result = document.createElement('pre');
    result.id = 'aov-columnar-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
