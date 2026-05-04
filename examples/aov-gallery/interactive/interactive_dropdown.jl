# title: Dropdown Filter
# description: Select an origin to filter the scatter plot

data(cars()) *
mapping(:horsepower, :mpg, color=:origin) *
visual(Scatter) *
config(
    width=500, height=350,
    title="Filter by Origin",
    params=[Dict(
        "name" => "origin_select",
        "value" => "All",
        "bind" => Dict(
            "input" => "select",
            "options" => ["All", "USA", "Europe", "Japan"],
        ),
    )],
    transform=[Dict(
        "filter" => "origin_select == 'All' || datum.origin == origin_select",
    )],
)
