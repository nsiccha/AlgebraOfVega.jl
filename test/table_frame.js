// A data table scrolls in a frame of its own, on a Pico page: the page keeps its
// width, what sits beside the figure stays in place, and the frame is a named tab
// stop for as long as it scrolls. Headless virtual time delivers ResizeObserver
// notifications after load unreliably (fit_width.js), so the driver calls
// `AoV._syncTableFrame` the way the observer does.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    const IDS = ['tf-raw', 'tf-de', 'tf-in-grid', 'tf-in-flex', 'tf-fits', 'tf-both', 'tf-two', 'tf-own', 'tf-own-raw', 'tf-app'];
    const el = id => document.getElementById(id);
    const previewOf = id => el(id).closest('figure').querySelector('details.aov-data-preview');
    const open = async id => {
        const details = previewOf(id);
        details.open = true;
        for (let i = 0; i < 200 && !details.querySelector('.aov-table-frame'); i++) await pause(10);
        return details;
    };
    const close = async id => { previewOf(id).open = false; await pause(20); };
    const frameIn = root => root.querySelector('.aov-table-frame');
    const left = e => e.getBoundingClientRect().left;
    const width = e => e.getBoundingClientRect().width;
    const near = (a, b) => Math.abs(a - b) <= 1;
    const pageKeepsWidth = when => {
        const root = document.documentElement;
        check(root.scrollWidth <= root.clientWidth, 'the page is ' + root.scrollWidth + ' wide in a ' + root.clientWidth + ' window ' + when);
    };
    const expectStop = (frame, name, when) => {
        check(frame.getAttribute('tabindex') === '0', 'no tab stop ' + when);
        check(frame.getAttribute('role') === 'figure', 'role ' + frame.getAttribute('role') + ' ' + when);
        check(frame.getAttribute('aria-label') === name, 'named ' + frame.getAttribute('aria-label') + ' ' + when);
    };
    const expectNoStop = (frame, when) => {
        ['tabindex', 'role', 'aria-label'].forEach(attr => check(!frame.hasAttribute(attr), 'keeps ' + attr + ' ' + when));
    };

    try {
        for (const id of IDS) await ready(id);
        pageKeepsWidth('with every preview closed');
        check(!document.querySelector('.aov-table-frame'), 'a frame exists before a preview opened');

        // The report: a narrow pane in block flow. Open, the table scrolls in its
        // frame, as wide as the pane; the page does not move.
        const pane = el('tf-pane');
        const paneWidth = width(pane);
        const raw = await open('tf-raw');
        const frame = frameIn(raw), table = frame.querySelector('table');
        pageKeepsWidth('with the raw table open in a narrow pane');
        check(width(pane) === paneWidth, 'the pane went from ' + paneWidth + ' to ' + width(pane));
        check(width(frame) <= paneWidth, 'the frame is ' + width(frame) + ' wide in a ' + paneWidth + ' pane');
        check(width(frame) > paneWidth / 2, 'the frame collapsed to ' + width(frame));
        check(width(table) > 2 * paneWidth, 'the fixture table is only ' + width(table) + ' wide');
        check(frame.scrollWidth > frame.clientWidth, 'the frame does not scroll sideways');
        check(frame.parentElement.classList.contains('aov-data-raw-body'), 'the frame is not in the raw body');
        expectStop(frame, 'Scrollable table: Messwerte', 'on a wide table');
        // It scrolls for real, and the page stays put.
        frame.scrollLeft = 300;
        check(frame.scrollLeft === 300, 'the frame scrolled to ' + frame.scrollLeft);
        check(window.scrollX === 0, 'the page scrolled to ' + window.scrollX);
        frame.scrollLeft = 0;
        // A long table keeps its horizontal scrollbar in reach.
        check(table.getBoundingClientRect().height > innerHeight, 'the fixture table is only ' +
            table.getBoundingClientRect().height + ' tall');
        check(frame.clientHeight <= 0.7 * innerHeight + 1, 'the frame is ' + frame.clientHeight + ' tall in a ' + innerHeight + ' window');
        check(frame.scrollHeight > frame.clientHeight, 'the frame does not scroll down');

        // The tab stop's role leaves the frame's layout alone under Pico.
        const control = document.createElement('div');
        control.setAttribute('role', 'group');
        document.body.append(control);
        check(getComputedStyle(control).display === 'inline-flex', 'Pico is not on the page');
        control.remove();
        check(getComputedStyle(frame).display === 'block', 'the frame displays as ' + getComputedStyle(frame).display);
        check(getComputedStyle(frame).marginBottom === '0px', 'the frame has a bottom margin of ' + getComputedStyle(frame).marginBottom);

        // The container decides: wide enough and short enough, the stop goes.
        const save = {pane: pane.style.width, height: frame.style.maxHeight};
        pane.style.width = (width(table) + 40) + 'px';
        frame.style.maxHeight = 'none';
        AoV._syncTableFrame(frame);
        expectNoStop(frame, 'with room for the table');
        pane.style.width = save.pane;
        frame.style.maxHeight = save.height;
        AoV._syncTableFrame(frame);
        expectStop(frame, 'Scrollable table: Messwerte', 'in a narrow pane again');
        // A hidden frame scrolls nothing.
        frame.style.display = 'none';
        AoV._syncTableFrame(frame);
        expectNoStop(frame, 'while hidden');
        frame.style.display = '';
        AoV._syncTableFrame(frame);
        expectStop(frame, 'Scrollable table: Messwerte', 'shown again');

        // Opening again keeps the one frame.
        await close('tf-raw');
        await open('tf-raw');
        AoV._frameTables(raw);
        check(raw.querySelectorAll('.aov-table-frame').length === 1, 'reopened, the preview has ' + raw.querySelectorAll('.aov-table-frame').length + ' frames');
        check(raw.querySelector('.aov-table-frame .aov-table-frame') === null, 'frames are nested');
        // A data change renders the table anew, in one frame.
        AoV._dataChanged('tf-raw');
        await pause(50);
        check(raw.querySelectorAll('.aov-table-frame').length === 1, 'after a data change the preview has ' + raw.querySelectorAll('.aov-table-frame').length + ' frames');
        expectStop(frameIn(raw), 'Scrollable table: Messwerte', 'after a data change');
        await close('tf-raw');

        // The name is in the card's words.
        const german = await open('tf-de');
        expectStop(frameIn(german), 'Scrollbare Tabelle: Felder', 'on a German card');
        await close('tf-de');

        // Columns that take a minimum width from their content: the frame keeps the
        // table out of that minimum, so the neighbour stays where it was. The control
        // takes the containment off, which is what the column grew from.
        for (const [id, rightId] of [['tf-in-grid', 'tf-grid-right'], ['tf-in-flex', 'tf-flex-right']]) {
            const right = el(rightId);
            const x = left(right);
            const details = await open(id);
            const f = frameIn(details);
            pageKeepsWidth('with a table open in ' + id);
            check(near(left(right), x), id + ': the column beside it moved from ' + x + ' to ' + left(right));
            check(f.scrollWidth > f.clientWidth, id + ': the frame does not scroll sideways');
            f.style.contain = 'none';
            check(left(right) > x + 100, id + ': without the containment the column beside it stays at ' + left(right));
            f.style.contain = '';
            check(near(left(right), x), id + ': the column beside it did not come back from ' + left(right));
            await close(id);
            check(near(left(right), x), id + ': closed, the column beside it is at ' + left(right));
        }

        // Room for the table: no sideways scrolling and no tab stop.
        const fits = await open('tf-fits');
        const fitFrame = frameIn(fits);
        check(fitFrame.scrollWidth <= fitFrame.clientWidth, 'the short table scrolls sideways');
        check(fitFrame.scrollHeight <= fitFrame.clientHeight, 'the short table scrolls down');
        check(near(width(fitFrame.querySelector('table')), width(fitFrame)), 'the short table does not fill its frame');
        expectNoStop(fitFrame, 'on a table that fits');
        await close('tf-fits');

        // Summary and raw rows: both panes have frames, and the hidden one is no stop.
        const both = await open('tf-both');
        const prettyBody = both.querySelector('.aov-data-pretty-body');
        const prettyFrame = frameIn(prettyBody);
        check(!!prettyFrame, 'the summary table has no frame');
        check(prettyBody.querySelector('figcaption').parentElement === prettyBody, 'the summary caption moved into the frame');
        pageKeepsWidth('with the summary open in a narrow pane');
        check(width(prettyFrame) <= width(el('tf-both-pane')), 'the summary frame is ' + width(prettyFrame) + ' wide');
        expectStop(prettyFrame, 'Scrollable table: Summary', 'on a wide summary');
        AoV.toggleDataView(both.querySelector('button[data-view="raw"]'), 'raw');
        const rawFrame = frameIn(both.querySelector('.aov-data-raw-body'));
        check(!!rawFrame, 'the raw table has no frame after the toggle');
        pageKeepsWidth('with the raw rows toggled on');
        expectStop(rawFrame, 'Scrollable table: Summary', 'on the raw rows after the toggle');
        AoV._syncTableFrame(prettyFrame);
        expectNoStop(prettyFrame, 'on the summary hidden by the toggle');
        AoV.toggleDataView(both.querySelector('button[data-view="pretty"]'), 'pretty');
        AoV._syncTableFrame(prettyFrame);
        expectStop(prettyFrame, 'Scrollable table: Summary', 'on the summary toggled back');
        await close('tf-both');

        // Two sources: each table in a frame of its own, its heading outside, in view.
        const two = await open('tf-two');
        const twoBody = two.querySelector('.aov-data-raw-body');
        const frames = twoBody.querySelectorAll(':scope > .aov-table-frame');
        const headings = twoBody.querySelectorAll(':scope > h6');
        check(frames.length === 2, 'two sources gave ' + frames.length + ' frames');
        check(headings.length === 2, 'two sources gave ' + headings.length + ' headings outside the frames');
        check(frames[0].previousElementSibling === headings[0], 'the first heading is not right above its frame');
        check(frames[0].querySelectorAll('table').length === 1 && frames[1].querySelectorAll('table').length === 1, 'a frame does not hold exactly one table');
        check(frames[0].scrollWidth > frames[0].clientWidth, 'the wide source does not scroll');
        check(frames[1].scrollWidth <= frames[1].clientWidth, 'the narrow source scrolls');
        pageKeepsWidth('with two tables open');
        await close('tf-two');

        // A table the caller wrote gets the same frame, with and without the raw rows.
        for (const [id, title] of [['tf-own', 'Own'], ['tf-own-raw', 'Own and raw']]) {
            const details = await open(id);
            const f = frameIn(details);
            check(!!f, id + ': the caller\'s table has no frame');
            check(f.querySelector('td').textContent.startsWith('a_long_cell'), id + ': the frame does not hold the caller\'s table');
            pageKeepsWidth('with the table of ' + id + ' open');
            check(f.scrollWidth > f.clientWidth, id + ': the caller\'s table does not scroll');
            expectStop(f, 'Scrollable table: ' + title, 'on the table of ' + id);
            await close(id);
        }

        // The public entry point, into a container of the app's, outside any figure.
        const box = el('tf-app-box');
        AoV.showPlotData('tf-app', box, {});
        const appFrame = frameIn(box);
        check(!!appFrame, 'showPlotData left its table without a frame');
        pageKeepsWidth('with showPlotData in an app container');
        expectStop(appFrame, 'Scrollable table', 'outside a captioned figure');
        check(width(appFrame) <= width(box.parentElement), 'the app container\'s frame is ' + width(appFrame) + ' wide');
        // The frame goes with the container, as the render does each time.
        delete box.dataset.aovRendered;
        AoV.showPlotData('tf-app', box, {});
        check(box.querySelectorAll('.aov-table-frame').length === 1, 'a second render left ' + box.querySelectorAll('.aov-table-frame').length + ' frames');
        pageKeepsWidth('with everything rendered');
    } catch (e) {
        failures.push(String(e && e.stack || e));
    }
    const result = document.createElement('pre');
    result.id = 'aov-table-frame-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
})();
