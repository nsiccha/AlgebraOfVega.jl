"""
    PlotTexts

The words AoV's own plot chrome shows: the caption's "More" toggle, the
caption row's download and Share buttons, the "Show data" preview and its
summary table, the channel picker's labels, and standalone HTML exports. Build one with [`plot_texts`](@ref) and
pass it as `texts=` to `with_plot_caption`, `to_html`, [`auto_remap_node`](@ref),
[`mapping_controls`](@ref), [`caption_share_button`](@ref),
[`with_caption_share`](@ref) or [`summary_share_button`](@ref).

A text in braces is a placeholder AoV fills in: `image` takes `{format}`
(`PNG`, `SVG`); `interval` takes `{point}` (the `median` text) and `{width}`
(`95%`).
"""
struct PlotTexts
    more::String            # the caption's toggle that opens its long text
    csv::String             # caption button: download the plot's data as CSV
    image::String           # caption button: download an image
    html::String            # caption button: download the card as one HTML file
    share::String           # caption Share button
    copied::String          # a Share button's flash after copying
    copy_link::String       # accessible name of a summary line's 🔗 button
    copy_link_hint::String  # tooltip of a summary line's 🔗 button
    show_data::String       # the data preview's disclosure
    show_summary::String    # the disclosure when only a summary table is shown
    pretty::String          # preview toggle: the summary table
    raw::String             # preview toggle: the raw rows
    no_data::String         # raw preview of a plot without data
    no_summary::String      # summary preview without summary rows
    median::String          # the summary's point estimate
    interval::String        # the summary table's caption
    value::String           # header of the summary's value column when the value has no name
    color::String           # channel picker labels
    row::String
    column::String
    ungrouped::String
    pooled::String
    x::String
    y::String
    untitled::String        # title of a standalone HTML page without a caption title
    lang::String            # `lang` of a standalone HTML page
end

const _PLOT_TEXT_PLACEHOLDERS = (image = (:format,), interval = (:point, :width))

const _PLOT_TEXT_LOCALES = (
    en = (
        more = "More",
        csv = "⬇ CSV",
        image = "⬇ {format}",
        html = "⬇ HTML",
        share = "Share",
        copied = "Copied!",
        copy_link = "Copy shareable link",
        copy_link_hint = "Copy a shareable link to this view",
        show_data = "Show data",
        show_summary = "Show summary",
        pretty = "Pretty",
        raw = "Raw",
        no_data = "(no data available)",
        no_summary = "(no summary data available)",
        median = "Median",
        interval = "{point} [{width} credible interval]",
        value = "value",
        color = "Color",
        row = "Row",
        column = "Column",
        ungrouped = "Ungrouped",
        pooled = "Pooled",
        x = "X",
        y = "Y",
        untitled = "AoV plot",
        lang = "en",
    ),
    de = (
        more = "Mehr",
        csv = "⬇ CSV",
        image = "⬇ {format}",
        html = "⬇ HTML",
        share = "Teilen",
        copied = "Kopiert!",
        copy_link = "Teilbaren Link kopieren",
        copy_link_hint = "Einen teilbaren Link zu dieser Ansicht kopieren",
        show_data = "Daten anzeigen",
        show_summary = "Zusammenfassung anzeigen",
        pretty = "Übersicht",
        raw = "Rohdaten",
        no_data = "(keine Daten verfügbar)",
        no_summary = "(keine Zusammenfassung verfügbar)",
        median = "Median",
        interval = "{point} [{width}-Kredibilitätsintervall]",
        value = "Wert",
        color = "Farbe",
        row = "Zeile",
        column = "Spalte",
        ungrouped = "Ungruppiert",
        pooled = "Zusammengefasst",
        x = "X",
        y = "Y",
        untitled = "AoV-Grafik",
        lang = "de",
    ),
)

"""
    plot_texts(locale::Symbol=:en; texts...) -> PlotTexts

The [`PlotTexts`](@ref) for `locale` (`:en` or `:de`), with any of its texts
replaced by keyword:

```julia
const DE = plot_texts(:de; show_data="Kennzahlen anzeigen")
with_plot_caption(spec, "Kapazität"; plot_id="kapazitaet", texts=DE)
```

An unknown locale or text name, or a placeholder the text does not take
(`"{fromat}"`), throws an `ArgumentError`.
"""
function plot_texts(locale::Symbol=:en; texts...)
    haskey(_PLOT_TEXT_LOCALES, locale) || throw(ArgumentError(string("plot_texts: unknown locale ",
        repr(locale), "; available: ", join(repr.(keys(_PLOT_TEXT_LOCALES)), ", "))))
    names = fieldnames(PlotTexts)
    for name in keys(texts)
        name in names || throw(ArgumentError(string("plot_texts: unknown text ", repr(name),
            "; texts are ", join(names, ", "))))
    end
    merged = merge(getfield(_PLOT_TEXT_LOCALES, locale), (; (k => string(v) for (k, v) in pairs(texts))...))
    for name in names
        allowed = get(_PLOT_TEXT_PLACEHOLDERS, name, ())
        for m in eachmatch(r"\{([A-Za-z_]+)\}", merged[name])
            Symbol(m[1]) in allowed || throw(ArgumentError(string("plot_texts: ", name, " has no placeholder {",
                m[1], "}", isempty(allowed) ? "" : string("; it takes ", join(("{$p}" for p in allowed), ", ")))))
        end
    end
    PlotTexts((merged[name] for name in names)...)
end

const _EN_PLOT_TEXTS = plot_texts(:en)

# A text with its placeholders filled in. The runtime's `AoV._text` fills the
# same templates the same way.
_plot_text(texts::PlotTexts, name::Symbol; values...) =
    replace(getfield(texts, name), r"\{([A-Za-z_]+)\}" => m -> string(values[Symbol(m[2:end-1])]))

# The texts the browser runtime writes itself (preview contents, the HTML
# export). LOCKSTEP: `_TEXTS_EN` in `vendor/aov-runtime.js` holds their
# English values; `test/plot_texts.jl` pins the two together.
const _RUNTIME_TEXT_NAMES = (:no_data, :no_summary, :median, :interval, :value, :untitled, :lang)

_runtime_texts_json(texts::PlotTexts) =
    _vl_json(NamedTuple{_RUNTIME_TEXT_NAMES}(getfield.(Ref(texts), _RUNTIME_TEXT_NAMES)))

# Attributes for the element that carries a card's texts to the runtime:
# none for English, so existing output stays byte-identical.
_runtime_texts_attrs(texts::PlotTexts) = texts == _EN_PLOT_TEXTS ? (;) :
    (; data_aov_texts=_runtime_texts_json(texts))

# The picker's label for a channel.
const _CHANNEL_TEXTS = Dict("color" => :color, "row" => :row, "column" => :column,
    "detail" => :ungrouped, "off" => :pooled, "x" => :x, "y" => :y)

_channel_label(texts::PlotTexts, ch::AbstractString) =
    haskey(_CHANNEL_TEXTS, ch) ? getfield(texts, _CHANNEL_TEXTS[ch]) : uppercasefirst(ch)
