using TestItemRunner

# A cached answer embeds the complete figure at once. Long facet headers
# stop shrinking with their cells, so subtracting the first overshoot once
# leaves the right-hand legend outside the frame (cached-faceted-f-e9db22f5).
@testitem "facet titles do not leave a corrected plot wider than its frame" setup=[AoVFitWidthBrowser] tags=[:regression, :browser] begin
    using HTMXObjects
    quantities = ["AUC over the final window (ng/mL·h)", "Maximum (ng/mL)",
        "Time of maximum (h)", "Minimum over the final window (ng/mL)",
        "Average over the final window (ng/mL)"]
    doses = [5.0, 10.0, 20.0, 40.0, 60.0]
    cols = (; dose=Float64[], scenario=String[], quantity=String[], q50=Float64[],
        lo=Float64[], hi=Float64[], lo50=Float64[], hi50=Float64[])
    for (qi, q) in enumerate(quantities), (si, s) in enumerate(["Daily", "Twice daily"]), d in doses
        m = qi == 3 ? 100.0 : d * [1000.0, 200.0, 1.0, 2.0, 40.0][qi] * (si == 1 ? 1.0 : 0.8)
        push!(cols.dose, d); push!(cols.scenario, s); push!(cols.quantity, q); push!(cols.q50, m)
        push!(cols.lo, 0.02m); push!(cols.hi, qi == 3 ? 300.0 : 5m)
        push!(cols.lo50, 0.7m); push!(cols.hi50, 1.5m)
    end
    facet = (; layout=:quantity => sorter(quantities) => "")
    ribbon = data(cols) * mapping(:dose => "Dose (mg)", :q50; color=:scenario => "Scenario", facet...) *
        lineribbon(bands=[:lo => :hi, :lo50 => :hi50])
    marker = data((; dose=fill(60.0, 5), quantity=quantities)) * mapping(:dose; facet...) *
        visual(VLines; linestyle=:dash, color=:ink)
    span = data((; from=fill(5.0, 5), to=fill(10.0, 5), quantity=quantities)) * mapping(:from, :to; facet...) *
        visual(VSpan; color=:ink, alpha=0.45, ymin=0.975, ymax=1.0)
    spec = (ribbon + marker + span) * config(scales=scales(X=(; scale=log10, nice=false))) *
        config(encoding=(; x=(; axis=(; values=doses)))) * config(facet=(; linkyaxes=:none))
    plot = html(with_plot_caption(spec, CaptionSpec(; title="Dose–response"); plot_id="ft-cached"))
    # A header alone can exceed the budget: shrinking must stop at the
    # readable minimum and leave the full content in the scrolling frame.
    floor_plot = html(vdraw(spec * config(config=(; header=(; labelFontSize=80, labelLimit=0)));
        id="ft-floor", height=120))
    probe = """<script>window.fitTitleEmbeds = {};
        const originalEmbed = window.vegaEmbed;
        window.vegaEmbed = function(selector, spec, opts) {
            const id = selector.slice(1);
            const widths = fitTitleEmbeds[id] = fitTitleEmbeds[id] || [];
            widths.push(spec.spec.width);
            if (widths.length > 20) throw new Error(id + ': fit did not converge');
            return originalEmbed(selector, spec, opts);
        };</script>"""
    mktempdir(prefix="kb-fit-titles-") do dir
        HTMXObjects.copy_vendorfiles(dir; packages=(:pico,), runtime=false)
        body = "<link rel='stylesheet' href='file://$(joinpath(dir, "pico.min.css"))'>" *
            "<style>body{margin:0;font-size:16px}</style>" * probe *
            "<div id='ft-column' style='width:1040px'>" * plot * "</div>" *
            "<div style='width:1040px'>" * floor_plot * "</div>"
        browser_checks(body, joinpath(@__DIR__, "fit_width_titles.js"), "aov-fit-width-titles-results"; min_checks=35)
    end
end
