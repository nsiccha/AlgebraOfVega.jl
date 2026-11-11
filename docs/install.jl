# Run in the Julia environment where AlgebraOfVega should be installed.
# The package currently depends on unregistered packages; resolve the complete
# public dependency set together, as in the documentation CI workflow.
using Pkg
Pkg.add([
    PackageSpec(url="https://github.com/nsiccha/$name.jl", rev=revision)
    for (name, revision) in [
        ("DynamicObjects", "pre-inference"),
        ("HTMX", "dev"),
        ("HTMXObjects", "devibe"),
        ("Treebars", "main"),
        ("AlgebraOfVega", "dev"),
    ]
])
