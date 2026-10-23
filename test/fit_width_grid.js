// Plots sharing a grid or flex row, each embedded by its inline script while
// the page is parsed, are sized for their own column: the runtime measures
// them once the parser has reached the plots after them, never against the
// whole row. The page's probe script (before the plots) records the width each
// plot's container offered at every render in `window.aovGridEmbeds`.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }

    try {
        const ids = ['gr-a1', 'gr-a2', 'gr-b1', 'gr-b2', 'gr-c1', 'gr-c2'];
        for (const id of ids) await ready(id);
        // A layered plot's post-paint correction may re-embed it once.
        await pause(600);
        for (const id of ids) await ready(id);
        for (const id of ids) {
            const el = document.getElementById(id);
            const column = el.parentElement.clientWidth;
            const row = el.parentElement.parentElement.clientWidth;
            check(column < 0.6 * row, id + ': its column is ' + column + 'px of a ' + row + 'px row, not half');
            const offered = window.aovGridEmbeds.filter(e => e.id === id).map(e => e.offered);
            check(offered.length > 0, id + ': no render recorded');
            check(offered.every(w => Math.abs(w - column) <= 1),
                id + ': rendered for ' + offered.join(', ') + 'px, its column is ' + column + 'px');
            const canvas = el.querySelector('canvas').clientWidth;
            check(canvas <= column + 2 && canvas >= column - 60,
                id + ': canvas ' + canvas + 'px in a ' + column + 'px column');
        }
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-grid-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
