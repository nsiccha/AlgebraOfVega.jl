// Spec fragments (`to_html(spec)`) swapped in by htmx into a page that loads no
// Vega of its own (`swap`), and one parsed with its page (`parsed`). See
// test/swapped_fragment.jl.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    const uncaught = [];
    window.addEventListener('error', e => uncaught.push(String(e.message)));
    const logged = [];
    const consoleError = console.error;
    console.error = function (...args) { logged.push(args.map(String).join(' ')); return consoleError.apply(this, args); };
    // At most 5 s of (virtual) time each, so a run that never draws still
    // reports within the item's --virtual-time-budget.
    async function until(ready, what) {
        for (let i = 0; i < 250; i++) {
            if (ready()) return true;
            await pause(20);
        }
        failures.push(what + ': timed out');
        return false;
    }
    const plot = id => document.getElementById(id);
    const drawn = id => !!plot(id) && plot(id).classList.contains('vega-embed') && !!plot(id).querySelector('canvas');
    const swap = (url, target) => htmx.ajax('GET', url, {target, swap: 'innerHTML'});

    if (window.AOV_FIXTURE.mode === 'parsed') {
        // Parsed with the page: the Vega tags ran first, so it draws at once.
        check(typeof window.vegaEmbed === 'function', 'parsed page: vegaEmbed is defined');
        await until(() => drawn('swap-parsed'), 'parsed plot draws');
        check(drawn('swap-parsed'), 'parsed plot drew');
    } else {
        // A fragment whose Vega scripts cannot load, swapped in before any Vega
        // has loaded, says so in its container and in the console.
        check(typeof window.vegaEmbed === 'undefined', 'no Vega before the first swap');
        await swap('broken.html', '#broken');
        await until(() => plot('swap-broken')?.getAttribute('role') === 'alert', 'broken plot reports its failure');
        const text = plot('swap-broken')?.textContent || '';
        check(text.includes('vega_head()'), 'broken plot names vega_head(): ' + text);
        check(text.includes('/missing/vega.min.js'), 'broken plot names the script that did not load: ' + text);
        check(!drawn('swap-broken'), 'broken plot draws nothing');
        check(logged.some(m => m.includes('swap-broken') && m.includes('vega_head()')),
            'the console names the broken plot and vega_head(): ' + JSON.stringify(logged));

        // Still no Vega: htmx runs this fragment's embed before its script
        // tags have loaded. It draws once they have.
        check(typeof window.vegaEmbed === 'undefined', 'no Vega before the first good swap');
        await swap('first.html', '#first');
        await until(() => drawn('swap-first'), 'first swapped plot draws');
        check(drawn('swap-first'), 'first swapped plot drew');
        check(plot('swap-first')?.getAttribute('role') !== 'alert', 'first swapped plot reports no failure');

        // Vega is loaded now: a later swap draws at once.
        check(typeof window.vegaEmbed === 'function', 'Vega is loaded after the first good swap');
        await swap('second.html', '#second');
        await until(() => drawn('swap-second'), 'second swapped plot draws');
        check(drawn('swap-second'), 'second swapped plot drew');
        check(!logged.some(m => m.includes('swap-first') || m.includes('swap-second')),
            'no errors logged for the drawn plots: ' + JSON.stringify(logged));
    }
    check(uncaught.length === 0, 'uncaught errors: ' + uncaught.join(' | '));
    return {checks, failures};
})().catch(e => ({checks: 0, failures: [String(e && e.stack || e)]})).then(report => {
    document.getElementById('aov-swap-results').textContent = JSON.stringify(report);
});
