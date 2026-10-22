# vsave.jl — write the Vega-Lite figure to a PDF, SVG or PNG file
# (snag `static-pdf-expor-6f71e52e`, design decision `0qoxatl`).
#
# `sdraw`/`sdraw_file` draw through Makie, which has no analogue for a
# `geoshape` map or the interval analyses. `vsave` writes the figure `vdraw`
# shows instead: it lowers with `to_vegalite(spec; interactive=false)` and
# hands the spec to the vl-convert command-line tool
# (https://github.com/vega/vl-convert), which embeds Vega and Vega-Lite and
# renders without a browser. The tool is external, found through
# `ENV["AOV_VL_CONVERT"]` or `PATH`, so AoV gains no Julia dependency.

const _VSAVE_SUBCOMMANDS = Dict(".pdf" => "vl2pdf", ".svg" => "vl2svg", ".png" => "vl2png")
const _VSAVE_LOCALES = Dict(:de => "de-DE", :en => "en-US")
const _VSAVE_URL_FORMATS = Dict(".csv" => "csv", ".tsv" => "tsv", ".topojson" => "topojson")

"""
    vsave(spec, path; locale=nothing, scale=nothing, ppi=nothing, auto_remap=nothing) -> path
    vsave(spec, scales(...), path; kwargs...) -> path

Write the figure `vdraw(spec)` shows to a file, as PDF, SVG or PNG by the
extension of `path`, and return `path`. Every AoV figure works, including
`geoshape` maps with longitude/latitude marks and the interval analyses that
`sdraw` cannot draw. The file has Vega's own print look: white background,
dark text, the figure's own palette. Interactive parts (zoom, legend
selection, tooltips, a frame player) are left out; a `config(frame=…)`
figure shows its `start` frame.

The figure is rendered by the [vl-convert](https://github.com/vega/vl-convert/releases)
command-line tool (AoV is tested with 1.9.0). Put it on `PATH` or set
`ENV["AOV_VL_CONVERT"]` to its path; a missing tool is an error that says so.

- `locale`: number and date formats, `:de` (`1.234,5`), `:en`, or a d3 locale
  name such as `"fr-FR"`. Default: vl-convert's English.
- `scale`, `ppi`: PNG resolution (`scale=2` doubles the pixel size). A PDF or
  SVG is vector output and takes neither.
- `auto_remap`: a channel-picker figure's keywords, as for
  [`to_vegalite`](@ref), to write the figure that picker shows first.

Size the figure with `config(width=…, height=…)`; without them Vega-Lite's
defaults apply. A data URL naming a local file — such as
`geoshape("districts.geojson")`, read relative to the current directory — is
read into the spec, because vl-convert loads no local files; an `http(s)` URL is
left to vl-convert.

    for (name, rows) in regions
        vsave(data(rows) * mapping(:AGS; color=:share) * geoshape(geo) *
              config(title=name, width=500, height=500), "maps/\$name.pdf";
              locale=:de)
    end
"""
function vsave(spec, path::AbstractString; auto_remap::Union{Nothing,NamedTuple}=nothing, kwargs...)
    cmd = _vsave_command(path; kwargs...)
    _vsave_render(to_vegalite(spec; interactive=false, auto_remap), path, cmd)
end

function vsave(spec, sc::AlgebraOfGraphics.Scales, path::AbstractString;
               auto_remap::Union{Nothing,NamedTuple}=nothing, kwargs...)
    cmd = _vsave_command(path; kwargs...)
    _vsave_render(to_vegalite(spec, sc; interactive=false, auto_remap), path, cmd)
end

# The vl-convert invocation for `path`, checked before the figure is lowered.
function _vsave_command(path::AbstractString; locale=nothing, scale=nothing, ppi=nothing)
    ext = lowercase(last(splitext(path)))
    sub = get(_VSAVE_SUBCOMMANDS, ext, nothing)
    isnothing(sub) && throw(ArgumentError(
        "vsave: cannot tell the file format from \"$path\"; end the path in .pdf, .svg or .png"))
    opts = String[]
    if sub == "vl2png"
        isnothing(scale) || push!(opts, "--scale", string(scale))
        isnothing(ppi) || push!(opts, "--ppi", string(ppi))
    elseif !(isnothing(scale) && isnothing(ppi))
        throw(ArgumentError("vsave: `scale` and `ppi` set a PNG's resolution; a $(ext[2:end]) file is vector output and takes neither"))
    end
    if !isnothing(locale)
        name = _vsave_locale(locale)
        push!(opts, "--format-locale", name, "--time-format-locale", name)
    end
    `$(_vl_convert()) $sub $opts`
end

_vsave_locale(l::AbstractString) = String(l)
_vsave_locale(l::Symbol) = get(_VSAVE_LOCALES, l) do
    throw(ArgumentError("vsave: unknown locale :$l; use :de, :en or a d3 locale name such as \"fr-FR\""))
end

function _vl_convert()
    exe = get(ENV, "AOV_VL_CONVERT", "")
    if !isempty(exe)
        isfile(exe) || error("vsave: ENV[\"AOV_VL_CONVERT\"] is \"$exe\", which is not a file; point it at the vl-convert executable")
        return exe
    end
    found = Sys.which("vl-convert")
    isnothing(found) && error("vsave needs the vl-convert command-line tool, which is not on PATH. " *
        "Download it from https://github.com/vega/vl-convert/releases (AoV is tested with 1.9.0), " *
        "then put it on PATH or set ENV[\"AOV_VL_CONVERT\"] to its path.")
    found
end

function _vsave_render(vl, path::AbstractString, cmd::Cmd)
    mktempdir() do dir
        input = joinpath(dir, "figure.vl.json")
        write(input, _vl_json(_vsave_inline_data(vl)))
        err = IOBuffer()
        success(pipeline(`$cmd --input $input --output $path`; stdout=devnull, stderr=err)) ||
            error("vsave: vl-convert could not write \"$path\":\n" * String(take!(err)))
    end
    path
end

# vl-convert loads no local file: a `geoshape(...)` URL naming a .geojson on
# disk — relative, absolute or file:// — renders an empty map with exit 0 and
# no warning (measured with vl-convert 1.9.0). So every Vega-Lite URL data
# object (`url`, optional `format`/`name`) naming a local file is read into the
# spec; http(s) and data: URLs stay. The walk copies the objects on its way and
# never writes into the lowered spec, which `to_vegalite(::Dict)` returns as the
# caller's own Dict; inline `values` payloads are shared, not walked.
_vsave_inline_data(x) = x
_vsave_inline_data(v::AbstractVector) = Any[_vsave_inline_data(e) for e in v]
function _vsave_inline_data(d::AbstractDict)
    url = get(d, "url", nothing)
    if url isa AbstractString && all(k -> string(k) in ("url", "format", "name"), keys(d))
        file = _vsave_local_file(url)
        isnothing(file) || return _vsave_file_data(d, url, file)
    end
    Dict{String,Any}(string(k) => (string(k) == "values" ? v : _vsave_inline_data(v)) for (k, v) in d)
end

function _vsave_local_file(url::AbstractString)
    lower = lowercase(url)
    startswith(lower, "file://") && return url[8:end]
    (startswith(lower, "data:") || occursin(r"^[a-z][a-z0-9+.-]*://", lower)) && return nothing
    url
end

function _vsave_file_data(d::AbstractDict, url::AbstractString, file::AbstractString)
    path = abspath(file)
    isfile(path) || throw(ArgumentError(
        "vsave: the data URL \"$url\" names no file ($path); a local path is read relative to the current directory"))
    format = Dict{String,Any}(string(k) => v for (k, v) in get(d, "format", Dict{String,Any}()))
    kind = get!(() -> get(_VSAVE_URL_FORMATS, lowercase(last(splitext(path))), "json"), format, "type")
    values = kind in ("json", "topojson") ?
        JSON.parse(read(path, String); dicttype=Dict{String,Any}) : read(path, String)
    out = Dict{String,Any}("values" => values, "format" => format)
    haskey(d, "name") && (out["name"] = d["name"])
    out
end
