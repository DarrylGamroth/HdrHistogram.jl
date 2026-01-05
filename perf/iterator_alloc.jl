#!/usr/bin/env julia
using HdrHistogram

function record_loop!(h, n)
    for _ in 1:n
        HdrHistogram.record_value!(h, 1)
    end
end

function iter_recorded(h)
    for _ in HdrHistogram.RecordedValuesIterator(h)
    end
end

function iter_all(h)
    for _ in HdrHistogram.AllValuesIterator(h)
    end
end

function iter_percentile(h)
    for _ in HdrHistogram.PercentileIterator(h, 5)
    end
end

h = HdrHistogram.Histogram(1, 1000, 2)
record_loop!(h, 1000)

println("record_value_alloc=", @allocated record_loop!(h, 1000))
println("recorded_iter_alloc=", @allocated iter_recorded(h))
println("all_iter_alloc=", @allocated iter_all(h))
println("percentile_iter_alloc=", @allocated iter_percentile(h))
