# title: Log Transform
# description: Apply log transform to y in mapping

let x = collect(1:100)
    y = [sqrt(xi) + 20xi + 100 for xi in x]
    df = (; x, y)
    data(df) * mapping(:x, :y) * visual(Lines) *
        config(title="y = √x + 20x + 100 (log scale)",
               encoding=Dict("y" => Dict("scale" => Dict("type" => "log"))))
end
