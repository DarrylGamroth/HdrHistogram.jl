using HdrHistogram

const HH = HdrHistogram

function bench(label, f, n)
    GC.gc()
    f()
    GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f()
    end
    elapsed = (time_ns() - t0) / 1e9
    rate = n / elapsed
    alloc = @allocated f()
    println(rpad(label, 28), "ops/sec=", round(rate, digits=1), " alloc=", alloc)
end

hist = HH.Histogram(1, 1_000_000, 3)
for i in 1:200_000
    HH.record_value!(hist, i % 10_000)
end

bench("mean", () -> HH.mean(hist), 50_000)
bench("stddev", () -> HH.stddev(hist), 50_000)
bench("p99", () -> HH.value_at_percentile(hist, 99.0), 50_000)

percentiles = [50.0, 90.0, 99.0, 99.9]
values = zeros(Int64, length(percentiles))
bench("percentile vector", () -> HH.value_at_percentile(hist, percentiles, values), 50_000)

bench("count_at_value", () -> HH.count_at_value(hist, 1234), 200_000)
