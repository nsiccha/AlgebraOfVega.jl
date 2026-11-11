# Repeated measurements

Two thermometers record a vessel during a short heating experiment. The table below contains a reading from each instrument at every observation time. Time is measured in minutes and temperature in degrees Celsius. These are declared teaching data, not observations from a published experiment. The comparison concerns agreement between the instruments and their relation to an operating threshold. It does not estimate a heating law, calibrate either instrument, or establish a safe operating temperature.

## Data

```@example measurements
using AlgebraOfVega, Statistics
using Main.DocsPlots # hide
readings = (
    minute = repeat([0, 1, 2, 3, 4], 2),
    temperature = [18.0, 21.0, 25.0, 28.0, 30.0,
                   18.4, 21.3, 25.5, 28.2, 30.4],
    instrument = repeat(["A", "B"], inner=5),
)
[(time_min=readings.minute[i], temperature_C=readings.temperature[i],
  instrument=readings.instrument[i]) for i in eachindex(readings.minute)]
```

Each row is one reading. Keeping both instruments in the same columns makes the instrument identifier available to color, grouping, and tooltips. A named tuple of equal-length columns satisfies the table interface; a DataFrame is optional. The measurements retain their physical units in the data. Labels add the units to the axes, without changing the numeric values supplied to the browser.

## Figure

The figure joins readings within each instrument and places the operating threshold on the same temperature axis.

```@example measurements
observed = data(readings) *
    mapping(:minute => "Time (min)",
            :temperature => "Temperature (°C)"; color=:instrument => "Instrument") *
    visual(ScatterLines)
limit = 27.0
threshold = data((temperature=[limit],)) *
    mapping(:temperature) * visual(HLines; color=:ink, linestyle=:dash)
comparison = (observed + threshold) * config(
    height=300,
    scales=scales(Color=(categories=["A", "B"], palette=["#2a78d6", "#eb6834"])),
)
vdraw(comparison);
DocsPlots.figure(comparison, "measurements"; caption="The instruments follow the same rising trajectory. The dashed rule marks the operating threshold; later observations lie above it.") # hide
```

The points are observations. The connecting segments show their order, without claiming that temperature changed linearly between sampling times. Both instruments share an axis, so their vertical separation is comparable throughout the experiment. The dashed rule is a separate layer with its own table and a single mapped coordinate. For `HLines`, that coordinate is the vertical position. Its neutral ink follows the page theme; the instrument colors retain their meaning in either theme.

The algebra separates these decisions. Multiplication adds mappings and a visual to a dataset. Addition overlays the resulting layers. Configuration applies to the combined figure. Explicit category order keeps instrument A blue and instrument B orange even if the input row order changes. A color legend is meaningful here because each color identifies an instrument, rather than a different temperature range.

## Specification

The generated specification exposes the actual marks and coordinate fields that the browser receives.

```@example measurements
vl = to_vegalite(comparison; interactive=false)
marktype(layer) = layer["mark"] isa AbstractDict ? layer["mark"]["type"] : layer["mark"]
[(mark=marktype(layer),
  channels=sort!(collect(keys(get(layer, "encoding", Dict()))))) for layer in vl["layer"]]
```

Inspect the generated channels when a figure does not match an intended mapping, before adding raw Vega-Lite overrides. The specification describes a browser figure; it is not a Makie scene. `interactive=false` omits the automatically added interaction parameters for this inspection. It does not change the observations or turn the connected lines into a fitted model.

## Diagnostics

Before interpreting differences, check that the instruments were observed at matching times and that every value is finite.

```@example measurements
 a = findall(==("A"), readings.instrument)
 b = findall(==("B"), readings.instrument)
@assert readings.minute[a] == readings.minute[b]
@assert all(isfinite, readings.temperature)
differences = readings.temperature[b] .- readings.temperature[a]
(paired_times_min=readings.minute[a],
 difference_B_minus_A_C=round.(differences; digits=2),
 mean_difference_C=round(mean(differences); digits=2))
```

The differences are positive at every paired time, consistent with the orange points appearing above the blue ones. Their mean is a descriptive offset for these readings. It is not a confidence interval or an estimate of instrument bias in an independent population. A calibration study would need a reference standard, repeated experiments, and a model for measurement error. Here, the numerical check supports precisely the visual claim: one instrument reads higher throughout this table.

The threshold comparison also comes from the data used in the figure.

```@example measurements
[(instrument=name,
  first_recorded_time_above_limit_min=minimum(readings.minute[i] for i in eachindex(readings.minute)
      if readings.instrument[i] == name && readings.temperature[i] > limit))
 for name in ["A", "B"]]
```

These are the first recorded times above the threshold. The table cannot determine the exact crossing time between observations. Reading an interpolated crossing off a connecting segment would add an assumption absent from the data. If the table had no reading above the threshold, the query would need to represent that case explicitly instead of reporting a time.

## Interpretation

A shared axis makes the observed offset visible without normalizing either series. Normalization would answer a different question about relative change and would remove some of the information needed for instrument comparison. The threshold belongs to the original temperature scale, so keeping both series in degrees Celsius also makes the rule directly interpretable. A separate panel for each instrument would require the reader to compare positions across panels and to verify that both panels used the same scale.

The figure shows all rows in the declared table. In a larger experiment, inspect missing values, repeated timestamps, and instrument identifiers before joining points. A missing observation should not silently become a zero temperature, and a repeated timestamp can represent either a replicate or a data-entry problem. Decide which meaning applies before aggregation. Retaining a separate replicate identifier allows the table to distinguish repeated readings from the instrument identity used for color.

These choices concern the data represented by the marks. Zooming or hiding a series changes the browser view; it does not change the data or the diagnostic calculations printed on this page.

## Output

The same object can be saved as an HTML document for a browser. A rendered node uses the package runtime, including its handling of the host theme.

```@example measurements
html = to_html(to_node(comparison; id="temperature-comparison"); source=:inline)
write("temperature-export.html", html)
(html_document=startswith(lstrip(html), "<!DOCTYPE html>"),
 contains_figure=occursin("temperature-comparison", html))
```

An inline document includes the plotting libraries so it can open without fetching a CDN. Keep generated documents outside version control. The [output guide](../guides/output.md) distinguishes this export from a JSON specification and from a static image. For a report that needs uncertainty estimates, start from the actual distribution or fitted-model summary and use the [interval example](intervals.md); connecting these measurements alone provides no uncertainty calculation.

## Reproduce

```@raw html
<details><summary>Build commands and receipt</summary>
```

The [developer regression tool](https://github.com/nsiccha/AlgebraOfVega.jl/blob/dev/bench/README.md) is separate from this example. The documentation environment runs all blocks above in order. No fit, network dataset, or random seed is needed. From the repository root, after dependency setup:

```sh
julia --project=docs docs/make.jl
```

```@eval
Main.DocsPlots.receipt("examples/measurements.md")
```

```@raw html
</details>
```
