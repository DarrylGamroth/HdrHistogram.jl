using HdrHistogram

const HH = HdrHistogram

function bench(label, n, f, args...)
    GC.gc()
    f(args...)
    GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f(args...)
    end
    elapsed = (time_ns() - t0)
    ns_per = elapsed / n
    rate = 1e9 / ns_per
    alloc = @allocated f(args...)
    println(rpad(label, 28),
        "ops/sec=", round(rate, digits=1),
        " ns/op=", round(ns_per, digits=1),
        " alloc=", alloc)
end

hist = HH.Histogram(1, 1_000_000, 3)
for i in 1:200_000
    HH.record_value!(hist, i % 10_000)
end

bench("mean", 50_000, HH.mean, hist)
bench("stddev", 50_000, HH.stddev, hist)
bench("p99", 50_000, HH.value_at_percentile, hist, 99.0)

percentiles = [50.0, 90.0, 99.0, 99.9]
values = zeros(Int64, length(percentiles))
bench("percentile vector", 50_000, HH.value_at_percentile, hist, percentiles, values)

bench("count_at_value", 200_000, HH.count_at_value, hist, 1234)

iter = HH.RecordedValuesIterator(hist)
state = HH.recorded_values_state(iter)
bench("mean (reuse state)", 50_000, HH.mean, hist, iter, state)
bench("stddev (reuse state)", 50_000, HH.stddev, hist, iter, state)
bench("p99 (reuse state)", 50_000, HH.value_at_percentile, hist, 99.0, iter, state)
bench("percentile vector (reuse)", 50_000, HH.value_at_percentile, hist, percentiles, values, iter, state)
