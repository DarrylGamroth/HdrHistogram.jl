using Test
using Base64
using HdrHistogram

include("aqua.jl")

const LOWEST = 1
const HIGHEST = 60 * 60 * 1000 * 1000 # e.g. for 1 hr in usec units
const SIGNIFICANT = 3
const TEST_VALUE_LEVEL = 4
const INTERVAL = 10_000
const SCALE = 512
const SCALED_INTERVAL = INTERVAL * SCALE

@testset "Basic" begin
    h = HdrHistogram.Histogram(Int64, LOWEST, HIGHEST, SIGNIFICANT)
    @test HdrHistogram.bucket_count(h) == 22
    @test HdrHistogram.sub_bucket_count(h) == 2048
    @test HdrHistogram.counts_length(h) == 23552
    @test HdrHistogram.unit_magnitude(h) == 0
    @test HdrHistogram.sub_bucket_half_count_magnitude(h) == 10
    @test HdrHistogram.counts_index(h, 0, 0) == 0
end

struct DummyHistogram <: HdrHistogram.AbstractHistogram{Int64}
    offset::Int64
    len::Int64
end

HdrHistogram.normalizing_index_offset(h::DummyHistogram) = h.offset
HdrHistogram.counts_length(h::DummyHistogram) = h.len

@testset "Normalize Index" begin
    h = DummyHistogram(3, 10)
    @test HdrHistogram.normalize_index(h, 2) == 9
    @test HdrHistogram.normalize_index(h, 12) == 9
    @test HdrHistogram.normalize_index(h, 15) == 2
end

@testset "Empty" begin
    h = HdrHistogram.Histogram(Int64, LOWEST, HIGHEST, SIGNIFICANT)
    @test min(h) == 0
    @test max(h) == 0
    @test HdrHistogram.mean(h) == 0
    @test HdrHistogram.stddev(h) == 0
end

@testset "Min Tracking Count Type" begin
    h = HdrHistogram.Histogram(Int8, 1, 1000, 2)
    @test min(h) == 0
    @test HdrHistogram.min_value(h) == typemax(Int64)
    HdrHistogram.record_value!(h, 300)
    @test HdrHistogram.min_value(h) == 300
end

@testset "Bucket Sizing Count Type" begin
    h1 = HdrHistogram.Histogram(Int8, 1, 1_000_000, 2)
    h2 = HdrHistogram.Histogram(Int64, 1, 1_000_000, 2)
    @test HdrHistogram.bucket_count(h1) == HdrHistogram.bucket_count(h2)
    @test HdrHistogram.counts_length(h1) == HdrHistogram.counts_length(h2)
end

@testset "Large Numbers" begin
    h = HdrHistogram.Histogram(20_000_000, 100_000_000, 5)

    HdrHistogram.record_value!(h, 100_000_000)
    HdrHistogram.record_value!(h, 20_000_000)
    HdrHistogram.record_value!(h, 30_000_000)

    @test HdrHistogram.values_are_equivalent(h, 20_000_000, HdrHistogram.value_at_percentile(h, 50.0))
    @test HdrHistogram.values_are_equivalent(h, 30_000_000, HdrHistogram.value_at_percentile(h, 50.0))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 83.33))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 83.34))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 99.0))
end

@testset "Recorded Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_value!(h, TEST_VALUE_LEVEL)
    @test HdrHistogram.count_at_value(h, TEST_VALUE_LEVEL) == 1
    @test HdrHistogram.total_count(h) == 1
end

@testset "Highest Equivalent Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    @test 8183 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8180 * 1024)
    @test 8191 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8191 * 1024)
    @test 8199 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8193 * 1024)
    @test 9999 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 9995 * 1024)
    @test 10007 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 10007 * 1024)
    @test 10015 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 10008 * 1024)
end

@testset "Scaled Highest Equivalent Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    @test HdrHistogram.highest_equivalent_value(h, 8180) == 8183
    @test HdrHistogram.highest_equivalent_value(h, 8191) == 8191
    @test HdrHistogram.highest_equivalent_value(h, 8193) == 8199
    @test HdrHistogram.highest_equivalent_value(h, 9995) == 9999
    @test HdrHistogram.highest_equivalent_value(h, 10007) == 10007
    @test HdrHistogram.highest_equivalent_value(h, 10008) == 10015
end

@testset "Maximum and Minimum" begin
    h = HdrHistogram.Histogram(20000000, 100000000, 5)
    HdrHistogram.record_value!(h, 100000000)
    HdrHistogram.record_value!(h, 20000000)
    HdrHistogram.record_value!(h, 30000000)
    @test HdrHistogram.max_value(h) == 100000000
    @test HdrHistogram.min_value(h) == 20000000
end

@testset "Get value at percentile" begin
    h = HdrHistogram.Histogram(LOWEST, 3600000000, 3)
    HdrHistogram.record_value!(h, 1)
    HdrHistogram.record_value!(h, 2)
    @test HdrHistogram.value_at_percentile(h, 50.0) == 1
    @test HdrHistogram.value_at_percentile(h, 50.00000000000001) == 1
    HdrHistogram.record_value!(h, 2)
    HdrHistogram.record_value!(h, 2)
    HdrHistogram.record_value!(h, 2)
    @test HdrHistogram.value_at_percentile(h, 30.0) == 2
    @test HdrHistogram.value_at_percentile(h, Inf) == 2
    @test HdrHistogram.value_at_percentile(h, NaN) == 1
end

@testset "Mean and Standard Deviation" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    val = [1000, 1000, 3000, 3000]
    for v in val
        HdrHistogram.record_value!(h, v)
    end
    @test HdrHistogram.mean(h) == 2000.5
    @test HdrHistogram.stddev(h) == 1000.5
end

function load_histogram()
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_value!(h, 1000, 10_000)
    HdrHistogram.record_value!(h, 100_000_000)
    return h
end

function load_corrected_histogram()
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_corrected_value!(h, 1000, INTERVAL, 10_000)
    HdrHistogram.record_corrected_value!(h, 100_000_000, INTERVAL)
    return h
end

function load_scaled_histogram()
    h = HdrHistogram.Histogram(1000, HIGHEST * SCALE, SIGNIFICANT)
    HdrHistogram.record_value!(h, 1000 * SCALE, 10_000)
    HdrHistogram.record_value!(h, 100_000_000 * SCALE)
    return h
end

function load_scaled_corrected_histogram()
    h = HdrHistogram.Histogram(1000, HIGHEST * SCALE, SIGNIFICANT)
    HdrHistogram.record_corrected_value!(h, 1000 * SCALE, SCALED_INTERVAL, 10_000)
    HdrHistogram.record_corrected_value!(h, 100_000_000 * SCALE, SCALED_INTERVAL)
    return h
end

@testset "Total count" begin
    h = load_histogram()
    @test HdrHistogram.total_count(h) == 10001
    h = load_corrected_histogram()
    @test HdrHistogram.total_count(h) == 20000
end

@testset "Reset Internal Counters" begin
    h = HdrHistogram.Histogram(Int8, 1, 1000, 2)
    HdrHistogram.counts(h)[1] = 2
    HdrHistogram.counts(h)[6] = 3
    HdrHistogram.reset_internal_counters!(h)
    @test HdrHistogram.total_count(h) == 5
    @test HdrHistogram.min_value(h) == HdrHistogram.value_at_index(h, 5)
    expected_max = HdrHistogram.highest_equivalent_value(h, HdrHistogram.value_at_index(h, 5))
    @test HdrHistogram.max_value(h) == expected_max
end

@testset "Out of range" begin
    h = HdrHistogram.Histogram(1, 1000, 4)
    # @test HdrHistogram.record_value!(h, 32767)
    @test_throws ArgumentError HdrHistogram.record_value!(h, -1)
    @test_throws ArgumentError HdrHistogram.record_value!(h, 32767, 0)
    @test_throws ArgumentError HdrHistogram.record_value!(h, 32768)
end

@testset "Checked Count Access" begin
    for h in (
        HdrHistogram.Histogram(1, 1000, 2),
        HdrHistogram.AtomicHistogram(1, 1000, 2),
        HdrHistogram.ConcurrentHistogram(1, 1000, 2),
    )
        HdrHistogram.record_value!(h, 10)
        last_index = HdrHistogram.counts_length(h) - 1
        @test HdrHistogram.count_at_index(h, Int64(last_index)) >= 0
        @test_throws BoundsError HdrHistogram.count_at_index(h, Int64(last_index + 1))
        @test_throws BoundsError HdrHistogram.counts_get_direct(h, last_index + 1)
        @test HdrHistogram.count_at_value(h, typemax(Int64)) ==
              HdrHistogram.count_at_index(h, Int64(last_index))
    end
end

@testset "Bulk Recording" begin
    h = HdrHistogram.Histogram(1, 1000, 2)
    @test push!(h, 10) === h
    @test append!(h, [10, 20, 30]) === h
    @test HdrHistogram.record_values!(h, (40, 50), 2) === h
    @test HdrHistogram.total_count(h) == 8
    @test HdrHistogram.count_at_value(h, 10) == 2
    @test HdrHistogram.count_at_value(h, 40) == 2

    recorder = HdrHistogram.Recorder(1, 1000, 2)
    @test append!(recorder, 1:10) === recorder
    @test HdrHistogram.total_count(HdrHistogram.interval_histogram(recorder)) == 10
end

@testset "Java-compatible Addition" begin
    source = HdrHistogram.Histogram(1, 1_000_000, 2)
    HdrHistogram.record_value!(source, 100_000)
    source_index = HdrHistogram.counts_index_for(source, 100_000)
    source_low = HdrHistogram.value_at_index(source, source_index)
    source_high = HdrHistogram.highest_equivalent_value(source, source_low)

    target = HdrHistogram.Histogram(1, 1_000_000, 3)
    HdrHistogram.start_time_stamp!(source, 100)
    HdrHistogram.end_time_stamp!(source, 400)
    HdrHistogram.start_time_stamp!(target, 200)
    HdrHistogram.end_time_stamp!(target, 300)
    @test HdrHistogram.add!(target, source) === target
    @test HdrHistogram.count_at_value(target, source_low) == 1
    @test HdrHistogram.count_at_value(target, source_high) == 0
    @test HdrHistogram.start_time_stamp(target) == 100
    @test HdrHistogram.end_time_stamp(target) == 400

    direct = HdrHistogram.Histogram(1, 1000, 2)
    append!(direct, [10, 20, 20])
    HdrHistogram.add(direct, direct)
    @test HdrHistogram.total_count(direct) == 6
    @test HdrHistogram.count_at_value(direct, 20) == 4

    too_small = HdrHistogram.Histogram(1, 1000, 2)
    too_large = HdrHistogram.Histogram(1, 1_000_000, 2)
    append!(too_large, [10, 1_000_000])
    @test_throws ArgumentError HdrHistogram.add(too_small, too_large)
    @test HdrHistogram.total_count(too_small) == 0
end

@testset "Copy and Corrected Copy" begin
    # Configuration matrix: every counter width crosses every concrete
    # histogram variant for ordinary copy/copy-to behavior.
    for C in (Int16, Int32, Int64)
        for constructor in (
            HdrHistogram.Histogram,
            HdrHistogram.AtomicHistogram,
            HdrHistogram.ConcurrentHistogram,
            HdrHistogram.SynchronizedHistogram,
        )
            source = constructor(C, 1, 1_000_000, 3)
            HdrHistogram.record_value!(source, 0, 2)
            HdrHistogram.record_value!(source, 10, 3)
            HdrHistogram.record_value!(source, 10_000)
            HdrHistogram.start_time_stamp!(source, 100)
            HdrHistogram.end_time_stamp!(source, 400)
            HdrHistogram.tag!(source, "source")

            copied = copy(source)
            @test typeof(copied) === typeof(source)
            @test copied == source
            @test isequal(copied, source)
            @test hash(copied) == hash(source)
            @test copied !== source
            @test HdrHistogram.start_time_stamp(copied) == 100
            @test HdrHistogram.end_time_stamp(copied) == 400
            @test HdrHistogram.tag(copied) === nothing

            target = constructor(C, 1, 1_000_000, 3)
            HdrHistogram.record_value!(target, 999)
            HdrHistogram.tag!(target, "old-target")
            @test copyto!(target, source) === target
            @test target == source
            @test HdrHistogram.count_at_value(target, 999) == 0
            @test HdrHistogram.tag(target) === nothing
            @test copyto!(target, target) === target
        end
    end

    for constructor in (
        HdrHistogram.Histogram,
        HdrHistogram.ConcurrentHistogram,
        HdrHistogram.SynchronizedHistogram,
    )
        source = constructor(Int32, 3)
        HdrHistogram.record_value!(source, 10_000_000)
        copied = copy(source)
        @test copied == source
        @test HdrHistogram.auto_resize(copied)
        @test HdrHistogram.highest_trackable_value(copied) ==
              HdrHistogram.highest_trackable_value(source)
    end

    configured = HdrHistogram._init_with_config(
        HdrHistogram.Histogram{Int64}, 1, 1_000_000, 3, true, 0.5, 17)
    HdrHistogram.record_value!(configured, 10, 3)
    configured_copy = copy(configured)
    @test configured_copy == configured
    @test HdrHistogram.conversion_ratio(configured_copy) == 0.5
    @test HdrHistogram.normalizing_index_offset(configured_copy) == 17
    configured_removed = similar(configured)
    HdrHistogram.record_value!(configured_removed, 10)
    HdrHistogram.subtract!(configured_copy, configured_removed)
    @test HdrHistogram.count_at_value(configured_copy, 10) == 2
    @test HdrHistogram.min_nonzero(configured_copy) == 10

    source = HdrHistogram.Histogram(Int32, 1, 1_000_000, 3)
    HdrHistogram.record_value!(source, 10_000)
    HdrHistogram.start_time_stamp!(source, 12)
    HdrHistogram.end_time_stamp!(source, 34)
    corrected = HdrHistogram.copy_corrected(source, 1_000)
    @test HdrHistogram.total_count(corrected) == 10
    @test HdrHistogram.start_time_stamp(corrected) == 12
    @test HdrHistogram.end_time_stamp(corrected) == 34

    target = similar(source)
    @test HdrHistogram.copy_corrected!(target, source, 1_000) === target
    @test target == corrected
    alias_copy = HdrHistogram.copy_corrected_for_coordinated_omission(source, 1_000)
    @test alias_copy == corrected
    HdrHistogram.reset!(target)
    @test HdrHistogram.copy_into_corrected_for_coordinated_omission!(target, source, 1_000) === target
    @test target == corrected

    self_corrected = copy(source)
    @test HdrHistogram.copy_corrected!(self_corrected, self_corrected, 1_000) === self_corrected
    @test self_corrected == corrected
end

@testset "Range and Inverse Queries" begin
    for histogram in (
        HdrHistogram.Histogram(Int16, 1, 1_000_000, 3),
        HdrHistogram.AtomicHistogram(Int32, 1, 1_000_000, 3),
        HdrHistogram.ConcurrentHistogram(Int64, 1, 1_000_000, 3),
        HdrHistogram.SynchronizedHistogram(Int16, 1, 1_000_000, 3),
    )
        @test HdrHistogram.min_nonzero(histogram) == typemax(Int64)
        @test HdrHistogram.min_nonzero_value(histogram) == typemax(Int64)
        @test HdrHistogram.percentile_at_or_below_value(histogram, 10) == 100.0
        @test HdrHistogram.count_between_values(histogram, 0, typemax(Int64)) == 0

        HdrHistogram.record_value!(histogram, 0, 2)
        HdrHistogram.record_value!(histogram, 10, 3)
        HdrHistogram.record_value!(histogram, 10_000)
        @test HdrHistogram.min_nonzero(histogram) == 10
        @test HdrHistogram.count_between_values(histogram, 0, 10) == 5
        @test HdrHistogram.count_between_values(histogram, 11, 9_999) == 0
        @test HdrHistogram.count_between_values(histogram, 10_000, typemax(Int64)) == 1
        @test HdrHistogram.count_between_values(histogram, 10_000, 10) == 0
        @test HdrHistogram.percentile_at_or_below_value(histogram, 0) ≈ 100 / 3
        @test HdrHistogram.percentile_at_or_below_value(histogram, 10) ≈ 250 / 3
        @test HdrHistogram.percentile_at_or_below_value(histogram, typemax(Int64)) == 100.0
        @test_throws ArgumentError HdrHistogram.count_between_values(histogram, -1, 10)
        @test_throws ArgumentError HdrHistogram.percentile_at_or_below_value(histogram, -1)
    end
end

@testset "Subtraction and Semantic Equality" begin
    for C in (Int16, Int32, Int64)
        for constructor in (
            HdrHistogram.Histogram,
            HdrHistogram.AtomicHistogram,
            HdrHistogram.ConcurrentHistogram,
            HdrHistogram.SynchronizedHistogram,
        )
            target = constructor(C, 1, 1_000_000, 3)
            HdrHistogram.record_value!(target, 0, 2)
            HdrHistogram.record_value!(target, 10, 3)
            HdrHistogram.record_value!(target, 10_000)
            HdrHistogram.start_time_stamp!(target, 100)
            HdrHistogram.end_time_stamp!(target, 400)
            HdrHistogram.tag!(target, "keep")

            source = constructor(C, 1, 1_000_000, 3)
            HdrHistogram.record_value!(source, 0)
            HdrHistogram.record_value!(source, 10, 2)
            @test HdrHistogram.subtract!(target, source) === target
            @test HdrHistogram.total_count(target) == 3
            @test HdrHistogram.count_at_value(target, 0) == 1
            @test HdrHistogram.count_at_value(target, 10) == 1
            @test HdrHistogram.count_at_value(target, 10_000) == 1
            @test HdrHistogram.start_time_stamp(target) == 100
            @test HdrHistogram.end_time_stamp(target) == 400
            @test HdrHistogram.tag(target) == "keep"
        end
    end

    # A lower-resolution destination exercises value remapping and rollback.
    destination = HdrHistogram.Histogram(1, 1_000_000, 2)
    append!(destination, (10, 100_000))
    before = copy(destination)
    too_many = HdrHistogram.Histogram(1, 1_000_000, 3)
    HdrHistogram.record_value!(too_many, 10)
    HdrHistogram.record_value!(too_many, 100_000, 2)
    @test_throws ArgumentError HdrHistogram.subtract!(destination, too_many)
    @test destination == before

    removable = HdrHistogram.Histogram(1, 1_000_000, 3)
    HdrHistogram.record_value!(removable, 10)
    @test HdrHistogram.subtract(destination, removable) === destination
    @test HdrHistogram.total_count(destination) == 1

    out_of_range = HdrHistogram.Histogram(1, 10_000_000, 2)
    HdrHistogram.record_value!(out_of_range, 10_000_000)
    unchanged = copy(destination)
    @test_throws ArgumentError HdrHistogram.subtract!(destination, out_of_range)
    @test destination == unchanged

    self = HdrHistogram.Histogram(1, 1_000, 2)
    append!(self, (10, 20))
    HdrHistogram.start_time_stamp!(self, 7)
    HdrHistogram.end_time_stamp!(self, 9)
    HdrHistogram.tag!(self, "preserved")
    @test HdrHistogram.subtract!(self, self) === self
    @test HdrHistogram.total_count(self) == 0
    @test HdrHistogram.start_time_stamp(self) == 7
    @test HdrHistogram.end_time_stamp(self) == 9
    @test HdrHistogram.tag(self) == "preserved"

    small = HdrHistogram.Histogram(Int16, 1, 1_000, 3)
    large = HdrHistogram.AtomicHistogram(Int64, 1, 1_000_000, 3)
    append!(small, (1, 10, 100))
    append!(large, (1, 10, 100))
    @test small == large
    @test large == small
    @test hash(small) == hash(large)
    HdrHistogram.start_time_stamp!(small, 1)
    HdrHistogram.start_time_stamp!(large, 2)
    HdrHistogram.tag!(small, "left")
    HdrHistogram.tag!(large, "right")
    @test small == large
    HdrHistogram.record_value!(large, 200)
    @test small != large

    different_precision = HdrHistogram.Histogram(1, 1_000, 2)
    append!(different_precision, (1, 10, 100))
    @test small != different_precision

    different_ratio = HdrHistogram._init_with_config(
        HdrHistogram.Histogram{Int16}, 1, 1_000, 3, false, 0.5, 0)
    append!(different_ratio, (1, 10, 100))
    @test small != different_ratio
end

@testset "Auto Resize" begin
    h = HdrHistogram.Histogram(3)
    HdrHistogram.record_value!(h, 1)
    HdrHistogram.record_value!(h, 10_000_000)
    @test HdrHistogram.total_count(h) == 2
    @test HdrHistogram.highest_trackable_value(h) >= 10_000_000
end

@testset "Atomic Histogram" begin
    h = HdrHistogram.AtomicHistogram(1, 1000, 2)
    HdrHistogram.record_value!(h, 10)
    HdrHistogram.record_value!(h, 20, 2)
    @test HdrHistogram.count_at_value(h, 10) == 1
    @test HdrHistogram.count_at_value(h, 20) == 2
    @test HdrHistogram.total_count(h) == 3
    @test HdrHistogram.min_value(h) == 10
    @test HdrHistogram.max_value(h) == 20

    typed = HdrHistogram.AtomicHistogram(Int64, Int32(1), Int32(1000), Int32(2))
    @test HdrHistogram.counts_length(typed) == HdrHistogram.counts_length(h)
end

@testset "Concurrent Histogram" begin
    h = HdrHistogram.ConcurrentHistogram(1, 1000, 2)
    HdrHistogram.record_value!(h, 10)
    HdrHistogram.record_value!(h, 20, 2)
    @test HdrHistogram.count_at_value(h, 10) == 1
    @test HdrHistogram.count_at_value(h, 20) == 2
    @test HdrHistogram.total_count(h) == 3
    @test HdrHistogram.min_value(h) == 10
    @test HdrHistogram.max_value(h) == 20

    auto = HdrHistogram.ConcurrentHistogram(3)
    HdrHistogram.record_value!(auto, 1)
    HdrHistogram.record_value!(auto, 10_000_000)
    @test HdrHistogram.total_count(auto) == 2
    @test HdrHistogram.highest_trackable_value(auto) >= 10_000_000

    stressed = HdrHistogram.ConcurrentHistogram(2)
    writers = max(2, Threads.nthreads())
    tasks = [Threads.@spawn begin
        for i in 1:2000
            value = (1, 1000, 100_000, 10_000_000)[mod1(i + writer, 4)]
            HdrHistogram.record_value!(stressed, value)
        end
    end for writer in 1:writers]
    foreach(fetch, tasks)
    expected_total = 2000 * writers
    @test HdrHistogram.total_count(stressed) == expected_total
    @test sum(HdrHistogram.count_at_index(stressed, Int64(i))
        for i in 0:HdrHistogram.counts_length(stressed)-1) == expected_total
end

@testset "Parametric Counter Families" begin
    for C in (Int16, Int32, Int64)
        for histogram in (
            HdrHistogram.Histogram(C, 1, 1_000_000, 3),
            HdrHistogram.AtomicHistogram(C, 1, 1_000_000, 3),
            HdrHistogram.ConcurrentHistogram(C, 1, 1_000_000, 3),
            HdrHistogram.SynchronizedHistogram(C, 1, 1_000_000, 3),
        )
            HdrHistogram.record_value!(histogram, 42)
            HdrHistogram.record_value!(histogram, 42, 2)
            @test HdrHistogram.total_count(histogram) == 3
            @test HdrHistogram.count_at_value(histogram, 42) == 3
        end

        for histogram in (
            HdrHistogram.Histogram(C, 3),
            HdrHistogram.ConcurrentHistogram(C, 3),
            HdrHistogram.SynchronizedHistogram(C, 3),
        )
            HdrHistogram.record_value!(histogram, 1_000_000)
            @test HdrHistogram.total_count(histogram) == 1
            @test HdrHistogram.highest_trackable_value(histogram) >= 1_000_000
        end
    end

    for C in (Int16, Int32)
        for constructor in (
            HdrHistogram.Histogram,
            HdrHistogram.AtomicHistogram,
            HdrHistogram.ConcurrentHistogram,
            HdrHistogram.SynchronizedHistogram,
        )
            limit = Int64(typemax(C))
            histogram = constructor(C, 1, 1000, 2)
            HdrHistogram.record_value!(histogram, 10, limit)
            @test_throws OverflowError HdrHistogram.record_value!(histogram, 10)
            @test HdrHistogram.count_at_value(histogram, 10) == limit
            @test HdrHistogram.total_count(histogram) == limit

            target = constructor(C, 1, 1000, 2)
            source = constructor(C, 1, 1000, 2)
            HdrHistogram.record_value!(target, 10, limit - 10)
            HdrHistogram.record_value!(source, 10, 20)
            @test_throws OverflowError HdrHistogram.add!(target, source)
            @test HdrHistogram.count_at_value(target, 10) == limit - 10
            @test HdrHistogram.total_count(target) == limit - 10
        end
    end

    for constructor in (HdrHistogram.AtomicHistogram, HdrHistogram.ConcurrentHistogram)
        histogram = constructor(Int32, 1, 1000, 2)
        writer_count = max(2, Threads.nthreads())
        records_per_writer = 2000
        writers = [Threads.@spawn begin
            for _ in 1:records_per_writer
                HdrHistogram.record_value!(histogram, 10)
            end
        end for _ in 1:writer_count]
        foreach(fetch, writers)
        @test HdrHistogram.count_at_value(histogram, 10) == records_per_writer * writer_count
        @test HdrHistogram.total_count(histogram) == records_per_writer * writer_count
    end

    recorder = HdrHistogram.Recorder(HdrHistogram.AtomicHistogram(Int16, 1, 1000, 2))
    HdrHistogram.record_value!(recorder, 10)
    @test HdrHistogram.count_at_value(HdrHistogram.interval_histogram(recorder), 10) == 1

    single = HdrHistogram.SingleWriterRecorder(HdrHistogram.Histogram(Int32, 1, 1000, 2))
    HdrHistogram.record_value!(single, 20)
    @test HdrHistogram.count_at_value(HdrHistogram.interval_histogram(single), 20) == 1
end

@testset "Synchronized Histogram" begin
    h = HdrHistogram.SynchronizedHistogram(1, 1000, 2)
    HdrHistogram.record_value!(h, 10)
    HdrHistogram.record_value!(h, 20, 2)
    @test HdrHistogram.count_at_value(h, 10) == 1
    @test HdrHistogram.count_at_value(h, 20) == 2
    @test HdrHistogram.total_count(h) == 3
    @test HdrHistogram.min_value(h) == 10
    @test HdrHistogram.max_value(h) == 20

    lock(h) do
        @test HdrHistogram.count_at_value(h, 20) == 2
    end

    left = HdrHistogram.SynchronizedHistogram(1, 1000, 2)
    right = HdrHistogram.SynchronizedHistogram(1, 1000, 2)
    HdrHistogram.record_value!(left, 10)
    HdrHistogram.record_value!(right, 20)
    additions = (
        Threads.@spawn(HdrHistogram.add(left, right)),
        Threads.@spawn(HdrHistogram.add(right, left)),
    )
    foreach(fetch, additions)
    @test HdrHistogram.total_count(left) >= 2
    @test HdrHistogram.total_count(right) >= 2
end

@testset "Interval Recorder" begin
    r = HdrHistogram.IntervalRecorder(HdrHistogram.Histogram(1, 1000, 2))
    HdrHistogram.record_value!(r, 10)
    HdrHistogram.record_value!(r, 20)
    interval = HdrHistogram.interval_histogram(r)
    @test HdrHistogram.total_count(interval) == 2
    @test HdrHistogram.count_at_value(interval, 10) == 1
    @test HdrHistogram.count_at_value(interval, 20) == 1

    HdrHistogram.record_value!(r, 10)
    interval2 = HdrHistogram.interval_histogram(r, interval)
    @test HdrHistogram.total_count(interval2) == 1
    @test HdrHistogram.count_at_value(interval2, 10) == 1
end

@testset "Recorder" begin
    r = HdrHistogram.Recorder(2)
    HdrHistogram.record_value!(r, 10)
    interval = HdrHistogram.interval_histogram(r)
    @test HdrHistogram.total_count(interval) == 1
    @test HdrHistogram.count_at_value(interval, 10) == 1
    @test HdrHistogram.end_time_stamp(interval) >= HdrHistogram.start_time_stamp(interval)

    HdrHistogram.record_value!(r, 10, 2)
    interval2 = HdrHistogram.interval_histogram(r, interval)
    @test HdrHistogram.total_count(interval2) == 2
    @test HdrHistogram.count_at_value(interval2, 10) == 2

    serialized = HdrHistogram.Recorder(HdrHistogram.Histogram(1, 1000, 2))
    writers = [Threads.@spawn(append!(serialized, fill(10, 1000))) for _ in 1:max(2, Threads.nthreads())]
    foreach(fetch, writers)
    @test HdrHistogram.total_count(HdrHistogram.interval_histogram(serialized)) ==
          1000 * max(2, Threads.nthreads())
end

@testset "SingleWriterRecorder" begin
    r = HdrHistogram.SingleWriterRecorder(2)
    HdrHistogram.record_value!(r, 10)
    interval = HdrHistogram.interval_histogram(r)
    @test HdrHistogram.total_count(interval) == 1
    @test HdrHistogram.count_at_value(interval, 10) == 1

    HdrHistogram.record_corrected_value!(r, 10_000, 1000)
    interval2 = HdrHistogram.interval_histogram(r, interval)
    @test HdrHistogram.total_count(interval2) > 1
end

@testset "Recorder Concurrent Sampling" begin
    recorder = HdrHistogram.Recorder(1, 1_000_000, 3)
    writer_count = max(2, Threads.nthreads())
    records_per_writer = 5000
    writers = [Threads.@spawn begin
        for i in 1:records_per_writer
            HdrHistogram.record_value!(recorder, mod1(i + writer, 1000))
            i % 100 == 0 && yield()
        end
    end for writer in 1:writer_count]

    sampled = 0
    recycle = nothing
    while !all(istaskdone, writers)
        interval = recycle === nothing ? HdrHistogram.interval_histogram(recorder) :
                   HdrHistogram.interval_histogram(recorder, recycle)
        sampled += HdrHistogram.total_count(interval)
        recycle = interval
        yield()
    end
    foreach(fetch, writers)
    interval = recycle === nothing ? HdrHistogram.interval_histogram(recorder) :
               HdrHistogram.interval_histogram(recorder, recycle)
    sampled += HdrHistogram.total_count(interval)
    @test sampled == records_per_writer * writer_count

    single = HdrHistogram.SingleWriterRecorder(1, 1_000_000, 3)
    writer = Threads.@spawn begin
        for i in 1:10_000
            HdrHistogram.record_value!(single, mod1(i, 1000))
            i % 100 == 0 && yield()
        end
    end
    sampled = 0
    recycle = nothing
    while !istaskdone(writer)
        interval = recycle === nothing ? HdrHistogram.interval_histogram(single) :
                   HdrHistogram.interval_histogram(single, recycle)
        sampled += HdrHistogram.total_count(interval)
        recycle = interval
        yield()
    end
    fetch(writer)
    interval = recycle === nothing ? HdrHistogram.interval_histogram(single) :
               HdrHistogram.interval_histogram(single, recycle)
    sampled += HdrHistogram.total_count(interval)
    @test sampled == 10_000
end

@testset "Encoding Roundtrip" begin
    h = HdrHistogram.Histogram(1, 1000, 3)
    for v in 1:100
        HdrHistogram.record_value!(h, v)
    end
    buf = HdrHistogram.encode_into_byte_buffer(h)
    decoded = HdrHistogram.decode_from_byte_buffer(buf)
    @test HdrHistogram.total_count(decoded) == HdrHistogram.total_count(h)
    @test min(decoded) == min(h)
    @test max(decoded) == max(h)
    @test HdrHistogram.value_at_percentile(decoded, 99.0) == HdrHistogram.value_at_percentile(h, 99.0)
end

@testset "Encoding Compressed Roundtrip" begin
    h = HdrHistogram.Histogram(1, 1000, 3)
    for v in 1:100
        HdrHistogram.record_value!(h, v)
    end
    buf = HdrHistogram.encode_into_compressed_byte_buffer(h)
    decoded = HdrHistogram.decode_from_compressed_byte_buffer(buf)
    @test HdrHistogram.total_count(decoded) == HdrHistogram.total_count(h)
    @test min(decoded) == min(h)
    @test max(decoded) == max(h)
end

@testset "Encoding Workspace and Decoder Bounds" begin
    h = HdrHistogram._init_with_config(
        HdrHistogram.Histogram{Int64}, 1, 1000, 2, false, 1.0, 17)
    append!(h, [0, 1, 10, 100, 1000])
    workspace = HdrHistogram.EncodingWorkspace()
    encoded = HdrHistogram.encode_into_compressed_byte_buffer!(workspace, h)
    decoded = HdrHistogram.decode_from_compressed_byte_buffer(encoded)
    @test HdrHistogram.normalizing_index_offset(decoded) == 17
    @test [HdrHistogram.count_at_value(decoded, Int64(v)) for v in (0, 1, 10, 100, 1000)] == ones(Int, 5)
    @test HdrHistogram.encode_into_compressed_byte_buffer!(workspace, h) === encoded

    valid = HdrHistogram.encode_into_byte_buffer(HdrHistogram.Histogram(1, 1000, 2))

    zero_writer = HdrHistogram.BufferWriter(16)
    HdrHistogram.zigzag_put_long!(zero_writer, -10_000)
    oversized_zero_run = HdrHistogram.finish!(zero_writer)
    malformed = vcat(valid[1:HdrHistogram.ENCODING_HEADER_SIZE], oversized_zero_run)
    malformed_writer = HdrHistogram.BufferWriter(malformed, 1)
    HdrHistogram.write_at_be_i32!(malformed_writer, 5, Int32(length(oversized_zero_run)))
    @test_throws ArgumentError HdrHistogram.decode_from_byte_buffer(malformed)

    truncated = vcat(valid[1:HdrHistogram.ENCODING_HEADER_SIZE], UInt8[0x80])
    truncated_writer = HdrHistogram.BufferWriter(truncated, 1)
    HdrHistogram.write_at_be_i32!(truncated_writer, 5, Int32(1))
    @test_throws ArgumentError HdrHistogram.decode_from_byte_buffer(truncated)

    invalid_offset = HdrHistogram.encode_into_byte_buffer(h)
    invalid_offset_writer = HdrHistogram.BufferWriter(invalid_offset, 1)
    HdrHistogram.write_at_be_i32!(invalid_offset_writer, 9, typemax(Int32))
    @test_throws ArgumentError HdrHistogram.decode_from_byte_buffer(invalid_offset)
end

@testset "Log Reader Writer Roundtrip" begin
    h = HdrHistogram.Histogram(1, 1000, 2)
    HdrHistogram.record_value!(h, 10)
    HdrHistogram.record_value!(h, 20)
    HdrHistogram.start_time_stamp!(h, 1_000)
    HdrHistogram.end_time_stamp!(h, 2_000)
    HdrHistogram.tag!(h, "example")
    io = IOBuffer()
    writer = HdrHistogram.HistogramLogWriter(io)
    HdrHistogram.output_interval_histogram(writer, h)
    seekstart(io)
    reader = HdrHistogram.HistogramLogReader(io)
    decoded = HdrHistogram.next_interval_histogram(reader)
    @test decoded !== nothing
    @test HdrHistogram.total_count(decoded) == 2
    @test HdrHistogram.tag(decoded) == "example"
    @test HdrHistogram.start_time_stamp(decoded) == 1000
    @test HdrHistogram.end_time_stamp(decoded) == 2000
end

@testset "Log Reader Java Sample" begin
    path = joinpath(@__DIR__, "fixtures", "jHiccup-2.0.6.logV1.hlog")
    io = open(path, "r")
    reader = HdrHistogram.HistogramLogReader(io)
    decoded = HdrHistogram.next_interval_histogram(reader)
    close(io)
    @test decoded !== nothing
    @test HdrHistogram.total_count(decoded) > 0
end

@testset "Log Scanner Processor" begin
    buf = IOBuffer()
    writer = HdrHistogram.HistogramLogWriter(buf)
    HdrHistogram.output_log_format_version(writer)
    HdrHistogram.output_legend(writer)

    h = HdrHistogram.Histogram(1, 1000, 2)
    HdrHistogram.record_value!(h, 10)
    HdrHistogram.start_time_stamp!(h, 1_000)
    HdrHistogram.end_time_stamp!(h, 2_000)
    HdrHistogram.output_interval_histogram(writer, h)

    h2 = HdrHistogram.Histogram(1, 1000, 2)
    HdrHistogram.record_value!(h2, 20)
    HdrHistogram.start_time_stamp!(h2, 2_000)
    HdrHistogram.end_time_stamp!(h2, 3_000)
    HdrHistogram.tag!(h2, "tagged")
    HdrHistogram.output_interval_histogram(writer, h2)

    seekstart(buf)
    scanner = HdrHistogram.HistogramLogScanner(buf)
    decoded_counts = Int[]
    HdrHistogram.process!(scanner, on_histogram = (tag, ts, len, reader) -> begin
        if tag == "tagged"
            push!(decoded_counts, HdrHistogram.total_count(read(reader)))
        end
        false
    end)
    @test decoded_counts == [1]

    seekstart(buf)
    processor = HdrHistogram.HistogramLogProcessor(buf)
    interval_out = IOBuffer()
    accumulated, tags = HdrHistogram.process!(processor, interval_io=interval_out, all_tags=true, percentiles_io=nothing)
    @test accumulated !== nothing
    @test HdrHistogram.total_count(accumulated) == 2
    @test "tagged" in tags
end

@testset "Java Interop" begin
    javac = Sys.which("javac")
    java = Sys.which("java")
    java_repo = get(ENV, "HDRHISTOGRAM_JAVA_DIR",
        normpath(joinpath(@__DIR__, "..", "..", "HdrHistogram")))
    java_src = joinpath(java_repo, "src", "main", "java")
    if haskey(ENV, "HDRHISTOGRAM_JAVA_DIR")
        @test javac !== nothing
        @test java !== nothing
        @test isdir(java_src)
    end
    if javac === nothing || java === nothing || !isdir(java_src)
        @test_skip "java/javac or the Java HdrHistogram reference source is not available"
    else
        interop_src = joinpath(@__DIR__, "interop", "org", "HdrHistogram", "JavaInterop.java")
        mktempdir() do builddir
            interop_src_root = joinpath(@__DIR__, "interop")
            classpath_separator = Sys.iswindows() ? ';' : ':'
            sourcepath = string(java_src, classpath_separator, interop_src_root)
            run(`$javac -cp $java_src -sourcepath $sourcepath -d $builddir $interop_src`)
            classpath = string(builddir, classpath_separator, java_src)

            payload = readchomp(`$java -cp $classpath org.HdrHistogram.JavaInterop encode 1 1000000 3 1 2 3 10:4 1000:2`)
            decoded = HdrHistogram.decode_from_compressed_byte_buffer(base64decode(payload))
            @test HdrHistogram.total_count(decoded) == 9
            @test HdrHistogram.count_at_value(decoded, 10) == 4
            @test HdrHistogram.count_at_value(decoded, 1000) == 2

            h = HdrHistogram.Histogram(1, 1000000, 3)
            for v in (1, 2, 3)
                HdrHistogram.record_value!(h, v)
            end
            HdrHistogram.record_value!(h, 10, 4)
            HdrHistogram.record_value!(h, 1000, 2)
            payload2 = base64encode(HdrHistogram.encode_into_compressed_byte_buffer(h))
            stats = readchomp(`$java -cp $classpath org.HdrHistogram.JavaInterop decode $payload2`)
            parts = split(stats, ',')
            @test parse(Int64, parts[1]) == HdrHistogram.total_count(h)
            @test parse(Int64, parts[2]) == min(h)
            @test parse(Int64, parts[3]) == max(h)
            @test parse(Int64, parts[4]) == HdrHistogram.value_at_percentile(h, 99.0)

            log_output = read(`$java -cp $classpath org.HdrHistogram.JavaInterop log 1 1000000 3 1000 2000 tag=java 10 20:2`, String)
            reader = HdrHistogram.HistogramLogReader(IOBuffer(log_output))
            logged = HdrHistogram.next_interval_histogram(reader)
            @test logged !== nothing
            @test HdrHistogram.tag(logged) == "java"
            @test HdrHistogram.total_count(logged) == 3

            corr = readchomp(`$java -cp $classpath org.HdrHistogram.JavaInterop corrected 1 1000000 3 1000 10000 1`)
            corr_parts = split(corr, ',')
            expected_total = parse(Int64, corr_parts[1])
            expected_p99 = parse(Int64, corr_parts[2])
            base = HdrHistogram.Histogram(1, 1000000, 3)
            HdrHistogram.record_value!(base, 10000)
            corrected = HdrHistogram.Histogram(1, 1000000, 3)
            HdrHistogram.add_while_correcting_for_coordinated_omission(corrected, base, 1000)
            @test HdrHistogram.total_count(corrected) == expected_total
            @test HdrHistogram.value_at_percentile(corrected, 99.0) == expected_p99

            java_features = split(readchomp(`$java -cp $classpath org.HdrHistogram.JavaInterop features`), ',')
            source = HdrHistogram.Histogram(1, 1_000_000, 3)
            HdrHistogram.record_value!(source, 0, 2)
            HdrHistogram.record_value!(source, 10, 3)
            HdrHistogram.record_value!(source, 10_000)
            HdrHistogram.start_time_stamp!(source, 100)
            HdrHistogram.end_time_stamp!(source, 400)
            HdrHistogram.tag!(source, "source")
            copied = copy(source)
            larger_copy = HdrHistogram.Histogram(1, 2_000_000, 3)
            copyto!(larger_copy, source)
            corrected_copy = HdrHistogram.copy_corrected(source, 1_000)
            remainder = copy(source)
            removed = HdrHistogram.Histogram(1, 1_000_000, 3)
            HdrHistogram.record_value!(removed, 0)
            HdrHistogram.record_value!(removed, 10, 2)
            HdrHistogram.subtract!(remainder, removed)

            @test parse(Bool, java_features[1]) == (copied == source)
            @test parse(Bool, java_features[2]) == (larger_copy == source)
            @test parse(Int64, java_features[3]) == HdrHistogram.start_time_stamp(copied)
            @test parse(Int64, java_features[4]) == HdrHistogram.end_time_stamp(copied)
            @test parse(Bool, java_features[5]) == (HdrHistogram.tag(copied) === nothing)
            @test parse(Int64, java_features[6]) == HdrHistogram.total_count(corrected_copy)
            @test parse(Int64, java_features[7]) == HdrHistogram.value_at_percentile(corrected_copy, 99.0)
            @test parse(Int64, java_features[8]) == HdrHistogram.min_nonzero(source)
            @test parse(Int64, java_features[9]) == HdrHistogram.count_between_values(source, 0, 10)
            @test parse(Float64, java_features[10]) ≈
                  HdrHistogram.percentile_at_or_below_value(source, 10)
            @test parse(Int64, java_features[11]) == HdrHistogram.total_count(remainder)
            @test parse(Int64, java_features[12]) == HdrHistogram.count_at_value(remainder, 0)
            @test parse(Int64, java_features[13]) == HdrHistogram.count_at_value(remainder, 10)
            @test parse(Int64, java_features[14]) == HdrHistogram.count_at_value(remainder, 10_000)
        end
    end
end

@testset "Recorded Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.RecordedValuesIterator(h)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        else
            @test count_added_in_this_iteration == 1
        end
        index += 1
    end
    @test index == 2

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.RecordedValuesIterator(h)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        end
        @test HdrHistogram.count_at_value_iterated_to(i) != 0
        @test HdrHistogram.count_at_value_iterated_to(i) == count_added_in_this_iteration
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test total_added_count == 20000
    @test total_added_count == HdrHistogram.total_count(h)
end

@testset "Percentile Output Type" begin
    h = HdrHistogram.Histogram(Int8, 1, 1000, 2)
    append!(h, mod1.(1:200, 100))
    values = HdrHistogram.value_at_percentile(h, [50.0, 100.0])
    @test eltype(values) == Int64
    @test HdrHistogram.count_at_percentile(h, 99.0) > typemax(Int8)
end

@testset "No Alloc Record Value" begin
    h = HdrHistogram.Histogram(1, 1000, 2)
    function record_loop!(hist)
        for _ in 1:1000
            HdrHistogram.record_value!(hist, 1)
        end
        return nothing
    end
    record_loop!(h)
    alloc = @allocated record_loop!(h)
    @test alloc == 0
end

@testset "No Alloc Recorders" begin
    atomic = HdrHistogram.AtomicHistogram(1, 1000, 2)
    concurrent = HdrHistogram.ConcurrentHistogram(1, 1000, 2)
    recorder = HdrHistogram.Recorder(HdrHistogram.ConcurrentHistogram(1, 1000, 2))
    single = HdrHistogram.SingleWriterRecorder(HdrHistogram.Histogram(1, 1000, 2))

    @test @allocated(HdrHistogram.record_value!(atomic, 10)) == 0
    @test @allocated(HdrHistogram.record_value!(concurrent, 10)) == 0
    @test @allocated(HdrHistogram.record_value!(recorder, 10)) == 0
    @test @allocated(HdrHistogram.record_value!(single, 10)) == 0

    narrow_atomic = HdrHistogram.AtomicHistogram(Int16, 1, 1000, 2)
    narrow_concurrent = HdrHistogram.ConcurrentHistogram(Int32, 1, 1000, 2)
    @test @allocated(HdrHistogram.record_value!(narrow_atomic, 10)) == 0
    @test @allocated(HdrHistogram.record_value!(narrow_concurrent, 10)) == 0

    auto = HdrHistogram.ConcurrentHistogram(2)
    HdrHistogram.record_value!(auto, 1000)
    @test @allocated(HdrHistogram.record_value!(auto, 10)) == 0
end

@testset "No Alloc Direct Queries and Merge" begin
    h = HdrHistogram.Histogram(1, 1_000_000, 3)
    append!(h, 1:10_000)
    values = zeros(Int64, 3)
    percentiles = [50.0, 90.0, 99.0]
    HdrHistogram.mean(h)
    HdrHistogram.stddev(h)
    HdrHistogram.value_at_percentile(h, 99.0)
    HdrHistogram.value_at_percentile(h, percentiles, values)
    HdrHistogram.min_nonzero(h)
    HdrHistogram.count_between_values(h, 100, 1_000)
    HdrHistogram.percentile_at_or_below_value(h, 1_000)

    @test @allocated(HdrHistogram.mean(h)) == 0
    @test @allocated(HdrHistogram.stddev(h)) == 0
    @test @allocated(HdrHistogram.value_at_percentile(h, 99.0)) == 0
    @test @allocated(HdrHistogram.value_at_percentile(h, percentiles, values)) == 0
    @test @allocated(HdrHistogram.min_nonzero(h)) == 0
    @test @allocated(HdrHistogram.count_between_values(h, 100, 1_000)) == 0
    @test @allocated(HdrHistogram.percentile_at_or_below_value(h, 1_000)) == 0
    @test @allocated(hash(h)) == 0

    target = similar(h)
    HdrHistogram.add!(target, h)
    HdrHistogram.reset!(target)
    @test @allocated(HdrHistogram.add!(target, h)) == 0

    copyto!(target, h)
    @test @allocated(copyto!(target, h)) == 0
    @test @allocated(target == h) == 0

    removed = similar(h)
    append!(removed, 100:200)
    HdrHistogram.subtract!(target, removed)
    copyto!(target, h)
    @test @allocated(HdrHistogram.subtract!(target, removed)) == 0

    correction_source = HdrHistogram.Histogram(1, 1_000_000, 3)
    HdrHistogram.record_value!(correction_source, 10_000)
    correction_target = similar(correction_source)
    HdrHistogram.copy_corrected!(correction_target, correction_source, 1_000)
    @test @allocated(HdrHistogram.copy_corrected!(correction_target, correction_source, 1_000)) == 0

    writer = HdrHistogram.BufferWriter(0)
    HdrHistogram.encode_into_byte_buffer!(writer, h)
    @test @allocated(HdrHistogram.encode_into_byte_buffer!(writer, h)) == 0
end

@testset "No Alloc Iterator" begin
    h = HdrHistogram.Histogram(1, 1000, 2)
    for v in 1:10
        HdrHistogram.record_value!(h, v)
    end
    function iter_recorded_state(iter, state)
        while true
            res = iterate(iter, state)
            res === nothing && return nothing
            _, state = res
        end
    end
    iter = HdrHistogram.RecordedValuesIterator(h)
    state = HdrHistogram.HistogramIteratorState(iter)
    iter_recorded_state(iter, state)
    alloc = @allocated iter_recorded_state(iter, state)
    @test alloc == 0

    function consume_iterator(iter)
        total = 0
        for item in iter
            total += HdrHistogram.count_added_in_this_iteration_step(item)
        end
        return total
    end

    recorded = HdrHistogram.RecordedValuesIterator(h)
    all_values = HdrHistogram.AllValuesIterator(h)
    percentiles = HdrHistogram.PercentileIterator(h, 5)
    linear = HdrHistogram.LinearIterator(h, 10)
    logarithmic = HdrHistogram.LogarithmicIterator(h, 10, 2.0)
    foreach(consume_iterator, (recorded, all_values, percentiles, linear, logarithmic))
    @test @allocated(consume_iterator(recorded)) == 0
    @test @allocated(consume_iterator(all_values)) == 0
    @test @allocated(consume_iterator(percentiles)) == 0
    @test @allocated(consume_iterator(linear)) == 0
    @test @allocated(consume_iterator(logarithmic)) == 0
end

@testset "Recorded Values Iterator Zero" begin
    h = HdrHistogram.Histogram(1, 8, 1)
    HdrHistogram.record_value!(h, 0)
    HdrHistogram.record_value!(h, 1)
    values = Int64[]
    for i in HdrHistogram.RecordedValuesIterator(h)
        push!(values, HdrHistogram.value_iterated_to(i))
    end
    @test values == [0, 1]
end

@testset "All Values Iterator Range" begin
    h = HdrHistogram.Histogram(1, 8, 1)
    HdrHistogram.record_value!(h, 0)
    HdrHistogram.record_value!(h, 1)
    count = 0
    first_value = nothing
    last_value = nothing
    for i in HdrHistogram.AllValuesIterator(h)
        v = HdrHistogram.value_iterated_to(i)
        if count == 0
            first_value = v
        end
        last_value = v
        count += 1
    end
    @test count == HdrHistogram.counts_length(h)
    @test first_value == 0
    last_index_value = HdrHistogram.value_at_index(h, HdrHistogram.counts_length(h) - 1)
    @test last_value == HdrHistogram.highest_equivalent_value(h, last_index_value)
end

@testset "All Values Iterator Empty" begin
    h = HdrHistogram.Histogram(1, 8, 1)
    count = 0
    first_value = nothing
    last_value = nothing
    for i in HdrHistogram.AllValuesIterator(h)
        v = HdrHistogram.value_iterated_to(i)
        if count == 0
            first_value = v
        end
        last_value = v
        count += 1
    end
    @test count == HdrHistogram.counts_length(h)
    @test first_value == 0
    last_index_value = HdrHistogram.value_at_index(h, HdrHistogram.counts_length(h) - 1)
    @test last_value == HdrHistogram.highest_equivalent_value(h, last_index_value)
end

# This test is from the C implementation which allows concurrent modification
# @testset "Linear Iterator Buckets" begin
#     step_count = 0
#     total_count = 0
#     h = HdrHistogram.Histogram(1, 255, 2)
#     vals = [193, 255, 0, 1, 64, 128]
#     for i in vals
#         HdrHistogram.record_value!(h, i)
#     end

#     for i in HdrHistogram.LinearIterator(h, 64)
#         total_count += HdrHistogram.count_added_in_this_iteration_step(i)
#         if step_count == 0
#             HdrHistogram.record_value!(h, 2)
#         end
#         step_count += 1
#     end

#     @test step_count == 4
#     @test total_count == 6
# end

@testset "Linear Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.LinearIterator(h, 100_000)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test HdrHistogram.value_iterated_to(i) == 99_999
            @test count_added_in_this_iteration == 10000
        elseif index == 999
            @test count_added_in_this_iteration == 1
        else
            @test count_added_in_this_iteration == 0
        end
        index += 1
    end
    @test index == 1000

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.LinearIterator(h, 10_000)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            # Java-compatible first bucket is range [0, 9999].
            # value 1000  count = 10000
            @test HdrHistogram.value_iterated_to(i) == 9_999
            @test count_added_in_this_iteration == 10_000
        end
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test index == 10000
    @test total_added_count == 20000
end

@testset "Logarithmic Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.LogarithmicIterator(h, 10_000, 2.0)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test HdrHistogram.value_iterated_to(i) == 9_999
            @test count_added_in_this_iteration == 10000
        elseif index == 14
            @test count_added_in_this_iteration == 1
        else
            @test count_added_in_this_iteration == 0
        end
        index += 1
    end
    @test index == 15

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.LogarithmicIterator(h, 10_000, 2.0)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            # Java-compatible first bucket is range [0, 9999].
            # value 1000  count = 10000
            @test HdrHistogram.value_iterated_to(i) == 9_999
            @test count_added_in_this_iteration == 10_000
        end
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test index == 15
    @test total_added_count == 20000
end

function compare_values(a, b, ϵ)
    @test abs(a - b) <= (b * ϵ)
end

@testset "Check percentiles" begin
    h = load_histogram()
    compare_values(HdrHistogram.value_at_percentile(h, 30.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.99), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.999), 100000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 100.0), 100000000, 0.001)

    h = load_corrected_histogram()
    compare_values(HdrHistogram.value_at_percentile(h, 30.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 50.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 75.0), 50000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 90.0), 80000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.0), 98000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.999), 100000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 100.0), 100000000, 0.001)

    percentiles = [30.0, 99.0, 99.99, 99.999, 100.0]
    vals = zeros(Int64, length(percentiles))
    HdrHistogram.value_at_percentile(h, percentiles, vals)
    for (p, v) in zip(percentiles, vals)
        compare_values(HdrHistogram.value_at_percentile(h, p), v, 0.001)
    end

    @test_throws ArgumentError HdrHistogram.value_at_percentile(h, [99.0, 50.0])
end

@testset "Significant Figures Zero" begin
    h = HdrHistogram.Histogram(1, 2, 0)
    @test HdrHistogram.significant_figures(h) == 0
    @test HdrHistogram.counts_length(h) > 0
end

@testset "Percentile Iterator" begin
    h = load_histogram()
    for i in HdrHistogram.PercentileIterator(h, 5)
        expected = HdrHistogram.highest_equivalent_value(h, HdrHistogram.value_at_percentile(h, HdrHistogram.percentile(i)))
        @test HdrHistogram.value_iterated_to(i) == expected
    end
end

@testset "Test scaling equivalence" begin
    h1 = load_corrected_histogram()
    h2 = load_scaled_corrected_histogram()

    compare_values(HdrHistogram.mean(h1) * SCALE,
        HdrHistogram.mean(h2),
        0.000001)
    compare_values(HdrHistogram.total_count(h1),
        HdrHistogram.total_count(h2),
        0)

    expected_99th = HdrHistogram.value_at_percentile(h1, 99.0) * SCALE
    scaled_99th = HdrHistogram.value_at_percentile(h2, 99.0)

    compare_values(HdrHistogram.lowest_equivalent_value(h1, expected_99th),
        HdrHistogram.lowest_equivalent_value(h2, scaled_99th),
        0)
end
