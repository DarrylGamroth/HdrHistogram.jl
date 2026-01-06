using HdrHistogram

const HH = HdrHistogram

function bench_record!(label, n, f, args...)
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
    println(rpad(label, 24),
        "ops/sec=", round(rate, digits=1),
        " ns/op=", round(ns_per, digits=1),
        " alloc=", alloc)
end

const N = 1_000_000

hist = HH.Histogram(1, 1000, 2)
bench_record!("Histogram record", N, HH.record_value!, hist, 10)

atomic = HH.AtomicHistogram(1, 1000, 2)
bench_record!("Atomic record", N, HH.record_value!, atomic, 10)

concurrent = HH.ConcurrentHistogram(1, 1000, 2)
bench_record!("Concurrent record", N, HH.record_value!, concurrent, 10)

recorder = HH.Recorder(HH.ConcurrentHistogram(1, 1000, 2))
bench_record!("Recorder record", N, HH.record_value!, recorder, 10)

single = HH.SingleWriterRecorder(HH.Histogram(1, 1000, 2))
bench_record!("SingleWriter record", N, HH.record_value!, single, 10)
