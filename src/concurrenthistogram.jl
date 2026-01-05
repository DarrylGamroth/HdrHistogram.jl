mutable struct ConcurrentHistogram{C} <: AbstractHistogram{C}
    const lowest_discernible_value::Int64
    highest_trackable_value::Int64
    const unit_magnitude::UInt64
    const significant_figures::Int64
    const sub_bucket_half_count_magnitude::UInt64
    const sub_bucket_half_count::Int64
    const sub_bucket_mask::Int64
    const sub_bucket_count::Int64
    const leading_zero_count_base::Int64
    bucket_count::Int64
    @atomic min_value::Int64
    @atomic max_value::Int64
    const normalizing_index_offset::Int64
    const conversion_ratio::Float64
    start_time_msec::Int64
    end_time_msec::Int64
    tag::Union{Nothing,String}
    const auto_resize::Bool
    @atomic total_count::Int64
    @atomic counts::AtomicCounts{C}
    const resize_lock::ReentrantLock
end

@static if VERSION < v"1.12"
    counts_init(::Type{<:ConcurrentHistogram{C}}, counts_len) where {C} = zeros(C, counts_len)
else
    function counts_init(::Type{<:ConcurrentHistogram{C}}, counts_len) where {C}
        counts = Base.AtomicMemory{C}(undef, counts_len)
        for i in 1:counts_len
            @atomic counts[i] = zero(C)
        end
        return counts
    end
end

lowest_discernible_value(h::ConcurrentHistogram) = h.lowest_discernible_value

highest_trackable_value(h::ConcurrentHistogram) = h.highest_trackable_value
highest_trackable_value!(h::ConcurrentHistogram, value) = h.highest_trackable_value = value

unit_magnitude(h::ConcurrentHistogram) = h.unit_magnitude

significant_figures(h::ConcurrentHistogram) = h.significant_figures

sub_bucket_half_count_magnitude(h::ConcurrentHistogram) = h.sub_bucket_half_count_magnitude

sub_bucket_half_count(h::ConcurrentHistogram) = h.sub_bucket_half_count

sub_bucket_mask(h::ConcurrentHistogram) = h.sub_bucket_mask

sub_bucket_count(h::ConcurrentHistogram) = h.sub_bucket_count

leading_zero_count_base(h::ConcurrentHistogram) = h.leading_zero_count_base

bucket_count(h::ConcurrentHistogram) = h.bucket_count
bucket_count!(h::ConcurrentHistogram, value) = h.bucket_count = value

min_value(h::ConcurrentHistogram) = @atomic h.min_value
min_value!(h::ConcurrentHistogram, value) = @atomic h.min_value = value

max_value(h::ConcurrentHistogram) = @atomic h.max_value
max_value!(h::ConcurrentHistogram, value) = @atomic h.max_value = value

normalizing_index_offset(h::ConcurrentHistogram) = h.normalizing_index_offset

conversion_ratio(h::ConcurrentHistogram) = h.conversion_ratio

start_time_stamp(h::ConcurrentHistogram) = h.start_time_msec
start_time_stamp!(h::ConcurrentHistogram, value) = h.start_time_msec = value

end_time_stamp(h::ConcurrentHistogram) = h.end_time_msec
end_time_stamp!(h::ConcurrentHistogram, value) = h.end_time_msec = value

tag(h::ConcurrentHistogram) = h.tag
tag!(h::ConcurrentHistogram, value) = h.tag = value

auto_resize(h::ConcurrentHistogram) = h.auto_resize

total_count(h::ConcurrentHistogram) = @atomic h.total_count
total_count!(h::ConcurrentHistogram, value) = @atomic h.total_count = value
total_count_inc!(h::ConcurrentHistogram, value) = @atomic h.total_count += value

counts(h::ConcurrentHistogram) = h.counts
counts!(h::ConcurrentHistogram, value) = @atomic h.counts = value
counts_length(h::ConcurrentHistogram) = length(h.counts)

"""
    ConcurrentHistogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new concurrent histogram with the specified configuration.
"""
function ConcurrentHistogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(ConcurrentHistogram{C}, Int64(lowest_discernible_value), Int64(highest_trackable_value),
        Int64(significant_figures), false)
end

"""
    ConcurrentHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new concurrent histogram with the specified configuration.
"""
function ConcurrentHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(ConcurrentHistogram{Int64}, Int64(lowest_discernible_value), Int64(highest_trackable_value),
        Int64(significant_figures), false)
end

"""
    ConcurrentHistogram(numberOfSignificantValueDigits)

Construct an auto-resizing concurrent histogram with a lowest discernible value of 1 and an auto-adjusting
highestTrackableValue. Can auto-resize up to track values up to (typemax(Int64) / 2).
"""
function ConcurrentHistogram(significant_figures)
    return _init(ConcurrentHistogram{Int64}, 1, 2, Int64(significant_figures), true)
end

function _init_with_config(::Type{ConcurrentHistogram{C}},
    lowest_discernible_value::Int64,
    highest_trackable_value::Int64,
    significant_figures::Int64,
    auto_resize::Bool,
    conversion_ratio::Float64,
    normalizing_index_offset::Int64) where {C}
    if !(0 <= significant_figures <= 5)
        throw(ArgumentError("number of significant_figures must be between 0 and 5"))
    end

    if !(1 <= lowest_discernible_value <= (typemax(Int64) ÷ 2))
        throw(ArgumentError("lowest_discernible_value >=1 and <= $(typemax(Int64) ÷ 2)"))
    end

    if !(highest_trackable_value >= lowest_discernible_value * 2)
        throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
    end

    largest_value_with_single_unit_resolution = 2 * 10^significant_figures
    sub_bucket_count_magnitude = ceil(Int64, log2(largest_value_with_single_unit_resolution))
    sub_bucket_half_count_magnitude = sub_bucket_count_magnitude - 1

    unit_magnitude = floor(UInt64, log2(lowest_discernible_value)) % 64

    if sub_bucket_count_magnitude + unit_magnitude > 62
        throw(ArgumentError("Cannot represent significant_figures worth of values beyond lowest_discernible_value"))
    end

    leading_zero_count_base = 64 - unit_magnitude - sub_bucket_count_magnitude

    sub_bucket_count = 2^sub_bucket_count_magnitude
    sub_bucket_half_count = sub_bucket_count >> 1
    sub_bucket_mask = (sub_bucket_count - 1) << unit_magnitude

    bucket_count = buckets_needed_to_cover_value(highest_trackable_value, sub_bucket_count, unit_magnitude)
    counts_len = (bucket_count + 1) * sub_bucket_half_count

    return ConcurrentHistogram{C}(lowest_discernible_value, highest_trackable_value, unit_magnitude,
        significant_figures, sub_bucket_half_count_magnitude, sub_bucket_half_count,
        sub_bucket_mask, sub_bucket_count, leading_zero_count_base, bucket_count,
        typemax(Int64), 0, normalizing_index_offset, conversion_ratio,
        typemax(Int64), 0, nothing, auto_resize, 0,
        counts_init(ConcurrentHistogram{C}, counts_len), ReentrantLock())
end

@inline function counts_get_direct(h::ConcurrentHistogram, index)
    i = index + 1
    return @inbounds @atomic h.counts[i]
end

@inline function counts_inc_direct!(h::ConcurrentHistogram, index, value)
    i = index + 1
    return @inbounds @atomic h.counts[i] += value
end

@inline function counts_set_direct!(h::ConcurrentHistogram, index, value)
    i = index + 1
    @inbounds @atomic h.counts[i] = value
end

@inline function update_min_max!(h::ConcurrentHistogram, value)
    @atomic h.min_value min value
    @atomic h.max_value max value
end

function resize!(h::ConcurrentHistogram{C}, highest_trackable_value) where {C}
    lock(h.resize_lock)
    try
        if !(highest_trackable_value >= lowest_discernible_value(h) * 2)
            throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
        end
        new_bucket_count = buckets_needed_to_cover_value(highest_trackable_value, sub_bucket_count(h), unit_magnitude(h))
        new_counts_len = (new_bucket_count + 1) * sub_bucket_half_count(h)
        old_counts = counts(h)
        old_len = counts_length(h)
        new_counts = counts_init(ConcurrentHistogram{C}, new_counts_len)
        for i in 1:old_len
            @inbounds @atomic new_counts[i] = @atomic old_counts[i]
        end
        counts!(h, new_counts)
        bucket_count!(h, new_bucket_count)
        highest_trackable_value!(h, highest_trackable_value)
    finally
        unlock(h.resize_lock)
    end
end

@inline function record_value!(h::ConcurrentHistogram, value::Int64, count::Int64=1)
    if auto_resize(h)
        lock(h.resize_lock)
        try
            return Base.invoke(record_value!, Tuple{AbstractHistogram, Int64, Int64}, h, value, count)
        finally
            unlock(h.resize_lock)
        end
    end
    return Base.invoke(record_value!, Tuple{AbstractHistogram, Int64, Int64}, h, value, count)
end

@inline function record_corrected_value!(h::ConcurrentHistogram, value::Int64, expected_interval::Int64, count::Int64=1)
    if auto_resize(h)
        lock(h.resize_lock)
        try
            return Base.invoke(record_corrected_value!, Tuple{AbstractHistogram, Int64, Int64, Int64},
                h, value, expected_interval, count)
        finally
            unlock(h.resize_lock)
        end
    end
    return Base.invoke(record_corrected_value!, Tuple{AbstractHistogram, Int64, Int64, Int64},
        h, value, expected_interval, count)
end

@static if VERSION < v"1.12"
    function reset!(h::ConcurrentHistogram{C}) where {C}
        total_count!(h, 0)
        min_value!(h, typemax(Int64))
        max_value!(h, 0)
        start_time_stamp!(h, typemax(Int64))
        end_time_stamp!(h, 0)
        tag!(h, nothing)
        fill!(counts(h), zero(C))
    end
else
    function reset!(h::ConcurrentHistogram{C}) where {C}
        total_count!(h, 0)
        min_value!(h, typemax(Int64))
        max_value!(h, 0)
        start_time_stamp!(h, typemax(Int64))
        end_time_stamp!(h, 0)
        tag!(h, nothing)
        for i in 1:counts_length(h)
            @atomic h.counts[i] = zero(C)
        end
    end
end
