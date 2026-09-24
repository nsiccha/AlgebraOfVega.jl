# --- High-level widgets and recipes ---

"""
    ecdf_grid(table, columns; group=nothing, width=250, height=180)

Render a grid of ECDF plots, one per column, colored by `group`.
Returns an HTMX `h.div` node with flex-wrap layout.

- `table`: any Tables.jl-compatible table (DataFrame, NamedTuple, etc.)
- `columns`: vector of column names (Symbols) to plot
- `group`: optional column name for color grouping (e.g. `:chain`, `:model`)
- `width`, `height`: per-plot dimensions

Example (posterior parameter ECDFs colored by chain):
```julia
ecdf_grid(draws_df, [:alpha, :beta, :sigma]; group=:chain)
```
"""
function ecdf_grid(table, columns; group=nothing, width=250, height=180)
    plots = map(columns) do col
        vals = Tables.getcolumn(table, col)
        if !isnothing(group)
            grp = string.(Tables.getcolumn(table, group))
            plot_tbl = (; value=vals, _group=grp)
            spec = data(plot_tbl) * mapping(:value; color=:_group) *
                visual(ECDFPlot) * config(width=width, height=height)
        else
            plot_tbl = (; value=vals)
            spec = data(plot_tbl) * mapping(:value) *
                visual(ECDFPlot) * config(width=width, height=height)
        end
        (string(col), vdraw(spec))
    end
    h.div(; class="u-flex-wide u-flex-wrap")(
        [h.div(h.h5(name), node) for (name, node) in plots]...
    )
end

"""
    ppc_overlay(obs, pred; x, y, col=nothing, row=nothing, group=nothing,
                color=nothing, truth=nothing, obs_mark=Scatter, obs_size=30,
                truth_color="red", truth_strokeWidth=2, truth_strokeDash=[4,4])

Build a posterior predictive check overlay: observations + prediction draws + optional truth.
Returns composable AoG layers — combine with `* config(...)` and pipe to `|> vdraw`.

- `obs`: observation data table
- `pred`: prediction draws table (one row per draw × observation)
- `x`, `y`: column names for the axes
- `col`, `row`: optional faceting columns
- `group`: draw identifier column (e.g. `:draw_id`) for prediction ribbons
- `color`: optional color column for predictions (e.g. `:model` for comparisons)
- `truth`: optional ground-truth data table (rendered as dashed lines)

Example:
```julia
ppc_overlay(obs_df, pred_df;
    x=:time_h, y=:value, col=:assay_name, row=:subject_name,
    group=:draw_id,
) * config(width=250, height=100, facet=(; linkxaxes=:none, linkyaxes=:none)) |> vdraw
```
"""
function ppc_overlay(obs, pred; x, y, col=nothing, row=nothing, group=nothing,
                     color=nothing, truth=nothing, obs_mark=Scatter, obs_size=30,
                     truth_color="red", truth_strokeWidth=2, truth_strokeDash=[4,4])
    facet_kw = Dict{Symbol,Any}()
    !isnothing(col) && (facet_kw[:col] = col)
    !isnothing(row) && (facet_kw[:row] = row)

    obs_layer = data(obs) * mapping(x, y; facet_kw...) * visual(obs_mark; size=obs_size)

    pred_kw = copy(facet_kw)
    !isnothing(group) && (pred_kw[:group] = group)
    !isnothing(color) && (pred_kw[:color] = color)
    pred_layer = data(pred) * mapping(x, y; pred_kw...) * lineribbon()

    layers = pred_layer + obs_layer

    if !isnothing(truth)
        truth_layer = data(truth) * mapping(x, y; facet_kw...) *
            visual(Lines; color=truth_color, strokeWidth=truth_strokeWidth, strokeDash=truth_strokeDash)
        layers = layers + truth_layer
    end

    layers
end
