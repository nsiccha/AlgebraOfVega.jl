# Snapshot generation and comparison for VL spec regression testing.
#
# Usage (from the repo root or web/ dir):
#   julia --project=web web/src/test/snapshots.jl generate   # save current specs as reference
#   julia --project=web web/src/test/snapshots.jl compare    # compare current specs against saved reference
#
# Each gallery entry gets a deterministic RNG seed based on its ID,
# so reordering entries doesn't change their output.

using Random, JSON

# Load the gallery module (which includes AlgebraOfVega, HTMXObjects, etc.)
# This file lives at web/src/test/snapshots.jl → parent is web/src/
include(joinpath(@__DIR__, "..", "AlgebraOfVegaGallery.jl"))
using .AlgebraOfVegaGallery
using AlgebraOfVega: to_vegalite
using HTMXObjects: Gallery, GalleryItem, find_item

SNAPSHOTS_DIR = joinpath(@__DIR__, "snapshots")

function entry_seed(id::String)
    # Stable seed: hash the ID to a UInt64, use as seed
    hash(id) % UInt32
end

function generate_spec(item::GalleryItem)
    id = item.id
    Random.seed!(entry_seed(id))
    # Run the example in the gallery module's namespace so dataset
    # aliases (cars(), tips(), …) and AoV exports all resolve.
    spec = Base.include(AlgebraOfVegaGallery, item.path)
    # Some examples return an HTMX.Node directly (widgets, custom HTML).
    # Those have no VL JSON representation — store null.
    isnothing(spec) && return id => nothing
    try
        vl = to_vegalite(spec)
        id => vl
    catch e
        if e isa MethodError
            # spec is an HTMX.Node or other non-VL type — expected for
            # interactive widget examples; store null.
            id => nothing
        else
            rethrow(e)
        end
    end
end

function generate_all()
    results = Dict{String,Any}()
    for item in AlgebraOfVegaGallery.APPDATA.gallery.items
        id, vl = generate_spec(item)
        results[id] = vl
    end
    results
end

function save_snapshots(; dir=SNAPSHOTS_DIR)
    mkpath(dir)
    specs = generate_all()
    for (id, vl) in specs
        path = joinpath(dir, "$id.json")
        if isnothing(vl)
            # Entry returns nothing or an HTMX.Node — save null marker
            write(path, "null")
        else
            write(path, JSON.json(vl, 2))
        end
    end
    # Save an index of all entry IDs for staleness detection
    index_path = joinpath(dir, "_index.json")
    write(index_path, JSON.json(sort(collect(keys(specs))), 2))
    println("Saved $(length(specs)) snapshots to $dir")
end

function load_snapshots(; dir=SNAPSHOTS_DIR)
    index_path = joinpath(dir, "_index.json")
    isfile(index_path) || error("No snapshot index at $index_path — run `generate` first")
    ids = JSON.parsefile(index_path)
    specs = Dict{String,Any}()
    for id in ids
        path = joinpath(dir, "$id.json")
        isfile(path) || error("Missing snapshot: $path")
        specs[id] = JSON.parsefile(path)
    end
    specs
end

function compare_snapshots(; dir=SNAPSHOTS_DIR)
    saved = load_snapshots(; dir)
    current = generate_all()

    # Check for missing/extra entries
    saved_ids = Set(keys(saved))
    current_ids = Set(keys(current))
    added = setdiff(current_ids, saved_ids)
    removed = setdiff(saved_ids, current_ids)

    n_pass = 0
    n_fail = 0
    failures = String[]

    if !isempty(added)
        println("NEW entries (no saved snapshot): ", join(sort(collect(added)), ", "))
    end
    if !isempty(removed)
        println("REMOVED entries (snapshot exists but no gallery entry): ", join(sort(collect(removed)), ", "))
    end

    for id in sort(collect(intersect(saved_ids, current_ids)))
        s = saved[id]
        c = current[id]
        if s == c
            n_pass += 1
        else
            n_fail += 1
            push!(failures, id)
            # Show first difference
            s_json = JSON.json(s, 2)
            c_json = JSON.json(c, 2)
            s_lines = split(s_json, '\n')
            c_lines = split(c_json, '\n')
            for i in 1:max(length(s_lines), length(c_lines))
                sl = i <= length(s_lines) ? s_lines[i] : "<missing>"
                cl = i <= length(c_lines) ? c_lines[i] : "<missing>"
                if sl != cl
                    println("FAIL $id — first diff at line $i:")
                    println("  saved:   ", sl)
                    println("  current: ", cl)
                    break
                end
            end
        end
    end

    println("\n$(n_pass) passed, $(n_fail) failed, $(length(added)) new, $(length(removed)) removed")
    if !isempty(failures)
        println("Failed: ", join(failures, ", "))
    end
    n_fail == 0 && isempty(removed)
end

# --- CLI ---
if abspath(PROGRAM_FILE) == @__FILE__
    cmd = length(ARGS) >= 1 ? ARGS[1] : "compare"
    if cmd == "generate"
        save_snapshots()
    elseif cmd == "compare"
        ok = compare_snapshots()
        exit(ok ? 0 : 1)
    else
        println("Usage: julia web/src/test/snapshots.jl [generate|compare]")
        exit(1)
    end
end
