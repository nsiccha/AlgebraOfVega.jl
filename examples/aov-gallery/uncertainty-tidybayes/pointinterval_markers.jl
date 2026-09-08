# title: Interval estimates with categorical markers
# description: Median markers vary by chain while intervals retain parameter colours; marker groups remain separate during summarization.
data(sample_posterior_draws()) *
    mapping(:value; y=:parameter, color=:parameter, marker=:chain => "Chain") *
    pointinterval() * config(width=500, height=180)
