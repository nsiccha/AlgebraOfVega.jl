# title: Jittered Scatter
# description: Individual data points by origin with jitter

data(cars()) *
mapping(:origin, :mpg) *
visual(Scatter) *
config(width=400, height=350, title="MPG by Origin (Jittered)",
       transform=[Dict("calculate" => "(random() - 0.5) * 0.8", "as" => "jitter")],
       encoding=Dict("xOffset" => Dict("field" => "jitter", "type" => "quantitative",
                                        "scale" => Dict("domain" => [-0.5, 0.5]))))
