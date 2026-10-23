using TestItemRunner

# AoV's no-zero default (`scale.zero=false` on quantitative x/y) is decided on
# the finished spec, per shared scale. Vega-Lite drops `zero` from a log scale and
# logs `y-scale's "zero" is dropped as it does not work with log scale.` once per
# encoding: the default used to run before config lowering, so every log-scaled
# encoding carried AoV's `zero=false`, and a layered or faceted figure flooded the
# browser console (17 warnings on one page; snag `log-scale-zero-w-7b997a94`).
@testsnippet AoVNoZeroFixtures begin
    using AlgebraOfVega

    n = 24
    t = (x=repeat(1.0:6.0, 4), q50=exp.(range(0, 3; length=n)),
         q025=exp.(range(-0.5, 2.5; length=n)), q975=exp.(range(0.5, 3.5; length=n)),
         q25=exp.(range(-0.2, 2.8; length=n)), q75=exp.(range(0.2, 3.2; length=n)),
         method=repeat(["a", "b", "c", "d"]; inner=6), col=repeat(["L", "R"]; inner=12))
    ylog = scales(Y=(; scale=log10))
    scatter = data(t) * mapping(:x, :q50) * visual(Scatter)

    # Every Vega-Lite unit (a dict with a `mark`), in emission order.
    function units(node, out=Dict{String,Any}[])
        node isa Dict || return out
        haskey(node, "mark") && push!(out, node)
        for key in ("layer", "hconcat", "vconcat", "concat")
            for child in get(node, key, Any[])
                units(child, out)
            end
        end
        haskey(node, "spec") && units(node["spec"], out)
        out
    end
    scale(u, ch) = get(u["encoding"][ch], "scale", Dict{String,Any}())
    # No unit's `ch` carries a `zero`, and every one is log.
    log_without_zero(vl, ch="y") = all(u -> scale(u, ch) == Dict("type" => "log"), units(vl))
    # The linear `x` keeps AoV's default everywhere.
    x_default(vl) = all(u -> scale(u, "x") == Dict("zero" => false), units(vl))
end

@testitem "log-scaled y carries no zero default: config, positional and raw forms" setup=[AoVNoZeroFixtures] tags=[:translation, :config, :regression] begin
    # The reported shapes: a pointinterval, and lineribbon + Lines + Scatter layers
    # faceted by column, both with `config(scales=scales(Y=(; scale=log10)))`.
    vl = to_vegalite(data(t) * mapping(:x, :q50; color=:method) *
        pointinterval(bands=[:q025 => :q975, :q25 => :q75], orientation=:vertical) *
        config(scales=ylog))
    @test length(units(vl)) == 3
    @test log_without_zero(vl)

    base = data(t) * mapping(:x, :q50; col=:col)
    vl = to_vegalite((base * lineribbon(bands=[:q025 => :q975]) + base * visual(Lines) +
        base * visual(Scatter)) * config(scales=ylog))
    @test haskey(vl, "facet") && length(units(vl)) == 4
    @test log_without_zero(vl) && x_default(vl)

    # The positional `scales` form and a raw encoding override.
    for vl in (to_vegalite(scatter, ylog),
               to_vegalite(scatter * config(encoding=Dict("y" => Dict("scale" => Dict("type" => "log"))))))
        @test log_without_zero(vl) && x_default(vl)
    end
    # log2/ln and an x-axis log the same way.
    @test scale(to_vegalite(scatter, scales(Y=(; scale=log2))), "y") == Dict("type" => "log", "base" => 2)
    vl = to_vegalite(scatter * config(scales=scales(X=(; scale=log10))))
    @test log_without_zero(vl, "x") && scale(units(vl)[1], "y") == Dict("zero" => false)

    # The channel-picker lowering, plain and with the positional `scales` form.
    picked = data(t) * mapping(:x, :q50; color=:method) * visual(Scatter)
    remap = (; dims=["method" => "Method"])
    for vl in (to_vegalite(picked * config(scales=ylog); auto_remap=remap),
               to_vegalite(picked, ylog; auto_remap=remap))
        @test log_without_zero(vl) && x_default(vl)
    end
end

@testitem "no-zero default follows shared scales and keeps a caller's zero" setup=[AoVNoZeroFixtures] tags=[:translation, :config, :regression] begin
    # One summand sets the log; the other layer shares that y scale, so neither
    # gets the default (Vega-Lite would drop it from both).
    logged = scatter * config(encoding=Dict("y" => Dict("scale" => Dict("type" => "log"))))
    lines = data(t) * mapping(:x, :q75) * visual(Lines)
    vl = to_vegalite(logged + lines)
    @test [scale(u, "y") for u in units(vl)] == [Dict("type" => "log"), Dict{String,Any}()]
    @test x_default(vl)
    # With independent y scales the linear layer keeps its default.
    vl = to_vegalite((logged + lines) * config(resolve=Dict("scale" => Dict("y" => "independent"))))
    @test [scale(u, "y") for u in units(vl)] == [Dict("type" => "log"), Dict("zero" => false)]

    # Per-column Y scales: each column view has its own y scale.
    vl = to_vegalite(data(t) * mapping(:x, :q50; col=:col) * visual(Scatter) *
        config(scales=scales(Y=(; scale=Dict("L" => log10)))))
    @test haskey(vl, "hconcat")
    @test [scale(u, "y") for u in units(vl)] == [Dict("type" => "log"), Dict("zero" => false)]

    # Scale types that take zero keep the default.
    for (fn, type) in ((sqrt, "sqrt"), (symlog, "symlog"))
        @test scale(to_vegalite(scatter * config(scales=scales(Y=(; scale=fn)))), "y") ==
            Dict("type" => type, "zero" => false)
    end
    @test x_default(to_vegalite(scatter)) && scale(units(to_vegalite(scatter))[1], "y") == Dict("zero" => false)

    # A zero the caller writes passes through verbatim, log or not.
    for zero in (false, true)
        @test scale(to_vegalite(scatter * config(scales=scales(Y=(; scale=log10, zero)))), "y") ==
            Dict("type" => "log", "zero" => zero)
    end
    @test scale(to_vegalite(scatter * config(scales=scales(Y=(; zero=true)))), "y") == Dict("zero" => true)

    # A raw Vega-Lite Dict is the caller's spec: the positional form adds the log
    # and no default.
    raw = Dict{String,Any}("mark" => "point", "data" => Dict{String,Any}("values" => [Dict("x" => 1, "y" => 2)]),
        "encoding" => Dict{String,Any}("x" => Dict{String,Any}("field" => "x", "type" => "quantitative"),
                                       "y" => Dict{String,Any}("field" => "y", "type" => "quantitative")))
    vl = to_vegalite(raw, scales(X=(; scale=sqrt)))
    @test vl["encoding"]["x"]["scale"] == Dict("type" => "sqrt") && !haskey(vl["encoding"]["y"], "scale")
end
