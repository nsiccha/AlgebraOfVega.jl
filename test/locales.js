// Compile the actual AoV specs and exercise Vega's per-view locale and SVG labels.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const [vendor, ...files] = process.argv.slice(2);
const ctx = vm.createContext({console, structuredClone, setTimeout, clearTimeout});
for (const file of ['vega.min.js', 'vega-lite.min.js']) {
    vm.runInContext(fs.readFileSync(path.join(vendor, file), 'utf8'), ctx);
}

(async () => {
    for (const [i, file] of files.entries()) {
        ctx.spec = JSON.parse(fs.readFileSync(file, 'utf8'));
        const view = vm.runInContext(
            'new vega.View(vega.parse(vegaLite.compile(spec).spec), {renderer: "none"})', ctx);
        try {
            await view.runAsync();
            const locale = view.locale();
            const number = i === 0 ? '1.234,5' : '1,234.5';
            const month = i === 0 ? 'März' : 'March';
            assert.equal(locale.format(',.1f')(1234.5), number);
            assert.equal(locale.format('$,.2f')(1234.5), i === 0 ? '1.234,50\u00a0€' : '$1,234.50');
            assert.equal(locale.timeFormat('%A %B %b')(new Date(2026, 2, 1)),
                i === 0 ? 'Sonntag März Mrz' : 'Sunday March Mar');
            assert.equal(locale.timeFormat('%x')(new Date(2026, 2, 1)),
                i === 0 ? '01.03.2026' : '3/1/2026');
            const svg = await view.toSVG();
            assert.ok(svg.includes(`>${number}</text>`), 'localized numeric axis label');
            assert.ok(svg.includes(`>${month}</text>`), 'localized time axis label');
        } finally {
            view.finalize();
        }
    }
    console.log('German and English Vega locale rendering passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
