# title: Explicitly dodged intervals
# description: Use dodge_y to separate several interval estimates at one categorical position; color can remain an independent visual mapping.

interval_draws = (
    value = repeat([-0.15, 0.0, 0.1, 0.2], 3) .+ repeat([-0.35, 0.0, 0.35], inner=4),
    margin = fill("Random-effect SD", 12),
    model = repeat(["Prior", "PK only", "Joint"], inner=4),
    source = fill("Estimate", 12),
)

data(interval_draws) *
mapping(:value, y=:margin, color=:source, dodge_y=:model) *
pointinterval() *
config(width=500, height=140, title="Explicit interval dodge")
