using Documenter, DocumenterVitepress, AlgebraOfVega
import HTMXObjects

# Sync the canonical `htmxo-embed.ts` into our theme dir before
# DocumenterVitepress runs. The theme's `index.ts` imports from it.
HTMXObjects.vitepress_theme_install(joinpath(@__DIR__, "src", ".vitepress", "theme"))

# Generate gallery examples with Vega-Lite specs
include("generate_gallery.jl")

makedocs(
    sitename = "AlgebraOfVega.jl",
    modules  = [AlgebraOfVega],
    format   = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/nsiccha/AlgebraOfVega.jl",
        devurl = "dev",
        devbranch = "dev",
        build_vitepress = false,
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Translation Guide" => "translation.md",
        "Gallery" => "gallery.md",
        "FAQ" => "faq.md",
        "API" => "api.md",
    ],
    checkdocs = :none,
    warnonly = true,
)

# Copy public assets (JSON specs) into VitePress build directory
let src = joinpath(@__DIR__, "src", "public")
    dst = joinpath(@__DIR__, "build", ".documenter", "public")
    if isdir(src)
        cp(src, dst; force=true)
        @info "Copied public assets to $dst"
    end
end

# Build VitePress (after public assets are in place)
DocumenterVitepress.build_docs(joinpath(@__DIR__, "build"))

let redirect = joinpath(@__DIR__, "build", "index.html")
    isfile(redirect) || write(redirect, """
    <!DOCTYPE html>
    <html><head>
    <meta http-equiv="refresh" content="0; url=dev/">
    </head><body>Redirecting to <a href="dev/">dev</a>...</body></html>
    """)
end

DocumenterVitepress.deploydocs(
    repo = "github.com/nsiccha/AlgebraOfVega.jl",
    devbranch = "dev",
    push_preview = true,
)
