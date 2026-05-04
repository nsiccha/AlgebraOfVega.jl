# title: Remap Pre-aggregated Ribbon
# description: auto_remap_node on pre-aggregated lineribbon with color/row switching

id = "remap-precomp-lr"
summary = _preaggregate(faceted_regression_predictions(), :x, :panel, :site)
spec = data(summary) * mapping(:x, :median, color=:panel, row=:site) *
       lineribbon(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75]) *
       config(title="Remap Pre-aggregated Ribbon")
auto_remap_node(id, spec; dims=[:panel => "Condition", :site => "Site"])
