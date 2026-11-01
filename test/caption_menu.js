// A captioned plot's download menu in the browser, on a Pico page. The browser
// opens and closes the popover; the runtime keeps it at its button.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    const near = (a, b) => Math.abs(a - b) <= 1;
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    const menuOf = id => document.getElementById(id + '-download-menu');
    const toggleOf = id => document.querySelector('[popovertarget="' + id + '-download-menu"]:not([popovertargetaction])');
    const isOpen = menu => menu.matches(':popover-open');
    const open = async id => {
        if (!isOpen(menuOf(id))) toggleOf(id).click();
        await sleep(20);
        return menuOf(id);
    };
    const close = async id => { if (isOpen(menuOf(id))) menuOf(id).hidePopover(); await sleep(20); };
    const AZURE = 'rgb(1, 114, 173)';

    try {
        for (const id of ['cm-room', 'cm-clip', 'cm-left', 'cm-plain']) await ready(id);

        // Closed: one compact button in the row, and the title has the room.
        const room = document.getElementById('cm-room').closest('figure');
        const acts = room.querySelector('.caption-actions');
        const toggle = toggleOf('cm-room'), menu = menuOf('cm-room');
        check(toggle.parentElement === acts, 'the button is a child of the caption row');
        check(toggle.classList.contains('caption-action'), 'the button has the row look');
        check(/^⬇ Export\s*▾$/.test(toggle.textContent.trim()), 'button words: ' + toggle.textContent);
        check(toggle.querySelector('[aria-hidden="true"]').textContent === '▾', 'the caret is hidden from readers');
        check(getComputedStyle(menu).display === 'none', 'the menu starts closed');
        check(acts.getBoundingClientRect().width < 120, 'the row is one button wide: ' + acts.getBoundingClientRect().width);
        const title = room.querySelector('.caption-header').firstElementChild;
        check(title.getBoundingClientRect().width > 500, 'the title has the room: ' + title.getBoundingClientRect().width);
        check(near(title.getBoundingClientRect().top, toggle.getBoundingClientRect().top) ||
              title.getBoundingClientRect().top < toggle.getBoundingClientRect().bottom, 'the button stays beside the title');
        check([...menu.children].every(b => b.tagName === 'BUTTON'), 'the rows are buttons');
        check([...menu.children].map(b => b.textContent).join() === '⬇ CSV,⬇ PNG,⬇ SVG,⬇ HTML',
            'rows: ' + [...menu.children].map(b => b.textContent).join());

        // Open: under its button, against its right edge.
        await open('cm-room');
        check(isOpen(menu), 'the button opens the menu');
        let r = menu.getBoundingClientRect(), b = toggle.getBoundingClientRect();
        check(near(r.right, b.right), 'right edges agree: ' + r.right + ' vs ' + b.right);
        check(near(r.top, b.bottom + 2), 'under the button: ' + r.top + ' vs ' + b.bottom);
        check(r.height > 60 && r.height < 200, 'menu height: ' + r.height);
        check(r.width >= b.width - 1, 'at least as wide as its button: ' + r.width + ' vs ' + b.width);
        check(new Set([...menu.children].map(c => Math.round(c.getBoundingClientRect().left))).size === 1, 'rows line up');

        // The page's colours in both themes, never Pico's azure.
        for (const theme of ['light', 'dark']) {
            document.documentElement.setAttribute('data-theme', theme);
            document.getAnimations().forEach(a => a.finish());
            await sleep(20);
            const box = getComputedStyle(menu), row = getComputedStyle(menu.children[0]);
            const page = getComputedStyle(document.documentElement);
            check(box.backgroundColor === page.backgroundColor, theme + ': menu on the page background: ' + box.backgroundColor + ' vs ' + page.backgroundColor);
            check(row.backgroundColor === 'rgba(0, 0, 0, 0)', theme + ': a row is unfilled: ' + row.backgroundColor);
            check(row.color === box.color, theme + ': a row takes the text colour: ' + row.color);
            check(row.color !== AZURE && box.borderTopColor !== AZURE, theme + ': no azure');
            check(row.borderTopWidth === '0px', theme + ': a row has no button border');
            check(row.marginBottom === '0px', theme + ': a row has no Pico margin');
        }
        document.documentElement.removeAttribute('data-theme');
        await close('cm-room');

        // Each row runs its download and closes the menu.
        const calls = [];
        const originals = {};
        for (const name of ['downloadPlotData', 'downloadPlotImage', 'downloadPlotHtml']) {
            originals[name] = AoV[name];
            AoV[name] = function (...args) { calls.push([name, ...args]); };
        }
        const expected = [['downloadPlotData', 'cm-room', 'cm-room'], ['downloadPlotImage', 'cm-room', 'png', 'cm-room'],
                          ['downloadPlotImage', 'cm-room', 'svg', 'cm-room'], ['downloadPlotHtml', 'cm-room', 'cm-room']];
        for (let i = 0; i < 4; i++) {
            await open('cm-room');
            calls.length = 0;
            menu.children[i].click();
            await sleep(20);
            const got = calls[0] || [];
            check(calls.length === 1 && expected[i].every((v, j) => got[j] === v), 'row ' + i + ' calls ' + JSON.stringify(calls));
            check(!isOpen(menu), 'row ' + i + ' closes the menu');
        }
        Object.assign(AoV, originals);

        // The button also closes it, and opening another menu closes this one.
        await open('cm-room');
        toggle.click();
        await sleep(20);
        check(!isOpen(menu), 'the button closes the menu');
        await open('cm-room');
        await open('cm-clip');
        check(!isOpen(menu) && isOpen(menuOf('cm-clip')), 'one menu is open at a time');

        // A box around the figure does not clip it.
        const clipped = menuOf('cm-clip');
        const lastRow = clipped.children[3].getBoundingClientRect();
        const box = document.getElementById('cm-clip').closest('figure').parentElement.getBoundingClientRect();
        toggleOf('cm-clip').scrollIntoView({block: 'nearest'});
        await sleep(20);
        const row = clipped.children[3].getBoundingClientRect();
        check(document.elementFromPoint(row.left + row.width / 2, row.top + row.height / 2) === clipped.children[3],
            'the last row is on top: ' + (document.elementFromPoint(row.left + row.width / 2, row.top + row.height / 2) || {}).tagName);
        check(lastRow.height > 0 && box.height === 140, 'the fixture box clips at 140 px');
        await close('cm-clip');

        // It follows the page's scroll and stops when closed.
        await open('cm-room');
        window.scrollBy(0, 37);
        window.dispatchEvent(new Event('scroll'));
        await sleep(20);
        r = menu.getBoundingClientRect(); b = toggle.getBoundingClientRect();
        check(near(r.top, b.bottom + 2), 'follows the scroll: ' + r.top + ' vs ' + b.bottom);
        // Little room below: it opens above its button instead.
        window.scrollTo(0, 0);
        await close('cm-room');
        const spacer = document.createElement('div');
        spacer.style.height = (document.documentElement.clientHeight - toggle.getBoundingClientRect().bottom - 90) + 'px';
        room.parentElement.parentElement.insertBefore(spacer, room.parentElement);
        await open('cm-room');
        r = menu.getBoundingClientRect(); b = toggle.getBoundingClientRect();
        check(near(r.bottom, b.top - 2), 'opens above with little room below: ' + r.bottom + ' vs ' + b.top);
        check(r.top >= 0, 'stays on the screen');
        await close('cm-room');
        spacer.remove();
        window.scrollTo(0, 0);

        // A button at the left edge: the menu stays in the viewport.
        await open('cm-left');
        const left = menuOf('cm-left').getBoundingClientRect();
        check(left.left >= 0 && left.right <= document.documentElement.clientWidth, 'in the viewport: ' + left.left + '..' + left.right);
        check(near(left.top, toggleOf('cm-left').getBoundingClientRect().bottom + 2), 'still under its button');
        await close('cm-left');

        // Listeners go when it closes; a menu removed while open drops them on the next scroll.
        await open('cm-room');
        check(typeof menu._aovMenuDone === 'function', 'open: follows');
        await close('cm-room');
        check(menu._aovMenuDone === null, 'closed: no longer follows');

        // download_menu=false: the separate buttons, no menu.
        const plain = document.getElementById('cm-plain').closest('figure');
        check(plain.querySelectorAll('.caption-actions > .caption-action').length === 4, 'separate buttons');
        check(!plain.querySelector('[popover]'), 'no menu');

        // The saved HTML page has a working menu and its look.
        await open('cm-room');
        let saved = null;
        const trigger = AoV._triggerDownload;
        AoV._triggerDownload = function (text, filename, mime) { saved = {text, filename, mime}; };
        try { await AoV.downloadPlotHtml('cm-room', 'saved'); } finally { AoV._triggerDownload = trigger; }
        await close('cm-room');
        check(saved !== null, 'the card saves');
        if (saved) {
            const doc = new DOMParser().parseFromString(saved.text, 'text/html');
            const m = doc.getElementById('cm-room-download-menu');
            check(!!m && m.children.length === 4, 'the saved page has the rows');
            check(!!m && !m.hasAttribute('style'), 'the saved menu carries no place');
            check(!!doc.querySelector('[popovertarget="cm-room-download-menu"]:not([popovertargetaction])'), 'the saved page has the button');
            check([...doc.querySelectorAll('style')].some(s => s.textContent.includes('.aov-download-menu')), 'the saved page has the look');
            check(saved.text.includes('_downloadMenuToggle'), 'the saved page has the runtime');
        }
    } catch (e) {
        failures.push('threw: ' + (e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-caption-menu-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
