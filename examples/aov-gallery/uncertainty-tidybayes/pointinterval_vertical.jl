# title: Point + Interval (vertical)
# description: pointinterval with orientation=:vertical — category on x, value on y

data(posterior_draws()) *
mapping(:parameter, :value) *
pointinterval(orientation=:vertical) *
config(width=400, height=300, title="Point + Interval (vertical)")
