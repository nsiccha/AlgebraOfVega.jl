// Plot texts in the browser: a German and an English captioned plot on one
// page. The runtime writes each card's summary caption, empty-preview texts
// and HTML download in that card's language.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    const expected = window.AOV_FIXTURE.expected;
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }

    try {
        for (const id of Object.keys(expected)) {
            const want = expected[id];
            await ready(id);
            const figure = document.getElementById(id).closest('figure');
            const details = figure.querySelector('details.aov-data-preview');
            AoV._lazyRenderDataView(details, 'pretty');
            const caption = details.querySelector('.aov-data-pretty-body figcaption');
            check(caption && caption.textContent === want.caption,
                id + ': summary caption ' + JSON.stringify(caption && caption.textContent));

            const raw = document.createElement('div');
            figure.append(raw);
            AoV.showPlotData('no-such-plot', raw, {});
            check(raw.textContent === want.no_data, id + ': raw preview ' + JSON.stringify(raw.textContent));
            const summary = document.createElement('div');
            figure.append(summary);
            AoV.renderPrettySummary('no-such-plot', summary, {});
            check(summary.textContent === want.no_summary,
                id + ': summary preview ' + JSON.stringify(summary.textContent));
            raw.remove();
            summary.remove();

            let saved = null;
            const trigger = AoV._triggerDownload;
            AoV._triggerDownload = function (text, filename, mime) { saved = {text, filename, mime}; };
            try {
                await AoV.downloadPlotHtml(id, 'saved-' + id);
            } finally {
                AoV._triggerDownload = trigger;
            }
            check(saved !== null, id + ': no HTML download');
            const head = saved ? saved.text.slice(0, 200) : '';
            check(head.indexOf('<html lang="' + want.lang + '">') !== -1, id + ': download head ' + JSON.stringify(head));
            check(saved !== null && saved.text.indexOf('data-aov-texts="') !== -1 === (want.lang !== 'en'),
                id + ': download carries the texts attribute only when not English');
        }
        // An element outside every captioned figure reads the English set.
        check(AoV._texts(document.body)('untitled') === 'AoV plot', 'untitled outside a figure');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const result = document.createElement('pre');
    result.id = 'aov-texts-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
})();
