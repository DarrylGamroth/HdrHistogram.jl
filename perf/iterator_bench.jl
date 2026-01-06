using HdrHistogram

const HH = HdrHistogram

function bench(label, n, f, args...)
    GC.gc()
    f(args...)
    GC.gc()
    t0 = time_ns()
    for _ in 1:n
        f(args...)
    end
    elapsed = (time_ns() - t0)
    ns_per = elapsed / n
    rate = 1e9 / ns_per
    alloc = @allocated f(args...)
    println(rpad(label, 28),
        "ops/sec=", round(rate, digits=1),
        " ns/op=", round(ns_per, digits=1),
        " alloc=", alloc)
end

hist = HH.Histogram(1, 1_000_000, 3)
for i in 1:200_000
    HH.record_value!(hist, i % 10_000)
end

recorded_iter = HH.RecordedValuesIterator(hist)
all_iter = HH.AllValuesIterator(hist)
linear_iter = HH.LinearIterator(hist, 10_000)
log_iter = HH.LogarithmicIterator(hist, 10_000, 2.0)

function consume(iter::HH.RecordedValuesIterator)
    total = 0
    state = HH.recorded_values_state(iter)
    while HH.iterate!(iter, state)
        total += HH.count_added_in_this_iteration_step(state.iter_value)
    end
    return total
end

function consume(iter)
    total = 0
    state = HH.HistogramIteratorState(iter)
    while HH.iterate!(iter, state)
        total += HH.count_added_in_this_iteration_step(state.iter_value)
    end
    return total
end

function reset_state!(iter::HH.RecordedValuesIterator, state)
    h = HH.histogram(iter)
    state.total_count = HH.total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << HH.unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.visited_index = -1
    return state
end

function reset_state!(iter::HH.AllValuesIterator, state)
    h = HH.histogram(iter)
    state.total_count = HH.total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << HH.unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.visited_index = -1
    return state
end

function reset_state!(iter::HH.LinearIterator, state)
    h = HH.histogram(iter)
    state.total_count = HH.total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << HH.unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.current_step_highest_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_lowest_value_reporting_level =
        HH.lowest_equivalent_value(h, iter.value_units_per_bucket)
    return state
end

function reset_state!(iter::HH.LogarithmicIterator, state)
    h = HH.histogram(iter)
    state.total_count = HH.total_count(h)
    state.current_index = 0
    state.current_value_at_index = 0
    state.next_value_at_index = 1 << HH.unit_magnitude(h)
    state.previous_value_iterated_to = 0
    state.total_count_to_previous_index = 0
    state.total_count_to_current_index = 0
    state.total_value_to_current_index = 0
    state.count_at_this_value = 0
    state.fresh_sub_bucket = true
    state.specifics.next_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_highest_value_reporting_level = iter.value_units_per_bucket
    state.specifics.current_step_lowest_value_reporting_level =
        HH.lowest_equivalent_value(h, iter.value_units_per_bucket)
    return state
end

function consume_state(iter, state)
    total = 0
    while HH.iterate!(iter, state)
        total += HH.count_added_in_this_iteration_step(state.iter_value)
    end
    return total
end

function consume_reset!(iter, state)
    reset_state!(iter, state)
    return consume_state(iter, state)
end

recorded_state = HH.iterator_state(recorded_iter)
all_state = HH.HistogramIteratorState(all_iter)
linear_state = HH.HistogramIteratorState(linear_iter)
log_state = HH.HistogramIteratorState(log_iter)

bench("recorded iterator", 200, consume, recorded_iter)
bench("recorded iterator (reuse)", 200, consume_reset!, recorded_iter, recorded_state)
bench("all values iterator", 50, consume, all_iter)
bench("all values iterator (reuse)", 50, consume_reset!, all_iter, all_state)
bench("linear iterator", 200, consume, linear_iter)
bench("linear iterator (reuse)", 200, consume_reset!, linear_iter, linear_state)
bench("log iterator", 500, consume, log_iter)
bench("log iterator (reuse)", 500, consume_reset!, log_iter, log_state)
