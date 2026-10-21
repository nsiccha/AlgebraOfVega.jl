// A standalone `to_html(spec, caption; source=:inline)` page of a framed map
// plays with no server: the runtime builds the controls, the colour scale is
// shared by every frame, and play steps to the last frame.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    try {
        let view = null;
        for (let i = 0; i < 500 && !(view = AoV.views['fr-export']); i++) await pause();
        if (!view) throw new Error('fr-export: no view');
        const box = document.querySelector('[data-aov-frame-for="fr-export"]');
        check(!!box, 'export: controls');
        check(JSON.stringify(view.scale('color').domain()) === '[-2,3]',
            'export: colour domain ' + JSON.stringify(view.scale('color').domain()));
        box.querySelector('.aov-frame-play').click();
        for (let i = 0; i < 500 && AoV._frames['fr-export'].playing; i++) await pause();
        check(view.signal('aov_frame') === 2002 && box.querySelector('.aov-frame-value').textContent === '2002',
            'export after play: ' + view.signal('aov_frame'));
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-frame-export-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
