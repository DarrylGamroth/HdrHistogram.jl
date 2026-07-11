HdrHistogram.jl: Julia port of High Dynamic Range (HDR) Histogram

[![CI](https://github.com/DarrylGamroth/HdrHistogram.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/DarrylGamroth/HdrHistogram.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/DarrylGamroth/HdrHistogram.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/HdrHistogram.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

HdrHistogram
----------------------------------------------

This port contains a subset of the functionality supported by the Java
implementation.  The current supported features are:

* Histograms with parametric count size (`Int64`, `Int32`, and `Int16`; 64 bit counts default)
* Atomic histograms with parametric count size
* Concurrent histograms with parametric count size (concurrent recording; queries are not synchronized)
* Synchronized histograms with parametric count size (recording/query methods are locked)
* All iterator types (all values, recorded, percentiles, linear, logarithmic)
* Auto-resizing of histograms
* Reader/writer phaser and interval recorders
* Histogram encoding/decoding (V2 encode, V0-V2 decode)
* Histogram log reader/writer
* Recorder and SingleWriterRecorder interval sampling
* Histogram log scanner/processor helpers
* Copy/copy-to and coordinated-omission-corrected copies
* Histogram subtraction, range/inverse queries, explicit non-zero minima, and semantic equality

Features unlikely to be implemented:

* Double histograms
* Runtime histogram shifting or mutable auto-resize toggles (layout configuration remains immutable)

# Performance notes

* Recording into fixed-size histograms is allocation-free; auto-resize and interval histogram swaps allocate by design.
* Tests include no-allocation checks for fixed-size recording, bulk recording, direct queries, and all iterator types.
* `perf/iterator_alloc.jl` prints allocation counts for recording and iterator passes.
* `perf/record_bench.jl`, `perf/query_bench.jl`, `perf/iterator_bench.jl`, and `perf/logio_bench.jl` provide quick throughput/alloc benchmarks.
* Run benchmarks with `julia --project=perf -e 'using Pkg; Pkg.instantiate()'`, followed by e.g. `julia --project=perf perf/record_bench.jl`.
* Julia < 1.12 uses Atomix for atomic storage; it is installed automatically as a package dependency.
* Ordinary `for` iteration is allocation-free and yields immutable iteration values that are safe to retain.
* For `SynchronizedHistogram`, keep iterators and multi-step reads inside `lock(h) do ... end` blocks.
* `ConcurrentHistogram` auto-resize uses a writer phaser: ordinary inserts do not take the resize lock, while a resize still allocates and merges storage.
* Narrow atomic counters use checked updates and throw `OverflowError` rather than wrapping through negative counts.
* `mean`, `stddev`, percentile/range queries, compatible-layout `add`, `copyto!`,
  equality, and `subtract!` use direct count-array kernels and do not require iterator state.
* `push!`, `append!`, and `record_values!` provide idiomatic scalar and bulk recording APIs.
* `EncodingWorkspace` and the `encode_into_*_byte_buffer!` methods reuse encoding storage.
* The mutable `iterate!` cursor API remains available when explicit state reuse is convenient.
* Convenience helpers like `recorded_values_state(h)` or `linear_iterator_state(h, bucket)` return `(iter, state)` pairs.
* `percentile_plot` uses Plots.jl when available (optional dependency).

Example iterator usage:

```Julia
iter, state = HdrHistogram.recorded_values_state(histogram)
while HdrHistogram.iterate!(iter, state)
    v = state.iter_value
    # use HdrHistogram.value_iterated_to(v), etc.
end
```

Example allocation-free queries and bulk recording:

```Julia
append!(histogram, values)
m = HdrHistogram.mean(histogram)
p99 = HdrHistogram.value_at_percentile(histogram, 99.0)
```

Example percentile plot (requires Plots.jl):

```Julia
using HdrHistogram
using Plots

h = HdrHistogram.Histogram(1, 1000, 2)
for v in 1:100
    HdrHistogram.record_value!(h, v)
end

plt = HdrHistogram.percentile_plot(h; ticks_per_half_distance=5, value_scale=1.0)
display(plt)
```

# Simple Tutorial

## Recording values

```Julia
using HdrHistogram

# Initialize the histogram
histogram = HdrHistogram.Histogram(
    1,          # Minimum value
    3600000000, # Maximum value
    3           # Number of significant figures
)

# Record value
HdrHistogram.record_value!(
    histogram,      # Histogram to record to
    12345)          # Value to record

# Record value n times
HdrHistogram.record_value!(
    histogram,      # Histogram to record to
    12345,          # Value to record
    10)             # Record value 10 times

# Record an iterable of values in one bulk call
append!(histogram, values)

# Record value with correction for co-ordinated omission.
HdrHistogram.record_corrected_value!(
    histogram,      # Histogram to record to
    12345,          # Value to record
    1000)           # Record with expected interval of 1000.

# Print out the values of the histogram
HdrHistogram.percentile_print(
    stdout,         # IO to write to
    histogram,      # Histogram to print
    5,              # Granularity of printed values
    1.0)            # Multiplier for results

# Initialize interval recorder. Multiple tasks can write to a recorder at the same time
recorder = HdrHistogram.Recorder(
    1,          # Minimum value
    3600000000, # Maximum value
    3)          # Number of significant figures

# Record value
HdrHistogram.record_value!(
    recorder,       # Recorder to record to
    12345)          # Value to record

# Record value n times
HdrHistogram.record_value!(
    recorder,       # Recorder to record to
    12345,          # Value to record
    10)             # Record value 10 times

# Record value with correction for co-ordinated omission.
HdrHistogram.record_corrected_value!(
    recorder,       # Recorder to record to
    12345,          # Value to record
    1000)           # Record with expected interval of 1000.

# Read an interval histogram from the recorder and allocate a new one for recording
interval = HdrHistogram.interval_histogram(
    recorder)       # Recorder to read from

# Read an interval histogram from the recorder and recycle an old histogram for recording 
new_interval = HdrHistogram.interval_histogram(
    recorder,       # Recorder to read from 
    interval)       # Histogram to recycle    
```
