# title: Remap Encoding
# description: Client-side color/row switching via mapping_controls — no server round-trip

id = "remap-demo"
spec = data(cars()) * mapping(:horsepower, :mpg, color=:origin) * visual(Scatter) *
       config(title="Remap Encoding Demo")
auto_remap_node(id, spec; dims=[:origin => "Origin", :cylinders => "Cylinders"])
