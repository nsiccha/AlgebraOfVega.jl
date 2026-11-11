# Documentation

The site has four groups. Each page has one purpose.

| Group | Page | Purpose |
| --- | --- | --- |
| Start | `index.md` | Install the package and draw a complete first figure. |
| Guides | `guides/composition.md` | Combine data, mappings, marks, and layers. |
| Guides | `guides/scales.md` | Set units, category order, palettes, and axis scales. |
| Guides | `guides/output.md` | Choose browser nodes, specifications, and saved files. |
| Examples | `examples/measurements.md` | Compare repeated measurements with a reference line. |
| Examples | `examples/intervals.md` | Display distributions and inspect their empirical intervals. |
| Reference | `reference/construction.md` | Composition, mappings, marks, and configuration. |
| Reference | `reference/analyses.md` | Statistical summaries and geographic marks. |
| Reference | `reference/rendering.md` | Rendering, browser updates, captions, and exports. |
| Reference | `reference/data.md` | Tables, sample datasets, and explorer helpers. |

`make.jl` executes examples with strict Documenter checks. Figures are lowered
by the checked-out package and written below `docs/build/`. The existing
`VegaPlot` component uses the package's vendored browser runtime. No live
application or CDN is needed, and no generated figure is tracked.

The build uses Julia, the VitePress Node runtime, and Python 3 for a standard-library link/asset check. Run `julia --project=docs docs/make.jl` after resolving the docs environment.
On a managed KB worktree, use
`kb-acquire-compute-token --here --why 'docs verification' -- kb-run-compact kb-docs-build`.
`install.jl` is the public installer copied into the site; it supplies the
unregistered dependency closure in one Pkg transaction.

The helper supplies the temporary source-link remote and installs JavaScript
dependencies. CI owns deployment.

The former Getting Started, Translation Guide, FAQ, Gallery, and API pages
are replaced by this inventory. The separate generated gallery is removed.
The build emits redirects for the previous public URLs without retaining
duplicate content or navigation entries.

Local lint checks runnable fences, prose, navigation, and example lengths
until DocsKit supplies shared checks. A shared VitePress figure adapter is
also needed; the package's existing component is maintained here meanwhile.

`check_site.py` checks local links and writes a generated manifest. After a dev
deployment, CI waits for that revision and verifies every published file by
SHA-256, including figures and browser libraries.
