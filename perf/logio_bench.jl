pushfirst!(LOAD_PATH, dirname(@__DIR__))
using HdrHistogram
using BenchmarkTools

const HH = HdrHistogram
include(joinpath(@__DIR__, "benchutils.jl"))

hist = HH.Histogram(1, 1_000_000, 3)
for i in 1:100_000
    HH.record_value!(hist, i % 10_000)
end

report_benchmark("encode compressed", @benchmark(HH.encode_into_compressed_byte_buffer($hist), evals=1))
workspace = HH.EncodingWorkspace()
HH.encode_into_compressed_byte_buffer!(workspace, hist)
report_benchmark("encode compressed (reuse)",
    @benchmark(HH.encode_into_compressed_byte_buffer!($workspace, $hist), evals=1))
encoded = HH.encode_into_compressed_byte_buffer(hist)
report_benchmark("decode compressed", @benchmark(HH.decode_from_compressed_byte_buffer($encoded), evals=1))

function build_log(n)
    buf = IOBuffer()
    writer = HH.HistogramLogWriter(buf)
    HH.output_log_format_version(writer)
    HH.output_legend(writer)
    for i in 1:n
        h = HH.Histogram(1, 1_000_000, 3)
        HH.record_value!(h, i % 10_000)
        HH.start_time_stamp!(h, 1000 * i)
        HH.end_time_stamp!(h, 1000 * i + 1000)
        HH.output_interval_histogram(writer, h)
    end
    return take!(buf)
end

log_bytes = build_log(200)

function read_log!(bytes)
    reader = HH.HistogramLogReader(IOBuffer(bytes))
    while true
        h = HH.next_interval_histogram(reader)
        h === nothing && break
    end
    return nothing
end

report_benchmark("log reader", @benchmark(read_log!($log_bytes), evals=1))
