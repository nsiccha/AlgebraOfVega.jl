// Fixed vs responsive widths: a plot with an authored width renders at it and is
// not re-embedded when its container resizes; a default (container-sized) plot
// follows its container. A facet remap keeps each plot's sizing regime.
(async function () {
    const failures = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await pause(10);
        }
        throw new Error(id + ': embed did not complete');
    }
    // A container resize re-embeds after a 200ms debounce; wait it out.
    async function settle() { await pause(600); }
    const sized = id => !!(AoV._computedWidths && AoV._computedWidths[id]);

    try {
        const ids = ['fw-fixed-layered', 'fw-fixed-encfacet', 'fw-fixed-remap', 'fw-fit-layered', 'fw-fit-remap'];
        const views = {};
        for (const id of ids) views[id] = await ready(id);
        await settle();
        for (const id of ids) views[id] = AoV.views[id];

        // Authored widths are honoured: 180 for the view, 180 per cell for the
        // encoding facet (VL sizes top-level width per cell there).
        check(views['fw-fixed-layered'].width() === 180, 'fixed layered width ' + views['fw-fixed-layered'].width());
        check(!sized('fw-fixed-layered'), 'fixed layered was sized by the runtime');
        const cells = AoV._origSpecs['fw-fixed-encfacet'].width;
        check(cells === 180, 'fixed encoding facet cell width ' + cells);
        check(!sized('fw-fixed-encfacet'), 'fixed encoding facet was sized by the runtime');
        const canvasW = document.querySelector('#fw-fixed-encfacet canvas').clientWidth;
        check(canvasW > 360 && canvasW < 600,
            'fixed encoding facet rendered ' + canvasW + 'px wide (expected two 180px cells plus chrome)');
        // The default plot fills its 640px container.
        const fitW = views['fw-fit-layered'].width();
        check(sized('fw-fit-layered') && fitW > 500, 'fit layered width ' + fitW + ' did not follow its container');

        // Shrink every container: only the responsive plot re-embeds. The
        // ResizeObserver hands each width change to `_resizeReembed` after its
        // debounce; headless virtual time delivers no RO notifications after
        // load, so call it the way the observer does.
        for (const id of ids) document.getElementById('wrap-' + id).style.width = '420px';
        check(AoV._resizeReembed('fw-fixed-layered') === false, 'fixed layered asked to re-embed on resize');
        check(AoV._resizeReembed('fw-fixed-encfacet') === false, 'fixed encoding facet asked to re-embed on resize');
        check(AoV._resizeReembed('fw-fit-layered') === true, 'fit layered declined to re-embed on resize');
        await settle();
        check(AoV.views['fw-fixed-layered'] === views['fw-fixed-layered'], 'fixed layered re-embedded on resize');
        check(AoV.views['fw-fixed-encfacet'] === views['fw-fixed-encfacet'], 'fixed encoding facet re-embedded on resize');
        const fit = await ready('fw-fit-layered', views['fw-fit-layered']);
        check(fit !== views['fw-fit-layered'], 'fit layered did not re-embed on resize');
        check(fit.width() < fitW, 'fit layered width ' + fit.width() + ' did not shrink from ' + fitW);
        check(AoV.views['fw-fixed-layered'].width() === 180, 'fixed layered width changed on resize');

        // A column-facet remap keeps the regime: authored width → 180 cells;
        // container-sized → runtime-sized cells.
        for (const id of ['fw-fixed-remap', 'fw-fit-remap']) {
            const before = AoV.views[id];
            AoV.remapEncoding(id, {column: 'panel'});
            await ready(id, before);
        }
        const fixedSpec = AoV._cur['fw-fixed-remap'].spec;
        check(fixedSpec.facet && fixedSpec.facet.column, 'fixed remap did not facet');
        check(fixedSpec.spec && fixedSpec.spec.width === 180, 'fixed remap cell width ' + (fixedSpec.spec && fixedSpec.spec.width));
        check(!sized('fw-fixed-remap'), 'fixed remap was sized by the runtime');
        const fitSpec = AoV._cur['fw-fit-remap'].spec;
        check(fitSpec._aov && fitSpec._aov.fitWidth === true, 'fit remap lost its fitWidth marker');
        check(sized('fw-fit-remap') && AoV._computedWidths['fw-fit-remap'].kind === 'facet',
            'fit remap was not sized as a facet: ' + JSON.stringify(AoV._computedWidths['fw-fit-remap']));
        // And back: the fixed plot keeps its width, the fit one is responsive again.
        for (const id of ['fw-fixed-remap', 'fw-fit-remap']) {
            const before = AoV.views[id];
            AoV.remapEncoding(id, {column: null});
            await ready(id, before);
        }
        check(AoV.views['fw-fixed-remap'].width() === 180, 'fixed unwrap width ' + AoV.views['fw-fixed-remap'].width());
        check(AoV.views['fw-fit-remap'].width() > 300, 'fit unwrap width ' + AoV.views['fw-fit-remap'].width());
    } catch (error) {
        failures.push(error.stack || String(error));
    }
    const result = document.createElement('pre');
    result.id = 'aov-fit-width-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
