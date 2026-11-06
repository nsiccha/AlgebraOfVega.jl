// A plot's tooltip in the browser: one surface in the page's own colours, the
// background behind the plot and its text colour, per plot and across theme
// switches. A page's table rules stay out of it (Pico paints every cell in the
// page's background and text colour). Text that cannot be read on the background
// found behind the plot gets a surface of its own. `theme=:none`, a page's own
// tooltip rules and an embed's own tooltip theme keep what they ask for.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 500; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    function mark(view) {
        let found = null;
        (function walk(item) {
            if (found) return;
            if (item.mark && item.mark.role === 'mark' && item.tooltip != null) { found = item; return; }
            (item.items || []).forEach(walk);
        })(view.scenegraph().root);
        if (!found) throw new Error('no mark with a tooltip');
        return found;
    }
    // What the shown tooltip looks like. Opened through Vega's own tooltip
    // path, as a hover and the runtime's tap both reach it.
    function look(view) {
        const item = mark(view);
        view._handler.handleTooltip({clientX: 400, clientY: 300}, item, true);
        const el = document.getElementById('vg-tooltip-element');
        const cs = sel => getComputedStyle(sel ? el.querySelector(sel) : el);
        const out = {
            classes: el.className, shown: el.classList.contains('visible'),
            surface: cs().backgroundColor, border: cs().borderTopColor, color: cs().color,
            keyBack: cs('td.key').backgroundColor, keyColor: cs('td.key').color,
            valueBack: cs('td.value').backgroundColor, valueColor: cs('td.value').color,
            heading: el.querySelector('h2') ? cs('h2').color : null
        };
        view._handler.handleTooltip({clientX: 0, clientY: 0}, item, false);
        out.left = Array.from(el.classList).filter(c => /-theme$/.test(c));
        return out;
    }
    const channels = css => {
        const m = /rgba?\(([^)]*)\)/.exec(css);
        if (!m) throw new Error('not a colour: ' + css);
        const v = m[1].split(/[\s,\/]+/).map(Number);
        return v.length === 3 ? v.concat(1) : v;
    };
    const opaque = css => channels(css).slice(0, 3).join(', ');
    const lum = c => {
        const lin = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
    };
    // Contrast of a possibly translucent colour on an opaque one.
    const contrast = (fore, back) => {
        const f = channels(fore), b = channels(back);
        const c = [0, 1, 2].map(i => f[i] * f[3] + b[i] * (1 - f[3]));
        const [hi, lo] = [lum(c), lum(b)].sort((x, y) => y - x);
        return (hi + 0.05) / (lo + 0.05);
    };
    // One surface: the expected colours on the container, nothing on the
    // cells, text that reads at WCAG AA, and no theme left once it closes.
    function surface(l, back, text, what) {
        check(l.shown, what + ': no tooltip shown');
        check(l.surface === 'rgb(' + back + ')', what + ': surface ' + l.surface + ', expected ' + back);
        check(l.color === 'rgb(' + text + ')', what + ': text ' + l.color + ', expected ' + text);
        check(l.border === 'rgba(' + text + ', 0.15)', what + ': border ' + l.border);
        check(l.keyBack === 'rgba(0, 0, 0, 0)' && l.valueBack === 'rgba(0, 0, 0, 0)',
            what + ': cells paint a surface of their own: ' + l.keyBack + ', ' + l.valueBack);
        check(l.keyColor === 'rgba(' + text + ', 0.75)', what + ': keys ' + l.keyColor);
        check(l.valueColor === 'rgb(' + text + ')', what + ': values ' + l.valueColor);
        const bg = 'rgb(' + back + ')';
        check(contrast(l.valueColor, bg) >= 4.5 && contrast(l.keyColor, bg) >= 4.5,
            what + ': contrast ' + contrast(l.valueColor, bg).toFixed(2) + ', keys ' + contrast(l.keyColor, bg).toFixed(2));
        check(l.left.length === 0, what + ': theme left on the closed tooltip: ' + l.left);
    }
    // Switch the page and re-embed what follows it.
    async function setPage(ids, change) {
        const before = {};
        ids.forEach(id => { before[id] = AoV.views[id]; });
        change(document.documentElement);
        // Under virtual time CSS transitions never advance (testing notes).
        document.getAnimations().forEach(a => a.finish());
        AoV.refreshTheme();
        for (const id of ids) await ready(id, before[id]);
        await sleep(50);
    }
    const page = () => opaque(getComputedStyle(document.documentElement).backgroundColor);
    const textOf = id => opaque(getComputedStyle(document.getElementById(id)).color);

    async function picoPage() {
        const followers = ['tt-host', 'tt-title', 'tt-hero', 'tt-translucent', 'tt-shade'];
        for (const id of [...followers, 'tt-card', 'tt-none']) await ready(id);
        const cardView = AoV.views['tt-card'];
        const cell = document.querySelector('.aov-cell');
        const cellView = async previous => {
            for (let i = 0; i < 500; i++) {
                const c = AoV._cellViews && AoV._cellViews.get(cell);
                if (c && c.view !== previous && cell.querySelectorAll('svg path').length) return c.view;
                await sleep(10);
            }
            throw new Error('the cell chart was not drawn');
        };

        for (const theme of ['light', 'dark']) {
            const previousCell = theme === 'light' ? null : AoV._cellViews.get(cell).view;
            await setPage(theme === 'light' ? [] : followers, html => html.setAttribute('data-theme', theme));
            check((lum(channels('rgb(' + page() + ')')) < 0.05) === (theme === 'dark'), theme + ': the page is ' + page());
            const text = textOf('tt-host');
            surface(look(AoV.views['tt-host']), page(), text, theme + ' page');

            // The second plot of a look shares its theme, and a tooltip's
            // heading (Pico colours every h2) takes the surface's text colour.
            const titled = look(AoV.views['tt-title']);
            surface(titled, page(), text, theme + ' titled');
            check(titled.classes === look(AoV.views['tt-host']).classes, theme + ': one look, two themes');
            check(titled.heading === 'rgb(' + text + ')', theme + ': heading ' + titled.heading);

            // Each plot's own surroundings, whatever the page: the shared
            // element changes look between plots.
            surface(look(AoV.views['tt-card']), '250, 240, 220', '60, 40, 20', theme + ' card');
            check(look(AoV.views['tt-card']).classes !== titled.classes, theme + ': card and page share a look');
            // A card with colours of its own does not follow the page's switch.
            check(AoV.views['tt-card'] === cardView, theme + ': the card re-embedded');

            // A background image: the colour found behind the plot is the
            // page's, not what the text is read on.
            surface(look(AoV.views['tt-hero']), theme === 'light' ? '32, 32, 32' : page(), '240, 240, 240', theme + ' gradient');
            // A translucent card: its colour is not what lies behind the plot.
            surface(look(AoV.views['tt-translucent']), theme === 'light' ? '255, 255, 255' : '32, 32, 32', text, theme + ' translucent white');
            surface(look(AoV.views['tt-shade']), theme === 'light' ? '255, 255, 255' : '0, 0, 0', text, theme + ' translucent black');

            // A cell chart takes its look from its own cell.
            const drawn = await cellView(previousCell);
            surface(look(drawn), page(), text, theme + ' cell chart');

            // theme=:none keeps vega-tooltip's light look, whose cells must
            // not stay dark or take the page's text colour.
            const none = look(AoV.views['tt-none']);
            check(none.classes.split(' ').includes('light-theme'), theme + ' none: ' + none.classes);
            check(none.surface === 'rgba(255, 255, 255, 0.95)' && none.color === 'rgb(0, 0, 0)', theme + ' none: ' + none.surface + ' ' + none.color);
            check(none.keyBack === 'rgba(0, 0, 0, 0)' && none.valueBack === 'rgba(0, 0, 0, 0)', theme + ' none: cells ' + none.valueBack);
            check(none.keyColor === 'rgb(128, 128, 128)' && none.valueColor === 'rgb(0, 0, 0)', theme + ' none: ' + none.keyColor + ' ' + none.valueColor);
        }
    }

    async function plainPage() {
        const ids = ['tt-host'];
        await ready('tt-host');
        surface(look(AoV.views['tt-host']), '250, 250, 250', '30, 40, 50', 'light');
        await setPage(ids, html => html.setAttribute('data-theme', 'dark'));
        surface(look(AoV.views['tt-host']), '20, 24, 31', '200, 210, 220', 'dark');
        await setPage(ids, html => html.removeAttribute('data-theme'));
        surface(look(AoV.views['tt-host']), '250, 250, 250', '30, 40, 50', 'light again');
        // The background alone changes: the tooltip follows.
        await setPage(ids, html => html.setAttribute('data-paper', ''));
        surface(look(AoV.views['tt-host']), '250, 240, 220', '30, 40, 50', 'background only');
        // Nothing changes: nothing re-embeds, and no look is added.
        const view = AoV.views['tt-host'], looks = Object.keys(AoV._tipThemes).length;
        AoV.refreshTheme();
        await sleep(100);
        check(AoV.views['tt-host'] === view, 'an unchanged page re-embedded the plot');
        check(Object.keys(AoV._tipThemes).length === looks, 'an unchanged page added a tooltip look');
        // An embed's own tooltip options are its own.
        await ready('tt-opts');
        const own = look(AoV.views['tt-opts']);
        check(own.classes.split(' ').includes('dark-theme') && own.surface === 'rgba(32, 32, 32, 0.9)',
            'embed options: ' + own.classes + ' ' + own.surface);
        check(AoV._tooltipTheme(null) === AoV._tooltipTheme(null), 'no element: no stable look');
    }

    // A page with no colours keeps vega-tooltip's light look: #d9d9d9 is black
    // at .15 on white.
    async function barePage() {
        await ready('tt-host');
        const l = look(AoV.views['tt-host']);
        surface(l, '255, 255, 255', '0, 0, 0', 'bare');
        const b = channels(l.border), on = 255 * (1 - b[3]) + b[0] * b[3];
        check(Math.round(on) === 0xd9, 'bare: the border reads ' + on + ' on white, not #d9d9d9');
    }

    // A dark colour-scheme page paints no background of its own: there is no
    // colour to find, and white text on the white fallback cannot be read.
    async function schemePage() {
        await ready('tt-host');
        surface(look(AoV.views['tt-host']), '32, 32, 32', '255, 255, 255', 'dark color-scheme');
    }

    // A page's own tooltip rules win, whatever its stylesheet's place in the head.
    async function ownPage() {
        await ready('tt-host');
        const l = look(AoV.views['tt-host']);
        check(l.surface === 'rgb(1, 2, 3)', 'own rule: surface ' + l.surface);
        check(l.color === 'rgb(240, 240, 240)', 'own rule: text ' + l.color);
    }

    try {
        await ({pico: picoPage, plain: plainPage, bare: barePage, scheme: schemePage, own: ownPage})[window.AOV_TOOLTIP_PAGE]();
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-tooltip-theme-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
