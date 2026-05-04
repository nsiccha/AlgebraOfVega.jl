# Record the AoV gallery's HTML/JS/JSON output into `docs/public/live-aov/`
# so VitePress (CI) can ship the recordings as static assets. The deployed
# docs page embeds the gallery via `<div hx-get=".../live-aov/" hx-trigger="load">`,
# fetching the recorded fragments at runtime in the visitor's browser —
# same as the local dev flow (which proxies the live server), but
# resolved against committed files.
#
# Run locally before pushing the docs branch:
#
#     julia --project=web/app docs/record_gallery.jl
#
# The web/app project has the full set of dependencies needed
# (HTMXObjects, CairoMakie, TestModules, etc.). Then `git add
# docs/public/live-aov && git commit && git push` — CI picks up the
# recordings as part of the build.
#
# Override the URL prefix the recordings will be served under via
# `RECORD_BASE_PREFIX`; default `/AlgebraOfVega.jl/dev/live-aov` matches
# the GitHub Pages deploy at `nsiccha.github.io/AlgebraOfVega.jl/dev/`.

using HTMXObjects

include(joinpath(@__DIR__, "..", "web", "src", "AlgebraOfVegaGallery.jl"))
import .AlgebraOfVegaGallery as AoVG

const REPO_ROOT  = dirname(@__DIR__)
const OUTPUT_DIR = joinpath(@__DIR__, "src", "public", "live-aov")
const BASE       = get(ENV, "RECORD_BASE_PREFIX", "/AlgebraOfVega.jl/dev/live-aov")

println("Recording AoV gallery to $OUTPUT_DIR")
println("  record_base = $BASE")
println("  $(length(AoVG._gallery.items)) gallery items")

isdir(OUTPUT_DIR) && rm(OUTPUT_DIR; recursive=true)
mkpath(OUTPUT_DIR)

# Enumerate every URL the embedded gallery hits.
ids = [it.id for it in AoVG._gallery.items]
paths = String[]
push!(paths, "/")                              # gallery index (full + hx)
append!(paths, ["/plot/$id" for id in ids])    # per-card detail
append!(paths, ["/standalone/$id" for id in ids])  # `target=_blank` link
append!(paths, ["/spec/$id" for id in ids])    # raw Vega-Lite JSON
push!(paths, "/aov_runtime_js")                # AoV embed runtime (JS)
push!(paths, "/explorer")                      # data explorer
push!(paths, "/flagged")                       # flagged plots
# `/static_plot/$id` and `/flag/...` are POST or filesystem-bound; skip.

record!(AoVG.AppContext();
    record_dir  = OUTPUT_DIR,
    record_base = BASE,
    paths       = paths,
    full        = true,   # plain GET → page-wrapped HTML
    hx          = true,   # HX-Request: true → body fragment
    markdown    = false,  # AoV gallery has no useful markdown view
)

# Summary
n_html = 0; n_js = 0; n_json = 0; n_other = 0
for (root, _, files) in walkdir(OUTPUT_DIR)
    for f in files
        ext = lowercase(splitext(f)[2])
        ext == ".html" ? (n_html += 1) :
        ext == ".js"   ? (n_js   += 1) :
        ext == ".json" ? (n_json += 1) :
                         (n_other += 1)
    end
end
println("Wrote: $n_html .html, $n_js .js, $n_json .json, $n_other other")
println("Done. Commit `docs/src/public/live-aov/` and push.")
