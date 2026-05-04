# title: LineRibbon + Scatter overlay (works)
# description: Parallel of the PI-overlay bug but on lineribbon(bands=...): works. Regression entry so the counterpart PI-overlay fix doesn't break this path.

params = [\"a\", \"a\", \"a\", \"b\", \"b\", \"b\"]
indices = [1, 2, 3, 1, 2, 3]
medians = [2.0, 2.1, 2.2, 0.8, 0.9, 1.0]
q025s   = [1.5, 1.6, 1.7, 0.5, 0.6, 0.7]
q975s   = [2.5, 2.6, 2.7, 1.1, 1.2, 1.3]
q25s    = [1.8, 1.9, 2.0, 0.7, 0.8, 0.9]
q75s    = [2.2, 2.3, 2.4, 0.9, 1.0, 1.1]
summary = (; param=params, index=indices, median=medians,
             q025=q025s, q25=q25s, q75=q75s, q975=q975s)
truth = (; param=params, index=indices, truth=[2.05, 2.15, 2.25, 0.85, 0.95, 1.05])
lr = data(summary) * mapping(:index, :median, row=:param) *
     lineribbon(bands=[:q025 => :q975, :q25 => :q75])
overlay = data(truth) * mapping(:index, :truth, row=:param) *
          visual(Scatter; color=:black, filled=true)
(lr + overlay) * config(facet=(; linkyaxes=:none),
                         title=\"LineRibbon + Scatter overlay (works)\")
