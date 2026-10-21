// The frame player's controls, light and dark, idle and focused: never a host
// theme's primary colour (Pico 2 fills every button, its focus ring and a
// focused range thumb with azure) or the browser's accent blue (a bare range
// input). The play button is a text-colour outline, unless the page styles
// its buttons itself (`window.AOV_BUTTON_THEME` = the theme's colours): then
// it looks like the page's other buttons.
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
    // A visible, saturated blue: hue 190–250°, saturation > 0.45, value > 0.3.
    const blue = c => {
        const [r, g, b, a] = rgba(c), mx = Math.max(r, g, b), d = mx - Math.min(r, g, b);
        if (a < 13 || mx < 77 || d / mx < 0.45 || mx !== b) return false;
        const hue = 60 * (4 + (r - g) / d);
        return hue >= 190 && hue <= 250;
    };
    const colours = s => s.match(/(rgba?|color)\([^)]*\)|#[0-9a-f]{3,8}\b/gi) || [];
    // The colour a custom property paints with on `el` (Pico's thumb rule
    // reads `--pico-range-thumb-color` there); '' when the page sets none.
    const varColour = (el, name) => {
        const v = getComputedStyle(el).getPropertyValue(name).trim();
        return !v ? '' : /^currentcolor$/i.test(v) ? getComputedStyle(el).color : v;
    };
    const same = (a, b) => rgba(a).join() === rgba(b).join();
    // Resting colours: Pico transitions a control's colour, and under a virtual
    // time budget a running CSS transition never advances, so finish it.
    const settle = async () => { await pause(300); document.getAnimations().forEach(a => a.finish()); };
    try {
        let box = null;
        for (let i = 0; i < 500 && !(box = document.querySelector('[data-aov-frame-for="fr-neutral"]')); i++) await pause();
        if (!box) throw new Error('fr-neutral: no frame controls');
        for (const mode of ['light', 'dark']) {
            if (mode === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
            await settle();
            const play = box.querySelector('.aov-frame-play'), slider = box.querySelector('.aov-frame-slider');
            const text = getComputedStyle(box).color;
            const look = () => {
                const b = getComputedStyle(play);
                return [b.backgroundColor, b.borderTopColor, b.color, ...colours(b.boxShadow)];
            };
            const p = getComputedStyle(play), theme = window.AOV_BUTTON_THEME;
            check(same(p.color, theme ? theme.color : text), mode + ': play glyph ' + p.color + ', text ' + text);
            check(theme ? same(p.backgroundColor, theme.background) : rgba(p.backgroundColor)[3] === 0,
                mode + ': play background ' + p.backgroundColor);
            check(!look().some(blue), mode + ': blue on the idle play button: ' + look().join(' | '));
            check(same(getComputedStyle(slider).accentColor, text),
                mode + ': slider accent ' + getComputedStyle(slider).accentColor + ', text ' + text);
            const idle = varColour(slider, '--pico-range-thumb-color');
            check(!idle || !blue(idle), mode + ': idle thumb ' + idle);
            play.focus();
            await settle();
            check(document.activeElement === play && !look().some(blue),
                mode + ': blue on the focused play button: ' + look().join(' | '));
            slider.focus();
            await settle();
            const thumb = varColour(slider, '--pico-range-thumb-color');
            check(document.activeElement === slider && (thumb && idle ? same(thumb, idle) : thumb === idle),
                mode + ': focused thumb ' + thumb + ', idle ' + idle);
            slider.blur();
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-frame-neutral-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
