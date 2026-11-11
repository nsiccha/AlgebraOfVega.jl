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
