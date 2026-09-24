# Prompt: Adopt pre-aggregated `lineribbon(bands=...)` in bruno

## Context

AlgebraOfVega.jl (dev branch, commit f2a4f64) now supports `lineribbon(bands=[:q025 => :q975, :q25 => :q75])` — a pre-aggregated lineribbon that takes quantile columns directly instead of raw draws. This eliminates the `compute_ribbon_summary` aggregation step inside AoV.

**API**:
```julia
# Before (raw draws):
data(df) * mapping(:x, :y; group=:draw, color=:health) * lineribbon()

# After (pre-aggregated):
data(summary_df) * mapping(:x, :median => "Response"; color=:health) *
    lineribbon(bands=[:q025 => :q975, :q25 => :q75])
```

- Second positional = median column (required)
- `bands` = vector of `lo => hi` column name pairs (outermost band first)
- No `group=` mapping (error if combined with `bands`)
- Works with `color=`, `col=`/`row=` faceting, `auto_remap_node`, `config()`

## Where to adopt in bruno

### 1. Simulation tabs in `web-pkpd/src/analysis.jl` — `_sim_tab_plot` callers

The `build_plot` lambdas in these tabs compute population percentiles from `r.rv` (a 3D array: posterior samples × population dimension × doses), then expand into rows with a synthetic `draw` column per posterior sample. These rows are then passed to `lineribbon()` with `group=:draw`, which re-aggregates across the posterior samples to produce uncertainty bands.

With `bands=`, you can compute both the population percentiles AND the posterior uncertainty bands directly in Julia, producing one summary row per dose×group instead of N_posterior_samples rows.

**Files and approximate lines:**
- `analysis.jl:~1630` — dose amplification `build_plot`
- `analysis.jl:~1690` — accumulation ratio `build_plot`
- `analysis.jl:~1760` — fraction response `build_plot`

**Current pattern** (same in all three):
```julia
build_plot=(done, pcts, lkw, doses) -> begin
    df = DataFrame(dose_mg=Float64[], value=Float64[], draw=String[], ...)
    for r in done
        for pct in pcts
            med = mapslices(col -> _nanquantile(col, pct/100), r.rv, dims=2)[:, 1, :]
            for d_idx in 1:size(med, 1), (di, d) in enumerate(doses)
                push!(df, (; dose_mg=Float64(d), value=med[d_idx, di],
                    draw="..._p$(pct)_$d_idx", ...))
            end
        end
    end
    data(_dropnan(df)) * mapping(:dose_mg => "Dose (mg)", :value => "..."; group=:draw, color=:health) *
        lineribbon() * config(...)
end
```

**New pattern**: Compute posterior uncertainty bands directly:
```julia
build_plot=(done, pcts, lkw, doses) -> begin
    df = DataFrame(dose_mg=Float64[], q025=Float64[], q25=Float64[],
                   median=Float64[], q75=Float64[], q975=Float64[], ...)
    for r in done
        for pct in pcts
            # Population percentile across dim 2
            pop_pct = mapslices(col -> _nanquantile(col, pct/100), r.rv, dims=2)[:, 1, :]
            # Now pop_pct is [posterior_samples, doses] — compute uncertainty bands across posterior samples (dim 1)
            for (di, d) in enumerate(doses)
                col = pop_pct[:, di]
                push!(df, (; dose_mg=Float64(d),
                    q025=_nanquantile(col, 0.025), q25=_nanquantile(col, 0.25),
                    median=_nanquantile(col, 0.5), q75=_nanquantile(col, 0.75),
                    q975=_nanquantile(col, 0.975), ...))
            end
        end
    end
    data(_dropnan(df)) * mapping(:dose_mg => "Dose (mg)", :median => "..."; color=:health) *
        lineribbon(bands=[:q025 => :q975, :q25 => :q75]) * config(...)
end
```

This produces fewer rows (1 per dose×pct×group vs N_posterior_samples per dose×pct×group) and skips AoV's internal aggregation.

### 2. Population dose-response in `analysis.jl:~596-618`

Two branches: per-subject view (line ~593) and population view (line ~616). The population view does the same expansion pattern — compute population percentiles, expand across posterior samples into rows, pass to `lineribbon()`. Same conversion as above.

### 3. Population profile view in `analysis.jl:~622-654`

The population profile view (line ~628-654) does the same pattern with time as the x-axis instead of dose.

## What NOT to change

- **Per-subject views** (`view != "population"`) that use actual per-draw data with `group=:draw_id` — these pass real individual draws to lineribbon. Leave as-is.
- **PPC overlays** (`web-pkpd/src/analysis/ppc.jl`) — uses `ppc_overlay()` which internally calls `lineribbon()` with actual draws.
- **Covariate plots** (`web-pkpd/src/analysis/covariates.jl`) — uses actual per-draw data.
- **`_render_subject_timecourse`** in `WebPKPD.jl:~352` — actual per-draw predictions.
- **Mean concentration** (`web-pkpd/src/analysis/mean_conc.jl`) — uses actual draws.
- **`_dr_plot` in `dose_response.jl:~139`** — uses actual draws (`group=:draw`).

## How to verify

1. Start the bruno web-pkpd server
2. Navigate to each simulation tab (dose amplification, accumulation ratio, fraction response)
3. Select a fit, run the simulation
4. Verify the lineribbon plots render correctly with ribbons and median line
5. Test the `auto_remap_node` color/row/column switching still works
6. Compare output visually against the current version — should be identical

## Dependencies

- AlgebraOfVega.jl must be on the `dev` branch (or later, once merged to `main`)
- If bruno uses `bruno/.deps/AlgebraOfVega.jl`, update that checkout to the `dev` branch
- Server restart required once (new `PrecomputedRibbonAnalysis` struct definition), after that Revise handles everything
