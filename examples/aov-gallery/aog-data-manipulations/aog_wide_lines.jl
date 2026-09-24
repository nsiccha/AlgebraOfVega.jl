# title: Wide Data (Lines)
# description: Multiple y-columns mapped with color

let df = (; x=collect(0.0:0.5:10), y1=(0.0:0.5:10).^0.5, y2=(0.0:0.5:10).^0.6, y3=(0.0:0.5:10).^0.7)
    n = length(df.x)
    long = (; x=[df.x;df.x;df.x], y=[df.y1;df.y2;df.y3], group=[fill("y1",n);fill("y2",n);fill("y3",n)])
    data(long) * mapping(:x, :y, color=:group) * visual(Lines) *
        config(title="Wide Data as Lines")
end
