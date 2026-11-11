# AlgebraOfVega

```@setup assets
Main.DocsPlots.prepare_assets()
```

AlgebraOfVega turns AlgebraOfGraphics expressions into interactive Vega-Lite figures for the browser.

Install from the shell. The [installer](https://github.com/nsiccha/AlgebraOfVega.jl/blob/dev/docs/install.jl) resolves the unregistered dependencies together; it changes your Julia environment and is not run by the documentation build.

```sh
curl -fsSL https://nsiccha.github.io/AlgebraOfVega.jl/dev/install.jl | julia
```

```@example start
using AlgebraOfVega
using Main.DocsPlots # hide
measurements = (time = [0, 1, 2, 3], temperature = [18, 21, 25, 28])
plot = data(measurements) *
    mapping(:time => "Time (min)", :temperature => "Temperature (°C)") *
    visual(ScatterLines; color="#2a78d6") * config(height=210)
vdraw(plot);
DocsPlots.figure(plot, "start"; caption="Temperature rises at each observation; points mark measurements and the line joins them.") # hide
```

`*` combines a table, its column mappings, and a mark. `vdraw` returns an HTML node; a notebook or web page displays it. The browser draws the figure, so this path needs no Makie rendering backend.

## Next steps

Follow [Measurements](examples/measurements.md) for a complete comparison, or [Intervals](examples/intervals.md) for distribution summaries. The [composition guide](guides/composition.md) explains the algebra; the [output guide](guides/output.md) covers HTML, JSON, and image files.
