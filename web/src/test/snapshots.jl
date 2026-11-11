# Compatibility entry point; generated baselines live in a user cache.
include(joinpath(@__DIR__, "..", "..", "..", "bench", "snapshots.jl"))
if abspath(PROGRAM_FILE) == @__FILE__
    snapshots_main()
end
