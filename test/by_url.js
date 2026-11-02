// by_url in the browser (snag `odl-s-framed-reg-a3e457ca`): a layer whose
// rows the page fetches from an address draws exactly what the same rows
// written inline draw; a per-layer `calculate` adds its field to every row; a
// framed layer steps through the fetched rows; and a saved card's
// `AoV._preload` answers an address no server serves.
(async function () {
    const F = window.AOV_FIXTURE;
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
    // Drawn station symbols (items whose row carries a longitude), by name.
    function stations(view) {
        const out = {};
        (function walk(item) {
            if (item.mark?.marktype === 'symbol' && item.datum && 'lon' in item.datum)
                out[item.datum.name] = item;
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        return out;
    }

    try {
        const inline = stations(await ready('bu-inline'));
        const byUrl = stations(await ready('bu-url'));
        check(Object.keys(inline).length === F.names.length,
            'bu-inline: expected ' + F.names.length + ' stations, got ' + Object.keys(inline).length);
        check(JSON.stringify(Object.keys(byUrl).sort()) === JSON.stringify(F.names.slice().sort()),
            'bu-url: expected stations ' + F.names + ', got ' + Object.keys(byUrl));
        for (const name of F.names) {
            const a = inline[name], b = byUrl[name];
            if (!a || !b) continue;
            check(Math.abs(a.x - b.x) < 1e-6 && Math.abs(a.y - b.y) < 1e-6,
                'station ' + name + ' at (' + b.x + ', ' + b.y + ') from the address, (' + a.x + ', ' + a.y + ') inline');
            check(a.fill === b.fill, 'station ' + name + ': fill ' + b.fill + ' from the address, ' + a.fill + ' inline');
            check(b.datum.in_selected === (b.datum.AGS === F.selected),
                'station ' + name + ': in_selected ' + b.datum.in_selected + ' for AGS ' + b.datum.AGS);
            check(b.datum.kenn === a.datum.kenn, 'station ' + name + ': row field kenn ' + b.datum.kenn + ' vs ' + a.datum.kenn);
        }

        // A saved card answers its data URLs from AoV._preload: this plot's
        // address is served by nothing but the preload the page set up.
        const pre = stations(await ready('bu-preload'));
        check(Object.keys(pre).length === F.names.length,
            'bu-preload: expected ' + F.names.length + ' stations from the preloaded text, got ' + Object.keys(pre).length);

        // The script a "⬇ HTML" card carries for bu-url: its address and rows.
        const script = await AoV._preloadScript('bu-url');
        const m = /^<script>AoV\._preload\((.*)\);<\/script>$/s.exec(script);
        check(!!m, 'bu-url: preload script has an unexpected shape: ' + script.slice(0, 120));
        if (m) {
            const map = JSON.parse(m[1]);
            check(JSON.stringify(Object.keys(map)) === JSON.stringify([F.url]),
                'bu-url: preload keys ' + JSON.stringify(Object.keys(map)));
            check(map[F.url] === F.rows_json, 'bu-url: preloaded text differs from rows_json');
        }
        check(!/<\/script/i.test(script.slice(0, -'<\/script>'.length)),
            'bu-url: preload script spells a closing script tag inside its data');
        check(await AoV._preloadScript('bu-inline') === '', 'bu-inline: a plot with inline rows carries no preload');

        // A framed layer read from an address steps through the fetched rows.
        await ready('bu-frame');
        for (let i = 0; i < F.frames.length; i++) {
            await AoV.setFrame('bu-frame', i);
            const shown = Object.keys(stations(AoV.views['bu-frame'])).sort();
            check(JSON.stringify(shown) === JSON.stringify(F.frames[i].names),
                'bu-frame frame ' + F.frames[i].zeit + ': shows ' + JSON.stringify(shown) +
                ', expected ' + JSON.stringify(F.frames[i].names));
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const out = document.createElement('pre');
    out.id = 'aov-by-url-results';
    out.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(out);
})();
