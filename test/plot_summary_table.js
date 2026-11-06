// LOCKSTEP: a captioned plot's "Show summary" pane against `plot_summary_table`.
// Each figure's pane is opened and read off the page: a heading, a caption and a
// table make one section. A table without a caption is a source without a summary,
// which the pane lists raw and `plot_summary_table` leaves out.
(async function () {
    const failures = [];
    let figures = 0, numbers = 0, checks = 0;
    const fixture = window.AOV_FIXTURE;
    const pause = () => new Promise(resolve => setTimeout(resolve, 10));
    async function ready(id) {
        for (let i = 0; i < 1000; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await pause();
        }
        throw new Error(id + ': embed did not complete');
    }
    function paneSections(body) {
        const sections = [];
        let label = null, caption = null;
        for (const el of body.children) {
            if (el.tagName === 'H6') {
                label = el.textContent;
            } else if (el.tagName === 'FIGCAPTION') {
                caption = el.textContent;
            } else if (el.classList.contains('aov-table-frame')) {
                const table = el.querySelector('table');
                if (caption !== null) {
                    sections.push({
                        label, caption,
                        columns: Array.from(table.querySelectorAll('thead th'), th => th.textContent),
                        rows: Array.from(table.querySelectorAll('tbody tr'),
                            tr => Array.from(tr.children, td => td.textContent)),
                    });
                }
                label = null; caption = null;
            }
        }
        return sections;
    }

    const canonical = sections => JSON.stringify(sections.map(s => [s.label, s.caption, s.columns, s.rows]));

    for (const id of Object.keys(fixture.expected)) {
        try {
            await ready(id);
            const figure = document.getElementById(id).closest('figure');
            const details = figure.querySelector('details.aov-data-preview');
            AoV._lazyRenderDataView(details, 'pretty');
            const got = paneSections(details.querySelector('.aov-data-pretty-body'));
            figures++;
            const gotText = canonical(got), wantText = canonical(fixture.expected[id]);
            if (gotText !== wantText) failures.push(id + ': pane ' + gotText + ' but plot_summary_table ' + wantText);
        } catch (e) {
            failures.push(id + ': ' + String(e && e.stack || e));
        }
    }
    try {
        // A sparse grid's pad rows hold its cells in the view, and reach no reader.
        const isPad = r => r.__aov_pad === true;
        checks++;
        if (!AoV.views.sparse.data('source_0').some(isPad)) failures.push('sparse: the fixture has no pad rows');
        checks++;
        if (AoV._plotData('sparse').some(isPad)) failures.push('sparse: _plotData lists pad rows');
        for (const [x, p, rounded, plain] of fixture.numbers) {
            numbers++;
            const gotRounded = parseFloat(x.toPrecision(p)).toString();
            if (gotRounded !== rounded) failures.push(x + ' at ' + p + ' digits: ' + gotRounded + ' but ' + rounded);
            if (String(x) !== plain) failures.push(x + ': ' + String(x) + ' but ' + plain);
        }
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const result = document.createElement('pre');
    result.id = 'aov-summary-results';
    result.textContent = JSON.stringify({figures, numbers, checks, failures});
    document.body.append(result);
})();
