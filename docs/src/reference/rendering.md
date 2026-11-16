# Rendering

## Figures and specifications

```@docs
vdraw
to_node
to_vegalite
to_json
to_html
vsave
sdraw
sdraw!
sdraw_file
plot_size
```

## Fixed mark colours

Fixed marks can follow their background with `:background`. For example,
`visual(Scatter; color="#1f6fb5", strokecolor=:background, strokewidth=1.5)`
keeps its blue fill and draws a 1.5 px outline in the background colour.
`color`, `strokecolor` (or `stroke`) and `fill` accept this token. Use
`color=:ink` for the foreground text colour.

In a host-themed browser plot, `:background` follows the local solid page
background, compositing translucent ancestor colours. An explicit
`config(config=Dict("background" => "#182025"))` takes precedence; an explicit
`config.view.fill` supplies the surface inside the plotting area. Theme
changes refresh both foreground and background paint; after changing a
wrapper's CSS, call `AoV.refreshTheme()`. PNG/SVG downloads use the same
resolved surface. Saved HTML resolves its own page's background.

`vsave`, report images, bare-spec HTML and `theme=:none` use the configured
plot background, white by default. `sdraw` uses the Makie axis background;
`sdraw!` uses the destination axis, including an explicitly configured
`backgroundcolor`. Existing literal colours, `:ink` and palettes keep their
meaning. `:background` is a fixed solid paint, not a palette entry or a
per-pixel eraser over an image, gradient, grid line or another mark.

## Browser assets

```@docs
vega_head
vega_runtime
vega_controls
vega_cdn_urls
vega_sri_hashes
vega_vendor_dir
```

## Data updates

```@docs
update_data
append_data
replace_data
remove_data
update_spec
```

## Channel controls

```@docs
auto_remap_node
mapping_controls
resolve_channels
refine_channels
```

## Captions and summaries

Caption and table integration requires `using HTMXObjects`.

```@docs
with_plot_caption
draws_summary_table
cell_charts
plot_summary_md
PlotSummary
plot_summary_table
plot_texts
PlotTexts
```

## Sharing and downloads

```@docs
clean_share_url
caption_action_inject
caption_share_button
with_caption_share
with_caption_download
summary_share_button
```
