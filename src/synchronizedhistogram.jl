mutable struct SynchronizedHistogram{C} <: AbstractHistogram{C}
    inner::Histogram{C}
    const lock::ReentrantLock
end

"""
    SynchronizedHistogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new synchronized histogram with the specified configuration.
"""
function SynchronizedHistogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)
    inner = Histogram(C, lowest_discernible_value, highest_trackable_value, significant_figures)
    return SynchronizedHistogram{C}(inner, ReentrantLock())
end

"""
    SynchronizedHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new synchronized histogram with the specified configuration.
"""
function SynchronizedHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    inner = Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return SynchronizedHistogram{Int64}(inner, ReentrantLock())
end

"""
    SynchronizedHistogram(numberOfSignificantValueDigits)

Construct an auto-resizing synchronized histogram with a lowest discernible value of 1 and an auto-adjusting
highestTrackableValue. Can auto-resize up to track values up to (typemax(Int64) / 2).
"""
function SynchronizedHistogram(significant_figures)
    inner = Histogram(significant_figures)
    return SynchronizedHistogram{Int64}(inner, ReentrantLock())
end

function _init_with_config(::Type{SynchronizedHistogram{C}},
    lowest_discernible_value::Int64,
    highest_trackable_value::Int64,
    significant_figures::Int64,
    auto_resize::Bool,
    conversion_ratio::Float64,
    normalizing_index_offset::Int64) where {C}
    inner = _init_with_config(Histogram{C}, lowest_discernible_value, highest_trackable_value,
        significant_figures, auto_resize, conversion_ratio, normalizing_index_offset)
    return SynchronizedHistogram{C}(inner, ReentrantLock())
end

Base.lock(h::SynchronizedHistogram) = lock(h.lock)
Base.unlock(h::SynchronizedHistogram) = unlock(h.lock)
function Base.lock(f::Function, h::SynchronizedHistogram)
    lock(h.lock)
    try
        return f()
    finally
        unlock(h.lock)
    end
end

lowest_discernible_value(h::SynchronizedHistogram) = lowest_discernible_value(h.inner)
highest_trackable_value(h::SynchronizedHistogram) = highest_trackable_value(h.inner)
highest_trackable_value!(h::SynchronizedHistogram, value) = highest_trackable_value!(h.inner, value)
unit_magnitude(h::SynchronizedHistogram) = unit_magnitude(h.inner)
significant_figures(h::SynchronizedHistogram) = significant_figures(h.inner)
sub_bucket_half_count_magnitude(h::SynchronizedHistogram) = sub_bucket_half_count_magnitude(h.inner)
sub_bucket_half_count(h::SynchronizedHistogram) = sub_bucket_half_count(h.inner)
sub_bucket_mask(h::SynchronizedHistogram) = sub_bucket_mask(h.inner)
sub_bucket_count(h::SynchronizedHistogram) = sub_bucket_count(h.inner)
leading_zero_count_base(h::SynchronizedHistogram) = leading_zero_count_base(h.inner)
bucket_count(h::SynchronizedHistogram) = bucket_count(h.inner)
bucket_count!(h::SynchronizedHistogram, value) = bucket_count!(h.inner, value)
min_value(h::SynchronizedHistogram) = min_value(h.inner)
min_value!(h::SynchronizedHistogram, value) = min_value!(h.inner, value)
max_value(h::SynchronizedHistogram) = max_value(h.inner)
max_value!(h::SynchronizedHistogram, value) = max_value!(h.inner, value)
normalizing_index_offset(h::SynchronizedHistogram) = normalizing_index_offset(h.inner)
conversion_ratio(h::SynchronizedHistogram) = conversion_ratio(h.inner)
start_time_stamp(h::SynchronizedHistogram) = start_time_stamp(h.inner)
start_time_stamp!(h::SynchronizedHistogram, value) = start_time_stamp!(h.inner, value)
end_time_stamp(h::SynchronizedHistogram) = end_time_stamp(h.inner)
end_time_stamp!(h::SynchronizedHistogram, value) = end_time_stamp!(h.inner, value)
tag(h::SynchronizedHistogram) = tag(h.inner)
tag!(h::SynchronizedHistogram, value) = tag!(h.inner, value)
auto_resize(h::SynchronizedHistogram) = auto_resize(h.inner)
total_count(h::SynchronizedHistogram) = total_count(h.inner)
total_count!(h::SynchronizedHistogram, value) = total_count!(h.inner, value)
total_count_inc!(h::SynchronizedHistogram, value) = total_count_inc!(h.inner, value)
counts(h::SynchronizedHistogram) = counts(h.inner)
counts!(h::SynchronizedHistogram, value) = counts!(h.inner, value)
counts_length(h::SynchronizedHistogram) = counts_length(h.inner)

@inline function record_value!(h::SynchronizedHistogram, value::Int64, count::Int64=1)
    lock(h.lock)
    try
        return record_value!(h.inner, value, count)
    finally
        unlock(h.lock)
    end
end

@inline function record_corrected_value!(h::SynchronizedHistogram, value::Int64, expected_interval::Int64, count::Int64=1)
    lock(h.lock)
    try
        return record_corrected_value!(h.inner, value, expected_interval, count)
    finally
        unlock(h.lock)
    end
end

function add(h::SynchronizedHistogram, from::AbstractHistogram)
    lock(h.lock)
    try
        return add(h.inner, from)
    finally
        unlock(h.lock)
    end
end

function add_while_correcting_for_coordinated_omission(h::SynchronizedHistogram, from::AbstractHistogram, expected_interval::Int64)
    lock(h.lock)
    try
        return add_while_correcting_for_coordinated_omission(h.inner, from, expected_interval)
    finally
        unlock(h.lock)
    end
end

function reset!(h::SynchronizedHistogram)
    lock(h.lock)
    try
        return reset!(h.inner)
    finally
        unlock(h.lock)
    end
end

function Base.min(h::SynchronizedHistogram)
    lock(h.lock)
    try
        return Base.min(h.inner)
    finally
        unlock(h.lock)
    end
end

function Base.max(h::SynchronizedHistogram)
    lock(h.lock)
    try
        return Base.max(h.inner)
    finally
        unlock(h.lock)
    end
end

function mean(h::SynchronizedHistogram)
    lock(h.lock)
    try
        return mean(h.inner)
    finally
        unlock(h.lock)
    end
end

function stddev(h::SynchronizedHistogram)
    lock(h.lock)
    try
        return stddev(h.inner)
    finally
        unlock(h.lock)
    end
end

function count_at_value(h::SynchronizedHistogram, value::Int64)
    lock(h.lock)
    try
        return count_at_value(h.inner, value)
    finally
        unlock(h.lock)
    end
end

function count_at_index(h::SynchronizedHistogram, index::Int64)
    lock(h.lock)
    try
        return count_at_index(h.inner, index)
    finally
        unlock(h.lock)
    end
end

function count_at_percentile(h::SynchronizedHistogram, percentile::Real)
    lock(h.lock)
    try
        return count_at_percentile(h.inner, percentile)
    finally
        unlock(h.lock)
    end
end

function value_at_percentile(h::SynchronizedHistogram, percentile::Real)
    lock(h.lock)
    try
        return value_at_percentile(h.inner, percentile)
    finally
        unlock(h.lock)
    end
end

function value_at_percentile(h::SynchronizedHistogram, percentiles, values::AbstractVector{<:Number})
    lock(h.lock)
    try
        return value_at_percentile(h.inner, percentiles, values)
    finally
        unlock(h.lock)
    end
end

function value_at_percentile(h::SynchronizedHistogram, percentiles::AbstractVector)
    lock(h.lock)
    try
        return value_at_percentile(h.inner, percentiles)
    finally
        unlock(h.lock)
    end
end

function percentile_print(io::IO, h::SynchronizedHistogram, ticks_per_half_distance, value_scale)
    lock(h.lock)
    try
        return percentile_print(io, h.inner, ticks_per_half_distance, value_scale)
    finally
        unlock(h.lock)
    end
end
