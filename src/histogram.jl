mutable struct Histogram{C} <: AbstractHistogram{C}
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
    min_value::Int64
    max_value::Int64
    const normalizing_index_offset::Int64
    const conversion_ratio::Float64
    start_time_msec::Int64
    end_time_msec::Int64
    tag::Union{Nothing,String}
    const auto_resize::Bool
    total_count::Int64
    const counts::Vector{C}
end

lowest_discernible_value(h::Histogram) = h.lowest_discernible_value

highest_trackable_value(h::Histogram) = h.highest_trackable_value
highest_trackable_value!(h::Histogram, value) = h.highest_trackable_value = value

unit_magnitude(h::Histogram) = h.unit_magnitude

significant_figures(h::Histogram) = h.significant_figures

sub_bucket_half_count_magnitude(h::Histogram) = h.sub_bucket_half_count_magnitude

sub_bucket_half_count(h::Histogram) = h.sub_bucket_half_count

sub_bucket_mask(h::Histogram) = h.sub_bucket_mask

sub_bucket_count(h::Histogram) = h.sub_bucket_count

leading_zero_count_base(h::Histogram) = h.leading_zero_count_base

bucket_count(h::Histogram) = h.bucket_count
bucket_count!(h::Histogram, value) = h.bucket_count = value

min_value(h::Histogram) = h.min_value
min_value!(h::Histogram, value) = h.min_value = value

max_value(h::Histogram) = h.max_value
max_value!(h::Histogram, value) = h.max_value = value

normalizing_index_offset(h::Histogram) = h.normalizing_index_offset

conversion_ratio(h::Histogram) = h.conversion_ratio

start_time_stamp(h::Histogram) = h.start_time_msec
start_time_stamp!(h::Histogram, value) = h.start_time_msec = value

end_time_stamp(h::Histogram) = h.end_time_msec
end_time_stamp!(h::Histogram, value) = h.end_time_msec = value

tag(h::Histogram) = h.tag
tag!(h::Histogram, value) = h.tag = value

auto_resize(h::Histogram) = h.auto_resize

total_count(h::Histogram) = h.total_count
total_count!(h::Histogram, value) = h.total_count = value
total_count_inc!(h::Histogram, value) = h.total_count += value

counts(h::Histogram) = h.counts
counts_length(h::Histogram) = length(h.counts)

function _add_direct!(h::Histogram{Int64}, from::Histogram)
    destination_counts = counts(h)
    source_counts = counts(from)
    observed_total = Int64(0)
    @inbounds @simd for i in eachindex(destination_counts, source_counts)
        count = source_counts[i]
        destination_counts[i] += count
        observed_total += Int64(count)
    end
    return _finish_direct_add!(h, from, observed_total)
end

function _add_direct!(h::Histogram{C}, from::Histogram) where {C}
    destination_counts = counts(h)
    source_counts = counts(from)
    observed_total = Int64(0)
    @inbounds for i in eachindex(destination_counts, source_counts)
        count = source_counts[i]
        destination_counts[i] = _checked_add_count(destination_counts[i], count)
        observed_total += Int64(count)
    end
    return _finish_direct_add!(h, from, observed_total)
end

function _subtract_direct!(h::Histogram{C}, from::Histogram) where {C}
    destination_counts = counts(h)
    source_counts = counts(from)
    @inbounds for i in eachindex(destination_counts, source_counts)
        source_count = Int64(source_counts[i])
        destination_count = Int64(destination_counts[i])
        if source_count > 0 && source_count > destination_count
            logical_index = normalize_index(i - 1, -normalizing_index_offset(from), length(source_counts))
            _throw_subtract_count(value_at_index(from, logical_index), source_count, destination_count)
        end
    end

    observed_total_count = Int64(0)
    min_non_zero_index = typemax(Int64)
    max_index = Int64(-1)
    offset = normalizing_index_offset(h)
    counts_len = length(destination_counts)
    @inbounds @simd for i in eachindex(destination_counts, source_counts)
        source_count = max(Int64(source_counts[i]), 0)
        remaining = Int64(destination_counts[i]) - source_count
        destination_counts[i] = convert(C, remaining)
        if remaining > 0
            logical_index = offset == 0 ? i - 1 : normalize_index(i - 1, -offset, counts_len)
            observed_total_count += remaining
            max_index = max(max_index, logical_index)
            logical_index == 0 || (min_non_zero_index = min(min_non_zero_index, logical_index))
        end
    end
    min_non_zero_index == typemax(Int64) && (min_non_zero_index = -1)
    return _set_internal_counters_from_observed!(h, observed_total_count,
        min_non_zero_index, max_index)
end

"""
    Histogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `C`: The type of the histogram's counters, which must be a subtype of `Signed`.
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function Histogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(Histogram{C}, Int64(lowest_discernible_value), Int64(highest_trackable_value),
        Int64(significant_figures), false)
end

"""
    Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(Histogram{Int64}, Int64(lowest_discernible_value), Int64(highest_trackable_value),
        Int64(significant_figures), false)
end

"""
    Histogram(numberOfSignificantValueDigits)

Construct an auto-resizing histogram with a lowest discernible value of 1 and an auto-adjusting
highestTrackableValue. Can auto-resize up to track values up to (typemax(Int64) / 2).

# Arguments
- `numberOfSignificantValueDigits::Int`: The number of significant decimal digits to which the histogram will
    maintain value resolution and separation. Must be a non-negative.

"""
function Histogram(significant_figures)
    return _init(Histogram{Int64}, 1, 2, Int64(significant_figures), true)
end

function Histogram(C::Type{<:Signed}, significant_figures)
    return _init(Histogram{C}, 1, 2, Int64(significant_figures), true)
end
