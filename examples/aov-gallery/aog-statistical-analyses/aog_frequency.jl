# title: Frequency Count
# description: Count occurrences per category

data(cars()) * mapping(:origin) * frequency() *
config(title="Car Count by Origin")
