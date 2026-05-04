# title: Scatter filled by default
# description: visual(Scatter) fills by default (matches Makie). Override with filled=false for hollow markers.

df = (; x=1:10, y=randn(10))
filled = data(df) * mapping(:x, :y) * visual(Scatter; color=:black) *
         config(title="visual(Scatter) -- filled (default)")
hollow = data(df) * mapping(:x, :y) * visual(Scatter; color=:black, filled=false) *
         config(title="visual(Scatter; filled=false) -- hollow")
(filled + hollow)
