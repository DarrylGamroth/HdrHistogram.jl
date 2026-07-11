using Aqua

@testset "Aqua.jl" begin
    Aqua.test_all(HdrHistogram; stale_deps=(ignore=[:Atomix],))
end
