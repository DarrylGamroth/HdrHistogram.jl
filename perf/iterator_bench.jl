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

recorded_iter = HH.RecordedValuesIterator(hist)
all_iter = HH.AllValuesIterator(hist)
linear_iter = HH.LinearIterator(hist, 10_000)
log_iter = HH.LogarithmicIterator(hist, 10_000, 2.0)

function consume(iter)
    total = 0
    state = iterate(iter)
    while state !== nothing
        v, st = state
        total += HH.count_added_in_this_iteration_step(v)
        state = iterate(iter, st)
    end
    return total
end

bench("recorded iterator", () -> consume(recorded_iter), 200)
bench("all values iterator", () -> consume(all_iter), 50)
bench("linear iterator", () -> consume(linear_iter), 200)
bench("log iterator", () -> consume(log_iter), 500)
