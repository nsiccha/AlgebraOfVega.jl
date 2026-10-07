using TestItemRunner

# A loopback HTTP origin for browser items that need one: pages loading
# `vega_head(source=:vendor)` assets, and `fetch`, which file:// pages cannot
# use. Serves `dir` at `/<mount>/` and `vega_vendor_dir()` at `/vendor/` through
# HTMXObjects' own `staticfiles`, the way an app does, with the far-future
# cache lifetime the content-versioned `?v=` URLs allow. The port is free at
# bind time: a fixed one collides with whatever else runs on a shared host.
@testmodule AoVBrowserServer begin
import Sockets
using HTMXObjects, AlgebraOfVega
export with_page_server

const VENDOR_HEADERS = ["Cache-Control" => "public, max-age=31536000, immutable"]

function with_page_server(f, dir)
    socket = Sockets.listen(Sockets.localhost, 0)
    port = Int(Sockets.getsockname(socket)[2])
    close(socket)
    mount = "aov-test-" * basename(dir)
    staticfiles(dir, mount)
    staticfiles(vega_vendor_dir(), "vendor"; headers=VENDOR_HEADERS)
    server = HTMXObjects.serve(; host="127.0.0.1", port, async=true,
        access_log=nothing, runtime_tracking=false)
    try
        f("http://127.0.0.1:$port/$mount")
    finally
        close(server)
    end
end
end
