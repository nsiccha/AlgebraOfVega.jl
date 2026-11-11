module DocsPlots
using AlgebraOfVega, Documenter, SHA, Markdown
const BUILD = joinpath(@__DIR__, "build")
const PUBLIC = joinpath(BUILD, "public")
const FIGURES = joinpath(PUBLIC, "figures")
function prepare_assets()
    mkpath(PUBLIC)
    cp(joinpath(@__DIR__, "install.jl"), joinpath(PUBLIC, "install.jl"); force=true)
    cp(vega_vendor_dir(), joinpath(PUBLIC, "vendor"); force=true)
end
function figure(spec, id; caption="")
    mkpath(FIGURES)
    write(joinpath(FIGURES, id * ".json"), to_json(spec))
    Base.HTML("""
    <figure class="docs-figure">
    <VegaPlot src="/figures/$id.json" plot-id="docs-$id" />
    <figcaption>$caption</figcaption>
    </figure>
    """)
end
function receipt(file)
    src = read(joinpath(@__DIR__, "src", file))
    revision = readchomp(`git -C $(@__DIR__) rev-parse HEAD`)
    dirty = !isempty(readchomp(`git -C $(@__DIR__) status --porcelain --untracked-files=no`))
    Markdown.parse("""
    | Build input | Value |
    | --- | --- |
    | Package revision | `$revision`$(dirty ? " (working-tree edits present)" : "") |
    | Example SHA-256 | `$(bytes2hex(sha256(src)))` |
    | Julia | `$(VERSION)` |
    | Data | Deterministic values declared on this page; no fitted model or cache. |
    """)
end
end
