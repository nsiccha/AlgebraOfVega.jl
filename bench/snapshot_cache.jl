# Baseline transport is separate from gallery execution so it can be checked
# without compiling or rendering the gallery.
using Downloads, SHA

const SNAPSHOT_REVISION = "f96a064557589494d2a1b6ae75c16449758009fb"
const SNAPSHOT_REPO = normpath(joinpath(@__DIR__, ".."))
const SNAPSHOT_SOURCE_PATH = "web/src/test/snapshots"
const SNAPSHOT_CACHE = get(ENV, "AOV_SNAPSHOT_CACHE",
    joinpath(get(ENV, "XDG_CACHE_HOME", joinpath(homedir(), ".cache")),
             "AlgebraOfVega", "snapshots", SNAPSHOT_REVISION))

function baseline_file(name; dir=SNAPSHOT_CACHE)
    occursin(r"^[A-Za-z0-9_-]+\.json$", name) || error("Invalid baseline filename: $name")
    path = joinpath(dir, name)
    receipt = path * ".sha256"
    if isfile(path) && isfile(receipt) && bytes2hex(sha256(read(path))) == strip(read(receipt, String))
        return path
    end
    mkpath(dir)
    source = "$SNAPSHOT_SOURCE_PATH/$name"
    bytes = try
        read(pipeline(`git -C $SNAPSHOT_REPO show $SNAPSHOT_REVISION:$source`; stderr=devnull))
    catch
        url = "https://raw.githubusercontent.com/nsiccha/AlgebraOfVega.jl/$SNAPSHOT_REVISION/$source"
        io = IOBuffer()
        Downloads.download(url, io)
        take!(io)
    end
    # A temporary sibling keeps an interrupted download from looking complete.
    temporary, io = mktemp(dir)
    try
        write(io, bytes)
        close(io)
        mv(temporary, path; force=true)
        write(receipt, bytes2hex(sha256(bytes)) * "\n")
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    path
end
