using Revise
includet(joinpath(@__DIR__, "..", "gallery.jl"))

begin
    Gallery.terminate()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8000
    Gallery.serve(; host="0.0.0.0", revise=:lazy, port, async=true)
end
