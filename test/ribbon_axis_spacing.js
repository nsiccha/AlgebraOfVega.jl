(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const id = 'ribbon-axis';
    async function ready(previous) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views[id] && AoV.views[id] !== previous && !AoV._inFlight[id]) return AoV.views[id];
            await new Promise(r => setTimeout(r, 10));
        }
        throw new Error('ribbon-axis did not embed');
    }
    try {
        let view = await ready();
        for (const theme of ['light', 'dark']) {
            document.documentElement.dataset.theme = theme;
            const previous = view;
            AoV._reembeds[id]();
            view = await ready(previous);
            if (AoV._ribbonViews[id].view !== 'intervals') {
                document.querySelector('[data-aov-ribbon-view-for="ribbon-axis"][data-view="intervals"]').click();
                view = await ready(view);
            }
            check(view.scale('x').type === 'log', theme + ': x stays logarithmic');
            check(AoV._ribbonViews[id].view === 'intervals', theme + ': Intervals active');
            const scale = view.scale('x');
            check(Math.abs((scale(40) - scale(4)) - (scale(100) - scale(10))) < 1e-6,
                theme + ': equal ratios have equal screen distances');
            const axes = [...document.querySelectorAll('#ribbon-axis g.role-axis')]
                .filter(a => (a.getAttribute('aria-label') || '').startsWith('X-axis'));
            check(axes.length > 0, theme + ': rendered x axes found');
            for (const axis of axes) {
                const labels = [...axis.querySelectorAll('g.role-axis-label text')]
                    .filter(t => t.textContent.trim());
                check(labels.length > 1 && labels.length < 10, theme + ': bounded numeric ticks');
                check(labels.every(t => t.textContent.length <= 6), theme + ': concise numeric labels');
                const boxes = labels.map(t => t.getBoundingClientRect()).sort((a, b) => a.left - b.left);
                check(boxes.every((b, i) => !i || boxes[i - 1].right <= b.left + 0.5),
                    theme + ': tick labels do not overlap');
            }
        }
    } catch (error) { failures.push(error.stack || String(error)); }
    const out = document.createElement('pre');
    out.id = 'aov-ribbon-axis-results';
    out.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(out);
}());
