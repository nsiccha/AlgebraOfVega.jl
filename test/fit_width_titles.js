(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function settle(id) {
        for (let i = 0; i < 300; i++) {
            if (AoV.views[id] && !AoV._inFlight[id]) { await pause(100); if (!AoV._inFlight[id]) return; }
            await pause(10);
        }
        throw new Error(id + ': embed did not settle');
    }
    function fitted(label) {
        const id = 'ft-cached', el = document.getElementById(id), frame = el.parentElement;
        const width = el.querySelector('canvas.marks').clientWidth, room = frame.clientWidth;
        check(width <= room + 2, label + ': canvas ' + width + 'px exceeds ' + room + 'px');
        check(width >= room - 30, label + ': only ' + width + 'px of ' + room + 'px filled');
        check(frame.scrollWidth <= room + 2, label + ': frame scrolls by ' + (frame.scrollWidth - room) + 'px');
        check(AoV._computedWidths[id].nCols === 4, label + ': lost the four-plus-one wrap');
        const view = AoV.views[id], labels = [], right = [];
        (function walk(group, x) {
            (group.items || []).forEach(mark => {
                if (mark.role === 'legend-label') (mark.items || []).forEach(item => labels.push(item.text));
                if (mark.marktype !== 'group') return;
                (mark.items || []).forEach(item => {
                    if (mark.role === 'legend') right.push(x + item.bounds.x2);
                    walk(item, x + (item.x || 0));
                });
            });
        })(view.scenegraph().root.items[0], view.origin()[0] + view.padding().left);
        check(labels.includes('Twice daily'), label + ': missing the full legend label');
        check(right.length > 0 && right.every(x => x <= room), label + ': legend outside the frame: ' + right);
    }
    try {
        await settle('ft-cached'); await settle('ft-floor');
        fitted('cached');
        const initial = fitTitleEmbeds['ft-cached'];
        check(initial.length >= 3 && initial.length <= 6, 'cached: expected a measured correction after the first, got ' + initial);
        check(initial.every((w, i) => !i || w < initial[i - 1]), 'cached: corrections did not strictly shrink: ' + initial);
        const floor = AoV._computedWidths['ft-floor'], el = document.getElementById('ft-floor');
        check(floor.width === 100, 'oversized headers: stopped before the readable minimum: ' + floor.width);
        check(el.parentElement.scrollWidth > el.parentElement.clientWidth, 'oversized headers: no in-frame scroll');
        check(el.parentElement.tabIndex === 0, 'oversized headers: scrolling frame is not keyboard reachable');
        check(floor.nCols === 1, 'oversized headers: stopped before trying one column');
        check(fitTitleEmbeds['ft-floor'].length <= 6, 'oversized headers: too many attempts: ' + fitTitleEmbeds['ft-floor']);

        for (const theme of ['dark', 'light']) {
            document.documentElement.dataset.theme = theme;
            AoV.refreshTheme();
            await settle('ft-cached');
            fitted(theme);
        }
        // The primary interaction redraws the same data with different chrome.
        document.querySelector('[data-aov-ribbon-view-for="ft-cached"][data-view="ribbons"]').click();
        await settle('ft-cached');
        fitted('ribbons');
        document.querySelector('[data-aov-ribbon-view-for="ft-cached"][data-view="intervals"]').click();
        await settle('ft-cached');
        fitted('intervals');
        const widths = fitTitleEmbeds['ft-cached'], count = widths.length;
        const lastWidth = widths[count - 1];
        AoV._resizeReembed('ft-cached');
        await settle('ft-cached');
        check(widths.length === count + 1, 'unchanged resize restarted the correction sequence');
        check(widths[widths.length - 1] === lastWidth, 'unchanged resize changed the settled cell width');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-titles-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
