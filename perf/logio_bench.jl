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
for i in 1:100_000
    HH.record_value!(hist, i % 10_000)
end

bench("encode compressed", () -> HH.encode_into_compressed_byte_buffer(hist), 200)
encoded = HH.encode_into_compressed_byte_buffer(hist)
bench("decode compressed", () -> HH.decode_from_compressed_byte_buffer(encoded), 200)

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

bench("log reader", () -> begin
    reader = HH.HistogramLogReader(IOBuffer(log_bytes))
    while true
        h = HH.next_interval_histogram(reader)
        h === nothing && break
    end
    nothing
end, 50)
