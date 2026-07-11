const _RECORDER_INSTANCE_ID = Threads.Atomic{Int64}(0)

@inline function _next_recorder_id()
    return Threads.atomic_add!(_RECORDER_INSTANCE_ID, 1)
end

@inline function _now_msec()
    return round(Int64, time() * 1000)
end

@inline function _compatible_replacement(active::AbstractHistogram, replacement::AbstractHistogram)
    return typeof(active) == typeof(replacement) &&
           lowest_discernible_value(active) == lowest_discernible_value(replacement) &&
           significant_figures(active) == significant_figures(replacement) &&
           (auto_resize(replacement) || highest_trackable_value(replacement) >= highest_trackable_value(active))
end

mutable struct Recorder{T<:AbstractHistogram}
    const instance_id::Int64
    const phaser::WriterReaderPhaser
    @atomic active::T
    inactive::Union{Nothing,T}
    const serialize_writers::Bool
    const writer_lock::ReentrantLock
    function Recorder(histogram::T) where {T<:AbstractHistogram}
        start_time_stamp!(histogram, _now_msec())
        serialize_writers = !(histogram isa Union{AtomicHistogram,ConcurrentHistogram,SynchronizedHistogram})
        new{T}(_next_recorder_id(), WriterReaderPhaser(), histogram, nothing,
            serialize_writers, ReentrantLock())
    end
end

Recorder(number_of_significant_value_digits) = Recorder(ConcurrentHistogram(number_of_significant_value_digits))
Recorder(lowest_discernible_value, highest_trackable_value, significant_figures) =
    Recorder(AtomicHistogram(lowest_discernible_value, highest_trackable_value, significant_figures))

mutable struct SingleWriterRecorder{T<:AbstractHistogram}
    const instance_id::Int64
    const phaser::WriterReaderPhaser
    active::T
    inactive::Union{Nothing,T}
    function SingleWriterRecorder(histogram::T) where {T<:AbstractHistogram}
        start_time_stamp!(histogram, _now_msec())
        new{T}(_next_recorder_id(), WriterReaderPhaser(), histogram, nothing)
    end
end

SingleWriterRecorder(number_of_significant_value_digits) = SingleWriterRecorder(Histogram(number_of_significant_value_digits))
SingleWriterRecorder(lowest_discernible_value, highest_trackable_value, significant_figures) =
    SingleWriterRecorder(Histogram(lowest_discernible_value, highest_trackable_value, significant_figures))

@inline function record_value!(r::Recorder, value::Int64, count::Int64=1)
    r.serialize_writers && lock(r.writer_lock)
    val = writer_critical_section_enter(r.phaser)
    try
        record_value!((@atomic r.active), value, count)
    finally
        writer_critical_section_exit(r.phaser, val)
        r.serialize_writers && unlock(r.writer_lock)
    end
end

@inline function record_corrected_value!(r::Recorder, value::Int64, expected_interval::Int64, count::Int64=1)
    r.serialize_writers && lock(r.writer_lock)
    val = writer_critical_section_enter(r.phaser)
    try
        record_corrected_value!((@atomic r.active), value, expected_interval, count)
    finally
        writer_critical_section_exit(r.phaser, val)
        r.serialize_writers && unlock(r.writer_lock)
    end
end


function record_values!(r::Recorder, values)
    r.serialize_writers && lock(r.writer_lock)
    val = writer_critical_section_enter(r.phaser)
    try
        active = @atomic r.active
        record_values!(active, values)
        return r
    finally
        writer_critical_section_exit(r.phaser, val)
        r.serialize_writers && unlock(r.writer_lock)
    end
end


function record_values!(r::SingleWriterRecorder, values)
    val = writer_critical_section_enter(r.phaser)
    try
        record_values!(r.active, values)
        return r
    finally
        writer_critical_section_exit(r.phaser, val)
    end
end

Base.push!(r::Union{Recorder,SingleWriterRecorder}, value::Integer) =
    (record_value!(r, Int64(value)); r)
Base.append!(r::Union{Recorder,SingleWriterRecorder}, values) = record_values!(r, values)

@inline record_value!(r::Union{Recorder,SingleWriterRecorder}, value::Integer, count::Integer=1) =
    record_value!(r, Int64(value), Int64(count))
@inline record_corrected_value!(r::Union{Recorder,SingleWriterRecorder}, value::Integer,
    expected_interval::Integer, count::Integer=1) =
    record_corrected_value!(r, Int64(value), Int64(expected_interval), Int64(count))

@inline function record_value!(r::SingleWriterRecorder, value::Int64, count::Int64=1)
    val = writer_critical_section_enter(r.phaser)
    try
        record_value!(r.active, value, count)
    finally
        writer_critical_section_exit(r.phaser, val)
    end
end

@inline function record_corrected_value!(r::SingleWriterRecorder, value::Int64, expected_interval::Int64, count::Int64=1)
    val = writer_critical_section_enter(r.phaser)
    try
        record_corrected_value!(r.active, value, expected_interval, count)
    finally
        writer_critical_section_exit(r.phaser, val)
    end
end

function _interval_histogram(recorder::Recorder, replacement::Union{Nothing,AbstractHistogram})
    reader_lock(recorder.phaser)
    try
        active = @atomic recorder.active
        if replacement !== nothing && !_compatible_replacement(active, replacement)
            throw(ArgumentError("replacement histogram is incompatible with recorder configuration"))
        end
        inactive = replacement === nothing ? recorder.inactive : replacement
        if inactive === nothing
            inactive = similar(active)
        end
        reset!(inactive)
        inactive = @atomicswap recorder.active = inactive
        now = _now_msec()
        start_time_stamp!((@atomic recorder.active), now)
        end_time_stamp!(inactive, now)
        flip_phase(recorder.phaser, 500_000)
        recorder.inactive = nothing
        return inactive
    finally
        reader_unlock(recorder.phaser)
    end
end

function _interval_histogram(recorder::SingleWriterRecorder, replacement::Union{Nothing,AbstractHistogram})
    reader_lock(recorder.phaser)
    try
        active = recorder.active
        if replacement !== nothing && !_compatible_replacement(active, replacement)
            throw(ArgumentError("replacement histogram is incompatible with recorder configuration"))
        end
        inactive = replacement === nothing ? recorder.inactive : replacement
        if inactive === nothing
            inactive = similar(active)
        end
        reset!(inactive)
        recorder.active, inactive = inactive, recorder.active
        now = _now_msec()
        start_time_stamp!(recorder.active, now)
        end_time_stamp!(inactive, now)
        flip_phase(recorder.phaser, 500_000)
        recorder.inactive = nothing
        return inactive
    finally
        reader_unlock(recorder.phaser)
    end
end

interval_histogram(r::Recorder) = _interval_histogram(r, nothing)
interval_histogram(r::Recorder, inactive::AbstractHistogram) = _interval_histogram(r, inactive)
interval_histogram(r::SingleWriterRecorder) = _interval_histogram(r, nothing)
interval_histogram(r::SingleWriterRecorder, inactive::AbstractHistogram) = _interval_histogram(r, inactive)

function reset!(r::Recorder)
    _ = interval_histogram(r)
    _ = interval_histogram(r)
    return nothing
end

function reset!(r::SingleWriterRecorder)
    _ = interval_histogram(r)
    _ = interval_histogram(r)
    return nothing
end
