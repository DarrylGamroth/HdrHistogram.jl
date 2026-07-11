pushfirst!(LOAD_PATH, dirname(@__DIR__))
using HdrHistogram
using BenchmarkTools

const HH = HdrHistogram
include(joinpath(@__DIR__, "benchutils.jl"))

values = Int64[mod(i * 7919, 900) + 1 for i in 1:4096]

hist = HH.Histogram(1, 1000, 2)
report_benchmark("Histogram record batch",
    @benchmark(HH.record_values!($hist, $values), evals=1), operations=length(values))

atomic = HH.AtomicHistogram(1, 1000, 2)
report_benchmark("Atomic record batch",
    @benchmark(HH.record_values!($atomic, $values), evals=1), operations=length(values))

concurrent = HH.ConcurrentHistogram(1, 1000, 2)
report_benchmark("Concurrent record batch",
    @benchmark(HH.record_values!($concurrent, $values), evals=1), operations=length(values))

auto_concurrent = HH.ConcurrentHistogram(2)
HH.record_value!(auto_concurrent, 1000)
report_benchmark("Auto concurrent record batch",
    @benchmark(HH.record_values!($auto_concurrent, $values), evals=1), operations=length(values))

recorder = HH.Recorder(HH.ConcurrentHistogram(1, 1000, 2))
report_benchmark("Recorder record batch",
    @benchmark(HH.record_values!($recorder, $values), evals=1), operations=length(values))

single = HH.SingleWriterRecorder(HH.Histogram(1, 1000, 2))
report_benchmark("SingleWriter record batch",
    @benchmark(HH.record_values!($single, $values), evals=1), operations=length(values))
