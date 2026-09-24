# title: Box Plot
# description: Box plot by category with color dodge

let species = [["Adelie","Chinstrap","Gentoo"][mod1(k,3)] for k in 1:200]
    sex = [isodd(k) ? "male" : "female" for k in 1:200]
    depth = [s == "Adelie" ? 18.0 : s == "Chinstrap" ? 18.5 : 15.0 for s in species] .+ randn(200)
    df = (; species, bill_depth=depth, sex)
    data(df) * visual(BoxPlot) * mapping(:species, :bill_depth, color=:sex, dodge_x=:sex) *
        config(title="Box Plot by Species & Sex")
end
