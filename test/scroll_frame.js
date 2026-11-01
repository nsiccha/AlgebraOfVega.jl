// A plot that scrolls in its `.aov-plot-area` is a named tab stop for exactly
// as long as it scrolls. Headless virtual time delivers ResizeObserver
// notifications after load unreliably (fit_width.js), so the driver calls
// `AoV._syncScrollFrame` the way the observer does.
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
    const el = id => document.getElementById(id);
    const area = id => el(id).closest('.aov-plot-area');
    const expectStop = (id, name, when) => {
        const a = area(id);
        check(a.getAttribute('tabindex') === '0', id + ' is no tab stop ' + when);
        check(a.getAttribute('role') === 'figure', id + ' has role ' + a.getAttribute('role') + ' ' + when);
        check(a.getAttribute('aria-label') === name, id + ' is named ' + a.getAttribute('aria-label') + ' ' + when);
    };
    const expectNoStop = (id, when) => {
        const a = area(id);
        ['tabindex', 'role', 'aria-label'].forEach(attr =>
            check(!a.hasAttribute(attr), id + ' keeps ' + attr + ' ' + when));
    };
    const rows = n => Array.from({length: n}, (_, i) => ({x: i, y: i}));
    const bars = extra => Object.assign({data: {values: rows(30)}, mark: 'bar', height: 60, encoding: {
        x: {field: 'x', type: 'ordinal'}, y: {field: 'y', type: 'quantitative'}}}, extra);
    try {
        const fixture = window.AOV_FIXTURE;
        for (const id of Object.keys(fixture.names)) await ready(id);
        for (const id of fixture.fits) await ready(id);

        // Under Pico a `[role=group]` is an inline-flex button row with a bottom
        // margin (the control proves Pico is on the page), so the tab stop's
        // role must leave the frame's layout alone.
        const control = document.createElement('div');
        control.setAttribute('role', 'group');
        document.body.append(control);
        check(getComputedStyle(control).display === 'inline-flex', 'Pico is not on the page');
        control.remove();
        for (const id of Object.keys(fixture.names)) {
            const style = getComputedStyle(area(id));
            check(style.display === 'block', id + ' displays as ' + style.display + ' once it is a tab stop');
            check(style.marginBottom === '0px', id + ' has a bottom margin of ' + style.marginBottom + ' once it is a tab stop');
        }

        // Named after what the reader knows the plot by, in the card's words.
        for (const [id, name] of Object.entries(fixture.names)) expectStop(id, name, 'when it scrolls');
        // A plot that fits adds no tab stop.
        for (const id of fixture.fits) expectNoStop(id, 'when it fits');

        // The spec's title in Vega-Lite's other spellings.
        const titled = el('sf-title-object');
        await AoV.embed('sf-title-object', bars({width: 900, title: {text: ['Two', 'lines']}}), {actions: false});
        await ready('sf-title-object');
        expectStop('sf-title-object', 'Scrollable plot: Two lines', 'with a multi-line title');
        check(titled.closest('.aov-plot-area').tabIndex === 0, 'the title object plot is out of the tab order');

        // A plot embedded straight into the frame (the explorer's #explorer-plot).
        await AoV.embed('sf-direct', bars({width: 900}), {actions: false});
        await ready('sf-direct');
        expectStop('sf-direct', 'Scrollable plot', 'embedded into the frame itself');

        // A plot outside any frame embeds as before.
        await AoV.embed('sf-frameless', bars({width: 900}), {actions: false});
        check(!!(await ready('sf-frameless')), 'a plot outside a frame did not embed');
        check(!AoV._scrollFrames['sf-frameless'], 'a plot outside a frame is watched');

        // The container decides: wide enough, the stop goes; narrow again, it is back.
        const sync = id => AoV._syncScrollFrame(id);
        const wrap = el('sf-wrap'), width = wrap.style.width;
        wrap.style.width = '1400px'; sync('sf-bare');
        expectNoStop('sf-bare', 'in a wide container');
        wrap.style.width = width; sync('sf-bare');
        expectStop('sf-bare', 'Scrollable plot', 'in a narrow container again');

        // A hidden frame scrolls nothing; shown again, it does.
        wrap.style.display = 'none'; sync('sf-bare');
        expectNoStop('sf-bare', 'while hidden');
        wrap.style.display = ''; sync('sf-bare');
        expectStop('sf-bare', 'Scrollable plot', 'shown again');

        // A frame that does not scroll is no stop, however wide its plot: a
        // page without aov.css, whose frame just lets the plot spill.
        const bare = area('sf-bare');
        bare.style.overflow = 'visible'; sync('sf-bare');
        expectNoStop('sf-bare', 'without a scrolling frame');
        bare.style.overflow = ''; sync('sf-bare');
        expectStop('sf-bare', 'Scrollable plot', 'with its scrolling frame again');

        // A sub-tolerance overshoot is no scrolling to speak of.
        const probe = area('sf-narrow');
        const child = document.createElement('div');
        child.style.width = (probe.clientWidth + 2) + 'px';
        child.style.height = '1px';
        probe.appendChild(child); sync('sf-narrow');
        check(probe.scrollWidth - probe.clientWidth === 2, 'the 2 px overshoot measured ' + (probe.scrollWidth - probe.clientWidth));
        expectNoStop('sf-narrow', 'at 2 px over');
        child.style.width = (probe.clientWidth + 3) + 'px'; sync('sf-narrow');
        expectStop('sf-narrow', 'Scrollable plot', 'at 3 px over');
        child.remove(); sync('sf-narrow');
        expectNoStop('sf-narrow', 'at no overshoot');

        // A plot that grows with its data becomes a stop; shrunk, it stops being one.
        await AoV.embed('sf-grow', {data: {name: 'table', values: rows(3)}, mark: 'bar', height: 60,
            width: {step: 30}, encoding: {x: {field: 'x', type: 'ordinal'}, y: {field: 'y', type: 'quantitative'}}}, {actions: false});
        await ready('sf-grow');
        expectNoStop('sf-grow', 'with three bars');
        AoV.updateData('sf-grow', rows(40), 'table');
        await AoV.views['sf-grow'].runAsync();
        await pause(50);
        sync('sf-grow');
        expectStop('sf-grow', 'Scrollable plot', 'with forty bars');

        // The reader's focus and scroll position survive a re-embed. While the
        // render is in flight its frame is emptied and fits, as the observer
        // then measures it.
        bare.focus();
        check(document.activeElement === bare, 'the frame takes the focus');
        bare.scrollLeft = 120;
        const before = AoV.views['sf-bare'];
        const again = AoV._reembeds['sf-bare']();
        let duringRender = 0;
        while (AoV._inFlight['sf-bare']) {
            duringRender++;
            sync('sf-bare');
            if (!bare.hasAttribute('tabindex')) { failures.push('the stop dropped during a re-embed'); break; }
            await pause(0);
        }
        await again;
        await ready('sf-bare', before);
        check(duringRender > 0, 'the re-embed was never seen in flight');
        check(document.activeElement === bare, 'focus moved to ' + document.activeElement.tagName + ' after a re-embed');
        expectStop('sf-bare', 'Scrollable plot', 'after a re-embed');

        // Teardown drops the observer; the frame's words stay with the DOM.
        const ro = AoV._scrollFrames['sf-narrow'];
        check(ro instanceof ResizeObserver, 'sf-narrow has no observer');
        AoV.dispose('sf-narrow');
        check(!AoV._scrollFrames['sf-narrow'], 'dispose kept the observer');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-scroll-frame-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
