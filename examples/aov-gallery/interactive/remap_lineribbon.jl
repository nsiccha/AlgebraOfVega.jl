# title: Remap Line + Ribbon
# description: Client-side color/row/col switching on a lineribbon plot

id = "remap-lr"
preds = faceted_regression_predictions()
spec = data(preds) * mapping(:x, :y, group=:draw, color=:panel, row=:site) *
       lineribbon() * config(title="Remap Line + Ribbon")
auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])
