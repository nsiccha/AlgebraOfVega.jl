# Vendored Vega / Vega-Lite / Vega-Embed builds

Exact-pinned browser builds served by `vega_head(; source=:vendor|:inline)`
and `to_html(...; source=:inline)` so AoV plots render with no CDN access.
`:cdn` (the default) serves these same builds from jsDelivr with
subresource-integrity hashes; the three modes render identical output.

| File              | Package    | Version | sha256                                                           |
|-------------------|------------|---------|------------------------------------------------------------------|
| vega.min.js       | vega       | 5.33.1  | 463f3db6a40b20e9747b4ed38f37ed0add508838f9141b1cf8366784b07b30c8 |
| vega-lite.min.js  | vega-lite  | 5.23.0  | 58c27358e26f2d319cf62f45bc17a4c8362f08645001df2ec8d341eee4097c7f |
| vega-embed.min.js | vega-embed | 6.29.0  | 12d02acfbe3ec59ef9a37dd4822a2e04e2961b5bbb671bbe661d2221715b99da |

Provenance: `https://cdn.jsdelivr.net/npm/<pkg>@<version>/build/<file>`,
byte-identical to the bare `https://cdn.jsdelivr.net/npm/<pkg>@<version>` URL
the major-only tags used to resolve to (verified 2026-09-28). Bytes are stored
pristine, including the trailing `sourceMappingURL` comments (a missing `.map`
fails silently in devtools; no runtime effect).

Update recipe (bump the trio):

1. Download the three `build/*.min.js` files at the new versions and confirm
   each is byte-identical to its bare-URL form.
2. Replace the files here; update the table above.
3. Update `VEGA_VERSION` / `VEGALITE_VERSION` / `VEGA_EMBED_VERSION` and the
   `*_SRI` (sha384) constants in `src/js_runtime.jl`.
4. Update the sha256 lock in `test/items.jl` ("vendored vega trio" testitem).
