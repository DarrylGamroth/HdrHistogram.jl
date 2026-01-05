#!/usr/bin/env julia
using HdrHistogram

function read_values()
    values = Int64[]
    for line in eachline(stdin)
        s = strip(line)
        isempty(s) && continue
        push!(values, parse(Int64, s))
    end
    return values
end

function print_stats(h)
    println("total_count=", HdrHistogram.total_count(h))
    println("min=", min(h))
    println("max=", max(h))
    println("mean=", HdrHistogram.mean(h))
    println("stddev=", HdrHistogram.stddev(h))
    println("p50=", HdrHistogram.value_at_percentile(h, 50.0))
    println("p90=", HdrHistogram.value_at_percentile(h, 90.0))
    println("p99=", HdrHistogram.value_at_percentile(h, 99.0))
    println("p999=", HdrHistogram.value_at_percentile(h, 99.9))
    println("p100=", HdrHistogram.value_at_percentile(h, 100.0))
end

if length(ARGS) != 3
    println(stderr, "usage: compare.jl <lowest> <highest> <sigfigs>")
    exit(2)
end

lowest = parse(Int64, ARGS[1])
highest = parse(Int64, ARGS[2])
sigfigs = parse(Int64, ARGS[3])

h = HdrHistogram.Histogram(lowest, highest, sigfigs)
for v in read_values()
    HdrHistogram.record_value!(h, v)
end

print_stats(h)
