function report_benchmark(label, trial; operations::Int=1)
    estimate = minimum(trial)
    ns_per_operation = estimate.time / operations
    println(rpad(label, 32),
        "ns/op=", round(ns_per_operation, digits=2),
        " memory=", estimate.memory,
        " allocs=", estimate.allocs)
    return trial
end
