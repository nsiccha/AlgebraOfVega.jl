# Data

## Tables

```@docs
by_url
rows_json
preaggregate
classify_columns
table_to_rows
```

## Sample data

The small `sample_cars`, `sample_tips`, and penguin explorer fixtures are adapted from public teaching datasets: [Vega cars](https://github.com/vega/vega-datasets/blob/main/data/cars.json), [seaborn tips](https://github.com/mwaskom/seaborn-data/blob/master/tips.csv), and [Vega penguins](https://github.com/vega/vega-datasets/blob/main/data/penguins.json). They are plotting fixtures; use the original datasets for scientific analyses. The stock prices, city temperatures, population and sales counts, posterior draws, and regression predictions are synthetic teaching values. They do not report market prices, weather records, census counts, business results, or fitted research models.

```@docs
sample_cars
sample_tips
sample_stocks
sample_temperatures
sample_population
melt_population
sample_monthly_sales
melt_sales
sample_posterior_draws
sample_regression_predictions
sample_grouped_regression_predictions
sample_faceted_regression_predictions
sample_faceted_observations
```

## Explorer

```@docs
default_explorer_datasets
explorer_widget
write_explorer_assets
explorer_controls_html
explorer_js
explorer_data_init_js
```
