(async function () {
    const failures = [], errors = [];
    let checks = 0;
    const check = (ok, message) => { checks++; if (!ok) failures.push(message); };
    const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const originalError = console.error;
    console.error = (...args) => { errors.push(args.map(String).join(' ')); originalError(...args); };
    const ids = ['domain-picker', 'domain-layered', 'domain-faceted', 'domain-concat'];
    async function ready(id, previous) {
        for (let i = 0; i < 300; i++) {
            const view = AoV.views[id];
            if (view && view !== previous && !AoV._inFlight[id]) return view;
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        throw new Error(id + ': embed did not complete');
    }
    function encodings(spec, axis) {
        const out = [];
        function walk(s) {
            if (s.encoding?.[axis]?.field !== undefined) out.push(s.encoding[axis]);
            if (s.spec) walk(s.spec);
            (s.layer || s.hconcat || []).forEach(walk);
        }
        walk(spec);
        return out;
    }
    function verifyMarks(id, view, categoryAxis, restored) {
        const marks = [];
        function walk(item) {
            if (item.mark?.marktype === 'symbol' && item.datum?.category) marks.push(item);
            (item.items || []).forEach(walk);
        }
        walk(view.scenegraph().root);
        check(marks.length === 4, id + ': expected four marks, got ' + marks.length);
        check(marks.every(i => Number.isFinite(i.x) && Number.isFinite(i.y)), id + ': invalid mark positions');
        // Bounds are local to each mark's facet cell. Numeric remaps must fit
        // their new values, and nominal remaps must not produce null positions.
        check(marks.every(i => i.x >= 0 && i.x <= i.mark.group.width &&
            i.y >= 0 && i.y <= i.mark.group.height), id + ': marks outside their panel');
        const scales = Object.keys(view._runtime.scales)
            .filter(n => n === categoryAxis || n.endsWith('_' + categoryAxis));
        const domains = scales.map(n => view.scale(n).domain());
        const expected = restored ? ['B', 'spacer', 'A'] : ['C', 'D'];
        check(domains.length > 0 && domains.every(d => equal(d, expected)),
            id + ': category slots ' + JSON.stringify(domains));
    }
    try {
        for (const id of ids) {
            const cat = id === 'domain-concat' ? 'x' : 'y';
            const num = cat === 'x' ? 'y' : 'x';
            let view = await ready(id);
            const original = JSON.stringify(AoV._origSpecs[id]);
            const authored = AoV._results[id].spec;
            const authoredCat = encodings(authored, cat);
            const authoredNum = encodings(authored, num);
            check(authoredCat.length > 0 && authoredNum.length > 0, id + ': missing authored axes');
            check(authoredNum.every(e => equal(e.scale?.domain,
                id === 'domain-concat' ? [1, 3] : [0, 3])), id + ': missing authored numeric domain');
            verifyMarks(id, view, cat, true);
            // Selecting the current fields must keep the authored restrictions.
            const same = AoV._remappedSpec(id, {[cat]:'category', [num]:'value'});
            check(encodings(same, cat).every(e => equal(e.scale, authoredCat[0].scale) &&
                equal(e.sort, authoredCat[0].sort)), id + ': unchanged field lost categories');
            check(encodings(same, num).every((e, i) => equal(e.scale, authoredNum[i].scale)),
                id + ': unchanged field lost numeric domain');

            if (id === 'domain-picker') {
                const select = document.getElementById('aov-remap-y-' + id);
                select.value = 'other';
                select.dispatchEvent(new Event('change', {bubbles:true}));
                view = await ready(id, view);
                check(encodings(AoV._results[id].spec, cat).every(e => e.field === 'other'),
                    id + ': picker did not change the y field');
            }
            AoV.remapEncoding(id, {[cat]:'other', [num]:'larger'});
            view = await ready(id, view);
            const remapped = AoV._results[id].spec;
            const cats = encodings(remapped, cat), nums = encodings(remapped, num);
            check(cats.every(e => e.scale === undefined), id + ': empty category scale retained');
            check(cats.every(e => e.sort === undefined), id + ': authored category order retained');
            check(nums.every(e => e.scale.domain === undefined), id + ': authored numeric domain retained');
            check(nums.every((e, i) => {
                const expected = {...authoredNum[i].scale};
                delete expected.domain;
                return equal(e.scale, expected);
            }),
                id + ': unrelated scale settings changed');
            verifyMarks(id, view, cat, false);

            AoV.remapEncoding(id, {[cat]:'category', [num]:'value'});
            view = await ready(id, view);
            const restored = AoV._results[id].spec;
            check(encodings(restored, cat).every((e, i) => equal(e.scale, authoredCat[i].scale) &&
                equal(e.sort, authoredCat[i].sort)), id + ': category domain/order not restored');
            check(encodings(restored, num).every((e, i) => equal(e.scale, authoredNum[i].scale)),
                id + ': numeric domain not restored');
            verifyMarks(id, view, cat, true);
            check(JSON.stringify(AoV._origSpecs[id]) === original, id + ': original spec mutated');
        }
        // A sort policy is not an enumeration of values of the old field.
        for (const sort of ['descending', {encoding:'x', order:'descending'}, null]) {
            for (const id of ['domain-picker', 'domain-concat']) {
                const cat = id === 'domain-concat' ? 'x' : 'y';
                const saved = AoV._origSpecs[id];
                try {
                    AoV._origSpecs[id] = structuredClone(saved);
                    encodings(AoV._origSpecs[id], cat).forEach(e => { e.sort = sort; });
                    const remapped = AoV._remappedSpec(id, {[cat]:'other'});
                    check(encodings(remapped, cat).every(e => equal(e.sort, sort)),
                        id + ': non-array sort policy changed');
                } finally { AoV._origSpecs[id] = saved; }
            }
        }
        check(errors.length === 0, 'runtime errors: ' + errors.join('; '));
    } catch (error) {
        failures.push(error.stack);
    } finally {
        console.error = originalError;
        ids.forEach(id => AoV.dispose(id));
    }
    const result = document.createElement('pre');
    result.id = 'aov-remap-domain-results';
    result.textContent = JSON.stringify({checks, failures});
    document.body.append(result);
    document.title = failures.length ? 'FAIL' : 'PASS';
})();
