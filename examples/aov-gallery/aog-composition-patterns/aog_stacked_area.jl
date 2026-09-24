# title: Stacked Area
# description: Stacked area chart with color groups

let n = 12
    months = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3)
    category = repeat(["Web", "Mobile", "Desktop"], inner=12)
    values = [45,52,58,55,62,68,72,70,65,58,50,48,
              30,35,42,48,55,60,65,62,55,45,38,35,
              25,22,20,18,15,12,10,12,15,18,22,24]
    data((; month=months, value=values, category)) *
        mapping(:month, :value, color=:category) *
        visual(Band) *
        config(title="Traffic by Channel",
               encoding=Dict("y" => Dict("stack" => "zero")))
end
