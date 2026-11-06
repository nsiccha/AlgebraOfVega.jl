// Legend-label browser checks: every label of a continuous colour's legend lies
// inside the canvas, a figure whose labels already fit draws the same pixels as
// its unfitted control, and each cut-off control proves the cut was there.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 400; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    const canvasOf = id => document.getElementById(id).querySelector('canvas');
    // The drawn legend labels, with their extents in canvas pixels.
    function labelsOf(view) {
        const out = [];
        const origin = view.origin(), left = view.padding().left;
        const groupsX = item => {
            let x = 0, group = item.mark && item.mark.group;
            while (group) { x += group.x || 0; group = group.mark && group.mark.group; }
            return x;
        };
        (function walk(node) {
            if (node.marktype === 'text' && node.role === 'legend-label') {
                (node.items || []).forEach(item => {
                    if (item.opacity === 0 || item.text === null || item.text === '') return;
                    const shift = groupsX(item) + origin[0] + left;
                    out.push({text: item.text, align: item.align, dx: item.dx,
                        x1: item.bounds.x1 + shift, x2: item.bounds.x2 + shift});
                });
            }
            (node.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    async function whole(id, atLeast) {
        const view = await ready(id);
        const labels = labelsOf(view);
        const width = canvasOf(id).getBoundingClientRect().width;
        check(labels.length >= atLeast, id + ': expected at least ' + atLeast + ' labels, got ' + JSON.stringify(labels));
        labels.forEach(l => {
            check(l.x1 >= 0, id + ': "' + l.text + '" is cut at the left edge, x1=' + l.x1);
            check(l.x2 <= width, id + ': "' + l.text + '" is cut at the right edge of ' + width + ', x2=' + l.x2);
        });
        return labels;
    }

    try {
        // The start of the domain: the fix against its control.
        const low = await whole('low', 3);
        check(low[0].text === '−3.35', 'low: first label is the lowest tick, got ' + low[0].text);
        const lowControl = labelsOf(await ready('low-control'));
        check(lowControl[0].text === '−3.35' && lowControl[0].x1 < 0, 'low-control: the unfitted label must be cut, or this test proves nothing: ' + JSON.stringify(lowControl[0]));
        const compact = await whole('compact', 2);
        check(compact[0].text === '−102.5 Tsd.', 'compact: the labelExpr text is what is measured, got ' + compact[0].text);
        const compactControl = labelsOf(await ready('compact-control'));
        check(compactControl[0].x1 < 0, 'compact-control: the unfitted label must be cut: ' + JSON.stringify(compactControl[0]));
        check(low[1].dx === 0 && low[low.length - 1].dx === 0, 'low: only the label that hangs moves, got ' + JSON.stringify(low));

        await whole('top', 2);
        await whole('default-length', 2);
        await whole('font', 2);
        await whole('log', 2);
        await whole('dated', 2);
        await whole('stroke', 2);
        await whole('facet', 2);
        await whole('null-label', 1);

        // Frames keep the same fit in each frame.
        await whole('frame', 2);
        AoV.setFrame('frame', 1);
        await pause();
        await whole('frame', 2);

        // The far end, at the width regionexplorer-use measures for a map.
        const high = await whole('high', 2);
        const highControl = labelsOf(await ready('high-control'));
        const edge = canvasOf('high-control').getBoundingClientRect().width;
        check(highControl[highControl.length - 1].x2 > edge, 'high-control: the unfitted top label must be cut at ' + edge + ': ' + JSON.stringify(highControl));
        check(high[high.length - 1].text === highControl[highControl.length - 1].text || high.length < highControl.length,
            'high: the top label is the same tick, or Vega dropped it for overlap: ' + JSON.stringify(high));

        // Nothing to move: the same pixels, and the vertical gradient's labels stay.
        const same = async (a, b) => {
            await ready(a); await ready(b);
            check(canvasOf(a).toDataURL() === canvasOf(b).toDataURL(), a + ': pixels should equal ' + b);
        };
        await same('fits', 'fits-control');
        await same('exact', 'exact-control');
        await same('vertical', 'vertical-control');
        labelsOf(await ready('vertical')).forEach(l =>
            check(l.dx === 0 && l.align === 'left', 'vertical: a label must not move: ' + JSON.stringify(l)));
        // A positive control for `same`: the fit does change a figure that hangs.
        check(canvasOf('low').toDataURL() !== canvasOf('low-control').toDataURL(), 'low: the fit should change the pixels');

        // The picker's first drawing has the fit; a picked field draws a symbol legend.
        await whole('picker', 2);
        AoV.remapEncoding('picker', {color: 'g'});
        await pause();
        const picked = await whole('picker', 2);
        picked.forEach(l => check(l.dx === 0, 'picker: a symbol legend label must not move: ' + JSON.stringify(l)));

        // Rows that arrive later: the text and position of the new ticks are read.
        await ready('update');
        AoV.updateData('update', window.AOV_UPDATE_ROWS);
        for (let i = 0; i < 100 && !labelsOf(AoV.views.update).some(l => /Tsd/.test(l.text)); i++) await pause();
        const updated = await whole('update', 2);
        check(updated[0].text === '−102.5 Tsd.', 'update: the labels follow the rows, got ' + JSON.stringify(updated));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-legend-labels-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
