using Documenter, DocumenterVitepress, AlgebraOfVega

makedocs(
    sitename = "AlgebraOfVega.jl",
    modules  = [AlgebraOfVega],
    format   = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/nsiccha/AlgebraOfVega.jl",
        devurl = "dev",
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Translation Guide" => "translation.md",
        "Interactivity" => "interactivity.md",
        "Uncertainty Visualization" => "uncertainty.md",
        "Gallery" => "gallery.md",
        "API" => "api.md",
    ],
    checkdocs = :none,
    warnonly = true,
)

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
    devbranch = "main",
    push_preview = true,
)
