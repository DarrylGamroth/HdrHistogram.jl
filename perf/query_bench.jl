pushfirst!(LOAD_PATH, dirname(@__DIR__))
using HdrHistogram
using BenchmarkTools

const HH = HdrHistogram
include(joinpath(@__DIR__, "benchutils.jl"))

hist = HH.Histogram(1, 1_000_000, 3)
for i in 1:200_000
    HH.record_value!(hist, i % 10_000)
end

report_benchmark("mean", @benchmark(HH.mean($hist)))
report_benchmark("stddev", @benchmark(HH.stddev($hist)))
report_benchmark("p99", @benchmark(HH.value_at_percentile($hist, 99.0)))

percentiles = [50.0, 90.0, 99.0, 99.9]
values = zeros(Int64, length(percentiles))
report_benchmark("percentile vector",
    @benchmark(HH.value_at_percentile($hist, $percentiles, $values)))

report_benchmark("count_at_value", @benchmark(HH.count_at_value($hist, 1234)))

iter, state = HH.recorded_values_state(hist)
function percentile_vector_with_cursor!(h, percentiles, values, iter, state)
    for i in eachindex(percentiles, values)
        values[i] = HH.count_at_percentile(h, percentiles[i])
    end
    return HH.value_at_percentile(h, percentiles, values, iter, state)
end

report_benchmark("mean (iterator cursor)", @benchmark(HH.mean($hist, $iter, $state)))
report_benchmark("stddev (iterator cursor)", @benchmark(HH.stddev($hist, $iter, $state)))
report_benchmark("p99 (iterator cursor)",
    @benchmark(HH.value_at_percentile($hist, 99.0, $iter, $state)))
report_benchmark("percentile vector (cursor)",
    @benchmark(percentile_vector_with_cursor!($hist, $percentiles, $values, $iter, $state)))

report_benchmark("same-layout add",
    @benchmark(HH.add(target, $hist), setup=(target=similar($hist)), evals=1))
report_benchmark("add corrected",
    @benchmark(HH.add_while_correcting_for_coordinated_omission(target, $hist, 1000),
        setup=(target=similar($hist)), evals=1))
