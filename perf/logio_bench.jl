using HdrHistogram

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

hist = Histogram(1, 1_000_000, 3)
for i in 1:100_000
    record_value!(hist, i % 10_000)
end

bench("encode compressed", () -> encode_into_compressed_byte_buffer(hist), 200)
encoded = encode_into_compressed_byte_buffer(hist)
bench("decode compressed", () -> decode_from_compressed_byte_buffer(encoded), 200)

function build_log(n)
    buf = IOBuffer()
    writer = HistogramLogWriter(buf)
    output_log_format_version(writer)
    output_legend(writer)
    for i in 1:n
        h = Histogram(1, 1_000_000, 3)
        record_value!(h, i % 10_000)
        start_time_stamp!(h, 1000 * i)
        end_time_stamp!(h, 1000 * i + 1000)
        output_interval_histogram(writer, h)
    end
    return take!(buf)
end

log_bytes = build_log(200)

bench("log reader", () -> begin
    reader = HistogramLogReader(IOBuffer(log_bytes))
    while true
        h = next_interval_histogram(reader)
        h === nothing && break
    end
    nothing
end, 50)
