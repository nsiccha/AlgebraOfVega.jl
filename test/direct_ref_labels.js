(async function () {
    const id = 'direct-bound', out = {checks: [], errors: []};
    const check = (ok, name) => out.checks.push({ok: !!ok, name});
    const pause = () => new Promise(r => setTimeout(r, 25));
    window.addEventListener('error', e => out.errors.push(e.message));
    // The rule shares the x domain with the line. A reference with no rows
    // must not make Vega warn about an infinite extent of its field, while
    // rows the rule cannot place still do, under this plot's id.
    const warned = [], warn = console.warn;
    console.warn = function () {
        warned.push(Array.from(arguments).map(String).join(' '));
        return warn.apply(console, arguments);
    };
    const extentWarnings = () => warned.filter(w => w.includes('Infinite extent'));
    const ready = async win => {
        for (let i = 0; i < 300; i++) {
            if (win.AoV && win.AoV.views[id] && !win.AoV._inFlight[id]) return;
            await pause();
        }
        throw Error('plot did not finish embedding');
    };
    const marks = win => {
        const got = {rules: [], labels: []};
        (function walk(it) {
            if (it.mark && it.mark.role === 'mark') {
                if (it.mark.marktype === 'rule') got.rules.push(it);
                if (it.mark.marktype === 'text' && it.text === 'Detection limit') got.labels.push(it);
            }
            (it.items || []).forEach(walk);
        })(win.AoV.views[id].scenegraph().root);
        return got;
    };
    const update = async (win, values) => {
        const nodes = win.document.querySelectorAll('[data-aov-bound-for="' + id + '"]');
        check(nodes.length > 0, 'bound markers are present');
        for (const node of nodes) node.dispatchEvent(new win.CustomEvent('htmxo:bound-columns', {
            bubbles: true, detail: {n: values.length, columns: {mid: values}}
        }));
        for (let i = 0; i < 200; i++) {
            const m = marks(win);
            if (m.rules.length === values.length && m.labels.length === values.length &&
                m.rules.every((r, j) => r.datum.mid === values[j]) &&
                m.labels.every((r, j) => r.datum.mid === values[j])) break;
            await pause();
        }
        for (let i = 0; i < 5; i++) await pause();
        const m = marks(win);
        check(m.rules.length === values.length, 'rule count ' + values.length);
        check(m.labels.length === values.length, 'label count ' + values.length);
        check(m.labels.every((l, j) => l.datum.mid === values[j] &&
            Math.abs(l.x - m.rules[j].x) < 0.01 && l.bounds.y2 <= 0 && l.opacity !== 0),
            'labels follow the rule above the plot');
        return m;
    };
    try {
        await ready(window);
        for (const theme of ['light', 'dark']) {
            document.documentElement.setAttribute('data-theme', theme);
            AoV.refreshTheme();
            await ready(window);
            for (const v of [1, 5, 8]) {
                const m = await update(window, [v]);
                check(m.labels.every((l, j) => l.fill === m.rules[j].stroke), theme + ' label uses the rule ink');
            }
            const before = extentWarnings().length;
            await update(window, []);
            check(extentWarnings().length === before, theme + ' an empty reference logs no infinite extent');
            const shown = AoV.views[id];
            AoV._reembeds[id]();
            for (let i = 0; i < 200 && (AoV.views[id] === shown || AoV._inFlight[id]); i++) await pause();
            for (let i = 0; i < 5; i++) await pause();
            check(AoV.views[id] !== shown && marks(window).rules.length === 0, theme + ' re-embedded while empty');
            check(extentWarnings().length === before, theme + ' nor does a re-embed while it is empty');
            await update(window, [2, 2.1]);
            const ls = marks(window).labels;
            check(ls.length === 2 && (ls[0].bounds.y2 <= ls[1].bounds.y1 || ls[1].bounds.y2 <= ls[0].bounds.y1),
                theme + ' close constant labels occupy separate rows');
        }
        const marker = document.querySelector('[data-aov-bound-for="' + id + '"]');
        marker.dispatchEvent(new CustomEvent('htmxo:bound-columns', {
            bubbles: true, detail: {n: 1, columns: {mid: [null]}}
        }));
        for (let i = 0; i < 20; i++) await pause();
        check(marks(window).rules.length === 0, 'a rule without a position draws nothing');
        check(extentWarnings().some(w => w.startsWith('[' + id + '] WARN Infinite extent for field "mid"')),
            'rows without a position still warn, tagged with this plot');
        await update(window, [5]);
        let saved;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = text => { saved = text; };
        try { await AoV.downloadPlotHtml(id, 'threshold'); }
        finally { AoV._triggerDownload = trigger; }
        check(typeof saved === 'string', 'standalone HTML was downloaded');
        const frame = document.createElement('iframe');
        frame.style.width = '800px'; frame.style.height = '400px';
        const loaded = new Promise(r => frame.addEventListener('load', r, {once: true}));
        frame.srcdoc = saved; document.body.appendChild(frame); await loaded;
        await ready(frame.contentWindow);
        check(marks(frame.contentWindow).labels.length === 1, 'downloaded plot retains the constant label');
        await update(frame.contentWindow, [8]);
        await update(frame.contentWindow, []);
    } catch (e) { out.errors.push(String(e.stack || e)); }
    const pre = document.createElement('pre'); pre.id = 'direct-label-result';
    pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
})();
