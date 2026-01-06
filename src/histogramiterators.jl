struct AllValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end
histogram(iter::AllValuesIterator) = iter.histogram

mutable struct AllValuesIteratorState <: AbstractHistogramIteratorStateSpecific
    visited_index::Int64
end
HistogramIteratorState(iter::AllValuesIterator) = HistogramIteratorState(iter, AllValuesIteratorState(-1))

function reset_state!(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    h = histogram(iter)
    state.total_count = total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.visited_index = -1
    return state
end

function increment_iteration_level(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    state.specifics.visited_index = state.current_index
    return state
end

function reached_iteration_level(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    return state.specifics.visited_index != state.current_index
end

function has_next(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    h = histogram(iter)
    if total_count(h) != state.total_count
        error("Concurrent Modification Exception")
    end
    return state.current_index <= counts_length(h) - 1, state
end

struct RecordedValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end

histogram(iter::RecordedValuesIterator) = iter.histogram

mutable struct RecordedValuesIteratorState <: AbstractHistogramIteratorStateSpecific
    visited_index::Int64
end
HistogramIteratorState(iter::RecordedValuesIterator) = HistogramIteratorState(iter, RecordedValuesIteratorState(-1))

@inline function has_next(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    return has_next_base(iter, state)
end

function reset_state!(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    h = histogram(iter)
    state.total_count = total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.visited_index = -1
    return state
end

recorded_values_state(iter::RecordedValuesIterator) = HistogramIteratorState(iter)
function recorded_values_state(h::AbstractHistogram)
    iter = RecordedValuesIterator(h)
    return iter, iterator_state(iter)
end

function all_values_state(h::AbstractHistogram)
    iter = AllValuesIterator(h)
    return iter, iterator_state(iter)
end

function linear_iterator_state(h::AbstractHistogram, value_units_per_bucket::Int64)
    iter = LinearIterator(h, value_units_per_bucket)
    return iter, iterator_state(iter)
end

function logarithmic_iterator_state(h::AbstractHistogram, value_units_per_bucket::Int64, log_base::Float64)
    iter = LogarithmicIterator(h, value_units_per_bucket, log_base)
    return iter, iterator_state(iter)
end

function percentile_iterator_state(h::AbstractHistogram, ticks_per_half_distance::Int64)
    iter = PercentileIterator(h, ticks_per_half_distance)
    return iter, iterator_state(iter)
end

function mean(h::AbstractHistogram{C}, iter::RecordedValuesIterator{C}, state::HistogramIteratorState{RecordedValuesIteratorState}) where {C}
    reset_state!(iter, state)
    total = Int128(0)
    count_total = total_count(h)
    if count_total == zero(C)
        return 0.0
    end
    while iterate!(iter, state)
        i = state.iter_value
        total += count_at_value_iterated_to(i) * median_equivalent_value(h, value_iterated_to(i))
    end
    return total / count_total
end

function stddev(h::AbstractHistogram{C}, iter::RecordedValuesIterator{C}, state::HistogramIteratorState{RecordedValuesIteratorState}) where {C}
    reset_state!(iter, state)
    count_total = total_count(h)
    if count_total == zero(C)
        return 0.0
    end
    m = mean(h, iter, state)
    reset_state!(iter, state)
    geometric_dev_total = 0.0
    while iterate!(iter, state)
        i = state.iter_value
        dev = median_equivalent_value(h, value_iterated_to(i)) - m
        geometric_dev_total += dev^2 * count_at_value_iterated_to(i)
    end
    return sqrt(geometric_dev_total / count_total)
end

function value_at_percentile(h::AbstractHistogram, percentile::Real, iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    count = count_at_percentile(h, percentile)
    reset_state!(iter, state)
    while iterate!(iter, state)
        i = state.iter_value
        if total_count_to_this_value(i) >= count
            return percentile == zero(typeof(percentile)) ?
                   lowest_equivalent_value(h, value_iterated_to(i)) : highest_equivalent_value(h, value_iterated_to(i))
        end
    end
    return 0
end

function value_at_percentile(h::AbstractHistogram, percentiles, values::AbstractVector{<:Number},
    iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    reset_state!(iter, state)
    at_pos = 1
    while iterate!(iter, state)
        if at_pos > length(percentiles)
            break
        end
        i = state.iter_value
        while at_pos <= length(percentiles) && total_count_to_this_value(i) >= values[at_pos]
            values[at_pos] = percentiles[at_pos] == zero(eltype(percentiles)) ?
                             lowest_equivalent_value(h, value_iterated_to(i)) : highest_equivalent_value(h, value_iterated_to(i))
            at_pos += 1
        end
    end
end

function add(h::AbstractHistogram, from::AbstractHistogram,
    iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    reset_state!(iter, state)
    while iterate!(iter, state)
        i = state.iter_value
        record_value!(h, value_iterated_to(i), count_at_value_iterated_to(i))
    end
end

function add_while_correcting_for_coordinated_omission(h::AbstractHistogram, from::AbstractHistogram, expected_interval::Int64,
    iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    reset_state!(iter, state)
    while iterate!(iter, state)
        i = state.iter_value
        record_corrected_value!(h, value_iterated_to(i), expected_interval, count_at_value_iterated_to(i))
    end
end

function increment_iteration_level(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    state.specifics.visited_index = state.current_index
    return state
end

function reached_iteration_level(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    current_count = count_at_index(iter.histogram, state.current_index)
    return current_count != 0 && state.specifics.visited_index != state.current_index
end

struct PercentileIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    ticks_per_half_distance::Int64
end

histogram(iter::PercentileIterator) = iter.histogram

mutable struct PercentileIteratorState <: AbstractHistogramIteratorStateSpecific
    percentile_level_iterated_to::Float64
    percentile_level_iterated_from::Float64
    reached_last_recorded_value::Bool
end
HistogramIteratorState(iter::PercentileIterator) = HistogramIteratorState(iter, PercentileIteratorState(0.0, 0.0, false))

function reset_state!(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    h = histogram(iter)
    state.total_count = total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.percentile_level_iterated_to = 0.0
    state.specifics.percentile_level_iterated_from = 0.0
    state.specifics.reached_last_recorded_value = false
    return state
end

function has_next(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    if has_next_base(iter, state)[1]
        return true, state
    end
    if !state.specifics.reached_last_recorded_value && state.total_count > 0
        state.specifics.percentile_level_iterated_to = 100.0
        state.specifics.reached_last_recorded_value = true
        return true, state
    end
    return false, state
end

function increment_iteration_level(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    state.specifics.percentile_level_iterated_from = state.specifics.percentile_level_iterated_to
    percentile_gap = 100.0 - state.specifics.percentile_level_iterated_to
    if percentile_gap != 0.0
        half_distance = 2^floor(Int64, log2(100.0 / percentile_gap) + 1)
        percentile_reporting_ticks = half_distance * iter.ticks_per_half_distance
        state.specifics.percentile_level_iterated_to += 100.0 / percentile_reporting_ticks
    end
    return state
end

function reached_iteration_level(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    if state.count_at_this_value == 0
        return false
    end
    current_percentile = 100.0 * state.total_count_to_current_index / state.total_count
    return current_percentile >= state.specifics.percentile_level_iterated_to
end

function percentile_iterated_to(state::HistogramIteratorState{PercentileIteratorState})
    return state.specifics.percentile_level_iterated_to
end

function percentile_iterated_from(state::HistogramIteratorState{PercentileIteratorState})
    return state.specifics.percentile_level_iterated_from
end

struct LinearIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
end

histogram(iter::LinearIterator) = iter.histogram

mutable struct LinearIteratorState <: AbstractHistogramIteratorStateSpecific
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
end
HistogramIteratorState(iter::LinearIterator) = HistogramIteratorState(iter,
    LinearIteratorState(iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket)))

function reset_state!(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    h = histogram(iter)
    state.total_count = total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.current_step_highest_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_lowest_value_reporting_level =
        lowest_equivalent_value(h, iter.value_units_per_bucket)
    return state
end


function has_next(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    if has_next_base(iter, state)[1]
        return true, state
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return state.specifics.current_step_lowest_value_reporting_level < state.next_value_at_index, state
end

function increment_iteration_level(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    state.specifics.current_step_highest_value_reporting_level += iter.value_units_per_bucket
    state.specifics.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.specifics.current_step_highest_value_reporting_level)
    return state
end

function value_iterated_to(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    return state.specifics.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    return state.current_value_at_index >= state.specifics.current_step_lowest_value_reporting_level
end

struct LogarithmicIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
    log_base::Float64
end

histogram(iter::LogarithmicIterator) = iter.histogram

mutable struct LogarithmicIteratorState <: AbstractHistogramIteratorStateSpecific
    next_value_reporting_level::Float64
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
end
HistogramIteratorState(iter::LogarithmicIterator) = HistogramIteratorState(iter,
    LogarithmicIteratorState(iter.value_units_per_bucket,
        iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket)))

function reset_state!(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    h = histogram(iter)
    state.total_count = total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.next_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_highest_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_lowest_value_reporting_level =
        lowest_equivalent_value(h, iter.value_units_per_bucket)
    return state
end

function has_next(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    if has_next_base(iter, state)[1]
        return true, state
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return lowest_equivalent_value(iter.histogram, floor(Int64, state.specifics.next_value_reporting_level)) < state.next_value_at_index, state
end

function increment_iteration_level(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    state.specifics.next_value_reporting_level *= iter.log_base
    state.specifics.current_step_highest_value_reporting_level = floor(state.specifics.next_value_reporting_level) - 1
    state.specifics.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.specifics.current_step_highest_value_reporting_level)
    return state
end

function value_iterated_to(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    return state.specifics.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    return state.current_value_at_index >= state.specifics.current_step_lowest_value_reporting_level
end
