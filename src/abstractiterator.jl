abstract type AbstractHistogramIterator end

function histogram end
function increment_iteration_level end
function reached_iteration_level end

abstract type AbstractHistogramIteratorState end

abstract type AbstractHistogramItem end

abstract type AbstractHistogramIteratorStateSpecific end

mutable struct HistogramIterationValue <: AbstractHistogramItem
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

function set_iteration_value!(item::HistogramIterationValue, value_iterated_to::Int64, state::HistogramIteratorState)
    item.value_iterated_to = value_iterated_to
    item.value_iterated_from = state.previous_value_iterated_to
    item.count_at_value_iterated_to = state.count_at_this_value
    item.count_added_in_this_iteration_step = state.total_count_to_current_index - state.total_count_to_previous_index
    item.total_count_to_this_value = state.total_count_to_current_index
    item.total_value_to_this_value = state.total_value_to_current_index
    item.percentile = 100.0 * state.total_count_to_current_index / state.total_count
    item.percentile_iterated_to = percentile_iterated_to(state)
    return item
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
            set_iteration_value!(state.iter_value, val_iter_to, state)

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
        set_iteration_value!(state.iter_value, val_iter_to, state)

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

Base.iterate(iter::AbstractHistogramIterator) = iterate(iter, HistogramIteratorState(iter))
Base.eltype(::Type{<:AbstractHistogramIterator}) = HistogramIterationValue
Base.IteratorSize(::Type{<:AbstractHistogramIterator}) = Base.SizeUnknown()
Base.isdone(iter::AbstractHistogramIterator, state::HistogramIteratorState) = !has_next(iter, state)[1]

function percentile_iterated_to(state::HistogramIteratorState)
    return 100.0 * state.total_count_to_current_index / state.total_count
end

function percentile_iterated_from(state::HistogramIteratorState)
    return 100.0 * state.total_count_to_previous_index / state.total_count
end
