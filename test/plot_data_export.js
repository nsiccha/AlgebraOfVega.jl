// What a figure's real ⬇ CSV button downloads and its "Show data" pane lists.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const same = (got, want, message) => check(JSON.stringify(got) === JSON.stringify(want),
        message + ': ' + JSON.stringify(got) + ', not ' + JSON.stringify(want));
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id) {
        for (let i = 0; i < 500; i++) {
            if (AoV.views && AoV.views[id] && !AoV._inFlight[id]) return;
            await sleep(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // The files one click on the figure's CSV button gives.
    function csvOf(id) {
        const got = [], real = AoV._triggerDownload;
        AoV._triggerDownload = (text, filename) => {
            const lines = text.split('\n');
            got.push({filename, header: lines[0].split(','), rows: lines.length - 1, text});
        };
        try {
            const menu = document.getElementById(id + '-download-menu');
            [...menu.querySelectorAll('button')].find(b => b.textContent.includes('CSV')).click();
        } finally {
            AoV._triggerDownload = real;
        }
        return got;
    }
    // What the figure's "Show data" pane lists, freshly rendered.
    function paneOf(id) {
        const details = document.getElementById(id).closest('figure').querySelector('details.aov-data-preview');
        const body = details.querySelector('.aov-data-raw-body');
        delete body.dataset.aovRendered;
        AoV._lazyRenderDataView(details, 'raw');
        return {
            headings: [...body.querySelectorAll('h6')].map(h => h.textContent),
            rows: [...body.querySelectorAll('table tbody')].map(t => t.children.length),
        };
    }
    const names = files => files.map(f => f.filename);
    const counts = files => files.map(f => f.rows);

    try {
        for (const id of ['x-map', 'x-coloured', 'x-outline', 'x-two', 'x-labelled', 'x-one', 'x-facet', 'x-sparse']) await ready(id);

        // The reported map: its values are the last layer's, in a table of their own.
        let files = csvOf('x-map');
        same(names(files), ['x-map.csv'], 'map: one file under the figure\'s name');
        same(counts(files), [4], 'map: every value row');
        check(files[0].header.includes('value') && files[0].header.includes('point_key'), 'map: the value columns: ' + files[0].header);
        check(!files[0].header.includes('name'), 'map: not the region names: ' + files[0].header);
        check(!files[0].header.includes('geometry'), 'map: no looked-up geometry: ' + files[0].header);
        check(files[0].text.includes('4.5'), 'map: the values themselves');
        same(paneOf('x-map'), {headings: [], rows: [4]}, 'map: the pane lists the same rows');
        // Without a summary, the summary pane gives the same rows too.
        const pretty = document.createElement('div');
        AoV.renderPrettySummary('x-map', pretty, {});
        same([...pretty.querySelectorAll('table tbody')].map(t => t.children.length), [4], 'map: summary pane without a summary');

        // The geometry a layer looks up is a dataset, and it is read by no mark.
        const drawn = AoV._drawnDatasets('x-map');
        same(drawn.map(d => d.untagged), [false, false, true], 'map: which datasets draw values');
        const declared = AoV._results['x-map'].vgSpec.data.filter(d => !d.source).length;
        check(declared > drawn.length, 'map: a looked-up dataset is declared and not drawn from: ' + declared);

        // Live rows reach the export, as they reach the drawing.
        AoV.updateData('x-map', [
            {point_key: 'e', lon: 8.5, lat: 50.5, value: 9.25},
            {point_key: 'f', lon: 9.5, lat: 50.5, value: 8.25}], drawn[2].name);
        await sleep(50);
        files = csvOf('x-map');
        same(counts(files), [2], 'map: after a data update');
        check(files[0].text.includes('9.25'), 'map: the updated values');

        // The values colour the first layer, and the regions are context.
        files = csvOf('x-coloured');
        same(names(files), ['x-coloured.csv'], 'coloured map: one file');
        same(counts(files), [2], 'coloured map: the coloured rows');
        check(files[0].header.includes('value'), 'coloured map: the values: ' + files[0].header);

        // Nothing draws values: the button still gives what is drawn, without geometry.
        files = csvOf('x-outline');
        same(names(files), ['x-outline__s1.csv', 'x-outline__s2.csv'], 'outline map: each drawn dataset');
        same(counts(files), [3, 1], 'outline map: rows');
        check(files.every(f => !f.header.includes('geometry')), 'outline map: no looked-up geometry');

        // Two layers that draw values, with no facets: every row of both.
        files = csvOf('x-two');
        same(names(files), ['x-two__s1.csv', 'x-two__s2.csv'], 'two layers: a file each');
        same(counts(files), [3, 4], 'two layers: rows');
        // Sorted: a row's column order follows Julia's hash order, which versions change.
        same(files.map(f => [...f.header].sort()), [['x', 'y'], ['m', 'x']], 'two layers: each its own columns');
        same(paneOf('x-two'), {headings: ['_s1', '_s2'], rows: [3, 4]}, 'two layers: the pane');

        // `layer_labels` reads the same as on a faceted figure.
        files = csvOf('x-labelled');
        same(names(files), ['x-labelled__s1.csv', 'x-labelled_Modell.csv'], 'labels: file names');
        same(paneOf('x-labelled'), {headings: ['_s1', 'Modell'], rows: [3, 4]}, 'labels: the pane');

        // One layer: as ever.
        files = csvOf('x-one');
        same(names(files), ['x-one.csv'], 'one layer: its name');
        same(counts(files), [3], 'one layer: rows');
        same([...files[0].header].sort(), ['x', 'y'], 'one layer: columns');
        same(paneOf('x-one'), {headings: [], rows: [3]}, 'one layer: the pane');

        // Facets: a merged dataset, its sources apart. The text layer's source is a
        // note, as on a map, and the column that tells the sources apart stays out.
        files = csvOf('x-facet');
        same(names(files), ['x-facet__s1.csv', 'x-facet__s2.csv'], 'facets: the sources that draw values');
        same(counts(files), [3, 2], 'facets: rows');
        check(files.every(f => !f.header.includes('__src')), 'facets: no __src column');
        same(paneOf('x-facet').rows, [3, 2], 'facets: the pane');

        // A sparse grid's pad rows only hold its cells.
        files = csvOf('x-sparse');
        check(AoV.views['x-sparse'].data('source_0').some(r => r.__aov_pad === true), 'sparse: the fixture has pad rows');
        check(files.every(f => !f.header.includes('__aov_pad') && !f.text.includes('true')), 'sparse: no pad rows in the file');

        // A view that is gone gives nothing, and says so.
        const warned = [], warn = console.warn;
        console.warn = (...a) => warned.push(a.join(' '));
        try {
            AoV.downloadPlotData('no-such-plot', 'x', {});
        } finally {
            console.warn = warn;
        }
        check(warned.some(w => w.includes('no data for')), 'a missing plot warns');
    } catch (e) {
        failures.push('threw: ' + (e && e.stack || e));
    }
    const pre = document.createElement('pre');
    pre.id = 'aov-plot-data-export-results';
    pre.textContent = JSON.stringify({checks, failures});
    document.body.appendChild(pre);
})();
