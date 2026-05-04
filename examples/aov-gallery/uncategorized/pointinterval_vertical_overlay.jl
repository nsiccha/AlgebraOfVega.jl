# title: Vertical PI + Scatter overlay (BRM bug repro)
# description: Vertical pointinterval(bands=...) + visual(Scatter), row-faceted, integer :index, scalar params (one row per facet) — matches BRM's stan_generate truth overlay shape.

# Match BRM: integer :index, some scalar params (index=0), bands=3
params = ["α","β","σ","β","σ","σ"]  # scalars α once; β has index 0+1; σ has 0+1+2
indices = [0, 0, 0, 1, 1, 2]
medians = [2.0, 0.8, 1.2, 0.85, 1.25, 1.3]
q025s   = [1.5, 0.5, 1.0, 0.55, 1.05, 1.1]
q975s   = [2.5, 1.1, 1.4, 1.15, 1.45, 1.5]
q10s    = [1.7, 0.6, 1.1, 0.65, 1.15, 1.2]
q90s    = [2.3, 1.0, 1.3, 1.05, 1.35, 1.4]
q25s    = [1.8, 0.7, 1.15, 0.75, 1.2, 1.25]
q75s    = [2.2, 0.9, 1.25, 0.95, 1.3, 1.35]
summary = (; param=params, index=indices, median=medians,
             q025=q025s, q10=q10s, q25=q25s, q75=q75s, q90=q90s, q975=q975s)
truth = (; param=params, index=indices, truth=[2.05, 0.82, 1.22, 0.87, 1.27, 1.32])
pi = data(summary) * mapping(:index, :median, row=:param) *
     pointinterval(bands=[:q025 => :q975, :q10 => :q90, :q25 => :q75],
                   orientation=:vertical)
overlay = data(truth) * mapping(:index, :truth, row=:param) *
          visual(Scatter; color=:black, strokewidth=0)
(pi + overlay) * config(width=400, height=80, facet=(; linkyaxes=:none),
                         title="Vertical PI + Scatter overlay (BRM pattern)")
