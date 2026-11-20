module AlgebraOfVegaMakiePlotTypesExt

# Makie's own plot types and values in an AoV spec, once Makie is loaded (with
# or without AlgebraOfGraphics): `visual(Makie.Text)`, `histogram(Makie.BarPlot)`,
# `Makie.automatic` and `scale=Makie.pseudolog10` mean what AoV's own spellings
# mean. Drawing with Makie is the separate `AlgebraOfVegaMakieExt`, which also
# needs AlgebraOfGraphics.

import Makie
using AlgebraOfVega: AlgebraOfVega
using AlgebraOfVega.PlotTypes: Plot

# `Makie.Scatter` ↔ `Plot{:scatter}`: the token names the plotting function.
_aov_plottype(T::Type{<:Makie.Plot}) = Plot{nameof(Makie.plotfunc(T))}

AlgebraOfVega.visual(T::Type{<:Makie.Plot}; kwargs...) = AlgebraOfVega.visual(_aov_plottype(T); kwargs...)
AlgebraOfVega.histogram(T::Type{<:Makie.Plot}; options...) = AlgebraOfVega.histogram(_aov_plottype(T); options...)

# In a `mapping` or `scales(...)`, Makie's `automatic` and `pseudolog10` are
# AoV's `automatic` and `symlog` (see `AlgebraOfVega._selector`).
AlgebraOfVega._selector(::Makie.Automatic) = AlgebraOfVega.automatic
AlgebraOfVega._selector(f::Makie.ReversibleScale) = f === Makie.pseudolog10 ? AlgebraOfVega.symlog : f

# `scale=Makie.pseudolog10` anywhere a Vega-Lite scale function is read (also a
# per-panel `Dict` value) is `symlog`, which it was before AoV owned the name.
AlgebraOfVega._aog_scale_fn_to_vl(f::Makie.ReversibleScale) = f === Makie.pseudolog10 ?
    AlgebraOfVega._aog_scale_fn_to_vl(AlgebraOfVega.symlog) :
    invoke(AlgebraOfVega._aog_scale_fn_to_vl, Tuple{Any}, f)

end # module
