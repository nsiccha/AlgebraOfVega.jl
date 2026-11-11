function lint_docs(pages)
    @assert first.(pages) == ["Start", "Guides", "Examples", "Reference"]
    listed = Set(last(p) for (_, group) in pages for p in group)
    actual = Set(relpath(joinpath(root, file), joinpath(@__DIR__, "src"))
                 for (root, _, files) in walkdir(joinpath(@__DIR__, "src"))
                 for file in files if endswith(file, ".md"))
    @assert listed == actual "Page inventory and source pages differ"
    reference = join((read(joinpath(@__DIR__, "src", f), String) for f in listed if startswith(f, "reference/")), "\n")
    for name in names(AlgebraOfVega)
        name == :AlgebraOfVega && continue
        pattern = Regex("(?<![A-Za-z0-9_])" * string(name) * "(?![A-Za-z0-9_])")
        @assert occursin(pattern, reference) "Export missing from reference: $name"
    end
    banned = r"\b(seamless|robust|powerful|leverage|delve|crucial|comprehensive|unlock|simply)\b|it's worth noting"i
    for file in sort!(collect(listed))
        text = read(joinpath(@__DIR__, "src", file), String)
        @assert !occursin(r"(?m)^```(?:julia|jldoctest|python|javascript)\b", text) "Static runnable fence in $file"
        prose = replace(text, r"(?ms)^```.*?^```\s*$" => "")
        @assert !occursin(banned, prose) "Banned prose in $file"
        words = length(split(prose))
        if startswith(file, "guides/")
            @assert words < 1500 "Guide exceeds word limit: $file ($words)"
        elseif startswith(file, "examples/")
            @assert 800 <= words <= 1500 "Example word count: $file ($words; expected 800–1500)"
            @assert occursin("```@example", text) && occursin("DocsPlots.figure", text) "Example must execute and draw: $file"
        end
        @info "Docs lint" file words
    end
end
