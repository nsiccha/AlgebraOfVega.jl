# title: Multi Color Scales
# description: Continuous + discrete color on same plot

let x = collect(range(-3.14, 3.14, length=100))
    y = sin.(x)
    z = cos.(x)
    c = [isodd(i) ? "a" : "b" for i in 1:100]
    df = (; x, y, z, c)
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="Lines with continuous z coloring",
               encoding=Dict("color" => Dict("field" => "z", "type" => "quantitative")))
end
