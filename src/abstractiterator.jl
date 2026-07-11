abstract type AbstractHistogramIterator end

function histogram end
function increment_iteration_level end
function reached_iteration_level end

abstract type AbstractHistogramIteratorState end

abstract type AbstractHistogramItem end

abstract type AbstractHistogramIteratorStateSpecific end

function reset_state! end
function snapshot_specifics end
function snapshot_has_next end
function snapshot_reached_iteration_level end
function snapshot_increment_iteration_level end

struct HistogramIterationValue <: AbstractHistogramItem
    value_iterated_to::Int64
    value_iterated_from::Int64
    count_at_value_iterated_to::Int64
    count_added_in_this_iteration_step::Int64
    total_count_to_this_value::Int64
    total_value_to_this_value::Int64
    percentile::Float64
    percentile_iterated_to::Float64
end

HistogramIterationValue() = HistogramIterationValue(0, 0, 0, 0, 0, 0, 0.0, 0.0)

mutable struct HistogramIteratorState{S<:AbstractHistogramIteratorStateSpecific} <: AbstractHistogramIteratorState
    total_count::Int64
    current_index::Int64
    current_value_at_index::Int64
    next_value_at_index::Int64
    previous_value_iterated_to::Int64
    total_count_to_previous_index::Int64
    total_count_to_current_index::Int64
    total_value_to_current_index::Int64
    count_at_this_value::Int64
    fresh_sub_bucket::Bool
    specifics::S
    iter_value::HistogramIterationValue
end

HistogramIteratorState(iter::AbstractHistogramIterator, specifics::AbstractHistogramIteratorStateSpecific) = HistogramIteratorState(
    total_count(histogram(iter)),
    0, 0, 1 << unit_magnitude(histogram(iter)), 0, 0, 0, 0, 0, true, specifics,
    HistogramIterationValue())

function set_iteration_value!(::HistogramIterationValue, value_iterated_to::Int64, state::HistogramIteratorState)
    return HistogramIterationValue(
        value_iterated_to,
        state.previous_value_iterated_to,
        state.count_at_this_value,
        state.total_count_to_current_index - state.total_count_to_previous_index,
        state.total_count_to_current_index,
        state.total_value_to_current_index,
        100.0 * state.total_count_to_current_index / state.total_count,
        percentile_iterated_to(state),
    )
end

value_iterated_to(iter::HistogramIterationValue) = iter.value_iterated_to
value_iterated_from(iter::HistogramIterationValue) = iter.value_iterated_from
count_at_value_iterated_to(iter::HistogramIterationValue) = iter.count_at_value_iterated_to
count_added_in_this_iteration_step(iter::HistogramIterationValue) = iter.count_added_in_this_iteration_step
total_count_to_this_value(iter::HistogramIterationValue) = iter.total_count_to_this_value
total_value_to_this_value(iter::HistogramIterationValue) = iter.total_value_to_this_value
percentile(iter::HistogramIterationValue) = iter.percentile
percentile_iterated_to(iter::HistogramIterationValue) = iter.percentile_iterated_to

@inline function has_next_base(iter::AbstractHistogramIterator, state::HistogramIteratorState)
    h = histogram(iter)
    if total_count(h) != state.total_count
        error("Concurrent Modification Exception")
    end
    return state.total_count_to_current_index < state.total_count, state
end

function value_iterated_to(iter::AbstractHistogramIterator, state::HistogramIteratorState)
    h = histogram(iter)
    return highest_equivalent_value(h, state.current_value_at_index)
end

@inline function iterate!(iter::I, state::HistogramIteratorState{S}) where {I<:AbstractHistogramIterator,S<:AbstractHistogramIteratorStateSpecific}
    h = histogram(iter)

    while true
        next, state = has_next(iter, state)
        if !next
            break
        end
        count = count_at_index(h, state.current_index)
        state.count_at_this_value = count
        if state.fresh_sub_bucket
            state.total_count_to_current_index += count
            state.total_value_to_current_index += count * highest_equivalent_value(h, state.current_value_at_index)
            state.fresh_sub_bucket = false
        end
        if reached_iteration_level(iter, state)
            val_iter_to = value_iterated_to(iter, state)
            state.iter_value = set_iteration_value!(state.iter_value, val_iter_to, state)

            state.previous_value_iterated_to = val_iter_to
            state.total_count_to_previous_index = state.total_count_to_current_index

            state = increment_iteration_level(iter, state)

            if total_count(h) != state.total_count
                error("Concurrent Modification Exception")
            end

            return true
        end

        state.fresh_sub_bucket = true
        state.current_index += 1
        state.current_value_at_index = value_at_index(h, state.current_index)
        state.next_value_at_index = value_at_index(h, state.current_index + 1)
    end

    if state.total_count_to_current_index > state.total_count_to_previous_index
        # We are at the end of the iteration but we still need to report
        # the last iteration value
        val_iter_to = value_iterated_to(iter, state)
        state.iter_value = set_iteration_value!(state.iter_value, val_iter_to, state)

        # we do this one time only
        state.total_count_to_previous_index = state.total_count_to_current_index

        return true
    end

    return false
end

function Base.iterate(iter::I, state::HistogramIteratorState{S}) where {I<:AbstractHistogramIterator,S<:AbstractHistogramIteratorStateSpecific}
    if iterate!(iter, state)
        return state.iter_value, state
    end
    return nothing
end

struct HistogramIteratorSnapshot{S}
    total_count::Int64
    current_index::Int64
    current_value_at_index::Int64
    next_value_at_index::Int64
    previous_value_iterated_to::Int64
    total_count_to_previous_index::Int64
    total_count_to_current_index::Int64
    total_value_to_current_index::Int64
    count_at_this_value::Int64
    fresh_sub_bucket::Bool
    specifics::S
end

function HistogramIteratorSnapshot(iter::AbstractHistogramIterator)
    h = histogram(iter)
    return HistogramIteratorSnapshot(
        total_count(h),
        0,
        0,
        1 << unit_magnitude(h),
        0,
        0,
        0,
        0,
        0,
        true,
        snapshot_specifics(iter),
    )
end

@inline snapshot_value_iterated_to(iter::AbstractHistogramIterator, current_value_at_index, specifics) =
    highest_equivalent_value(histogram(iter), current_value_at_index)

@inline snapshot_percentile_iterated_to(iter::AbstractHistogramIterator, total_count_to_current_index,
    total_count, specifics) = 100.0 * total_count_to_current_index / total_count

@inline function _iteration_value(iter::AbstractHistogramIterator, value_to::Int64, previous_value_to::Int64,
    count_at_this_value::Int64, total_count_to_previous_index::Int64,
    total_count_to_current_index::Int64, total_value_to_current_index::Int64, total_count::Int64, specifics)
    return HistogramIterationValue(
        value_to,
        previous_value_to,
        count_at_this_value,
        total_count_to_current_index - total_count_to_previous_index,
        total_count_to_current_index,
        total_value_to_current_index,
        100.0 * total_count_to_current_index / total_count,
        snapshot_percentile_iterated_to(iter, total_count_to_current_index, total_count, specifics),
    )
end

@inline function Base.iterate(iter::I, state::HistogramIteratorSnapshot{S}) where {I<:AbstractHistogramIterator,S}
    h = histogram(iter)
    total_count(h) == state.total_count || error("Concurrent Modification Exception")

    current_index = state.current_index
    current_value_at_index = state.current_value_at_index
    next_value_at_index = state.next_value_at_index
    previous_value_iterated_to = state.previous_value_iterated_to
    total_count_to_previous_index = state.total_count_to_previous_index
    total_count_to_current_index = state.total_count_to_current_index
    total_value_to_current_index = state.total_value_to_current_index
    count_at_this_value = state.count_at_this_value
    fresh_sub_bucket = state.fresh_sub_bucket
    specifics = state.specifics

    while true
        has_next, specifics = snapshot_has_next(iter, state.total_count, current_index,
            next_value_at_index, total_count_to_current_index, specifics)
        has_next || break

        0 <= current_index < counts_length(h) || error("Concurrent Modification Exception")
        count_at_this_value = Int64(@inbounds counts_get_normalised(h, current_index))
        if fresh_sub_bucket
            total_count_to_current_index += count_at_this_value
            total_value_to_current_index +=
                count_at_this_value * highest_equivalent_value(h, current_value_at_index)
            fresh_sub_bucket = false
        end

        if snapshot_reached_iteration_level(iter, state.total_count, current_index,
            current_value_at_index, count_at_this_value, total_count_to_current_index, specifics)
            value_to = snapshot_value_iterated_to(iter, current_value_at_index, specifics)
            item = _iteration_value(iter, value_to, previous_value_iterated_to,
                count_at_this_value, total_count_to_previous_index,
                total_count_to_current_index, total_value_to_current_index,
                state.total_count, specifics)
            specifics = snapshot_increment_iteration_level(iter, current_index, specifics)
            next_state = HistogramIteratorSnapshot(
                state.total_count,
                current_index,
                current_value_at_index,
                next_value_at_index,
                value_to,
                total_count_to_current_index,
                total_count_to_current_index,
                total_value_to_current_index,
                count_at_this_value,
                false,
                specifics,
            )
            total_count(h) == state.total_count || error("Concurrent Modification Exception")
            return item, next_state
        end

        fresh_sub_bucket = true
        current_index += 1
        current_value_at_index = value_at_index(h, current_index)
        next_value_at_index = value_at_index(h, current_index + 1)
    end

    if total_count_to_current_index > total_count_to_previous_index
        value_to = snapshot_value_iterated_to(iter, current_value_at_index, specifics)
        item = _iteration_value(iter, value_to, previous_value_iterated_to,
            count_at_this_value, total_count_to_previous_index,
            total_count_to_current_index, total_value_to_current_index,
            state.total_count, specifics)
        next_state = HistogramIteratorSnapshot(
            state.total_count,
            current_index,
            current_value_at_index,
            next_value_at_index,
            value_to,
            total_count_to_current_index,
            total_count_to_current_index,
            total_value_to_current_index,
            count_at_this_value,
            false,
            specifics,
        )
        return item, next_state
    end
    return nothing
end

Base.iterate(iter::AbstractHistogramIterator) = iterate(iter, HistogramIteratorSnapshot(iter))
Base.eltype(::Type{<:AbstractHistogramIterator}) = HistogramIterationValue
Base.IteratorSize(::Type{<:AbstractHistogramIterator}) = Base.SizeUnknown()
Base.isdone(iter::AbstractHistogramIterator, state::HistogramIteratorState) = !has_next(iter, state)[1]
Base.isdone(iter::AbstractHistogramIterator, state::HistogramIteratorSnapshot) =
    !snapshot_has_next(iter, state.total_count, state.current_index, state.next_value_at_index,
        state.total_count_to_current_index, state.specifics)[1]

function percentile_iterated_to(state::HistogramIteratorState)
    return 100.0 * state.total_count_to_current_index / state.total_count
end

function percentile_iterated_from(state::HistogramIteratorState)
    return 100.0 * state.total_count_to_previous_index / state.total_count
end

function iterator_state(iter::AbstractHistogramIterator)
    state = HistogramIteratorState(iter)
    reset_state!(iter, state)
    return state
end
