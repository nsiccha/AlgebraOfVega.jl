// The caption share buttons in the browser: each copies its absolute URL,
// resolved against the page's current address, and flashes its copied word.
// The clipboard is captured, so what is checked is what the handler writes.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    const errors = [];
    window.addEventListener('error', e => errors.push(e.message));
    const copies = [];
    Object.defineProperty(navigator, 'clipboard', {configurable: true,
        value: {writeText: text => { copies.push(text); return Promise.resolve(); }}});
    // Click and report what reached the clipboard, and any error the click raised.
    async function copy(button) {
        copies.length = 0;
        const before = errors.length;
        button.click();
        await sleep(20);
        return {copied: copies.slice(), errors: errors.slice(before)};
    }
    const one = (got, expected) => got.errors.length === 0 && got.copied.length === 1 && got.copied[0] === expected;
    const show = got => JSON.stringify(got);
    const captionButton = (id, word) => [...document.getElementById(id).closest('figure')
        .querySelectorAll('.caption-actions button')].find(b => b.textContent === word);

    try {
        // The inputs changed: the page's address carries their state.
        history.replaceState(null, '', location.pathname + '?attenuation=0.00387&density=290#top');
        const here = () => location.origin + location.pathname + location.search;
        const dir = location.origin + location.pathname.replace(/[^/]*$/, '');

        // caption_share_button(""): the current address with its query, without the fragment.
        const row = document.querySelector('#cs-row button');
        let got = await copy(row);
        check(one(got, here()), 'caption_share_button(""): ' + show(got) + ' vs ' + here());
        check(row.textContent === 'Copied!', 'it flashes the copied word: ' + row.textContent);
        await sleep(1600);
        check(row.textContent === 'Copy link', 'it restores its label: ' + row.textContent);
        // A later change of state is what the next click copies.
        history.replaceState(null, '', location.pathname + '?attenuation=0.005&density=300');
        got = await copy(row);
        check(one(got, here()) && here().endsWith('?attenuation=0.005&density=300'), 'it follows the address: ' + show(got));

        // A relative URL resolves against the page's directory, without force=.
        got = await copy(document.querySelector('#cs-rel button'));
        check(one(got, dir + 'other.html?a=1'), 'a relative URL: ' + show(got));

        // with_plot_caption(...; share_url=...): the caption row's Share button.
        const share = captionButton('cs-plot', 'Share');
        check(!!share, 'the captioned plot has a Share button');
        got = share ? await copy(share) : {copied: [], errors: []};
        check(one(got, location.origin + '/p/Slug/analysis'), 'with_plot_caption share_url: ' + show(got));

        // with_caption_share: the button injected into an already-rendered figure.
        const injected = captionButton('cs-inj', 'Injected share');
        check(!!injected, 'with_caption_share injects its button');
        got = injected ? await copy(injected) : {copied: [], errors: []};
        check(one(got, location.origin + '/q?x=1'), 'with_caption_share: ' + show(got));

        // summary_share_button: copies and leaves its <details> closed.
        const details = document.getElementById('cs-summary');
        got = await copy(details.querySelector('summary button'));
        check(one(got, location.origin + '/s'), 'summary_share_button: ' + show(got));
        check(!details.open, 'the summary button does not toggle its details');

        check(errors.length === 0, 'no page errors: ' + errors.join('; '));
    } catch (e) {
        failures.push('threw: ' + (e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-caption-share-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
