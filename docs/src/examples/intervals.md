# Empirical intervals

Two sets of simulated measurement errors describe instruments with different precision. The values below are deterministic teaching data in degrees Celsius: the second set is a shifted, compressed copy of the first. They are neither posterior draws nor repeated estimates from a fitted model. The task is to summarize their centers and spreads, compare the summaries with the original values, and display the intervals without implying an inferential interpretation that the data do not support.

## Data

```@example intervals
using AlgebraOfVega, Statistics
using Main.DocsPlots # hide
errors_a = collect(-2.0:0.1:2.0)
errors_b = 0.4 .+ 0.5 .* errors_a
errors = (
    error = vcat(errors_a, errors_b),
    instrument = vcat(fill("A", length(errors_a)), fill("B", length(errors_b))),
)
[(instrument=name, observations=count(==(name), errors.instrument),
  range_C=extrema(errors.error[errors.instrument .== name])) for name in ["A", "B"]]
```

The equally spaced values make the construction visible. This spacing is not a sampling assumption or a recommended way to approximate a posterior. It gives a reproducible table whose quantiles can be checked independently. Each row remains an individual error, and the instrument label identifies the group whose distribution is summarized. There is no time coordinate: a line joining these values would suggest an ordering that the comparison does not use.

## Summary

Compute the central and outer quantiles for each instrument before drawing the intervals.

```@example intervals
summary = preaggregate(errors; y=:error, group_keys=[:instrument],
                       probs=[0.025, 0.25, 0.5, 0.75, 0.975])
[(instrument=summary.instrument[i], median_C=summary.median[i],
  central_interval_C=(summary.q25[i], summary.q75[i]),
  outer_interval_C=(summary.q025[i], summary.q975[i]))
 for i in eachindex(summary.instrument)]
```

The summary keeps one row per instrument. The median is the central marker; the paired lower and upper columns define the interval endpoints. These are quantiles of the observed values, interpolated by the quantile implementation. An interval does not necessarily contain the corresponding fraction of a small sample as an integer count. It describes endpoints of an empirical distribution, rather than a guarantee about future measurements.

For an actual posterior, the same columns could summarize retained draws. Their interpretation would then depend on the model, data, and sampling diagnostics. The plotting function cannot establish those conditions. Keep a fit's receipt and diagnostics with the cached summary, and supply that table to the plotting stage after the fit has completed. Rendering a page should not rerun the fit.

## Figure

The inner interval is thicker; the outer interval extends farther on each side of the median.

```@example intervals
intervals = data(summary) *
    mapping(:median => "Measurement error (°C)"; y=:instrument => "Instrument",
            color=:instrument => "Instrument") *
    pointinterval(bands=[:q025 => :q975, :q25 => :q75]) *
    config(height=200,
           scales=scales(Color=(categories=["A", "B"], palette=["#2a78d6", "#eb6834"])))
vdraw(intervals);
DocsPlots.figure(intervals, "intervals"; caption="Instrument B has a higher median and narrower empirical intervals. The point is the median; thick and thin segments use the inner and outer quantile pairs printed above.") # hide
```

The horizontal orientation places errors on a common numeric axis and instruments on separate rows. A reader can compare centers and widths without matching different vertical scales. Color repeats the row identity; position carries the comparison. The thin outer segment and thick inner segment share a center marker, but neither segment is forced to be symmetric around it. Asymmetric distributions can produce unequal distances from the median to the endpoints.

The `bands` argument names already computed columns, with the widest interval first. This avoids calculating the same summary again when several outputs use it. With raw observations, `pointinterval(probs=...)` can calculate the quantiles while lowering the figure. Choose one representation and keep its meaning explicit. Passing summary rows to the draw-level form would summarize those rows again, which is a different calculation.

## Diagnostics

Check the summary against direct quantiles of each source group and verify that the inner interval lies inside the outer one.

```@example intervals
checks = map(eachindex(summary.instrument)) do i
    source = errors.error[errors.instrument .== summary.instrument[i]]
    actual = [summary.q025[i], summary.q25[i], summary.median[i],
              summary.q75[i], summary.q975[i]]
    expected = quantile(source, [0.025, 0.25, 0.5, 0.75, 0.975])
    @assert actual ≈ expected
    @assert issorted(actual)
    (instrument=summary.instrument[i],
     matches_source=actual ≈ expected,
     outer_width_C=round(last(actual) - first(actual); digits=2))
end
checks
```

These checks connect the displayed endpoints to the input table. They would fail if a summary column were renamed incorrectly, its groups were mismatched, or its endpoints were reversed. They do not test the quality of a model fit. A diagnostics section for posterior draws would also need the sampler's convergence and effective-sample-size measures; a visually narrow interval alone does not indicate reliable computation.

The expected change in width follows from the declared construction of instrument B. Its errors are a positive rescaling of instrument A's errors plus a constant. Positive scaling changes every quantile width by the same factor; translation changes the center while preserving width. The output above provides the widths used in the figure, so this claim can be checked without relying on the appearance of the lines alone.

## Group identity

A summary row must retain every identifier needed to distinguish the distributions being compared. If instruments were measured under several conditions, include the condition in `group_keys` and map it to color or a facet as appropriate. Omitting it would pool observations across conditions before the figure was drawn. Adding a facet after that pooling cannot recover the lost distinction. The numerical checks should use the same group keys as the aggregation, so each displayed interval is compared with exactly the observations that produced it.

## Generated views

The specification has one interval layer for each supplied band and a point layer for the center. Its structure can be inspected before it reaches a browser.

```@example intervals
spec = to_vegalite(intervals; interactive=false)
[(mark=layer["mark"] isa AbstractDict ? layer["mark"]["type"] : layer["mark"],
  channels=sort!(collect(keys(layer["encoding"])))) for layer in spec["layer"]]
```

This structural view complements the numerical checks. An exported Vega-Lite specification records marks, mappings, and data; it does not carry the scientific interpretation of the intervals by itself. Include the units, interval definition, and source of the summaries in the caption of a saved report. The [output guide](../guides/output.md) describes browser documents and image exports, while the [analysis reference](../reference/analyses.md) covers related interval and ribbon functions.

## Reproduce

```@raw html
<details><summary>Build commands and receipt</summary>
```

The [developer regression tool](https://github.com/nsiccha/AlgebraOfVega.jl/blob/dev/bench/README.md) is separate from this example. All data and summaries are generated by the executed blocks on this page. No fit or random-number generator is used. After dependency setup, from the repository root:

```sh
julia --project=docs docs/make.jl
```

```@eval
Main.DocsPlots.receipt("examples/intervals.md")
```

```@raw html
</details>
```
