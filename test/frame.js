// Frame players in the browser (config(frame=…)): the controls after each
// framed plot, one frame shown at a time, scales and a map's framing fixed
// across frames, play/pause and the slider, the shown frame kept across
// resize, theme and update_spec re-embeds, refused raw-row data ops, the
// HTML download without the live controls, and teardown on removal.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms || 10));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    async function until(what, pred) {
        for (let i = 0; i < 500; i++) { if (pred()) return; await pause(); }
        throw new Error('timed out waiting for ' + what);
    }
    function items(view, type) {
        const out = [];
        (function walk(item, dx) {
            if (item.mark && item.mark.marktype === type && item.mark.role === 'mark') out.push({item, x1: dx + item.bounds.x1});
            const gx = item.mark && item.mark.marktype === 'group' ? dx + (item.x || 0) : dx;
            (item.items || []).forEach(child => walk(child, gx));
        })(view.scenegraph().root, 0);
        return out;
    }
    const box = id => document.querySelector('[data-aov-frame-for="' + id + '"]');
    const parts = id => {
        const b = box(id);
        return {play: b.querySelector('.aov-frame-play'), slider: b.querySelector('.aov-frame-slider'),
            label: b.querySelector('.aov-frame-value').textContent};
    };
    const fixture = window.AOV_FIXTURE;
    try {
        // --- The map: 2000 has A, B; 2001 has A, B, C; 2002 has A, C.
        let view = await ready('fr-map');
        const b = box('fr-map');
        check(!!b && b.previousElementSibling && b.previousElementSibling.classList.contains('aov-plot-area'),
            'map: the controls follow the plot area');
        check(document.querySelectorAll('[data-aov-frame-for="fr-map"]').length === 1, 'map: one controls element');
        let p = parts('fr-map');
        check(p.slider.max === '2' && p.slider.value === '0' && p.label === '2000',
            'map controls: max ' + p.slider.max + ' value ' + p.slider.value + ' label ' + p.label);
        check(p.play.getAttribute('aria-label') === 'Play', 'map: play button name ' + p.play.getAttribute('aria-label'));
        const seen = [];
        for (let i = 0; i < 3; i++) {
            await AoV.setFrame('fr-map', i);
            seen.push({lands: items(view, 'shape').map(s => s.item.datum.land).sort().join(''),
                fills: Object.fromEntries(items(view, 'shape').map(s => [s.item.datum.land, s.item.fill])),
                x1: Object.fromEntries(items(view, 'shape').map(s => [s.item.datum.land, Math.round(s.x1)])),
                domain: JSON.stringify(view.scale('color').domain()),
                label: parts('fr-map').label});
        }
        check(seen.map(s => s.lands).join('|') === 'AB|ABC|AC', 'map frames draw ' + seen.map(s => s.lands).join('|'));
        check(seen.map(s => s.label).join('|') === '2000|2001|2002', 'map labels ' + seen.map(s => s.label).join('|'));
        check(seen.every(s => s.domain === '[-2,3]'), 'map colour domain per frame ' + seen.map(s => s.domain).join(' '));
        // A is 1.0 in 2000 and in 2002: the same colour, as one shared scale draws it.
        check(seen[0].fills.A === seen[2].fills.A, 'map: A (1.0) is ' + seen[0].fills.A + ' in 2000, ' + seen[2].fills.A + ' in 2002');
        // C is absent in 2000: the projection still fits all frames, so A stays put.
        check(seen[0].x1.A === seen[1].x1.A && seen[1].x1.A === seen[2].x1.A,
            'map: A moves across frames ' + JSON.stringify(seen.map(s => s.x1.A)));

        // Play steps to the last frame and stops there (no loop) ...
        await AoV.setFrame('fr-map', 0);
        p.play.click();
        check(AoV._frames['fr-map'].playing && parts('fr-map').play.getAttribute('aria-label') === 'Pause',
            'map: playing after a click');
        await until('the map to stop', () => !AoV._frames['fr-map'].playing);
        p = parts('fr-map');
        check(AoV._frames['fr-map'].index === 2 && p.label === '2002' && view.signal('aov_frame') === 2002 &&
            p.play.getAttribute('aria-label') === 'Play',
            'map after play: index ' + AoV._frames['fr-map'].index + ' label ' + p.label + ' signal ' + view.signal('aov_frame'));
        // ... and from the last frame starts over at the first.
        p.play.click();
        check(AoV._frames['fr-map'].index === 0, 'map: play from the last frame restarts at ' + AoV._frames['fr-map'].index);
        await until('the map to stop again', () => !AoV._frames['fr-map'].playing);
        check(AoV._frames['fr-map'].index === 2, 'map: second play ends at ' + AoV._frames['fr-map'].index);

        // The slider shows a frame and pauses play.
        p.play.click();
        p.slider.value = '1';
        p.slider.dispatchEvent(new Event('input', {bubbles: true}));
        await pause(30);
        check(!AoV._frames['fr-map'].playing && view.signal('aov_frame') === 2001 && parts('fr-map').label === '2001',
            'map slider: playing ' + AoV._frames['fr-map'].playing + ' signal ' + view.signal('aov_frame'));

        // A resize re-embed keeps the shown frame and the shared domain.
        let old = view;
        check(AoV._resizeReembed('fr-map'), 'map: resize re-embeds');
        view = await ready('fr-map', old);
        check(view.signal('aov_frame') === 2001 && JSON.stringify(view.scale('color').domain()) === '[-2,3]',
            'map after resize: signal ' + view.signal('aov_frame') + ' domain ' + JSON.stringify(view.scale('color').domain()));
        check(document.querySelectorAll('[data-aov-frame-for="fr-map"]').length === 1, 'map: still one controls element after resize');

        // So does a host-theme switch.
        old = view;
        document.documentElement.setAttribute('data-theme', 'dark');
        view = await ready('fr-map', old);
        check(view.signal('aov_frame') === 2001, 'map after theme switch: signal ' + view.signal('aov_frame'));

        // Raw-row data ops are refused with a pointer to update_spec.
        const errors = [], origError = console.error;
        console.error = function () { errors.push(Array.prototype.join.call(arguments, ' ')); };
        const before = view.data('source_0').length;
        AoV.appendData('fr-map', [{land: 'A', year: 2003, anomaly: 5}]);
        await pause(30);
        console.error = origError;
        check(errors.some(e => e.indexOf('frame animation') !== -1 && e.indexOf('update_spec') !== -1) &&
            view.data('source_0').length === before, 'map appendData: ' + JSON.stringify(errors));

        // update_spec with a fourth year: one more frame, the shown one kept.
        old = view;
        (new Function(fixture.update))();
        view = await ready('fr-map', old);
        p = parts('fr-map');
        check(p.slider.max === '3' && AoV._frames['fr-map'].index === 1 && view.signal('aov_frame') === 2001 &&
            JSON.stringify(view.scale('color').domain()) === '[-2,5]',
            'map after update_spec: max ' + p.slider.max + ' index ' + AoV._frames['fr-map'].index +
            ' domain ' + JSON.stringify(view.scale('color').domain()));

        // --- Stacked bars: the y axis spans the tallest stack of any frame.
        view = await ready('fr-bars');
        const ys = [];
        for (let i = 0; i < 2; i++) { await AoV.setFrame('fr-bars', i); ys.push(JSON.stringify(view.scale('y').domain())); }
        check(ys[0] === ys[1] && view.scale('y').domain()[1] >= 11, 'bars y domain per frame ' + ys.join(' '));

        // --- A reference layer without the frame column is drawn in every frame.
        view = await ready('fr-ref');
        const refs = [];
        for (let i = 0; i < 2; i++) {
            await AoV.setFrame('fr-ref', i);
            refs.push(items(view, 'symbol').length + '/' + items(view, 'rule').length);
        }
        check(refs.join(' ') === '2/1 1/1', 'reference layer (points/rules) per frame ' + refs.join(' '));

        // --- Dates: the label shows the date, one point per frame, a fixed time axis.
        view = await ready('fr-time');
        const days = [];
        for (let i = 0; i < 3; i++) {
            await AoV.setFrame('fr-time', i);
            days.push(parts('fr-time').label + ':' + items(view, 'symbol').length + ':' + JSON.stringify(view.scale('x').domain().map(Number)));
        }
        check(days.every(d => d.split(':')[1] === '1') && new Set(days.map(d => d.split(':')[2])).size === 1 &&
            days.map(d => d.split(':')[0]).join(' ') === '2020-01-01 2020-01-02 2020-01-03', 'dates ' + days.join(' '));

        // --- German texts on a captioned figure; the HTML download leaves the live controls out.
        await ready('fr-de');
        p = parts('fr-de');
        check(p.play.getAttribute('aria-label') === 'Abspielen', 'German play button: ' + p.play.getAttribute('aria-label'));
        let saved = null;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = function (page) { saved = page; };
        await AoV.downloadPlotHtml('fr-de', 'fr-de');
        AoV._triggerDownload = trigger;
        const doc = saved && new DOMParser().parseFromString(saved, 'text/html');
        check(!!doc && !!doc.getElementById('fr-de') && !doc.querySelector('[data-aov-frame-for]'),
            'HTML download: ' + (saved ? 'controls left in the saved card' : 'nothing saved'));

        // --- Removing a playing plot stops its timer and drops its player.
        await ready('fr-bars');
        AoV.playFrames('fr-bars');
        const st = AoV._frames['fr-bars'];
        document.getElementById('fr-bars-wrap').remove();
        await until('fr-bars to be disposed', () => !AoV._frames['fr-bars']);
        check(!st.playing && st.timer === null, 'removed plot: playing ' + st.playing + ' timer ' + st.timer);
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-frame-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
