using HdrHistogram

const HH = HdrHistogram

function bench_record!(label, record_fn, n)
    GC.gc()
    record_fn()
    GC.gc()
    t0 = time_ns()
    for _ in 1:n
        record_fn()
    end
    elapsed = (time_ns() - t0) / 1e9
    rate = n / elapsed
    alloc = @allocated record_fn()
    println(rpad(label, 24), "ops/sec=", round(rate, digits=1), " alloc=", alloc)
end

const N = 1_000_000

hist = HH.Histogram(1, 1000, 2)
bench_record!("Histogram record", () -> HH.record_value!(hist, 10), N)

atomic = HH.AtomicHistogram(1, 1000, 2)
bench_record!("Atomic record", () -> HH.record_value!(atomic, 10), N)

concurrent = HH.ConcurrentHistogram(1, 1000, 2)
bench_record!("Concurrent record", () -> HH.record_value!(concurrent, 10), N)

recorder = HH.Recorder(HH.ConcurrentHistogram(1, 1000, 2))
bench_record!("Recorder record", () -> HH.record_value!(recorder, 10), N)

single = HH.SingleWriterRecorder(HH.Histogram(1, 1000, 2))
bench_record!("SingleWriter record", () -> HH.record_value!(single, 10), N)
