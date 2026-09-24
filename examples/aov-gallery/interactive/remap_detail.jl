# title: Remap with Detail
# description: Lineribbon with extra grouping dimensions via detail= for client-side remapping

# Simulate PK-style data: 2 assays × 2 groups × 2 sites × 50 draws
id = "remap-detail"
using Random
rng = Random.MersenneTwister(42)
rows = NamedTuple[]
for assay in ["CSF", "PBMC"], grp in ["Healthy", "PD"], site in ["US", "EU"]
    offset = (assay == "CSF" ? 0.0 : -2.0) + (grp == "PD" ? 1.5 : 0.0) + (site == "EU" ? 0.5 : 0.0)
    for d in 1:50, x in range(0, 5, length=20)
        push!(rows, (x=x, y=offset + 0.8x + 0.5randn(rng), draw=d, assay=assay, health=grp, site=site))
    end
end
df = (; (k => getindex.(rows, k) for k in keys(rows[1]))...)
spec = data(df) * mapping(:x, :y, group=:draw, color=:health, col=:assay) *
       lineribbon(; detail=[:site]) * config(title="Remap with Detail")
auto_remap_node(id, spec; dims=[:health => "Health", :site => "Site"],
    fixed=Dict(:column => "assay"))
