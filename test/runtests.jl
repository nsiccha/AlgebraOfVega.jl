module AlgebraOfVegaTests
using Test, Random, AlgebraOfVega, Tables, TestModules
include("AlgebraOfVegaTests.jl")
end

using TestModules
runtests!(AlgebraOfVegaTests)
