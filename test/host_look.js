// Host-look browser checks: host-themed plots take the page's font and its
// `--aov-*` look (palette, axis/grid/tick/domain, view-frame, legend and
// facet-header colours), keep authored colours, switch live through
// refreshTheme(), and carry the look into PNG/SVG downloads and a saved card.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const TEXT = 'rgba(30,40,50,1)', FAINT = 'rgba(30,40,50,0.133)';
    const PAGE_FONT = '"Test Grotesk", monospace', ALT_FONT = '"Alt Serif", serif';
    const TABLEAU = ['#4c78a8', '#f58518', '#e45756', '#72b7b2'];
    const ALT = ['rgb(10, 20, 30)', 'rgb(192, 255, 238)', 'rgb(1, 2, 3)', 'rgb(200, 100, 0)'];
    const themed = ['look-scatter', 'look-semantic', 'look-facet', 'look-authored', 'look-ink', 'look-face',
        'look-invalid', 'look-card'];
    async function ready(id, previous, win) {
        const A = (win || window).AoV;
        for (let i = 0; i < 300; i++) {
            const view = A.views[id];
            if (view && view !== previous && !A._inFlight[id]) return view;
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
    const role = (view, r) => items(view, i => i.mark?.role === r);
    const uniq = xs => [...new Set(xs)];
    const textFills = (view, r) => uniq(role(view, r).filter(i => i.mark.marktype === 'text').map(i => i.fill));
    const fonts = (view, r) => uniq(role(view, r).filter(i => i.mark.marktype === 'text').map(i => i.font));
    const ruleStrokes = (view, r) => uniq(role(view, r).filter(i => i.mark.marktype === 'rule').map(i => i.stroke));
    // The view frame: a single view's root `frame` group, or each facet cell
    // (`scope`); a facet's root carries no stroke.
    const frameStrokes = view => uniq(items(view, i => i.mark?.marktype === 'group' &&
        (i.mark.role === 'frame' || i.mark.role === 'scope') && 'stroke' in i).map(i => i.stroke));
    function viewFrame(view, expected, label) {
        const got = frameStrokes(view);
        check(same(got, expected), label + ': view frame ' + JSON.stringify(got) + ', expected ' + JSON.stringify(expected));
    }
    // Facet header labels and titles are both `title-text`; tell them by text.
    const headerFills = (view, texts) => uniq(role(view, 'title-text')
        .filter(i => texts.includes(i.text)).map(i => i.fill));
    function colorsBy(view, field) {
        const by = {};
        items(view, i => i.mark?.role === 'mark' && i.mark.marktype === 'symbol' && i.datum && i.datum[field] !== undefined)
            .forEach(i => { by[i.datum[field]] = i.fill || i.stroke; });
        return by;
    }
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    function palette(view, expected, label) {
        const by = colorsBy(view, 'cat');
        const got = ['c1', 'c2', 'c3', 'c4'].map(c => by[c]);
        check(same(got, expected), label + ': palette ' + JSON.stringify(got) + ', expected ' + JSON.stringify(expected));
    }
    function semantic(views, label) {
        const by = colorsBy(views['look-semantic'], 'state');
        check(by.passed === '#16826b' && by.failed === '#d94848', label + ': semantic palette changed ' + JSON.stringify(by));
    }
    function font(view, expected, label) {
        for (const r of ['axis-label', 'axis-title']) {
            const f = fonts(view, r);
            check(f.length === 1 && f[0] === expected, label + ': ' + r + ' font ' + JSON.stringify(f) + ', expected ' + expected);
        }
    }
    async function switchLook(alt) {
        const before = {};
        Object.keys(AoV.views).forEach(id => { before[id] = AoV.views[id]; });
        if (alt) document.documentElement.setAttribute('data-look', 'alt');
        else document.documentElement.removeAttribute('data-look');
        // A custom attribute is no theme switch the runtime watches for.
        AoV.refreshTheme();
        const after = {};
        for (const id of themed) after[id] = await ready(id, before[id]);
        for (let i = 0; i < 30; i++) await pause();
        after['look-none'] = AoV.views['look-none'];
        check(after['look-none'] === before['look-none'], 'theme none: re-embedded on a look switch');
        return after;
    }
    async function pixels(url) {
        const img = new Image();
        await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; img.src = url; });
        const c = document.createElement('canvas');
        c.width = img.width; c.height = img.height;
        const ctx = c.getContext('2d');
        ctx.drawImage(img, 0, 0);
        return ctx.getImageData(0, 0, c.width, c.height).data;
    }
    function hasPixel(data, rgb) {
        for (let i = 0; i < data.length; i += 4) {
            if (data[i] === rgb[0] && data[i + 1] === rgb[1] && data[i + 2] === rgb[2] && data[i + 3] === 255) return true;
        }
        return false;
    }

    try {
        let views = {};
        for (const id of [...themed, 'look-none']) views[id] = await ready(id);

        // --- No look set: the page font, Vega's palette and chrome. ---
        for (const id of themed.filter(id => id !== 'look-face')) font(views[id], PAGE_FONT, 'default ' + id);
        palette(views['look-scatter'], TABLEAU, 'default');
        semantic(views, 'default');
        check(same(ruleStrokes(views['look-scatter'], 'axis-grid'), [FAINT]), 'default: grid ' +
            JSON.stringify(ruleStrokes(views['look-scatter'], 'axis-grid')));
        check(role(views['look-scatter'], 'axis-tick').length > 0, 'default: no axis ticks');
        check(role(views['look-scatter'], 'axis-domain').length > 0, 'default: no axis domain');
        viewFrame(views['look-scatter'], [FAINT], 'default scatter');
        viewFrame(views['look-facet'], [FAINT], 'default facet');
        viewFrame(views['look-invalid'], ['rgb(4, 5, 7)'], 'default view colour');
        check(same(headerFills(views['look-facet'], ['p1', 'p2']), [TEXT]), 'default: header labels ' +
            JSON.stringify(headerFills(views['look-facet'], ['p1', 'p2'])));
        check(!fonts(views['look-none'], 'axis-label').includes(PAGE_FONT), 'theme none took the page font');
        check(!('font' in AoV.hostThemeConfig(null)), 'no element: font in the host config');

        // A web font nothing had used yet: the embed waited for its faces.
        check(window.AOV_FACE_BEFORE === false, 'test face was loaded before any plot used it');
        check(document.fonts.check('10px "AoV Test Face"') && document.fonts.check('bold 10px "AoV Test Face"'),
            'face plot rendered before its font loaded');
        font(views['look-face'], '"AoV Test Face"', 'face');

        // Invalid values are reported and ignored; valid ones still apply.
        const invalidEl = document.getElementById('look-invalid');
        const kids = invalidEl.childNodes.length;
        const warned = [];
        const warn = console.warn;
        console.warn = function () { warned.push([...arguments].join(' ')); };
        let invalidCfg;
        try { invalidCfg = AoV.hostThemeConfig(invalidEl); } finally { console.warn = warn; }
        check(invalidCfg.axis.gridColor === FAINT, 'invalid grid colour applied: ' + invalidCfg.axis.gridColor);
        check(!invalidCfg.range, 'palette with an invalid entry applied: ' + JSON.stringify(invalidCfg.range));
        check(invalidCfg.axis.tickColor === 'rgb(1, 2, 3)', 'valid tick colour beside invalid ones: ' + invalidCfg.axis.tickColor);
        check(invalidCfg.view.stroke === 'rgb(4, 5, 7)', 'valid view colour beside invalid ones: ' + invalidCfg.view.stroke);
        check(warned.length === 2 && warned.some(w => w.includes('--aov-grid-color') && w.includes('notacolor')) &&
            warned.some(w => w.includes('--aov-category') && w.includes('nocolor')), 'invalid values not reported: ' +
            JSON.stringify(warned));
        check(invalidEl.childNodes.length === kids, 'reading the look left nodes in the plot element');

        // Nothing changed, nothing re-embeds (the look is read the same way twice).
        await new Promise(resolve => setTimeout(resolve, 500));
        for (const id of themed) views[id] = await ready(id);
        AoV.refreshTheme();
        for (let i = 0; i < 30; i++) await pause();
        check(themed.every(id => AoV.views[id] === views[id]), 'refreshTheme re-embedded unchanged plots: ' +
            themed.filter(id => AoV.views[id] !== views[id]).join(','));

        // --- The page switches to its alternative look. ---
        views = await switchLook(true);
        const s = views['look-scatter'];
        palette(s, ALT, 'alt');
        font(s, ALT_FONT, 'alt');
        check(same(textFills(s, 'axis-label'), ['rgb(90, 0, 0)']), 'alt: axis labels ' + JSON.stringify(textFills(s, 'axis-label')));
        check(same(textFills(s, 'axis-title'), ['rgb(0, 90, 0)']), 'alt: axis titles ' + JSON.stringify(textFills(s, 'axis-title')));
        check(same(ruleStrokes(s, 'axis-grid'), ['rgb(0, 0, 90)']), 'alt: grid ' + JSON.stringify(ruleStrokes(s, 'axis-grid')));
        check(role(s, 'axis-tick').length === 0, 'alt: ticks drawn (--aov-tick-color: NONE)');
        check(role(s, 'axis-domain').length === 0, 'alt: axis line drawn (--aov-domain-color: none)');
        viewFrame(s, [null], 'alt scatter (--aov-view-color: none)');
        viewFrame(views['look-facet'], [null], 'alt facet (--aov-view-color: none)');
        check(same(textFills(s, 'legend-label'), ['rgb(91, 0, 0)']), 'alt: legend labels ' + JSON.stringify(textFills(s, 'legend-label')));
        check(same(textFills(s, 'legend-title'), ['rgb(0, 91, 0)']), 'alt: legend title ' + JSON.stringify(textFills(s, 'legend-title')));
        check(same(fonts(s, 'legend-label'), [ALT_FONT]), 'alt: legend font ' + JSON.stringify(fonts(s, 'legend-label')));
        semantic(views, 'alt');
        const facet = views['look-facet'];
        check(same(headerFills(facet, ['p1', 'p2']), ['rgb(92, 0, 0)']), 'alt: header labels ' +
            JSON.stringify(headerFills(facet, ['p1', 'p2'])));
        check(same(headerFills(facet, ['Panel']), ['rgb(0, 92, 0)']), 'alt: header title ' +
            JSON.stringify(headerFills(facet, ['Panel'])));
        // A spec's own config still wins key by key.
        check(same(textFills(views['look-authored'], 'axis-label'), ['#ff0000']), 'alt: authored labelColor overridden ' +
            JSON.stringify(textFills(views['look-authored'], 'axis-label')));
        check(same(textFills(views['look-authored'], 'axis-title'), ['rgb(0, 90, 0)']), 'alt: authored plot titles');
        // :ink keeps following the text colour.
        const inkStrokes = uniq(items(views['look-ink'], i => i.mark?.marktype === 'line' && i.stroke !== undefined).map(i => i.stroke));
        check(same(inkStrokes, [TEXT]), 'alt: ink line ' + JSON.stringify(inkStrokes));
        // An element-level property wins over the page's.
        font(views['look-face'], '"AoV Test Face"', 'alt face');
        check(same(ruleStrokes(views['look-invalid'], 'axis-grid'), [FAINT]), 'alt: invalid wrapper grid ' +
            JSON.stringify(ruleStrokes(views['look-invalid'], 'axis-grid')));
        viewFrame(views['look-invalid'], ['rgb(4, 5, 7)'], 'alt wrapper view colour');
        check(!fonts(views['look-none'], 'axis-label').includes(ALT_FONT), 'alt: theme none took the look font');

        // Downloads render with the same font and palette.
        const svg = await (await fetch(await AoV.plotImageURL('look-scatter', 'svg'))).text();
        check(svg.includes('Alt Serif') && ALT.every(c => svg.includes(c)), 'svg export lacks the look font or palette: ' +
            svg.slice(0, 300));
        const png = await pixels(await AoV.plotImageURL('look-scatter', 'png'));
        check(hasPixel(png, [10, 20, 30]) && hasPixel(png, [192, 255, 238]), 'png export lacks the look palette');

        // A saved card carries the look on its plot element and renders with it.
        let saved = null;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = function (text) { saved = text; };
        try { await AoV.downloadPlotHtml('look-card', 'look-card'); } finally { AoV._triggerDownload = trigger; }
        const doc = new DOMParser().parseFromString(saved || '', 'text/html');
        const savedPlot = doc.getElementById('look-card');
        const pinned = name => savedPlot ? savedPlot.style.getPropertyValue(name).trim() : '';
        check(pinned('--aov-font') === ALT_FONT, 'saved card font ' + pinned('--aov-font'));
        check(pinned('--aov-category').includes('#c0ffee') && pinned('--aov-category').includes('rgb(200, 100, 0)'),
            'saved card palette ' + pinned('--aov-category'));
        check(pinned('--aov-tick-color').toLowerCase() === 'none', 'saved card ticks ' + pinned('--aov-tick-color'));
        check(pinned('--aov-view-color') === 'none', 'saved card view frame ' + pinned('--aov-view-color'));
        const frame = document.createElement('iframe');
        frame.style.width = '900px';
        frame.style.height = '600px';
        const loaded = new Promise(resolve => frame.addEventListener('load', resolve, {once: true}));
        frame.srcdoc = saved || '';
        document.body.append(frame);
        await loaded;
        const savedView = await ready('look-card', null, frame.contentWindow);
        palette(savedView, ALT, 'saved card');
        font(savedView, ALT_FONT, 'saved card');
        check(role(savedView, 'axis-tick').length === 0, 'saved card: ticks drawn');
        viewFrame(savedView, [null], 'saved card');
        frame.remove();

        // --- And back to the page's default look. ---
        views = await switchLook(false);
        palette(views['look-scatter'], TABLEAU, 'back');
        font(views['look-scatter'], PAGE_FONT, 'back');
        check(role(views['look-scatter'], 'axis-tick').length > 0, 'back: no axis ticks');
        viewFrame(views['look-scatter'], [FAINT], 'back');
        check(same(textFills(views['look-scatter'], 'axis-label'), [TEXT]), 'back: axis labels');
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-host-look-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
