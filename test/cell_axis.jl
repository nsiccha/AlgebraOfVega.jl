using TestItemRunner

# A `cell_charts` column whose cells share a continuous x draws that axis once,
# at the bottom of the column's header cell, on the cells' scale and aligned with
# their plot area, so the in-row charts can be read off (decision 0qrccve, prong
# `cell-axis`). Before, the cells compared rows but showed no values at all.
@testitem "cell charts: the shared x axis in the column header" tags=[:cells, :browser] begin
    using AlgebraOfVega, HTMXObjects, HTMX, JSON
    import AlgebraOfGraphics
    html(x) = sprint(show, MIME"text/html"(), x)
    sites = ["a", "b", "c"]
    est = (; site=sites, q50=[0.1, 1.0, -0.4], q025=[-0.9, 0.4, -1.2], q975=[0.4, 1.7, 0.3])
    interval(; kw...) = cell_charts(data(est) * mapping(:q50 => "Change"; layout=:site) *
        pointinterval(bands=[:q025 => :q975]) * config(width=240, height=20); kw...)
    @test interval().column.vl["_aov"]["cells"]["axis"] === true
    @test interval(axis=false).column.vl["_aov"]["cells"]["axis"] === false

    chrome = something(Sys.which("google-chrome"), Sys.which("chromium"), "")
    if isempty(chrome)
        @test_skip "headless Chrome is not installed"
    else
        with_axis, without = interval(id="with-axis"), interval(id="without-axis", axis=false)
        classes = ["s", "m", "l"]
        bars = cell_charts(data((; site=repeat(sites, inner=3), k=repeat(classes, 3), n=collect(1.0:9))) *
            mapping(:k => sorter(classes), :n; layout=:site) * visual(BarPlot); id="bars")
        table(id, cells) = h.div(; id)(sortable_table(["Site", "Change", "Note"],
            [h.tr(; id="$id-$s")(h.td(s), cells[s], h.td("x")) for s in sites]))
        page = [table("t-axis", with_axis), table("t-none", without), table("t-bars", bars)]
        driver = """
        (async function () {
            const out = {};
            const pause = () => new Promise(r => setTimeout(r, 20));
            for (let i = 0; i < 300 && !(AoV._cellAxes && AoV._cellAxes.size); i++) await pause();
            for (let i = 0; i < 20; i++) await pause();
            const axes = id => [...document.querySelectorAll('#' + id + ' .aov-cell-axis')];
            out.counts = ['t-axis', 't-none', 't-bars'].map(id => axes(id).length);
            const holder = axes('t-axis')[0];
            if (holder) {
                const th = holder.closest('th');
                out.column = [...th.parentElement.cells].indexOf(th);
                // The header's text as the table's CSV export reads it (text nodes only).
                out.name = (function text(n) { let s = ''; n.childNodes.forEach(c => s += c.nodeType === 3 ? c.nodeValue : text(c)); return s; })(th).trim();
                const axisView = AoV._cellAxes.get(th).view;
                const el = document.querySelector('#t-axis span.aov-cell');
                const cellView = AoV._cellViews.get(el).view;
                const at = (view, box, v) => box.getBoundingClientRect().left + view.origin()[0] + view.scale('x')(v);
                out.offsets = [0, 1].map(v => at(axisView, axisView.container(), v) - at(cellView, cellView.container(), v));
                out.below = holder.getBoundingClientRect().bottom <= th.getBoundingClientRect().bottom + 0.5 &&
                    holder.getBoundingClientRect().top >= th.getBoundingClientRect().top;
            }
            const pre = document.createElement('pre'); pre.id = 'aov-cell-axis';
            pre.textContent = JSON.stringify(out); document.body.appendChild(pre);
        })();
        """
        mktempdir(prefix="kb-aov-cell-axis-") do dir
            head = join(html(n) for n in vega_head(; source=:inline))
            write(joinpath(dir, "page.html"), "<!doctype html><meta charset='utf-8'>" * head *
                "<body style='width:800px'>" * join(html(p) for p in page) * "<script>" * driver * "</script></body>")
            output = read(pipeline(`$chrome --headless=new --no-sandbox --disable-gpu
                --user-data-dir=$(joinpath(dir, "profile")) --window-size=1000,900
                --virtual-time-budget=20000 --dump-dom $("file://" * joinpath(dir, "page.html"))`,
                stderr=joinpath(dir, "chrome.log")), String)
            m = match(r"<pre id=\"aov-cell-axis\">([^<]*)</pre>", output)
            @test !isnothing(m)
            if !isnothing(m)
                r = JSON.parse(replace(m[1], "&quot;" => "\"", "&amp;" => "&"))
                @info "cell axis" r
                # One axis, over the interval column; none when turned off or for categories.
                @test r["counts"] == [1, 0, 0]
                @test r["column"] == 1 && r["below"] === true
                # Its ticks sit where the cells draw those values.
                @test all(d -> abs(d) <= 1, r["offsets"])
                # The header's own text (sorting, CSV) is unchanged: a canvas has none.
                @test r["name"] == "Change"
            end
        end
    end
end
