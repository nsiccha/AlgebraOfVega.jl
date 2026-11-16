// A data preview of more than 1,000 rows shows a page of them, with a pager
// above and below its frame. Every row is a page away, a click on a heading
// sorts all rows in the order HTMXObjects' `sortTable` gives a whole table,
// and ⬇ CSV still gives every row. A table of 1,000 rows is built whole, as
// before.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const same = (got, want, message) => check(JSON.stringify(got) === JSON.stringify(want),
        message + ': ' + JSON.stringify(got).slice(0, 300) + ', not ' + JSON.stringify(want).slice(0, 300));
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    const el = id => document.getElementById(id);
    const previewOf = id => el(id).closest('figure').querySelector('details.aov-data-preview');
    const open = async id => {
        const details = previewOf(id);
        details.open = true;
        for (let i = 0; i < 200 && !details.querySelector('.aov-table-frame'); i++) await pause(10);
        return details.querySelector('.aov-data-raw-body');
    };
    // A row as the text of its cells, and the rows a table shows.
    const rowText = tr => [...tr.cells].map(td => td.textContent).join('|');
    const shown = root => [...root.querySelectorAll('tbody > tr')].map(rowText);
    const pagers = root => [...root.querySelectorAll('.aov-table-pager')];
    const range = nav => nav.querySelector('.aov-table-pager-range').textContent;
    const buttonOf = (nav, key) => nav.querySelector('button[data-aov-page="' + key + '"]');
    const current = nav => nav.querySelector('button[aria-current="page"]');
    // Every row of a paged table, page by page, through its top pager.
    const allPages = root => {
        const nav = pagers(root)[0], out = [];
        buttonOf(nav, '0').click();
        for (;;) {
            out.push(...shown(root));
            const next = buttonOf(pagers(root)[0], 'next');
            if (next.disabled) break;
            next.click();
        }
        buttonOf(pagers(root)[0], '0').click();
        return out;
    };
    // What HTMXObjects' `sortTable` makes of the same rows as one whole table.
    const wholeSorted = (rows, cols, col, clicks) => {
        const table = document.createElement('table');
        table.append(AoV._tableHead(cols, (i, th) => window.sortTable(i, th)), AoV._tableBody(rows, cols));
        table.style.display = 'none';
        document.body.append(table);
        const th = table.querySelectorAll('th')[col];
        for (let k = 0; k < clicks; k++) th.click();
        const out = shown(table);
        table.remove();
        return out;
    };
    const csvOf = id => {
        const got = [], real = AoV._triggerDownload;
        AoV._triggerDownload = (text, filename) => got.push({filename, lines: text.split('\n')});
        try { AoV.downloadPlotData(id); } finally { AoV._triggerDownload = real; }
        return got;
    };

    try {
        for (const id of ['dp-whole', 'dp-pages', 'dp-de', 'dp-nocsv', 'dp-app']) await ready(id);
        check(typeof window.sortTable === 'function', 'HTMXObjects sortTable is not on the page');

        // 1,000 rows: built whole, sorted by HTMXObjects, no pager.
        const whole = await open('dp-whole');
        check(shown(whole).length === 1000, 'the 1,000-row table shows ' + shown(whole).length + ' rows');
        check(!whole.querySelector('.aov-table-pages, .aov-table-pager, .aov-table-pages-note'), 'a 1,000-row table has a pager');
        const wholeFrame = whole.querySelector('.aov-table-frame');
        check(wholeFrame && wholeFrame.parentElement === whole, 'the 1,000-row table\'s frame is not directly in the raw body');
        const real = window.sortTable;
        let calls = 0;
        window.sortTable = function () { calls++; return real.apply(this, arguments); };
        try {
            [...whole.querySelectorAll('th')].find(th => th.textContent === 'score').click();
        } finally { window.sortTable = real; }
        check(calls === 1, 'a heading of the 1,000-row table called sortTable ' + calls + ' times');

        // 2,500 rows: three pages.
        const groups = AoV._plotGroups('dp-pages');
        check(groups.length === 1, 'the fixture has ' + groups.length + ' datasets');
        const rows = groups[0].rows;
        check(rows.length === 2500, 'the fixture dataset has ' + rows.length + ' rows');
        const body = await open('dp-pages');
        const pages = body.querySelector('.aov-table-pages');
        check(!!pages, 'the 2,500-row table has no pages');
        const kids = [...pages.children].map(c => c.tagName.toLowerCase() + '.' + c.className);
        same(kids, ['nav.aov-table-pager', 'div.aov-table-frame', 'p.aov-table-pages-note', 'nav.aov-table-pager'],
            'the paged table\'s parts');
        const frame = pages.querySelector('.aov-table-frame'), table = frame.querySelector('table');
        const cols = [...table.querySelectorAll('th')].map(th => th.textContent);
        same(cols, ['code', 'label', 'note', 'score', 'x', 'y'], 'the columns');
        const expected = rows.map(r => cols.map(c => r[c] === null || r[c] === undefined ? '' : String(r[c])).join('|'));
        check(table.className === 'striped' && table.getAttribute('role') === 'grid', 'the paged table\'s class/role');
        same(shown(body), expected.slice(0, 1000), 'page 1 rows');
        const [top, bottom] = pagers(body);
        for (const [nav, name] of [[top, 'top'], [bottom, 'bottom']]) {
            check(range(nav) === 'Rows 1–1,000 of 2,500', name + ' pager reads ' + range(nav));
            check(nav.getAttribute('aria-label') === 'Table pages', name + ' pager is named ' + nav.getAttribute('aria-label'));
            same([...nav.querySelectorAll('button')].map(b => b.textContent), ['‹ Previous', '1', '2', '3', 'Next ›'], name + ' pager buttons');
            check(buttonOf(nav, 'prev').disabled && !buttonOf(nav, 'next').disabled, name + ': previous/next enabled wrongly on page 1');
            check(buttonOf(nav, 'prev').querySelector('span[aria-hidden="true"]').textContent === '‹ ', name + ': the arrow is not hidden');
            same([...nav.querySelectorAll('button[data-aov-page]:not([data-aov-page="prev"]):not([data-aov-page="next"])')]
                .map(b => b.getAttribute('aria-label')), ['Page 1', 'Page 2', 'Page 3'], name + ' page names');
            check(current(nav) && current(nav).textContent === '1', name + ': the current page is not 1');
            check(nav.querySelectorAll('[aria-current]').length === 1, name + ': more than one current page');
            const look = getComputedStyle(nav), b = getComputedStyle(buttonOf(nav, 'next'));
            check(look.display === 'flex' && look.justifyContent === 'flex-start', name + ' pager laid out ' + look.display + ' ' + look.justifyContent);
            check(b.backgroundColor === 'rgba(0, 0, 0, 0)', name + ': Pico fills the pager buttons ' + b.backgroundColor);
        }
        check(top.querySelector('.aov-table-pager-range').getAttribute('aria-live') === 'polite', 'the top range is not live');
        check(!bottom.querySelector('.aov-table-pager-range').hasAttribute('aria-live'), 'the bottom range is live too');
        const fr = frame.getBoundingClientRect();
        check(top.getBoundingClientRect().bottom <= fr.top + 1, 'the top pager is not above the frame');
        check(bottom.getBoundingClientRect().top >= fr.bottom - 1, 'the bottom pager is not below the frame');
        check(pages.querySelector('.aov-table-pages-note').textContent ===
            'A click on a column heading sorts all 2,500 rows. ⬇ CSV holds every row.',
            'the note reads ' + pages.querySelector('.aov-table-pages-note').textContent);
        check(frame.scrollHeight > frame.clientHeight, 'the fixture page does not scroll in its frame');

        // Next from the bottom pager: page 2, the frame back at its top, the
        // focus on the same button.
        frame.scrollTop = 400;
        check(frame.scrollTop > 0, 'the frame did not scroll');
        buttonOf(bottom, 'next').focus();
        buttonOf(bottom, 'next').click();
        const [top2, bottom2] = pagers(body);
        check(range(top2) === 'Rows 1,001–2,000 of 2,500' && range(bottom2) === range(top2), 'page 2 reads ' + range(top2));
        same(shown(body), expected.slice(1000, 2000), 'page 2 rows');
        check(frame.scrollTop === 0, 'the frame stayed at ' + frame.scrollTop);
        check(!buttonOf(top2, 'prev').disabled && current(top2).textContent === '2', 'page 2: previous or current wrong');
        check(document.activeElement === buttonOf(bottom2, 'next'), 'the focus left the bottom Next: ' +
            (document.activeElement && document.activeElement.outerHTML));
        // Next again: the last page, Next disabled, the focus on the current page.
        buttonOf(bottom2, 'next').click();
        const [top3, bottom3] = pagers(body);
        check(range(top3) === 'Rows 2,001–2,500 of 2,500', 'page 3 reads ' + range(top3));
        same(shown(body), expected.slice(2000), 'page 3 rows');
        check(buttonOf(top3, 'next').disabled, 'Next is enabled on the last page');
        check(document.activeElement === current(bottom3), 'the focus is not on the current page: ' +
            (document.activeElement && document.activeElement.outerHTML));
        // Page 1 by its button.
        buttonOf(top3, '0').click();
        check(range(pagers(body)[0]) === 'Rows 1–1,000 of 2,500', 'page 1 button gave ' + range(pagers(body)[0]));
        // Every row, in order, a page away.
        same(allPages(body), expected, 'all pages together');

        // A heading sorts all rows, in HTMXObjects' order, and shows page 1.
        for (const name of ['score', 'label', 'code', 'note']) {
            const col = cols.indexOf(name);
            for (const clicks of [1, 2]) {
                const th = table.querySelectorAll('th')[col];
                buttonOf(pagers(body)[0], '2').click();
                th.click();
                check(range(pagers(body)[0]) === 'Rows 1–1,000 of 2,500', name + ' sort shows ' + range(pagers(body)[0]));
                const dir = clicks === 1 ? 'ascending' : 'descending';
                check(th.getAttribute('aria-sort') === dir, name + ' is ' + th.getAttribute('aria-sort') + ', not ' + dir);
                check(table.querySelectorAll('th[aria-sort]').length === 1, name + ': several headings carry aria-sort');
                same(allPages(body), wholeSorted(rows, cols, col, clicks), name + ' ' + dir + ' against HTMXObjects sortTable');
            }
        }
        const scores = rows.map(r => r.score);
        table.querySelectorAll('th')[cols.indexOf('score')].click();
        check(Number(body.querySelector('tbody > tr').cells[cols.indexOf('score')].textContent) === Math.min(...scores),
            'ascending score does not start at the smallest of all rows');
        table.querySelectorAll('th')[cols.indexOf('score')].click();
        check(Number(body.querySelector('tbody > tr').cells[cols.indexOf('score')].textContent) === Math.max(...scores),
            'descending score does not start at the largest of all rows');
        // Sorting reorders a copy: the plot's rows and the CSV are as they were.
        same(AoV._plotGroups('dp-pages')[0].rows.map(r => cols.map(c => String(r[c])).join('|')).slice(0, 5),
            expected.slice(0, 5), 'the plot\'s rows after sorting');
        const csv = csvOf('dp-pages');
        check(csv.length === 1 && csv[0].lines.length === 2501, 'the CSV gives ' + (csv[0] && csv[0].lines.length) + ' lines');

        // German words and numbers.
        const deBody = await open('dp-de');
        const [deTop] = pagers(deBody);
        check(range(deTop) === 'Zeilen 1–1.000 von 2.500', 'German range reads ' + range(deTop));
        check(deTop.getAttribute('aria-label') === 'Tabellenseiten', 'German pager is named ' + deTop.getAttribute('aria-label'));
        same([...deTop.querySelectorAll('button')].map(b => b.textContent), ['‹ Zurück', '1', '2', '3', 'Weiter ›'], 'German buttons');
        check(buttonOf(deTop, '1').getAttribute('aria-label') === 'Seite 2', 'German page name ' + buttonOf(deTop, '1').getAttribute('aria-label'));
        check(deBody.querySelector('.aov-table-pages-note').textContent ===
            'Ein Klick auf eine Spaltenüberschrift sortiert alle 2.500 Zeilen. ⬇ CSV enthält jede Zeile.',
            'German note reads ' + deBody.querySelector('.aov-table-pages-note').textContent);

        // 1,001 rows and no CSV download: two pages, and the note names no CSV.
        const noCsv = await open('dp-nocsv');
        const [ncTop] = pagers(noCsv);
        same([...ncTop.querySelectorAll('button')].map(b => b.textContent), ['‹ Previous', '1', '2', 'Next ›'], '1,001-row buttons');
        check(noCsv.querySelector('.aov-table-pages-note').textContent === 'A click on a column heading sorts all 1,001 rows.',
            'no-CSV note reads ' + noCsv.querySelector('.aov-table-pages-note').textContent);
        buttonOf(ncTop, 'next').click();
        check(range(pagers(noCsv)[0]) === 'Rows 1,001–1,001 of 1,001' && shown(noCsv).length === 1, 'the last page of 1,001 rows');

        // The public entry point, into a container of the app's.
        const box = el('dp-app-box');
        AoV.showPlotData('dp-app', box, {});
        check(!!box.querySelector('.aov-table-pages .aov-table-frame table'), 'showPlotData in an app container has no pages');
        check(shown(box).length === 1000, 'showPlotData in an app container shows ' + shown(box).length + ' rows');
        check(box.querySelector('.aov-table-pages-note').textContent === 'A click on a column heading sorts all 2,500 rows.',
            'app note reads ' + box.querySelector('.aov-table-pages-note').textContent);
        delete box.dataset.aovRendered;
        AoV.showPlotData('dp-app', box, {});
        check(box.querySelectorAll('.aov-table-pages').length === 1, 'a second render left ' + box.querySelectorAll('.aov-table-pages').length + ' tables');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const result = document.createElement('pre');
    result.id = 'aov-data-pages-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
})();
