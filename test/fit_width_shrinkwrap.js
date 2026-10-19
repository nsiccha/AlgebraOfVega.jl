// A fitted plot whose container grows with its content (an auto-layout table
// cell, like a master/detail row's `<td colspan>`) settles at the room the
// container offers: its own render never widens the budget it is sized from.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    // The regression re-embedded without ever yielding the main thread; cap
    // the embeds so it fails this item instead of hanging the suite.
    const embeds = {};
    const embed = window.vegaEmbed;
    window.vegaEmbed = function (selector, spec, opts) {
        const id = selector.slice(1);
        embeds[id] = (embeds[id] || 0) + 1;
        if (embeds[id] === 21) failures.push(id + ': unbounded re-embed loop (stopped at 20 embeds)');
        if (embeds[id] > 20) return Promise.reject(new Error(id + ': unbounded re-embed loop'));
        return embed(selector, spec, opts);
    };
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // An htmx swap: insert the fragment, then run its scripts.
    function swapIn(target, template) {
        target.innerHTML = document.getElementById(template).innerHTML;
        target.querySelectorAll('script').forEach(old => {
            const script = document.createElement('script');
            script.textContent = old.textContent;
            old.replaceWith(script);
        });
    }
    const canvasWidth = id => document.querySelector('#' + id + ' canvas').clientWidth;
    const areaWidth = id => document.getElementById(id).parentElement.clientWidth;

    try {
        swapIn(document.getElementById('sw-cell'), 'sw-detail');
        swapIn(document.getElementById('sw-tol-cell'), 'sw-tol-plot');
        for (const id of ['sw-half-a', 'sw-half-b', 'sw-full', 'sw-tol']) await ready(id);
        await pause(600);

        // Before, each post-embed correction re-measured the cell its own
        // overshooting paint had just widened, opened a new sizing regime and
        // re-embedded again: a promise chain that grew the plots without end
        // and starved the page (snag rendered-layered-13357461).
        const table = document.getElementById('sw-table');
        check(table.offsetWidth === 900, 'detail table grew to ' + table.offsetWidth + 'px (its wrapper is 900px)');
        for (const id of ['sw-half-a', 'sw-half-b', 'sw-full']) {
            check(embeds[id] <= 2, id + ' embedded ' + embeds[id] + ' times (one sizing, at most one correction)');
            check(canvasWidth(id) <= areaWidth(id),
                id + ' canvas ' + canvasWidth(id) + 'px overflows its ' + areaWidth(id) + 'px frame');
            check(canvasWidth(id) > areaWidth(id) - 40,
                id + ' canvas ' + canvasWidth(id) + 'px does not fill its ' + areaWidth(id) + 'px frame');
        }

        // A resize re-embed in an unchanged container is a fixpoint: the
        // corrected width again, with no second correction.
        for (const id of ['sw-half-a', 'sw-full']) {
            const before = AoV.views[id], width = canvasWidth(id), count = embeds[id];
            check(AoV._resizeReembed(id) === true, id + ' declined to re-embed on resize');
            await ready(id, before);
            await pause(300);
            check(canvasWidth(id) === width, id + ' resized from ' + width + 'px to ' + canvasWidth(id) + 'px');
            check(embeds[id] === count + 1, id + ' took ' + (embeds[id] - count) + ' embeds to re-embed once');
        }
        check(table.offsetWidth === 900, 'detail table grew to ' + table.offsetWidth + 'px on resize re-embeds');

        // Within the correction's 2px tolerance nothing is corrected, so the
        // plot overshoots its budget and widens a 600px auto-layout table. A
        // budget measured with the plot in place then grew it by the overshoot
        // on every resize re-embed, and each growth fired the ResizeObserver
        // again (a re-embed every ~200ms, without end).
        const tolCell = document.getElementById('sw-tol-cell');
        const tolWidth = canvasWidth('sw-tol'), cellWidth = tolCell.clientWidth;
        check(tolWidth > 600 && tolWidth <= 602,
            'tolerance fixture renders ' + tolWidth + 'px, not within 2px past its 600px table');
        for (let i = 0; i < 3; i++) {
            const before = AoV.views['sw-tol'];
            AoV._resizeReembed('sw-tol');
            await ready('sw-tol', before);
        }
        check(canvasWidth('sw-tol') === tolWidth,
            'tolerance plot grew from ' + tolWidth + 'px to ' + canvasWidth('sw-tol') + 'px over 3 resize re-embeds');
        check(tolCell.clientWidth === cellWidth,
            'tolerance cell grew from ' + cellWidth + 'px to ' + tolCell.clientWidth + 'px over 3 resize re-embeds');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-shrinkwrap-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
