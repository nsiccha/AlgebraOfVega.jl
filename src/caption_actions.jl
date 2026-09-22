# Caption-row share/download actions (upstreamed from Bruno).
#
# Bruno's per-card Share / JSON-download buttons used to live as Bruno-local
# helpers (`web-pkpd/src/analysis.jl`, `captions.jl`, `qt.jl`, `qt/fit.jl`).
# They now live here so every AoV consumer gets them. The client-side
# semantics are preserved exactly:
# - the copied link is resolved to an ABSOLUTE URL against `window.location`
#   (correct under the production `/p/<Slug>/` reverse-proxy prefix);
# - `force=` / `plot_height=` params are stripped before copying;
# - the summary `🔗` button stops propagation so it never toggles an
#   enclosing `<details>`.

"""
    clean_share_url(url) -> String

Strip fragment-only params from a shareable card URL: removes `force=` and
`plot_height=` query params, drops a trailing bare `?`, and repairs a leading
`&` into `?` when the strip removed the first param. Pure string function.
"""
function clean_share_url(url::AbstractString)
    clean = replace(url, r"[&?]force=[^&]*" => "")
    clean = replace(clean, r"[&?]plot_height=[^&]*" => "")
    clean = replace(clean, r"\?$" => "")
    if !occursin('?', clean) && occursin('&', clean)
        clean = replace(clean, '&' => '?'; count=1)
    end
    String(clean)
end

# Escape a Julia string for interpolation into a single-quoted JS string
# literal. The pairs apply in a single simultaneous pass, so a backslash
# introduced by one replacement is never re-escaped by the other.
_js_squote(s::AbstractString) = replace(s, "'" => "\\'", "\\" => "\\\\")

"""
    caption_action_inject(rv, action_js) -> Node

Post-hoc caption-action injector: wraps the already-rendered `rv` in an
`h.div` plus a self-removing `<script>` that finds (or creates) the
`.caption-actions` span inside the enclosing `figure.captioned` and runs
`action_js` with it bound as `acts`.

`action_js` is a plain JS string with values already interpolated; it runs
inside `(function(acts){ … })(acts)`, so an early `return` in it exits only
the action while the `sc.remove()` cleanup still runs.
"""
function caption_action_inject(rv, action_js::AbstractString)
    h.div(rv, h.script(Raw("""
        (function(){
            var sc = document.currentScript;
            var fig = sc.closest('figure.captioned') || sc.parentElement;
            var acts = fig && fig.querySelector('.caption-actions');
            if (!acts) {
                var header = fig && fig.querySelector('.caption-header');
                if (!header) return;
                acts = document.createElement('span');
                acts.className = 'caption-actions';
                header.appendChild(acts);
            }
            (function(acts){ $(action_js) })(acts);
            sc.remove();
        })();
    """)))
end

# The Share-button action element, as `action_js` for `caption_action_inject`.
function _share_button_action_js(url::AbstractString, label::AbstractString)
    clean = _js_squote(clean_share_url(url))
    lab = _js_squote(label)
    """
        var btn = document.createElement('button');
        btn.className = 'outline caption-action';
        btn.type = 'button';
        btn.textContent = '$(lab)';
        btn.dataset.url = '$(clean)';
        btn.addEventListener('click', function(){
            var full = new URL(this.dataset.url, window.location.href).href;
            navigator.clipboard.writeText(full).then(function(){
                btn.textContent='Copied!';
                setTimeout(function(){btn.textContent='$(lab)'},1500);
            });
        });
        acts.appendChild(btn);
    """
end

"""
    caption_share_button(url; label="Share") -> Node

A first-class caption-row Share button: copies the absolute card URL (see
[`clean_share_url`](@ref)) to the clipboard and flashes `Copied!`. For use
directly in a caption `actions` row (e.g. `with_plot_caption(...;
share_url=...)`, which wires this for you).
"""
function caption_share_button(url::AbstractString; label::AbstractString="Share")
    clean = clean_share_url(url)
    lab = _js_squote(label)
    h.button(label;
        type="button", class="outline caption-action",
        data_url=clean,
        onclick="var b=this;var full=new URL(b.dataset.url,window.location.href).href;" *
                "navigator.clipboard.writeText(full).then(function(){b.textContent='Copied!';" *
                "setTimeout(function(){b.textContent='$(lab)'},1500);});")
end

"""
    with_caption_share(rv, url; label="Share") -> Node

Wrap the already-rendered `rv` so a Share button is injected into its
caption-actions row (via [`caption_action_inject`](@ref)). Same clipboard
semantics as [`caption_share_button`](@ref); use this form when the figure
was rendered elsewhere and only needs the button added afterwards.
"""
with_caption_share(rv, url::AbstractString; label::AbstractString="Share") =
    caption_action_inject(rv, _share_button_action_js(url, label))

"""
    with_caption_download(rv, url, label, filename) -> Node

Wrap the already-rendered `rv` so an `<a download>` link is injected into
its caption-actions row (via [`caption_action_inject`](@ref)). Unlike the
share helpers the `url` is used verbatim (no param stripping).
"""
function with_caption_download(rv, url::AbstractString, label::AbstractString, filename::AbstractString)
    # Bruno's original spliced these raw; escaping only changes bytes when a
    # quote/backslash is actually present, in which case the raw form broke.
    u, lab, fn = _js_squote(url), _js_squote(label), _js_squote(filename)
    caption_action_inject(rv, """
        var a = document.createElement('a');
        a.className = 'outline caption-action';
        a.setAttribute('role', 'button');
        a.textContent = '$(lab)';
        a.href = '$(u)';
        a.setAttribute('download', '$(fn)');
        acts.appendChild(a);
    """)
end

"""
    summary_share_button(url) -> Node

A `🔗` share button for a `<summary>` line (e.g. a lazy `<details>` summary):
copies the absolute URL (see [`clean_share_url`](@ref)) and flashes `✓`.
`stopPropagation` keeps the click from toggling the enclosing `<details>`.
Unlike [`with_caption_share`](@ref) this needs no `figure.captioned` — it is
the summary-shaped sibling for bare summaries.
"""
function summary_share_button(url::AbstractString)
    h.span(; class="lazy-share")(
        " ",
        h.button("🔗"; type="button", class="btn-tiny secondary outline",
            title="Copy a shareable link to this view", aria_label="Copy shareable link",
            data_url=clean_share_url(url)),
        h.script(Raw("""
            (function(){
                var sc=document.currentScript, btn=sc.previousElementSibling;
                btn.addEventListener('click', function(e){
                    e.preventDefault(); e.stopPropagation();
                    var full=new URL(btn.dataset.url, window.location.href).href;
                    navigator.clipboard.writeText(full).then(function(){
                        btn.textContent='✓';
                        setTimeout(function(){btn.textContent='🔗'}, 1500);
                    });
                });
                sc.remove();
            })();
        """)),
    )
end
