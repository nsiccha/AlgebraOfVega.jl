(async function () {
    if (location.search.includes('snapshot')) return;
    const failures = [], states = {};
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(r => setTimeout(r, 10));
    const ids = ['bg-points', 'bg-panel', 'bg-own', 'bg-view', 'bg-none', 'bg-fill', 'bg-color'];
    async function ready(id, previous) {
        for (let i = 0; i < 400; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error('embed timeout: ' + id);
    }
    function points(view) {
        const found = [];
        (function walk(item) {
            if (item.mark?.marktype === 'symbol' && item.datum?.x !== undefined) found.push(item);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return found;
    }
    const rgba = color => AoV._cssRGBA(color, document.body);
    const same = (a, b) => JSON.stringify(rgba(a)) === JSON.stringify(rgba(b));
    async function pixel(url) {
        const image = new Image();
        await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = reject; image.src = url; });
        const canvas = document.createElement('canvas'); canvas.width = image.width; canvas.height = image.height;
        const ctx = canvas.getContext('2d'); ctx.drawImage(image, 0, 0);
        return [...ctx.getImageData(1, 1, 1, 1).data];
    }
    async function inspect(theme, surface, panel) {
        const views = Object.fromEntries(await Promise.all(ids.map(async id => [id, await ready(id)])));
        const p = points(views['bg-points']);
        check(p.length === 24, theme + ': point count');
        check(p.every(i => same(i.stroke, surface) && i.strokeWidth === 1.5), theme + ': outlines');
        check(p.every(i => same(i.fill, '#1f6fb5') && i.opacity === 1 && i.size === 64), theme + ': fill, opacity, radius');
        check(points(views['bg-panel']).every(i => same(i.stroke, panel)), theme + ': translucent panel');
        check(points(views['bg-own']).every(i => same(i.stroke, '#456789')), theme + ': own background');
        check(points(views['bg-view']).every(i => same(i.stroke, '#aabbcc')), theme + ': own view fill');
        check(points(views['bg-none']).every(i => same(i.stroke, 'white')), theme + ': theme none');
        check(points(views['bg-fill']).every(i => same(i.fill, surface) && same(i.stroke, getComputedStyle(document.body).color)), theme + ': fill and ink');
        check(points(views['bg-color']).every(i => same(i.fill, surface)), theme + ': color');
        for (const [id, bg, paint = bg] of [['bg-points', surface], ['bg-panel', panel], ['bg-own', '#456789'], ['bg-view', '#445566', '#aabbcc']]) {
            const before = views[id].background();
            const png = await AoV.plotImageURL(id, 'png');
            check(JSON.stringify((await pixel(png)).slice(0, 3)) === JSON.stringify(rgba(bg).slice(0, 3)), theme + ': PNG ' + id);
            const svg = await (await fetch(await AoV.plotImageURL(id, 'svg'))).text();
            const doc = new DOMParser().parseFromString(svg, 'image/svg+xml');
            const marks = [...doc.querySelectorAll('[aria-roledescription="point"]')];
            check(marks.length === 24 && marks.every(m => same(m.getAttribute('stroke'), paint)), theme + ': SVG ' + id);
            check(views[id].background() === before, theme + ': download restores ' + id);
        }
        states[theme] = {surface, panel, points: p.map(i => ({fill:i.fill, stroke:i.stroke, width:i.strokeWidth, size:i.size, opacity:i.opacity}))};
    }
    try {
        await inspect('light', 'white', 'white');
        for (const [theme, surface, panel] of [['dark', 'rgb(24,28,37)', 'rgb(82,85,92)'], ['changed', 'rgb(40,50,60)', 'rgb(94,101,109)']]) {
            const old = {...AoV.views};
            document.documentElement.dataset.theme = theme;
            AoV.refreshTheme();
            await Promise.all(ids.filter(id => id !== 'bg-none').map(id => ready(id, old[id])));
            await inspect(theme, surface, panel);
        }
        const original = JSON.stringify(AoV._origSpecs['bg-points']);
        const remapped = AoV._remappedSpec('bg-points', {color:'x'});
        check(remapped.layer ? true : remapped.mark.color === '#1f6fb5', 'fixed colour survives picker');
        check(JSON.stringify(AoV._origSpecs['bg-points']) === original, 'stored spec unchanged');
        check(same(AoV._origSpecs['bg-points'].mark.stroke, 'white'), 'theme changes leave stored paint unresolved');
        check(!AoV._remappedSpec('bg-color', {color:'x'}).encoding.color, 'background colour survives picker');
        let saved;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = text => { saved = text; };
        try { await AoV.downloadPlotHtml('bg-points', 'background'); }
        finally { AoV._triggerDownload = trigger; }
        const frame = document.createElement('iframe');
        const loaded = new Promise(resolve => frame.addEventListener('load', resolve, {once:true}));
        frame.srcdoc = saved; document.body.append(frame); await loaded;
        for (let i = 0; i < 400 && !frame.contentWindow.AoV?.views['bg-points']; i++) await pause();
        const savedView = frame.contentWindow.AoV?.views['bg-points'];
        check(savedView && points(savedView).every(i => same(i.stroke, 'white')), 'saved HTML resolves its own white page');
        frame.remove();
    } catch (err) { failures.push(err.stack || String(err)); }
    const result = document.createElement('pre'); result.id = 'background-results';
    result.textContent = JSON.stringify({checks, failures, states}); document.body.appendChild(result);
})();
