// A plot replaced under the same id is sized for its own chrome: the fit
// correction the previous plot earned (a narrower width for its axis labels
// and legend) does not carry over to a plot with a legend or wider labels.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
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
    const frame = id => document.getElementById(id).parentElement;
    // The right edge, in canvas px, of each legend the view draws. A group
    // item's bounds are in its parent's coordinates; the root group sits at
    // the view's origin plus its padding.
    function legends(view) {
        const found = [];
        (function walk(group, x) {
            (group.items || []).forEach(mark => {
                if (mark.marktype !== 'group') return;
                (mark.items || []).forEach(item => {
                    if (mark.role === 'legend') found.push(Math.ceil(x + item.bounds.x2));
                    else walk(item, x + (item.x || 0));
                });
            });
        })(view.scenegraph().root.items[0], view.origin()[0] + view.padding().left);
        return found;
    }
    const ids = ['sp-ribbon', 'sp-dose', 'sp-update'];

    try {
        for (const id of ids) await ready(id);
        // The first plots' post-paint correction re-embeds each once.
        await pause(600);
        for (const id of ids) await ready(id);
        for (const id of ids) {
            // The precondition: each first plot was corrected, in the regime
            // its replacement is sized in.
            check(!!(AoV._corrections || {})[id], id + ': the first plot was not corrected');
            check(canvasWidth(id) <= frame(id).clientWidth + 2,
                id + ' (before): canvas ' + canvasWidth(id) + 'px in a ' + frame(id).clientWidth + 'px frame');
        }
        check(legends(AoV.views['sp-ribbon']).length === 0, 'sp-ribbon (before): an uncoloured ribbon draws a legend');

        const previous = {};
        ids.forEach(id => { previous[id] = AoV.views[id]; });
        swapIn(document.getElementById('wrap-sp-ribbon'), 'sp-ribbon-next');
        swapIn(document.getElementById('wrap-sp-dose'), 'sp-dose-next');
        swapIn(document.getElementById('sp-scripts'), 'sp-update-next');
        for (const id of ids) await ready(id, previous[id]);
        await pause(600);
        for (const id of ids) await ready(id);

        for (const id of ids) {
            const view = AoV.views[id], width = canvasWidth(id), room = frame(id).clientWidth;
            check(width <= room + 2, id + ': canvas ' + width + 'px overflows its ' + room + 'px frame');
            check(width > room - 60, id + ': canvas ' + width + 'px does not fill its ' + room + 'px frame');
            check(frame(id).scrollWidth <= room + 2, id + ': the frame scrolls by ' + (frame(id).scrollWidth - room) + 'px');
            const edges = legends(view);
            check(edges.length > 0, id + ': no colour legend drawn');
            check(edges.every(x => x <= room), id + ': legend ends at ' + edges.join(', ') + 'px, past the ' + room + 'px frame');
        }
        // A resize re-embed in the same container keeps the corrected width.
        const before = AoV.views['sp-ribbon'], width = canvasWidth('sp-ribbon');
        check(AoV._resizeReembed('sp-ribbon') === true, 'sp-ribbon declined to re-embed on resize');
        await ready('sp-ribbon', before);
        await pause(300);
        check(canvasWidth('sp-ribbon') === width, 'sp-ribbon resized from ' + width + 'px to ' + canvasWidth('sp-ribbon') + 'px');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-swap-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
