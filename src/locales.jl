# The pristine d3 definitions and their licenses live in vendor/locales/.
const _VEGA_LOCALE_NAMES = Dict(:de => "de-DE", :en => "en-US")
const _VEGA_LOCALES = Dict(lang => Dict(kind => let
    path = joinpath(@__DIR__, "..", "vendor", "locales", package, "$name.json")
    Base.include_dependency(path)
    JSON.parse(read(path, String); dicttype=Dict{String,Any})
end for (kind, package) in ("number" => "d3-format", "time" => "d3-time-format"))
    for (lang, name) in _VEGA_LOCALE_NAMES)

"""
    locale_config(lang::Symbol=:en) -> Config

Number and time locale for Vega plots: `:de` selects d3's German (`de-DE`)
definitions, `:en` selects US English (`en-US`, Vega's default). Unknown names
throw `ArgumentError`. The definitions are bundled; no download is needed.

Multiply it with a plot or another [`config`](@ref), for example
`spec * locale_config(:de) * config(config=(; legend=(; orient="top")))`.
It sets `config.locale.number` and `config.locale.time`, leaving axis, legend,
and format choices to the plot. `:en` explicitly restores English when composed
after `:de`. Each call owns its data, so editing one config affects no other.

The locale supplies decimal/group separators, currency, day/month names and
the `%x`/`%X`/`%c` time formats. For a particular date or tick layout, compose
`config(config=(; timeFormat="%d.%m.%Y", axisTemporal=(; format="%d.%m.%Y")))`.
Caption and control labels use [`plot_texts`](@ref) separately. This is a Vega
setting (`vdraw`, `to_vegalite`, `vsave`); Makie's `sdraw` ignores it.
"""
function locale_config(lang::Symbol=:en)
    locale = get(_VEGA_LOCALES, lang) do
        throw(ArgumentError("locale_config: unknown locale :$lang; use :de or :en"))
    end
    config(config=(; locale))
end
