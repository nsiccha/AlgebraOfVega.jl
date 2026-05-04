# title: VLines color mapping (bug)
# description: Two scatter layers (obs + pred) faceted by assay (col) × subject (row), plus a VLines dosing layer with its own color=:vessel mapping. The VLines should render one color per vessel, but the per-layer color mapping is currently ignored.

let
    subjects = [\"S1\", \"S2\"]
    assays   = [\"A\", \"B\"]
    obs = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_obs   = randn(40))
    pred = (;
        subject = repeat(subjects, inner=20),
        assay   = repeat(assays, 20),
        time_h  = repeat(collect(range(0, 24, length=20)), 2),
        y_pred  = randn(40) .+ 0.2)
    dose = (;
        subject = [\"S1\",\"S1\",\"S1\",\"S2\",\"S2\",\"S2\",\"S1\",\"S1\",\"S2\",\"S2\"],
        diet    = [\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\",\"Fed\",\"Fed\",\"Fasted\",\"Fed\"],
        amount_mug = [10.0, 20.0, 10.0, 10.0, 20.0, 10.0, 5.0, 5.0, 5.0, 5.0],
        time_h  = [0.0, 8.0, 16.0, 0.0, 8.0, 16.0, 0.0, 12.0, 0.0, 12.0],
        vessel  = [\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"IV\",\"Oral\",\"Oral\",\"IV\"])
    (data(obs) *
        mapping(:time_h => \"Time (h)\", :y_obs => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"black\") +
     data(pred) *
        mapping(:time_h => \"Time (h)\", :y_pred => \"Response\"; row=:subject, col=:assay) *
        visual(Scatter; color=\"steelblue\", opacity=0.6) +
     data(dose) *
        mapping(:time_h => \"Time (h)\"; row=:subject,
                color=:vessel => \"Vessel\",
                linestyle=:diet => \"Diet\",
                linewidth=:amount_mug => \"Dose (μg)\") *
        visual(VLines; opacity=0.5)) *
        config(title=\"VLines color=:vessel should render per-vessel colors\")
end
