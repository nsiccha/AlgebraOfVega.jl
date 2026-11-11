# Specification regression fixtures

The gallery comparison is a developer tool, separate from the documentation.
It generates Vega-Lite specifications from the example sources and compares
against the previously reviewed baseline.

```sh
julia --project=web bench/snapshots.jl compare
julia --project=web bench/snapshots.jl generate
```

Resolve the `web/` environment first. The original command at
`web/src/test/snapshots.jl` remains a forwarding entry point.

The baseline is pinned to public revision
`f96a064557589494d2a1b6ae75c16449758009fb`, under its original
`web/src/test/snapshots/` directory. `snapshot_cache.jl` reads those exact bytes
from local Git history, or the public raw-file URL when a shallow checkout
lacks that revision. It caches each file with a SHA-256 receipt under
`$XDG_CACHE_HOME/AlgebraOfVega/snapshots/<revision>` (default `~/.cache`).
`AOV_SNAPSHOT_CACHE` overrides that directory. A damaged cache entry is replaced.
The cache contains no fitted model and performs no sampling.

`generate` writes a separate `generated/` cache directory. It does not replace
the comparison baseline or create tracked JSON. A deliberate baseline update
must review the changed specifications and publish them outside the repository;
then update the pinned source in `snapshot_cache.jl`. The current baseline's
known gallery drift is preserved by this transport change.

The fixtures use the package's sample tables and synthetic example inputs.
The documentation's new measurements and intervals are independently declared
teaching data; neither needs these regression fixtures or a cached fit.
