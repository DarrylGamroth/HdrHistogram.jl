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
for i in 1:100_000
    HH.record_value!(hist, i % 10_000)
end

bench("encode compressed", 200, HH.encode_into_compressed_byte_buffer, hist)
encoded = HH.encode_into_compressed_byte_buffer(hist)
bench("decode compressed", 200, HH.decode_from_compressed_byte_buffer, encoded)

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

bench("log reader", 50, read_log!, log_bytes)
