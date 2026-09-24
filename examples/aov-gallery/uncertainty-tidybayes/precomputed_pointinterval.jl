# title: Pre-aggregated Point + Interval
# description: pointinterval from pre-computed quantile columns (no draws)

raw = posterior_draws()
summary = _preaggregate((; y=raw.value, parameter=raw.parameter), :parameter)
data(summary) * mapping(:median, y=:parameter) *
    pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
    config(width=500, height=200, title="Pre-aggregated Point + Interval")
