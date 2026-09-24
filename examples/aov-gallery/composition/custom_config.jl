# title: Custom Styling
# description: Customized background, fonts, and grid

data(tips()) *
mapping(:total_bill, :tip, color=:sex) *
visual(Scatter, size=80) *
config(
    width=500, height=350,
    title="Tips (Custom Style)",
    config=Dict(
        "background" => "#f8f8f8",
        "title" => Dict("fontSize" => 20, "anchor" => "start"),
        "axis" => Dict("grid" => true, "gridColor" => "#ddd"),
    ),
)
