// The Ribbons | Intervals switch keeps WCAG AA text contrast (4.5:1: its
// 0.85em text is not large) on both buttons, at rest and focused, light and
// dark, in a captioned figure and after a plain plot. The pressed button stays
// told apart from the other by its tint and weight. `window.AOV_CONTRAST_PAGE`
// names the page's theme for the messages.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms || 10));
    // Any CSS colour as [r, g, b, a] (0–255), painted by the browser itself.
    const ctx = Object.assign(document.createElement('canvas'), {width: 1, height: 1}).getContext('2d');
    const rgba = c => {
        ctx.clearRect(0, 0, 1, 1);
        ctx.fillStyle = 'rgba(0, 0, 0, 0)';
        ctx.fillStyle = c;
        ctx.fillRect(0, 0, 1, 1);
        return Array.from(ctx.getImageData(0, 0, 1, 1).data);
    };
    const over = ([r, g, b, a], under) => [r, g, b].map((v, i) => v * a / 255 + under[i] * (1 - a / 255));
    // What a reader sees behind an element's text: its own and its ancestors'
    // backgrounds, composited down to the first opaque one (the canvas is white).
    const backdrop = el => {
        const layers = [];
        for (let e = el; e; e = e.parentElement) {
            const c = rgba(getComputedStyle(e).backgroundColor);
            if (c[3] > 0) layers.push(c);
            if (c[3] === 255) break;
        }
        return layers.reverse().reduce((under, c) => over(c, under), [255, 255, 255]);
    };
    // WCAG 2 relative luminance and contrast ratio.
    const lum = rgb => rgb.map(v => (v /= 255) <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
        .reduce((s, v, i) => s + v * [0.2126, 0.7152, 0.0722][i], 0);
    const ratio = (a, b) => { const [hi, lo] = [lum(a), lum(b)].sort((p, q) => q - p); return (hi + 0.05) / (lo + 0.05); };
    const hex = rgb => '#' + rgb.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
    // Resting colours: Pico transitions a control's colour, and under a virtual
    // time budget a running CSS transition never advances, so finish it.
    const settle = async () => { await pause(300); document.getAnimations().forEach(a => a.finish()); };
    const page = window.AOV_CONTRAST_PAGE;
    const switches = id => [...document.querySelectorAll('[data-aov-ribbon-view-for="' + id + '"]')];
    const look = b => {
        const bg = backdrop(b);
        const fg = over(rgba(getComputedStyle(b).color), bg);
        return {bg, fg, ratio: ratio(fg, bg)};
    };
    try {
        for (const id of ['rc-cap', 'rc-plain']) {
            for (let i = 0; i < 500 && switches(id).length < 2; i++) await pause();
            if (switches(id).length !== 2) throw new Error(page + ' ' + id + ': no Ribbons | Intervals switch');
        }
        for (const mode of ['light', 'dark']) {
            if (mode === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
            await settle();
            for (const id of ['rc-cap', 'rc-plain']) {
                const where = page + ' ' + mode + ' ' + id;
                const bs = switches(id);
                const on = bs.find(b => b.getAttribute('aria-pressed') === 'true');
                const off = bs.find(b => b.getAttribute('aria-pressed') === 'false');
                if (!on || !off) throw new Error(where + ': no pressed and unpressed button');
                for (const b of [on, off]) {
                    const what = where + ' ' + b.dataset.view + (b === on ? ' (pressed)' : '');
                    let l = look(b);
                    check(l.ratio >= 4.5, what + ': ' + hex(l.fg) + ' on ' + hex(l.bg) + ' = ' + l.ratio.toFixed(2) + ':1');
                    b.focus();
                    await settle();
                    l = look(b);
                    check(document.activeElement === b && l.ratio >= 4.5,
                        what + ' focused: ' + hex(l.fg) + ' on ' + hex(l.bg) + ' = ' + l.ratio.toFixed(2) + ':1');
                    b.blur();
                    await settle();
                }
                check(ratio(look(on).bg, look(off).bg) > 1.1 && Number(getComputedStyle(on).fontWeight) >= 600,
                    where + ': the pressed button is not told apart: ' + hex(look(on).bg) + ' vs ' + hex(look(off).bg) +
                    ', weight ' + getComputedStyle(on).fontWeight);
            }
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-ribbon-contrast-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
