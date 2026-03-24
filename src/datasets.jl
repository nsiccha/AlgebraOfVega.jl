# Sample datasets for gallery examples and testing

"Sample cars dataset (62 rows): horsepower, mpg, origin, cylinders, weight, acceleration."
sample_cars() = (;
    horsepower = [130,165,150,150,140,198,220,215,225,190,170,160,150,225,95,95,97,85,88,46,87,90,95,113,90,215,200,210,193,88,90,95,100,105,100,88,100,165,175,153,150,180,170,175,110,72,100,88,86,90,70,76,65,69,60,70,95,80,54,90,86,110],
    mpg = [18,15,18,16,17,15,14,14,14,15,15,14,15,14,24,22,18,21,27,26,25,24,25,26,21,10,10,11,9,27,28,25,25,19,16,17,19,18,14,14,15,15,14,15,24,20,25,21,27,26,26,28,25,26,30,22,17,23,36,25,22,18],
    origin = ["USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","Europe","Europe","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","USA","USA","USA","Japan","Europe","Europe","Europe"],
    cylinders = [8,8,8,8,8,8,8,8,8,8,8,8,8,8,4,4,4,4,4,4,4,4,4,4,4,8,8,8,8,4,4,4,4,4,4,4,4,6,6,6,6,8,8,8,4,4,4,4,4,4,4,4,4,4,4,6,6,6,4,4,4,4],
    weight = [3504,3693,3436,3433,3449,4341,4354,4312,4425,3850,3563,3609,3761,3086,2372,2833,2774,2587,2130,1835,2672,2430,2375,2234,2648,4615,4376,4382,4732,2130,2264,2228,2046,2634,2702,2875,2901,3353,3169,2906,3380,3740,4080,3645,2585,2310,2472,2265,2110,2800,2110,2085,2245,1965,1755,2815,3210,3380,1760,2130,2205,2245],
    acceleration = [12.0,11.5,11.0,12.0,10.5,10.0,9.0,8.5,10.0,8.5,10.0,8.0,9.5,10.0,15.0,15.5,15.5,16.0,14.5,20.5,17.5,15.0,17.5,15.5,18.5,14.0,13.0,13.5,18.0,14.5,13.5,15.5,19.0,13.0,15.5,16.5,17.0,11.0,11.5,12.5,13.5,12.0,11.0,11.5,14.0,19.0,15.0,16.0,19.5,14.5,19.5,17.0,17.0,15.0,17.0,14.0,12.5,13.5,15.5,14.0,15.5,13.5],
)

"Sample tips dataset (20 rows): total_bill, tip, sex, day, size."
sample_tips() = (;
    total_bill = [16.99,10.34,21.01,23.68,24.59,25.29,8.77,26.88,15.04,14.78,10.27,35.26,15.42,18.43,14.83,21.58,10.33,16.29,16.97,20.65],
    tip = [1.01,1.66,3.50,3.31,3.61,4.71,2.0,3.12,1.96,3.23,1.71,5.0,1.57,3.0,1.44,3.5,1.7,3.31,3.5,3.35],
    sex = ["Female","Male","Male","Male","Female","Male","Male","Male","Male","Female","Male","Female","Male","Male","Female","Male","Male","Male","Male","Male"],
    day = ["Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun"],
    size = [2,3,3,2,4,4,2,4,2,2,2,4,2,2,2,2,3,3,3,3],
)

"Sample stocks dataset (18 rows): date, price, symbol (AAPL/GOOG/MSFT)."
sample_stocks() = let
    dates = ["2000-01-01","2000-02-01","2000-03-01","2000-04-01","2000-05-01","2000-06-01"]
    n = length(dates)
    (;
        date = repeat(dates, 3),
        price = [Float64[100,110,105,115,120,118]; Float64[80,85,90,88,92,95]; Float64[50,55,60,58,65,70]],
        symbol = [fill("AAPL", n); fill("GOOG", n); fill("MSFT", n)],
    )
end

"Sample temperatures dataset (36 rows): month, city (New York/London/Tokyo), temp."
sample_temperatures() = (;
    month = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3),
    city = [fill("New York", 12); fill("London", 12); fill("Tokyo", 12)],
    temp = [
        0,1,5,12,18,24,27,26,22,15,8,3,
        5,5,7,10,13,16,19,18,15,11,8,5,
        5,6,9,15,19,23,27,28,24,18,12,7,
    ],
)

"Sample penguins dataset (50 rows): species, island, bill_length, bill_depth, flipper_length, body_mass, sex."
sample_penguins() = (;
    species = ["Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Adelie","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Chinstrap","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo","Gentoo"],
    island = ["Torgersen","Torgersen","Torgersen","Torgersen","Torgersen","Torgersen","Biscoe","Biscoe","Dream","Dream","Dream","Dream","Dream","Dream","Torgersen","Torgersen","Biscoe","Biscoe","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Dream","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe","Biscoe"],
    bill_length = [39.1,39.5,40.3,36.7,39.3,38.9,37.8,37.7,36.6,38.7,42.5,34.4,46.0,37.8,38.6,41.1,37.6,38.7,34.6,36.6,46.5,50.0,51.3,45.4,52.7,45.2,46.1,51.3,46.0,51.3,46.6,51.7,47.0,52.0,46.1,50.0,48.7,50.2,45.1,46.5,46.3,42.9,46.1,44.5,47.8,48.2,50.0,47.3,42.8,45.1],
    bill_depth = [18.7,17.4,18.0,19.3,20.6,17.8,18.3,18.7,17.8,19.0,20.7,18.4,21.5,18.3,21.2,17.6,19.3,19.2,21.1,17.2,17.9,19.5,18.2,18.7,19.0,17.8,18.2,18.2,18.9,20.3,14.1,20.3,17.3,18.1,13.2,16.3,14.1,14.2,13.5,13.5,15.8,13.1,15.1,14.3,15.0,14.3,15.3,13.8,13.5,14.5],
    flipper_length = [181,186,195,193,190,181,174,180,187,195,187,184,194,174,191,182,181,169,185,186,192,196,197,188,197,198,178,197,195,187,215,194,199,197,211,230,210,218,215,210,215,215,210,212,215,210,218,217,210,215],
    body_mass = [3750,3800,3250,3450,3650,3625,3200,3600,3700,3450,3525,3325,4200,3400,3800,3950,3300,3450,3475,3600,3500,3900,3650,3525,3725,3950,3250,3750,4150,3900,4400,3775,3900,4150,4500,5700,4450,5200,4750,4550,4725,4150,4200,5250,5200,4775,5400,4725,4100,4400],
    sex = ["Male","Female","Female","Female","Male","Female","Female","Male","Female","Male","Female","Female","Male","Female","Female","Male","Female","Male","Male","Female","Female","Male","Male","Female","Male","Female","Female","Male","Male","Male","Female","Male","Female","Male","Female","Male","Female","Male","Female","Male","Male","Female","Male","Female","Male","Female","Male","Female","Female","Female"],
)

sample_population() = (;
    category = ["0-14","15-24","25-54","55-64","65+"],
    male = [25,18,40,12,10],
    female = [24,17,38,13,14],
)

melt_population(pop) = let
    n = length(pop.category)
    (;
        category = [pop.category; pop.category],
        count = [pop.male; pop.female],
        sex = [fill("Male", n); fill("Female", n)],
    )
end

sample_monthly_sales() = (;
    month = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"],
    online = [120,135,140,160,180,200,220,210,190,175,160,250],
    store = [200,180,190,170,160,150,140,145,155,170,180,300],
)

melt_sales(s) = let
    n = length(s.month)
    (;
        month = [s.month; s.month],
        sales = [s.online; s.store],
        channel = [fill("Online", n); fill("Store", n)],
    )
end


"Simulated posterior draws for 3 parameters (α, β, σ) across 4 chains."
function sample_posterior_draws(; n=500)
    (;
        parameter = [fill("α", n); fill("β", n); fill("σ", n)],
        value = [2.0 .+ 0.5 .* randn(n); 0.8 .+ 0.3 .* randn(n); 1.2 .+ 0.2 .* abs.(randn(n))],
        chain = [repeat(1:4, n÷4); repeat(1:4, n÷4); repeat(1:4, n÷4)],
    )
end

"Simulated draw-level regression predictions with columns x, y, draw."
function sample_regression_predictions(; n_x=50, n_draws=200)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    for d in 1:n_draws
        α = 2.0 + 0.5 * randn(1)[1]
        β = 0.8 + 0.3 * randn(1)[1]
        σ = 1.2 + 0.2 * abs(randn(1)[1])
        for x in xs
            push!(rows_x, x)
            push!(rows_y, α + β * x + σ * randn(1)[1])
            push!(rows_draw, d)
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw)
end

"Simulated grouped regression predictions with columns x, y, draw, group."
function sample_grouped_regression_predictions(; n_x=30, n_draws=100)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    rows_group = String[]
    for (gname, α0, β0) in [("Treatment A", 2.0, 0.8), ("Treatment B", 1.0, 1.5)]
        for d in 1:n_draws
            α = α0 + 0.5 * randn(1)[1]
            β = β0 + 0.3 * randn(1)[1]
            σ = 0.8 + 0.2 * abs(randn(1)[1])
            for x in xs
                push!(rows_x, x)
                push!(rows_y, α + β * x + σ * randn(1)[1])
                push!(rows_draw, d)
                push!(rows_group, gname)
            end
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw, group=rows_group)
end

"Simulated faceted regression predictions with columns x, y, draw, panel, site (for col+row faceting)."
function sample_faceted_regression_predictions(; n_x=30, n_draws=100)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    rows_panel = String[]
    rows_site = String[]
    conditions = [("Condition A", 2.0, 0.8, 0.8), ("Condition B", 1.0, 1.5, 1.0), ("Condition C", 3.0, -0.5, 0.6)]
    sites = [("Site 1", 0.0), ("Site 2", 1.5)]
    for (pname, α0, β0, σ0) in conditions
        for (sname, s_offset) in sites
            for d in 1:n_draws
                α = α0 + s_offset + 0.5 * randn(1)[1]
                β = β0 + 0.3 * randn(1)[1]
                σ = σ0 + 0.2 * abs(randn(1)[1])
                for x in xs
                    push!(rows_x, x)
                    push!(rows_y, α + β * x + σ * randn(1)[1])
                    push!(rows_draw, d)
                    push!(rows_panel, pname)
                    push!(rows_site, sname)
                end
            end
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw, panel=rows_panel, site=rows_site)
end

"Simulated observations matching `sample_faceted_regression_predictions` panels+sites, for overlay testing."
function sample_faceted_observations(; n_per_cell=5)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_panel = String[]
    rows_site = String[]
    conditions = [("Condition A", 2.0, 0.8, 1.5), ("Condition B", 1.0, 1.5, 2.0), ("Condition C", 3.0, -0.5, 1.2)]
    sites = [("Site 1", 0.0), ("Site 2", 1.5)]
    for (pname, α0, β0, σ0) in conditions
        for (sname, s_offset) in sites
            for _ in 1:n_per_cell
                x = 5.0 * rand()
                push!(rows_x, x)
                push!(rows_y, α0 + s_offset + β0 * x + σ0 * randn(1)[1])
                push!(rows_panel, pname)
                push!(rows_site, sname)
            end
        end
    end
    (x=rows_x, y=rows_y, panel=rows_panel, site=rows_site)
end

# --- Utilities for the explorer widget ---

"""
    classify_columns(tbl) -> (all, numeric, categorical)

Classify columns of a Tables.jl-compatible table into numeric and categorical.
Works with any table type (NamedTuples, DataFrames, etc.).
"""
function classify_columns(tbl)
    cols = string.(Tables.columnnames(tbl))
    numeric = [c for c in cols if eltype(Tables.getcolumn(tbl, Symbol(c))) <: Number]
    categorical = [c for c in cols if !(eltype(Tables.getcolumn(tbl, Symbol(c))) <: Number)]
    (all=cols, numeric=numeric, categorical=categorical)
end

"""
    table_to_rows(tbl) -> Vector{Dict{String,Any}}

Convert a Tables.jl-compatible table to a vector of row dicts (for JSON serialization).
Works with any table type (NamedTuples, DataFrames, etc.).
"""
function table_to_rows(tbl)
    cols = Tables.columnnames(tbl)
    n = length(Tables.getcolumn(tbl, first(cols)))
    [Dict(string(c) => Tables.getcolumn(tbl, c)[i] for c in cols) for i in 1:n]
end
