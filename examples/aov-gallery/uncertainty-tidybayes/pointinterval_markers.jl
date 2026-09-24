# title: Interval estimates with categorical markers
# description: Median markers vary by chain while one-to-one parameter colours remain centered; marker groups stay separate during summarization.
data(sample_posterior_draws()) *
    mapping(:value; y=:parameter, color=:parameter, marker=:chain => "Chain") *
    pointinterval() * config(width=500, height=180)
