// Host-theme browser checks: plots draw their chrome in the page's text colour
// on a transparent background, keep their mark colours, and re-embed (keeping
// reader state) when the page switches theme.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const fixture = window.AOV_FIXTURE;
    const send = name => (0, eval)(fixture.updates[name]);
    const LIGHT = 'rgba(30,40,50,1)', DARK = 'rgba(200,210,220,1)';
    const themed = ['theme-picker', 'theme-live', 'theme-authored', 'theme-ink'];
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function items(view, predicate) {
        const out = [];
        (function walk(item) {
            if (predicate(item)) out.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }
    const role = (view, r) => items(view, i => i.mark?.role === r && i.mark?.marktype === 'text');
    const fills = (view, r) => [...new Set(role(view, r).map(i => i.fill))];
    const rules = view => items(view, i => i.mark?.marktype === 'rule' && i.datum && i.datum.state !== undefined);
    const inkRules = view => items(view, i => i.mark?.marktype === 'rule' && i.datum && i.datum.lo_0_95_ !== undefined);
    const legendLabels = view => role(view, 'legend-label').map(i => i.text).sort().join(',');

    function chrome(id, view, text, label) {
        const axis = fills(view, 'axis-label');
        check(axis.length === 1 && axis[0] === text, label + ' ' + id + ': axis labels ' + JSON.stringify(axis) + ', expected ' + text);
        const titles = fills(view, 'axis-title');
        check(titles.length >= 1 && titles.every(f => f === text), label + ' ' + id + ': axis titles ' + JSON.stringify(titles));
        check(view.background() === 'transparent', label + ' ' + id + ': background ' + view.background());
    }
    function palette(view, label) {
        const byState = {};
        rules(view).forEach(r => { byState[r.datum.state] = r.stroke; });
        check(byState.passed === fixture.palette[0] && byState.failed === fixture.palette[1],
            label + ': semantic palette changed: ' + JSON.stringify(byState));
    }
    async function pixel(url, x, y) {
        const img = new Image();
        await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; img.src = url; });
        const c = document.createElement('canvas');
        c.width = img.width; c.height = img.height;
        const ctx = c.getContext('2d');
        ctx.drawImage(img, 0, 0);
        return [...ctx.getImageData(x, y, 1, 1).data];
    }
    async function switchTheme(dark) {
        const before = {};
        Object.keys(AoV.views).forEach(id => { before[id] = AoV.views[id]; });
        if (dark) document.documentElement.setAttribute('data-theme', 'dark');
        else document.documentElement.removeAttribute('data-theme');
        const after = {};
        for (const id of themed) after[id] = await ready(id, before[id]);
        for (let i = 0; i < 60; i++) await pause();
        after['theme-none'] = AoV.views['theme-none'];
        check(after['theme-none'] === before['theme-none'], 'theme none: re-embedded on a theme switch');
        return after;
    }

    try {
        let views = {};
        for (const id of [...themed, 'theme-none']) views[id] = await ready(id);

        // Light page.
        chrome('theme-picker', views['theme-picker'], LIGHT, 'light');
        // (theme-live starts empty: no tick labels until its rows stream in)
        check(fills(views['theme-live'], 'axis-title').join() === LIGHT, 'light theme-live: axis titles');
        chrome('theme-ink', views['theme-ink'], LIGHT, 'light');
        check(fills(views['theme-picker'], 'legend-label')[0] === LIGHT, 'light: legend labels not host-coloured');
        palette(views['theme-picker'], 'light');
        check(legendLabels(views['theme-picker']) === 'failed,passed', 'light: legend ' + legendLabels(views['theme-picker']));
        const ink = inkRules(views['theme-ink']);
        check(ink.length > 0 && ink.every(r => r.stroke === LIGHT), 'light: aov-ink rules ' + JSON.stringify(ink.map(r => r.stroke)));
        // Authored config wins key by key: axis labels stay red, titles follow the host.
        check(fills(views['theme-authored'], 'axis-label').join() === '#ff0000', 'authored axis labelColor overridden: ' +
            JSON.stringify(fills(views['theme-authored'], 'axis-label')));
        check(fills(views['theme-authored'], 'axis-title').join() === LIGHT, 'authored: titles not host-coloured');
        // theme none: Vega defaults.
        check(views['theme-none'].background() === 'white', 'theme none: background ' + views['theme-none'].background());
        check(!fills(views['theme-none'], 'axis-label').includes(LIGHT), 'theme none: axis labels took the host colour');
        check(!('theme-none' in AoV._themeKeys), 'theme none: recorded as themed');

        // No change, no re-embed.
        AoV.refreshTheme();
        for (let i = 0; i < 30; i++) await pause();
        check(AoV.views['theme-picker'] === views['theme-picker'], 'refreshTheme re-embedded an unchanged plot');

        // Reader state before the switch: streamed rows and a picker remap.
        send('append');
        for (let i = 0; i < 30; i++) await pause();
        check(AoV.views['theme-live'].data('source_0').length === 3, 'live: appended rows not drawn');
        chrome('theme-live', await ready('theme-live'), LIGHT, 'light streamed');
        const pickerBefore = AoV.views['theme-picker'];
        AoV.remapEncoding('theme-picker', {color: 'group'});
        views['theme-picker'] = await ready('theme-picker', pickerBefore);
        check(legendLabels(views['theme-picker']) === 'g1,g2', 'remap: legend ' + legendLabels(views['theme-picker']));

        // Dark page.
        views = await switchTheme(true);
        for (const id of ['theme-picker', 'theme-live', 'theme-ink']) chrome(id, views[id], DARK, 'dark');
        check(fills(views['theme-picker'], 'legend-label')[0] === DARK, 'dark: legend labels not host-coloured');
        check(legendLabels(views['theme-picker']) === 'g1,g2', 'dark: picker assignment lost: ' + legendLabels(views['theme-picker']));
        check(views['theme-live'].data('source_0').length === 3, 'dark: streamed rows lost');
        check(inkRules(views['theme-ink']).every(r => r.stroke === DARK), 'dark: aov-ink rules not host-coloured');
        // Back to the authored colour field: the palette survives the theme.
        const remapped = AoV.views['theme-picker'];
        AoV.remapEncoding('theme-picker', {color: 'state'});
        views['theme-picker'] = await ready('theme-picker', remapped);
        palette(views['theme-picker'], 'dark');
        chrome('theme-picker', views['theme-picker'], DARK, 'dark remap');
        check(fills(views['theme-authored'], 'axis-label').join() === '#ff0000', 'dark: authored axis labelColor overridden');
        check(fills(views['theme-authored'], 'axis-title').join() === DARK, 'dark: authored titles not host-coloured');
        check(!fills(views['theme-none'], 'axis-label').includes(DARK), 'dark: theme none took the host colour');

        // Exports: themed images are painted on the host background, the live
        // view goes back to transparent; an unthemed one keeps Vega's white.
        const png = await AoV.plotImageURL('theme-picker', 'png');
        check(JSON.stringify((await pixel(png, 1, 1)).slice(0, 3)) === '[20,24,31]', 'png export background ' +
            JSON.stringify(await pixel(png, 1, 1)));
        check(views['theme-picker'].background() === 'transparent', 'export left the live background opaque');
        const svg = await AoV.plotImageURL('theme-picker', 'svg');
        const svgText = await (await fetch(svg)).text();
        check(svgText.includes('rgb(20,24,31)') && svgText.includes(DARK),
            'svg export lacks host background or text colour: ' + svgText.slice(0, 400));
        const plainPng = await AoV.plotImageURL('theme-none', 'png');
        check(JSON.stringify((await pixel(plainPng, 1, 1)).slice(0, 3)) === '[255,255,255]', 'theme none png background changed');

        // update_spec on a themed picker plot keeps the theme and the assignment.
        const beforeSpec = AoV.views['theme-picker'];
        send('spec');
        for (let i = 0; i < 60; i++) await pause();
        const afterSpec = await ready('theme-picker');
        chrome('theme-picker', afterSpec, DARK, 'update_spec');
        check(legendLabels(afterSpec) === 'failed,passed', 'update_spec: picker assignment lost: ' + legendLabels(afterSpec));
        palette(afterSpec, 'update_spec');
        check(Math.max(...AoV._plotData('theme-picker').map(r => r.__point__ || 0)) > 24, 'update_spec: data not refreshed');
        check(afterSpec === beforeSpec || afterSpec.background() === 'transparent', 'update_spec: background');

        // And back.
        views = await switchTheme(false);
        for (const id of ['theme-picker', 'theme-live', 'theme-ink']) chrome(id, views[id], LIGHT, 'back to light');
        check(views['theme-live'].data('source_0').length === 3, 'light again: streamed rows lost');
        palette(views['theme-picker'], 'light again');

        // An element-level theme switch (a class on a wrapper) needs refreshTheme().
        const wrapper = document.getElementById('theme-live').parentElement;
        const liveBefore = AoV.views['theme-live'];
        wrapper.style.color = 'rgb(1,2,3)';
        AoV.refreshTheme();
        const liveAfter = await ready('theme-live', liveBefore);
        chrome('theme-live', liveAfter, 'rgba(1,2,3,1)', 'refreshTheme');

        // Disposal clears the per-plot theme state.
        AoV.dispose('theme-ink');
        check(!('theme-ink' in AoV._themeKeys) && !('theme-ink' in AoV._reembeds), 'dispose left theme state');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-host-theme-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
