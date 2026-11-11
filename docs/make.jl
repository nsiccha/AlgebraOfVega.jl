using Documenter, DocumenterVitepress, AlgebraOfVega
include("plots.jl")

const PAGES = [
    "Start" => ["First figure" => "index.md"],
    "Guides" => ["Composition" => "guides/composition.md", "Scales" => "guides/scales.md", "Output" => "guides/output.md"],
    "Examples" => ["Measurements" => "examples/measurements.md", "Intervals" => "examples/intervals.md"],
    "Reference" => ["Construction" => "reference/construction.md", "Analyses" => "reference/analyses.md",
                    "Rendering" => "reference/rendering.md", "Data" => "reference/data.md"],
]
include("lint.jl")
lint_docs(PAGES)

makedocs(
    sitename="AlgebraOfVega.jl",
    modules=[AlgebraOfVega],
    format=DocumenterVitepress.MarkdownVitepress(
        repo="github.com/nsiccha/AlgebraOfVega.jl",
        devurl="dev", devbranch="dev",
    ),
    pages=PAGES,
    checkdocs=:exports,
    warnonly=false,
)

# Keep old inbound links useful, without duplicate content in the site nav.
revision = readchomp(`git -C $(@__DIR__) rev-parse HEAD`)
for (i, base) in enumerate(readlines(joinpath(@__DIR__, "build", "bases.txt")))
    output = joinpath(@__DIR__, "build", string(i))
    for (old, target) in ["getting-started"=>"examples/measurements", "translation"=>"guides/composition",
                          "gallery"=>"examples/measurements", "gallery-examples"=>"examples/intervals",
                          "faq"=>"guides/output", "api"=>"reference/construction"]
        write(joinpath(output, old * ".html"), "<!doctype html><html><head><meta http-equiv=\"refresh\" content=\"0;url=$target.html\"></head><body><a href=\"$target.html\">Updated documentation</a></body></html>")
    end
    sitebase = isempty(base) ? "/" : "/AlgebraOfVega.jl/$base/"
    run(`python3 $(joinpath(@__DIR__, "check_site.py")) $output --base $sitebase --revision $revision`)
end
DocumenterVitepress.deploydocs(repo="github.com/nsiccha/AlgebraOfVega.jl", devbranch="dev", push_preview=true)
