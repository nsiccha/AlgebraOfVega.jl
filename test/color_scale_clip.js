// Colour-clipping browser checks: values outside `colorrange` paint the
// colormap's end colours (or `lowclip`/`highclip`), a NaN colour value paints
// `nan_color`, a NaN position stays undrawn, and a picker remap back to the
// authored colour field keeps the clip conditions.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    // Fill of each drawn data mark (geoshape `shape` or scatter `symbol`), by key.
    function fills(view, key, marktype) {
        const out = {};
        (function walk(item) {
            if (item.mark?.marktype === marktype && item.datum && item.datum[key] !== undefined)
                out[item.datum[key]] = item.fill;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const dark = fill => {
        const m = /rgb\((\d+), (\d+), (\d+)\)/.exec(fill || '');
        return !!m && (+m[1] + +m[2] + +m[3]) < 120;
    };

    try {
        const def = fills(await ready('clip-default'), 'ags', 'shape');
        check(Object.keys(def).length === 5, 'clip-default: expected 5 districts, got ' + JSON.stringify(def));
        check(def['01001'] === def['01002'], 'clip-default: -28 should take the low end colour of -20, got ' + def['01001'] + ' vs ' + def['01002']);
        check(def['01005'] === def['01004'], 'clip-default: 66 should take the high end colour of 20, got ' + def['01005'] + ' vs ' + def['01004']);
        check(!dark(def['01001']) && !dark(def['01005']), 'clip-default: out-of-range districts must not extrapolate to near-black: ' + JSON.stringify(def));
        check(def['01001'] !== def['01005'], 'clip-default: the two ends should differ');

        const col = fills(await ready('clip-colours'), 'ags', 'shape');
        check(col['01001'] === 'red', 'clip-colours: lowclip should paint -28 red, got ' + col['01001']);
        check(col['01003'] === 'green', 'clip-colours: highclip should paint 66 green, got ' + col['01003']);
        check(!!col['01002'] && ['red', 'green', 'grey'].indexOf(col['01002']) === -1, 'clip-colours: an in-range value keeps the scheme, got ' + col['01002']);
        check(col['01004'] === 'grey', 'clip-colours: nan_color should paint the NaN district grey, got ' + col['01004']);

        const pts = fills(await ready('clip-points'), 'id', 'symbol');
        check(pts.a === 'red' && pts.b === 'green', 'clip-points: clip colours on points, got ' + JSON.stringify(pts));
        check(pts.c === 'grey', 'clip-points: a NaN colour value paints nan_color, got ' + pts.c);
        check(!('d' in pts), 'clip-points: a NaN position stays undrawn, got ' + JSON.stringify(pts));

        // A continuous `Color` override on a figure that also colours routes by a
        // category: the map keeps its range and the routes paint in category colours
        // with a categorical legend (before, they painted nothing and the legend
        // listed the range bounds).
        const mixedView = await ready('clip-mixed');
        const mixed = fills(mixedView, 'ags', 'shape');
        check(mixed['01001'] === mixed['01002'] && !dark(mixed['01001']), 'clip-mixed: the map still clips to colorrange, got ' + JSON.stringify(mixed));
        const strokes = {};
        const labels = [];
        (function walk(item) {
            if (item.mark?.marktype === 'line' && item.datum && item.datum.check !== undefined)
                strokes[item.datum.check] = item.stroke;
            if (item.mark?.role === 'legend-label') labels.push(String(item.text));
            (item.items || []).forEach(walk);
        })(mixedView.scenegraph().root);
        const painted = s => !!s && s !== 'transparent';
        check(painted(strokes.ok) && painted(strokes['manual check']), 'clip-mixed: both routes are painted, got ' + JSON.stringify(strokes));
        check(strokes.ok !== strokes['manual check'], 'clip-mixed: the two categories differ, got ' + JSON.stringify(strokes));
        check(labels.includes('ok') && labels.includes('manual check'), 'clip-mixed: the routes legend lists the categories, got ' + JSON.stringify(labels));

        // The picker keeps an authored field's conditions, as it keeps its scale.
        const authored = {field: 'v', type: 'quantitative', scale: {domain: [-20, 20], clamp: true},
            condition: [{test: 'datum.v < -20', value: 'red'}]};
        check(JSON.stringify(AoV._remappedColor(authored, 'v', 'v').condition) === JSON.stringify(authored.condition),
            'remap: the authored field keeps its clip conditions');
        check(AoV._remappedColor(authored, 'other', 'Other').condition === undefined,
            'remap: another field gets no clip conditions');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-color-clip-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
