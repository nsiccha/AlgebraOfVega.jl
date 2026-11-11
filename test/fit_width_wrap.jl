using TestItemRunner

# Full facet headings and a legend can set a grid's minimum width even after
# every plot area has reached 100 px. Automatic columns must then reflow.
@testitem "wrapped facets fit their full headings and leave missing cells empty" setup=[AoVFitWidthBrowser] tags=[:regression, :browser, :facet] begin
    using HTMXObjects
    panels = ["Plasma ARV-102 — AUC over the final window (ng/mL·h)",
        "Plasma ARV-102 — Maximum (ng/mL)",
        "PBMC LRRK2 — Maximal decrease from baseline (%)",
        "CSF LRRK2 — Maximal decrease from baseline (%)",
        "Plasma ARV-102 — Minimum over the final window (ng/mL)",
        "QTcF — Maximal increase from baseline (ms)"]
    doses = [5.0, 10.0, 20.0, 40.0, 60.0]
    function figure(n, legend)
        rows = [(; dose=d, panel=p, scenario=s, q50=d * i, lo=0.5d * i,
            hi=1.5d * i, lo50=0.8d * i, hi50=1.2d * i)
            for (i, p) in enumerate(panels[1:n])
            for s in (legend ? ["Daily", "Twice daily"] : ["Daily"]) for d in doses]
        facet = (; layout=:panel => sorter(panels[1:n]) => "")
        color = legend ? (; color=:scenario => "Scenario") : (;)
        ribbon = data(rows) * mapping(:dose => "Dose (mg)", :q50 => "Median, 50 % and 95 % intervals";
            facet..., color...) * lineribbon(bands=[:lo => :hi, :lo50 => :hi50]) *
            (legend ? visual() : visual(; color=:ink))
        marker = data((; dose=fill(60.0, n), panel=panels[1:n])) * mapping(:dose; facet...) *
            visual(VLines; color=:ink, linestyle=:dash)
        span = data((; from=fill(10.0, n), to=fill(60.0, n), panel=panels[1:n])) *
            mapping(:from, :to; facet...) * visual(VSpan; color=:ink, alpha=0.45, ymin=0.975, ymax=1.0)
        (ribbon + marker + span) * config(scales=scales(X=(; scale=log10, nice=false)),
            facet=(; linkyaxes=:none), encoding=(; x=(; axis=(; values=doses))))
    end
    # Record every actual render, including corrections; exercise both renderers.
    probe = """<script>window.wrapFits = {};
        const originalEmbed = window.vegaEmbed;
        window.vegaEmbed = function(selector, spec, opts) {
            const id = selector.slice(1), history = wrapFits[id] = wrapFits[id] || [];
            history.push({cols: spec.columns, width: spec.spec.width});
            if (history.length > 100) throw new Error(id + ': fit did not converge');
            if (id.endsWith('-svg')) opts = Object.assign({}, opts, {renderer:'svg'});
            return originalEmbed(selector, spec, opts);
        };</script>"""
    mktempdir(prefix="kb-fit-wrap-") do dir
        HTMXObjects.copy_vendorfiles(dir; packages=(:pico,), runtime=false)
        body = "<link rel='stylesheet' href='file://$(joinpath(dir, "pico.min.css"))'>" *
            "<style>body{margin:0;font-size:16px}</style>" * probe
        for renderer in ("canvas", "svg"), n in (2, 4, 6), legend in (false, true)
            id = "fw-$n-$legend-$renderer"
            plot = with_plot_caption(figure(n, legend), CaptionSpec(; title=id); plot_id=id)
            body *= "<div id='column-$id' style='width:1040px'>" * html(plot) * "</div>"
        end
        # Deliberately incomplete fixed-count grid: its empty cells must remain
        # empty even if its authored geometry cannot fit the column.
        for (id, extra) in ("fw-explicit" => config(columns=4),
                "fw-fixed" => config(columns=4, width=180))
            body *= "<div style='width:1040px'>" * html(vdraw(figure(6, true) * extra; id)) * "</div>"
        end
        browser_checks(body, joinpath(@__DIR__, "fit_width_wrap.js"), "aov-fit-width-wrap-results"; min_checks=200)
    end
end
