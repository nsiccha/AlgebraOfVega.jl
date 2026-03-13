# Sample datasets for gallery examples and testing

sample_cars() = (;
    horsepower = [130,165,150,150,140,198,220,215,225,190,170,160,150,225,95,95,97,85,88,46,87,90,95,113,90,215,200,210,193,88,90,95,100,105,100,88,100,165,175,153,150,180,170,175,110,72,100,88,86,90,70,76,65,69,60,70,95,80,54,90,86,110],
    mpg = [18,15,18,16,17,15,14,14,14,15,15,14,15,14,24,22,18,21,27,26,25,24,25,26,21,10,10,11,9,27,28,25,25,19,16,17,19,18,14,14,15,15,14,15,24,20,25,21,27,26,26,28,25,26,30,22,17,23,36,25,22,18],
    origin = ["USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","Europe","Europe","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Europe","Europe","Europe","Europe","USA","USA","USA","USA","USA","USA","USA","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","Japan","USA","USA","USA","Japan","Europe","Europe","Europe"],
    cylinders = [8,8,8,8,8,8,8,8,8,8,8,8,8,8,4,4,4,4,4,4,4,4,4,4,4,8,8,8,8,4,4,4,4,4,4,4,4,6,6,6,6,8,8,8,4,4,4,4,4,4,4,4,4,4,4,6,6,6,4,4,4,4],
    weight = [3504,3693,3436,3433,3449,4341,4354,4312,4425,3850,3563,3609,3761,3086,2372,2833,2774,2587,2130,1835,2672,2430,2375,2234,2648,4615,4376,4382,4732,2130,2264,2228,2046,2634,2702,2875,2901,3353,3169,2906,3380,3740,4080,3645,2585,2310,2472,2265,2110,2800,2110,2085,2245,1965,1755,2815,3210,3380,1760,2130,2205,2245],
    acceleration = [12.0,11.5,11.0,12.0,10.5,10.0,9.0,8.5,10.0,8.5,10.0,8.0,9.5,10.0,15.0,15.5,15.5,16.0,14.5,20.5,17.5,15.0,17.5,15.5,18.5,14.0,13.0,13.5,18.0,14.5,13.5,15.5,19.0,13.0,15.5,16.5,17.0,11.0,11.5,12.5,13.5,12.0,11.0,11.5,14.0,19.0,15.0,16.0,19.5,14.5,19.5,17.0,17.0,15.0,17.0,14.0,12.5,13.5,15.5,14.0,15.5,13.5],
)

sample_tips() = (;
    total_bill = [16.99,10.34,21.01,23.68,24.59,25.29,8.77,26.88,15.04,14.78,10.27,35.26,15.42,18.43,14.83,21.58,10.33,16.29,16.97,20.65],
    tip = [1.01,1.66,3.50,3.31,3.61,4.71,2.0,3.12,1.96,3.23,1.71,5.0,1.57,3.0,1.44,3.5,1.7,3.31,3.5,3.35],
    sex = ["Female","Male","Male","Male","Female","Male","Male","Male","Male","Female","Male","Female","Male","Male","Female","Male","Male","Male","Male","Male"],
    day = ["Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun","Sun"],
    size = [2,3,3,2,4,4,2,4,2,2,2,4,2,2,2,2,3,3,3,3],
)

sample_stocks() = let
    dates = ["2000-01-01","2000-02-01","2000-03-01","2000-04-01","2000-05-01","2000-06-01"]
    n = length(dates)
    (;
        date = repeat(dates, 3),
        price = [Float64[100,110,105,115,120,118]; Float64[80,85,90,88,92,95]; Float64[50,55,60,58,65,70]],
        symbol = [fill("AAPL", n); fill("GOOG", n); fill("MSFT", n)],
    )
end

sample_temperatures() = (;
    month = repeat(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], 3),
    city = [fill("New York", 12); fill("London", 12); fill("Tokyo", 12)],
    temp = [
        0,1,5,12,18,24,27,26,22,15,8,3,
        5,5,7,10,13,16,19,18,15,11,8,5,
        5,6,9,15,19,23,27,28,24,18,12,7,
    ],
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

# Simple Box-Muller normal RNG (no dependencies)
function randn_bm(n)
    out = Float64[]
    while length(out) < n
        u1, u2 = rand(), rand()
        u1 == 0.0 && continue
        z0 = sqrt(-2 * log(u1)) * cos(2π * u2)
        z1 = sqrt(-2 * log(u1)) * sin(2π * u2)
        push!(out, z0, z1)
    end
    out[1:n]
end

function sample_posterior_draws(; n=500)
    (;
        parameter = [fill("α", n); fill("β", n); fill("σ", n)],
        value = [2.0 .+ 0.5 .* randn_bm(n); 0.8 .+ 0.3 .* randn_bm(n); 1.2 .+ 0.2 .* abs.(randn_bm(n))],
        chain = [repeat(1:4, n÷4); repeat(1:4, n÷4); repeat(1:4, n÷4)],
    )
end

function sample_regression_predictions(; n_x=50, n_draws=200)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    for d in 1:n_draws
        α = 2.0 + 0.5 * randn_bm(1)[1]
        β = 0.8 + 0.3 * randn_bm(1)[1]
        σ = 1.2 + 0.2 * abs(randn_bm(1)[1])
        for x in xs
            push!(rows_x, x)
            push!(rows_y, α + β * x + σ * randn_bm(1)[1])
            push!(rows_draw, d)
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw)
end

function sample_grouped_regression_predictions(; n_x=30, n_draws=100)
    xs = range(0, 5, length=n_x)
    rows_x = Float64[]
    rows_y = Float64[]
    rows_draw = Int[]
    rows_group = String[]
    for (gname, α0, β0) in [("Treatment A", 2.0, 0.8), ("Treatment B", 1.0, 1.5)]
        for d in 1:n_draws
            α = α0 + 0.5 * randn_bm(1)[1]
            β = β0 + 0.3 * randn_bm(1)[1]
            σ = 0.8 + 0.2 * abs(randn_bm(1)[1])
            for x in xs
                push!(rows_x, x)
                push!(rows_y, α + β * x + σ * randn_bm(1)[1])
                push!(rows_draw, d)
                push!(rows_group, gname)
            end
        end
    end
    (x=rows_x, y=rows_y, draw=rows_draw, group=rows_group)
end

# --- Utilities for the explorer widget ---

function classify_columns(tbl)
    cols = string.(Tables.columnnames(tbl))
    numeric = [c for c in cols if eltype(Tables.getcolumn(tbl, Symbol(c))) <: Number]
    categorical = [c for c in cols if !(eltype(Tables.getcolumn(tbl, Symbol(c))) <: Number)]
    (all=cols, numeric=numeric, categorical=categorical)
end

function table_to_rows(tbl)
    cols = Tables.columnnames(tbl)
    n = length(Tables.getcolumn(tbl, first(cols)))
    [Dict(string(c) => Tables.getcolumn(tbl, c)[i] for c in cols) for i in 1:n]
end
