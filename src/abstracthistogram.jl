abstract type AbstractHistogram{C<:Signed} end

#### MEMORY ####

counts_init(::Type{<:AbstractHistogram{C}}, counts_len) where {C} = zeros(C, counts_len)

function _init_with_config(H::Type{<:AbstractHistogram{C}},
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
        # sub_bucket_count entries can't be represented, with unit_magnitude applied, in a positive Int64.
        # Technically it still sort of works if their sum is 63: you can represent all but the last number
        # in the shifted sub_bucket_count. However, the utility of such a histogram vs ones whose magnitude here
        # fits in 62 bits is debatable, and it makes it harder to work through the logic.
        # Sums larger than 64 are totally broken as leading_zero_count_base would go negative.
        throw(ArgumentError("Cannot represent significant_figures worth of values beyond lowest_discernible_value"))
    end

    # Establish leading_zero_count_base, used in get_bucket_index() fast path:
    # subtract the bits that would be used by the largest value in bucket 0.
    leading_zero_count_base = 64 - unit_magnitude - sub_bucket_count_magnitude

    sub_bucket_count = 2^sub_bucket_count_magnitude
    sub_bucket_half_count = sub_bucket_count >> 1
    sub_bucket_mask = (sub_bucket_count - 1) << unit_magnitude

    bucket_count = buckets_needed_to_cover_value(highest_trackable_value, sub_bucket_count, unit_magnitude)
    counts_len = (bucket_count + 1) * sub_bucket_half_count

    return H(lowest_discernible_value, highest_trackable_value, unit_magnitude,
        significant_figures, sub_bucket_half_count_magnitude,
        sub_bucket_half_count, sub_bucket_mask, sub_bucket_count, leading_zero_count_base,
        bucket_count, typemax(Int64), 0, normalizing_index_offset, conversion_ratio,
        typemax(Int64), 0, nothing, auto_resize, 0, counts_init(H, counts_len))
end

function _init(H::Type{<:AbstractHistogram{C}},
    lowest_discernible_value::Int64,
    highest_trackable_value::Int64,
    significant_figures::Int64,
    auto_resize::Bool) where {C}
    return _init_with_config(H, lowest_discernible_value, highest_trackable_value,
        significant_figures, auto_resize, 1.0, 0)
end

"""
    Base.similar(h::T) where {T<:AbstractHistogram}

Construct a new empty `T` instance with the same configuration as `h`.

# Arguments
- `h::T`: An instance of a type that is a subtype of `AbstractHistogram`.

# Returns
- A new instance of the same type as `h` with the same configuration.
"""
function Base.similar(h::T) where {T<:AbstractHistogram}
    return _init(T, lowest_discernible_value(h), highest_trackable_value(h), significant_figures(h), auto_resize(h))
end

function reset!(h::AbstractHistogram{C}) where {C}
    total_count!(h, 0)
    min_value!(h, typemax(Int64))
    max_value!(h, 0)
    start_time_stamp!(h, typemax(Int64))
    end_time_stamp!(h, 0)
    tag!(h, nothing)
    fill!(counts(h), 0)
end

### COUNTS ###

function resize!(h::AbstractHistogram{C}, highest_trackable_value) where {C}
    if !(highest_trackable_value >= lowest_discernible_value(h) * 2)
        throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
    end
    bucket_count = buckets_needed_to_cover_value(highest_trackable_value, sub_bucket_count(h), unit_magnitude(h))
    counts_len = (bucket_count + 1) * sub_bucket_half_count(h)
    old_len = counts_length(h)
    Base.resize!(counts(h), counts_len)
    fill!(view(counts(h), old_len+1:counts_len), 0)
    bucket_count!(h, bucket_count)
    highest_trackable_value!(h, highest_trackable_value)
end

@inline function normalize_index(h::AbstractHistogram, index)
    return normalize_index(index, normalizing_index_offset(h), counts_length(h))
end

@inline function normalize_index(index, normalizing_offset, array_length)
    if normalizing_offset == 0
        return index
    end

    normalized_index = index - normalizing_offset

    if normalized_index < 0
        normalized_index += array_length
    elseif normalized_index >= array_length
        normalized_index -= array_length
    end

    return normalized_index
end

Base.@propagate_inbounds @inline function counts_get_direct(h::AbstractHistogram, index)
    i = index + 1
    @boundscheck checkbounds(counts(h), i)
    return @inbounds counts(h)[i]
end

Base.@propagate_inbounds @inline function counts_get_normalised(h::AbstractHistogram, index)
    return counts_get_direct(h, normalize_index(h, index))
end

Base.@propagate_inbounds @inline function counts_inc_direct!(h::AbstractHistogram, index, value)
    i = index + 1
    @boundscheck checkbounds(counts(h), i)
    return @inbounds counts(h)[i] += value
end

Base.@propagate_inbounds @inline function counts_inc_normalised!(h::AbstractHistogram, index, value)
    normalised_index = normalize_index(h, index)
    counts_inc_direct!(h, normalised_index, value)
    total_count_inc!(h, value)
end

Base.@propagate_inbounds @inline function counts_set_direct!(h::AbstractHistogram, index, value)
    i = index + 1
    @boundscheck checkbounds(counts(h), i)
    @inbounds counts(h)[i] = value
end

Base.@propagate_inbounds @inline function counts_set_normalised!(h::AbstractHistogram, index, value)
    counts_set_direct!(h, normalize_index(h, index), value)
end

@inline function update_min_max!(h::AbstractHistogram, value)
    value == 0 || min_value!(h, min(min_value(h), value))
    max_value!(h, max(max_value(h), value))
end

#### UTILITIES ####

function get_bucket_index(h::AbstractHistogram, value)
    return leading_zero_count_base(h) - leading_zeros(value | sub_bucket_mask(h))
end

function get_sub_bucket_index(value, bucket_index, unit_magnitude)
    return value >> ((bucket_index + unit_magnitude) % 64)
end

function counts_index(h::AbstractHistogram, bucket_index, sub_bucket_index)
    # Calculate the index for the first entry in the bucket
    bucket_base_index = (bucket_index + 1) << (sub_bucket_half_count_magnitude(h) % 64)
    # Calculate the offset in the bucket
    offset_in_bucket = sub_bucket_index - sub_bucket_half_count(h)
    return bucket_base_index + offset_in_bucket
end

function value_from_index(bucket_index, sub_bucket_index, unit_magnitude)
    return Int64(sub_bucket_index) << ((bucket_index + unit_magnitude) % 64)
end

function counts_index_for(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    return counts_index(h, bucket_index, sub_bucket_index)
end

function value_at_index(h::AbstractHistogram, index::Int64)
    bucket_index = (index >> (sub_bucket_half_count_magnitude(h) % 64)) - 1
    sub_bucket_index = (index & (sub_bucket_half_count(h) - 1)) + sub_bucket_half_count(h)

    if bucket_index < 0
        sub_bucket_index -= sub_bucket_half_count(h)
        bucket_index = 0
    end

    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function size_of_equivalent_value_range(h::AbstractHistogram, value::Int64)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    adjusted_bucket = (sub_bucket_index >= sub_bucket_count(h)) ? (bucket_index + 1) : bucket_index
    return 1 << ((unit_magnitude(h) + adjusted_bucket) % 64)
end

function size_of_equivalent_value_range_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    adjusted_bucket = (sub_bucket_index >= sub_bucket_count(h)) ? (bucket_index + 1) : bucket_index
    return 1 << ((unit_magnitude(h) + adjusted_bucket) % 64)
end

function lowest_equivalent_value(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function lowest_equivalent_value_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function next_non_equivalent_value(h::AbstractHistogram, value::Int64)
    return lowest_equivalent_value(h, value) + size_of_equivalent_value_range(h, value)
end

function highest_equivalent_value(h::AbstractHistogram, value)
    return next_non_equivalent_value(h, value) - 1
end

function median_equivalent_value(h::AbstractHistogram, value::Int64)
    return lowest_equivalent_value(h, value) + (size_of_equivalent_value_range(h, value) >> 1)
end

function reset_internal_counters!(h::AbstractHistogram{C}) where {C}
    min_non_zero_index = -1
    max_index = -1
    observed_total_count = 0

    # For compatability all indicies are 0-based
    @inbounds for i in 0:counts_length(h)-1
        if (count = counts_get_normalised(h, i)) > 0
            observed_total_count += count
            max_index = i
            if min_non_zero_index == -1 && i != 0
                min_non_zero_index = i
            end
        end
    end

    if max_index == -1
        max_value!(h, 0)
    else
        max_value = value_at_index(h, max_index)
        max_value!(h, highest_equivalent_value(h, max_value))
    end

    if min_non_zero_index == -1
        min_value!(h, typemax(Int64))
    else
        min_value!(h, value_at_index(h, min_non_zero_index))
    end

    total_count!(h, observed_total_count)
end

function buckets_needed_to_cover_value(value, sub_bucket_count, unit_magnitude)
    smallest_untrackable_value = Int64(sub_bucket_count) << (unit_magnitude % 64)
    buckets_needed = 1
    while smallest_untrackable_value <= value
        if smallest_untrackable_value > typemax(Int64) ÷ 2
            return buckets_needed + 1
        end
        smallest_untrackable_value <<= 1
        buckets_needed += 1
    end
    return buckets_needed
end

#### UPDATES ####

@noinline _throw_negative_value(value) = throw(ArgumentError("value $value must be >= 0"))
@noinline _throw_invalid_count(count) = throw(ArgumentError("count $count must be > 0"))
@noinline _throw_value_out_of_range(value) = throw(ArgumentError("value $value outside of histogram range"))

@inline function _record_value_at_index_unchecked!(h::AbstractHistogram, value::Int64, index, count::Int64)
    @inbounds counts_inc_normalised!(h, index, count)
    update_min_max!(h, value)
    return nothing
end

@inline function record_value!(h::AbstractHistogram, value::Int64, count::Int64=1)
    value >= 0 || _throw_negative_value(value)
    count > 0 || _throw_invalid_count(count)

    index = counts_index_for(h, value)
    if index >= counts_length(h)
        if auto_resize(h)
            resize!(h, value)
        else
            _throw_value_out_of_range(value)
        end
    end

    _record_value_at_index_unchecked!(h, value, index, count)
end

@inline record_value!(h::AbstractHistogram, value::Integer, count::Integer=1) =
    record_value!(h, Int64(value), Int64(count))

@inline function record_corrected_value!(h::AbstractHistogram, value::Int64, expected_interval::Int64, count::Int64=1)
    record_value!(h, value, count)

    value > expected_interval || return
    expected_interval > 0 || return

    missing_value = value - expected_interval
    while missing_value >= expected_interval
        record_value!(h, missing_value, count)
        missing_value -= expected_interval
    end
end

@inline record_corrected_value!(h::AbstractHistogram, value::Integer,
    expected_interval::Integer, count::Integer=1) =
    record_corrected_value!(h, Int64(value), Int64(expected_interval), Int64(count))

Base.push!(h::AbstractHistogram, value::Integer) = (record_value!(h, Int64(value)); h)

"""
    record_values!(histogram, values[, count])

Record every integer in `values`, optionally adding `count` occurrences of each
value. The histogram is returned so this method also backs `append!`.
"""
function record_values!(h::AbstractHistogram, values)
    for value in values
        record_value!(h, Int64(value))
    end
    return h
end

function record_values!(h::AbstractHistogram, values, count::Integer)
    count64 = Int64(count)
    for value in values
        record_value!(h, Int64(value), count64)
    end
    return h
end

Base.append!(h::AbstractHistogram, values) = record_values!(h, values)

@inline function _direct_add_compatible(h::AbstractHistogram, from::AbstractHistogram)
    return bucket_count(h) == bucket_count(from) &&
           sub_bucket_count(h) == sub_bucket_count(from) &&
           unit_magnitude(h) == unit_magnitude(from) &&
           normalizing_index_offset(h) == normalizing_index_offset(from) &&
           counts_length(h) == counts_length(from) &&
           !(from isa ConcurrentHistogram)
end

function _prepare_to_add!(h::AbstractHistogram, from::AbstractHistogram)
    total_count(from) == 0 && return
    highest_recordable = highest_equivalent_value(h, value_at_index(h, counts_length(h) - 1))
    source_max = max(from)
    if source_max > highest_recordable
        auto_resize(h) || throw(ArgumentError("source histogram contains values outside of destination range"))
        resize!(h, source_max)
    end
end

function _add_direct!(h::AbstractHistogram, from::AbstractHistogram)
    observed_total = Int64(0)
    @inbounds for i in 0:counts_length(from)-1
        count = counts_get_normalised(from, i)
        if count > 0
            counts_inc_direct!(h, normalize_index(h, i), count)
            observed_total += Int64(count)
        end
    end
    return _finish_direct_add!(h, from, observed_total)
end

@inline function _finish_direct_add!(h::AbstractHistogram, from::AbstractHistogram, observed_total::Int64)
    total_count_inc!(h, observed_total)
    if observed_total > 0
        update_min_max!(h, max_value(from))
        source_min = min_value(from)
        source_min == typemax(Int64) || update_min_max!(h, source_min)
    end
    return h
end

function _add_by_value!(h::AbstractHistogram, from::AbstractHistogram)
    @inbounds for i in 0:counts_length(from)-1
        count = counts_get_normalised(from, i)
        count > 0 && record_value!(h, value_at_index(from, i), Int64(count))
    end
    return h
end

function add(h::AbstractHistogram, from::AbstractHistogram)
    _prepare_to_add!(h, from)
    if _direct_add_compatible(h, from)
        _add_direct!(h, from)
    else
        _add_by_value!(h, from)
    end
    start_time_stamp!(h, min(start_time_stamp(h), start_time_stamp(from)))
    end_time_stamp!(h, max(end_time_stamp(h), end_time_stamp(from)))
    return h
end

"""Add `from` to `h` in place. `add` is retained as a Java-compatible alias."""
add!(h::AbstractHistogram, from::AbstractHistogram) = add(h, from)

function add_while_correcting_for_coordinated_omission(h::AbstractHistogram, from::AbstractHistogram, expected_interval::Int64)
    _prepare_to_add!(h, from)
    @inbounds for i in 0:counts_length(from)-1
        count = counts_get_normalised(from, i)
        if count > 0
            value = highest_equivalent_value(from, value_at_index(from, i))
            record_corrected_value!(h, value, expected_interval, Int64(count))
        end
    end
    return h
end

#### VALUES ####

function Base.max(h::AbstractHistogram{C}) where {C}
    if max_value(h) == zero(C)
        return 0
    end
    return highest_equivalent_value(h, max_value(h))
end

function max_value_as_double(h::AbstractHistogram{C}) where {C}
    return max(h) * conversion_ratio(h)
end

function Base.min(h::AbstractHistogram{C}) where {C}
    if total_count(h) == 0 || count_at_index(h, 0) > zero(C)
        return 0
    end

    if min_value(h) == typemax(Int64)
        return typemax(Int64)
    end

    return lowest_equivalent_value(h, min_value(h))
end

function count_at_percentile(h::AbstractHistogram, percentile::Real)
    # Truncate to 0..100%, and remove 1 unit of least precision to avoid roundoff overruns into next bucket when we
    # subsequently round up to the nearest integer:
    percentile_float = Float64(percentile)
    requested_percentile = isnan(percentile_float) ? 0.0 :
                           clamp(prevfloat(percentile_float), 0.0, 100.0)

    # Derive the count at the requested percentile. We round up to nearest integer to ensure that the
    # largest value that the requested percentile of overall recorded values is <= is actually included.
    return max(ceil(Int64, requested_percentile * total_count(h) / 100.0), 1)
end

function value_at_percentile(h::AbstractHistogram, percentile::Real)
    target_count = count_at_percentile(h, percentile)
    index = _index_at_cumulative_count(h, target_count)
    index < 0 && return 0
    value = value_at_index(h, index)
    return percentile == zero(typeof(percentile)) ?
           lowest_equivalent_value(h, value) : highest_equivalent_value(h, value)
end

function value_at_percentile(h::AbstractHistogram, percentiles, values::AbstractVector{<:Number})
    if length(percentiles) != length(values)
        throw(ArgumentError("percentiles and values must have the same length"))
    end
    @inbounds for i in 2:length(percentiles)
        if percentiles[i] < percentiles[i-1]
            throw(ArgumentError("percentiles must be sorted ascending"))
        end
    end

    # Reuse the destination array for cumulative-count targets.
    for i in eachindex(percentiles)
        values[i] = count_at_percentile(h, percentiles[i])
    end

    at_pos = firstindex(percentiles)
    last_pos = lastindex(percentiles)
    cumulative_count = Int64(0)
    @inbounds for index in 0:counts_length(h)-1
        cumulative_count += Int64(counts_get_normalised(h, index))
        while at_pos <= last_pos && cumulative_count >= values[at_pos]
            value = value_at_index(h, index)
            values[at_pos] = percentiles[at_pos] == zero(eltype(percentiles)) ?
                             lowest_equivalent_value(h, value) : highest_equivalent_value(h, value)
            at_pos += 1
        end
        at_pos > last_pos && return values
    end
    while at_pos <= last_pos
        @inbounds values[at_pos] = 0
        at_pos += 1
    end
    return values
end

function value_at_percentile(h::AbstractHistogram{C}, percentiles::AbstractVector) where {C}
    values = zeros(Int64, length(percentiles))
    value_at_percentile(h, percentiles, values)
    return values
end

function mean(h::AbstractHistogram{C}) where {C}
    total = Int128(0)
    count_total = total_count(h)
    if count_total == zero(C)
        return 0.0
    end
    @inbounds for i in 0:counts_length(h)-1
        count = counts_get_normalised(h, i)
        if count != 0
            value = median_equivalent_value(h, value_at_index(h, i))
            total += Int128(count) * value
        end
    end
    return total / count_total
end

function stddev(h::AbstractHistogram{C}) where {C}
    count_total = total_count(h)
    count_total == zero(C) && return 0.0
    average = mean(h)
    geometric_deviation_total = 0.0
    @inbounds for i in 0:counts_length(h)-1
        count = counts_get_normalised(h, i)
        if count != 0
            deviation = median_equivalent_value(h, value_at_index(h, i)) - average
            geometric_deviation_total += deviation^2 * count
        end
    end
    return sqrt(geometric_deviation_total / count_total)
end

function values_are_equivalent(h::AbstractHistogram, a::Int64, b::Int64)
    return lowest_equivalent_value(h, a) == lowest_equivalent_value(h, b)
end

function count_at_value(h::AbstractHistogram, value::Int64)
    value >= 0 || throw(ArgumentError("value $value must be >= 0"))
    index = clamp(counts_index_for(h, value), 0, counts_length(h) - 1)
    return @inbounds counts_get_normalised(h, index)
end

function count_at_index(h::AbstractHistogram, index::Int64)
    0 <= index < counts_length(h) || throw(BoundsError(counts(h), index + 1))
    return counts_get_normalised(h, index)
end

function _index_at_cumulative_count(h::AbstractHistogram, target_count::Integer)
    cumulative_count = Int64(0)
    index = 0
    limit = counts_length(h)

    # Four-at-a-time loading retains early-exit semantics while allowing LLVM to
    # combine adjacent non-atomic loads on the common zero-offset layout.
    @inbounds while index + 4 <= limit
        c0 = Int64(counts_get_normalised(h, index))
        c1 = Int64(counts_get_normalised(h, index + 1))
        c2 = Int64(counts_get_normalised(h, index + 2))
        c3 = Int64(counts_get_normalised(h, index + 3))
        chunk_total = c0 + c1 + c2 + c3
        if cumulative_count + chunk_total >= target_count
            cumulative_count += c0
            cumulative_count >= target_count && return index
            cumulative_count += c1
            cumulative_count >= target_count && return index + 1
            cumulative_count += c2
            cumulative_count >= target_count && return index + 2
            return index + 3
        end
        cumulative_count += chunk_total
        index += 4
    end

    @inbounds while index < limit
        cumulative_count += Int64(counts_get_normalised(h, index))
        cumulative_count >= target_count && return index
        index += 1
    end
    return -1
end

function percentile_print(io::IO, h::AbstractHistogram, ticks_per_half_distance, value_scale)
    @printf(io, "%12s %12s %12s %12s\n\n", "Value", "Percentile", "TotalCount", "1/(1-Percentile)")
    for i in PercentileIterator(h, ticks_per_half_distance)
        val = highest_equivalent_value(h, value_iterated_to(i)) / value_scale
        p = percentile(i) / 100.0
        total_count = total_count_to_this_value(i)
        inverted_percentile = 1.0 / (1.0 - p)
        @printf(io, "%12.5f %12f %12d %12.2f\n", val, p, total_count, inverted_percentile)
    end
    mean = HdrHistogram.mean(h) / value_scale
    stddev = HdrHistogram.stddev(h) / value_scale
    max = HdrHistogram.max(h) / value_scale

    @printf(io, "#[Mean    = %12.3f, StdDeviation   = %12.3f]\n", mean, stddev)
    @printf(io, "#[Max     = %12.3f, Total count    = %12d]\n", max, total_count(h))
    @printf(io, "#[Buckets = %12d, SubBuckets     = %12d]\n", bucket_count(h), sub_bucket_count(h))
end
