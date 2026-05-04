# title: Remap Pre-agg. PI — positional dim
# description: BRM-style repro: horizontal PI with :index on x (positional), :param on row (named). Verifies the pinned catch-all leaves positionally-assigned fields alone rather than combining them (was producing a `param/index` combo and „/ undefined“ titles).

raw = posterior_draws()
# Build a fake long-form summary: 3 params × 2 index positions, pre-aggregated.
params = repeat(["α", "β", "σ"]; inner=2)
indices = repeat(string.(1:2); outer=3)
medians = [2.0, 2.1, 0.8, 0.85, 1.2, 1.25]
q025s   = [1.5, 1.6, 0.5, 0.55, 1.0, 1.05]
q975s   = [2.5, 2.6, 1.1, 1.15, 1.4, 1.45]
summary = (; param=params, index=indices, median=medians, q025=q025s, q975=q975s)
spec = data(summary) *
       mapping(:index, :median, row=:param) *   # :index on x (positional); :param on row
       pointinterval(bands=[:q025 => :q975], orientation=:vertical) *
       config(width=400, height=150, title="BRM-style: positional :index + row=:param")
auto_remap_node("remap-pi-positional", spec;
    dims=["param" => "Parameter", "index" => "Index"],
    pinned=:row)
