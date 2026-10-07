// Standalone HTML export checks: `AoV.downloadPlotHtml` on a page that loads
// the Vega trio and AoV's runtime inline or by same-origin URL saves ONE file
// that carries every byte it needs, renders in isolation, and keeps its picker.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const fixture = window.AOV_FIXTURE;
    const id = fixture.id;
    async function ready(win, previous) {
        for (let i = 0; i < 500; i++) {
            const view = win.AoV && win.AoV.views && win.AoV.views[id];
            if (view && view !== previous && !win.AoV._inFlight[id]) return view;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function legend(view) {
        const out = [];
        (function walk(item) {
            if (item.mark?.role === 'legend-label' && item.mark?.marktype === 'text') out.push(item.text);
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out.sort().join(',');
    }
    const styled = win => {
        const probe = win.document.createElement('div');
        probe.className = 'aov-plot-area';
        win.document.body.append(probe);
        const overflow = win.getComputedStyle(probe).overflowX;
        probe.remove();
        return overflow;
    };

    try {
        const live = await ready(window);
        const byUrl = document.querySelectorAll('[data-aov-vendor][src], [data-aov-vendor][href]').length;
        check(byUrl === fixture.byUrl, 'assets loaded by URL: ' + byUrl + ', expected ' + fixture.byUrl);
        // (Split so this driver never carries the runtime's own marker,
        // which the exporter would copy into the saved page.)
        const runtimeMarker = 'window.AoV = ' + 'window.AoV ||';
        const inlineRuntime = [...document.scripts].some(s => !s.src &&
            (s.textContent || '').indexOf(runtimeMarker) !== -1);
        check(inlineRuntime === !fixture.linked, 'inline runtime present: ' + inlineRuntime);
        check(styled(window) === 'auto', 'live page: AoV stylesheet not applied');
        // The documented mount: `?v=`-versioned URLs route to the files, which
        // come back with the immutable lifetime the versions make safe.
        for (const el of document.querySelectorAll('[data-aov-vendor][src], [data-aov-vendor][href]')) {
            const url = el.src || el.href;
            check(/\?v=[0-9a-f]{16}$/.test(url), 'unversioned vendor URL ' + url);
            const response = await fetch(url);
            check(response.ok && (response.headers.get('cache-control') || '').indexOf('immutable') !== -1,
                url + ': HTTP ' + response.status + ', cache-control ' + response.headers.get('cache-control'));
        }
        check(legend(live) === 'failed,passed', 'live legend ' + legend(live));

        let saved = null;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = function (text, filename, mime) { saved = {text, filename, mime}; };
        try {
            await AoV.downloadPlotHtml(id, 'saved-card');
        } finally {
            AoV._triggerDownload = trigger;
        }
        check(saved && saved.filename === 'saved-card.html' && saved.mime === 'text/html', 'no html download');
        const page = saved ? saved.text : '';
        // Elements, not text: the inlined bytes may mention tags in strings.
        const doc = new DOMParser().parseFromString(page, 'text/html');
        check(doc.querySelectorAll('script[src]').length === 0, 'saved page loads a script by URL');
        check(doc.querySelectorAll('link').length === 0, 'saved page links a stylesheet');
        const marked = doc.querySelectorAll('script[data-aov-vendor], style[data-aov-vendor]').length;
        check(marked === fixture.savedMarked, 'saved page: ' + marked + ' vendored assets, expected ' + fixture.savedMarked);

        // Render the saved file in isolation: everything it runs is inline.
        const frame = document.createElement('iframe');
        frame.style.width = '1000px';
        frame.style.height = '800px';
        const loaded = new Promise(resolve => frame.addEventListener('load', resolve, {once: true}));
        frame.srcdoc = page;
        document.body.append(frame);
        await loaded;
        const win = frame.contentWindow;
        check(win.vega && win.vega.version === fixture.versions[0], 'saved page: vega ' + (win.vega && win.vega.version));
        check(win.vegaLite && win.vegaLite.version === fixture.versions[1], 'saved page: vega-lite ' + (win.vegaLite && win.vegaLite.version));
        check(win.vegaEmbed && win.vegaEmbed.version === fixture.versions[2], 'saved page: vega-embed ' + (win.vegaEmbed && win.vegaEmbed.version));
        check(typeof (win.AoV && win.AoV.remapEncoding) === 'function', 'saved page: no AoV runtime');
        check(styled(win) === 'auto', 'saved page: AoV stylesheet not applied');
        const view = await ready(win);
        check(win.AoV._plotData(id).length === AoV._plotData(id).length, 'saved page: rows ' +
            win.AoV._plotData(id).length + ' vs ' + AoV._plotData(id).length);
        check(legend(view) === 'failed,passed', 'saved page legend ' + legend(view));
        // The picker still re-facets inside the saved file.
        win.AoV.remapEncoding(id, {color: 'group'});
        const remapped = await ready(win, view);
        check(legend(remapped) === 'g1,g2', 'saved page remap legend ' + legend(remapped));
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-export-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
