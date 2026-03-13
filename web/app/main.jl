using Revise
using AlgebraOfVegaGallery

begin
    AlgebraOfVegaGallery.terminate()
    port = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8095
    AlgebraOfVegaGallery.serve(; host="0.0.0.0", revise=:lazy, port, async=true)
end
