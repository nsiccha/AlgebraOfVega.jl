# title: Remap with Pooled (off)
# description: Move a dimension to the "Pooled" channel to drop it from the encoding entirely — its values merge into one ribbon, unlike "Ungrouped" (detail) which splits per value.

# PK-style data: 2 health groups × 2 sites × 50 draws over x
id = "remap-off"
using Random
rng = Random.MersenneTwister(42)
rows = NamedTuple[]
for grp in ["Healthy", "PD"], site in ["US", "EU"]
    offset = (grp == "PD" ? 1.5 : 0.0) + (site == "EU" ? 0.5 : 0.0)
    for d in 1:50, x in range(0, 5, length=20)
        push!(rows, (x=x, y=offset + 0.8x + 0.5randn(rng), draw=d, health=grp, site=site))
    end
end
df = (; (k => getindex.(rows, k) for k in keys(rows[1]))...)
spec = data(df) * mapping(:x, :y, group=:draw, color=:health) *
       lineribbon() * config(title="Remap with Pooled (off)")
# `site` starts in the Pooled channel: absent from the encoding, so its values
# merge into the ribbon. Move it to Color/Row/Ungrouped in the picker to split,
# or move Health to Pooled to merge the two groups into a single line.
auto_remap_node(id, spec; dims=[:health => "Health", :site => "Site"], off=["site"])
