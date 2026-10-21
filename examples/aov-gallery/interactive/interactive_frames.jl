# title: Frame Animation
# description: Play through the months, one frame at a time; the temperature axis stays fixed

data(temperatures()) *
mapping(:city, :temp => "Temperature (°C)", color=:city) *
visual(BarPlot) *
config(
    width=400, height=300,
    title="Monthly mean temperature",
    scales=scales(Y=(; zero=true)),
    frame=(; field=:month => sorter("Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"), interval=0.6, loop=true),
)
