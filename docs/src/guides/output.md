# Output

Choose a browser node, a portable specification, or a saved document from the same plot expression.

## Browser nodes

```@example output
using AlgebraOfVega
using Main.DocsPlots # hide
plot = data((time=[0, 1, 2], temperature=[18, 21, 25])) *
    mapping(:time => "Time (min)", :temperature => "Temperature (°C)") *
    visual(Scatter; color="#2a78d6") * config(height=200)
node = vdraw(plot);
DocsPlots.figure(plot, "output"; caption="The browser node draws the three observations from the table.") # hide
```

`vdraw` and `to_node` return HTML nodes. A notebook or web application displays them; terminal printing is not a graphical display. A host page includes `vega_head()` once to load the plotting libraries and the AoV runtime. The runtime handles page themes and browser interactions.

## Documents

A standalone document can contain the libraries it needs.

```@example output
__docs_output__ = begin # hide
html = to_html(to_node(plot; id="saved-plot"); source=:inline)
write("saved-plot.html", html)
(starts_with_doctype=startswith(lstrip(html), "<!DOCTYPE html>"),
 has_plot=occursin("saved-plot", html))
end # hide
show(stdout, MIME"text/plain"(), __docs_output__) # hide
println() # hide
```

Open the generated HTML in a browser. `source=:inline` avoids external script requests; `source=:cdn` uses the package's pinned CDN scripts. For a site that serves its own assets, use `source=:vendor`, mount `vega_vendor_dir()`, and set `base` to that mount's browser URL. `runtime=:linked` then loads the package runtime as a separate cacheable file.

The node form above uses the AoV runtime. The bare `to_html(plot)` form uses Vega-Embed directly and retains Vega's default appearance. Use the node form when the figure should follow its host page's theme.

## Specifications

```@example output
__docs_output__ = begin # hide
specification = to_vegalite(plot; interactive=false)
json = to_json(plot; interactive=false)
write("saved-plot.json", json)
(schema=specification["\$schema"], mark=specification["mark"]["type"])
end # hide
show(stdout, MIME"text/plain"(), __docs_output__) # hide
println() # hide
```

`to_vegalite` returns a Julia dictionary; `to_json` serializes it. These are useful for inspection and integration with a Vega-Lite renderer. `interactive=false` removes automatic interaction parameters; it does not remove explicitly requested selections.

## Images

| Task | Function | Runtime requirement |
| --- | --- | --- |
| Save the Vega-rendered figure as SVG, PNG, or PDF | `vsave(plot, path)` | The vl-convert command-line tool on `PATH`, or `AOV_VL_CONVERT` |
| Save with Makie and return an image node | `sdraw(plot, path)` | A loaded Makie backend |
| Add to a Makie layout | `sdraw!(position, plot)` | A loaded Makie backend |
| Save through Makie | `sdraw_file(plot, path)` | A loaded Makie backend |

These tools are separate rendering paths. The Makie path supports line and precomputed ribbons, but does not support point, gradient, or dot intervals or geographic marks. The documentation environment does not install a static backend or vl-convert, so this guide demonstrates browser and JSON exports and lists image calls without an unevaluated code block.

A figure that updates after insertion needs a stable HTML id. `update_data` replaces raw rows, `append_data` adds rows, and `update_spec` lowers a new object. Use `update_spec` for summaries calculated in Julia; inserting raw observations into an already summarized browser dataset would not recompute its quantiles.

The [measurements example](../examples/measurements.md) saves a complete figure. The [interval example](../examples/intervals.md) shows a summary whose refreshed data require a new lowering.
