# title: Step Chart
# description: Staircase interpolation for cumulative/discrete data

let x = collect(1:20)
    y = cumsum(rand(20) .- 0.3)
    data((; x, y)) * mapping(:x, :y) * visual(Stairs) *
        config(title="Step Chart (Stairs)")
end
