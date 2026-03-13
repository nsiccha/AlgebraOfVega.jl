# Interactivity

AlgebraOfVega provides multiple levels of interactivity, from zero-config auto features to full HTMX integration.

## Auto-interactivity (zero config)

Every plot automatically gets:

- **Legend click filtering**: For single-view specs with a top-level `color` encoding, clicking legend items toggles group visibility. Uses VL `bind: "legend"` with `empty: true`.
- **Nearest-point tooltip**: For `line`/`area` marks, the tooltip snaps to the nearest data point.

These are added by `add_auto_interactivity!` and require no user code.

!!! warning "Legend binding limitation"
    `bind: "legend"` only works with **top-level** color encoding. For layered specs where color is per-sublayer (e.g. tidybayes compositions), it silently breaks the entire spec. The auto-interactivity intentionally skips these cases.

## Dropdown filtering (`config(select=...)`)

Add client-side dropdown widgets that filter data without server interaction:

```julia
# Single dropdown
spec = data(df) * mapping(:x, :y, color=:group) * visual(Scatter) *
    config(select=:group)

# Multiple dropdowns
spec = data(df) * mapping(:x, :y) * visual(Scatter) *
    config(select=[:origin, :cylinders])
```

Each field gets a dropdown with "All" + sorted unique values. Selecting a value filters the data via VL expression filters. "All" shows everything.

For layered specs, the top-level filter transform only affects layers that inherit shared data — layers with their own embedded data (e.g. CI bands) are unaffected.

## Custom VL interactivity via config

For full control, pass VL `params` and conditional encodings via `config()`:

```julia
# Brush selection
config(
    params=[Dict("name" => "brush", "select" => "interval")],
    encoding=Dict("opacity" => Dict(
        "condition" => Dict("param" => "brush", "value" => 1),
        "value" => 0.1,
    )),
)

# Slider parameter
config(
    params=[Dict(
        "name" => "min_hp",
        "value" => 50,
        "bind" => Dict("input" => "range", "min" => 0, "max" => 300),
    )],
    transform=[Dict("filter" => "datum.horsepower >= min_hp")],
)
```

## HTMX integration

Wire Vega signals to server-side Julia handlers:

```julia
draw(spec;
    id="my-plot",
    signals=[(signal="brush", url="/on_brush", target="#stats", debounce=200)],
)
```

When the Vega `brush` signal fires, it sends `GET /on_brush?field1=[min,max]&field2=[min,max]` via HTMX, swapping the response into `#stats`.

### Server-side data update

Update a plot's data without re-rendering:

```julia
update_data("my-plot", filtered_data)  # returns an h.script node
```

## Data Explorer

The gallery includes a fully client-side Data Explorer at `/explorer`. All datasets are embedded in the page; changing dropdowns for x, y, color, facet row, facet col, and mark type rebuilds the Vega-Lite spec in JavaScript with no server round-trips.
