mutable struct IntervalRecorder{T<:AbstractHistogram}
    const phaser::WriterReaderPhaser
    @atomic active::T
    const serialize_writers::Bool
    const writer_lock::ReentrantLock
    function IntervalRecorder(histogram::T) where {T}
        new{T}(
            WriterReaderPhaser(),
            histogram,
            !(histogram isa Union{AtomicHistogram,ConcurrentHistogram,SynchronizedHistogram}),
            ReentrantLock(),
        )
    end
end

function record_value!(r::IntervalRecorder, value::Int64, count::Int64=1)
    r.serialize_writers && lock(r.writer_lock)
    val = writer_critical_section_enter(r.phaser)
    try
        record_value!((@atomic r.active), value, count)
    finally
        writer_critical_section_exit(r.phaser, val)
        r.serialize_writers && unlock(r.writer_lock)
    end
end

function record_corrected_value!(r::IntervalRecorder, value::Int64, expected_interval::Int64, count::Int64=1)
    r.serialize_writers && lock(r.writer_lock)
    val = writer_critical_section_enter(r.phaser)
    try
        record_corrected_value!((@atomic r.active), value, expected_interval, count)
    finally
        writer_critical_section_exit(r.phaser, val)
        r.serialize_writers && unlock(r.writer_lock)
    end
end

function record_values!(r::IntervalRecorder, values)
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

Base.push!(r::IntervalRecorder, value::Integer) = (record_value!(r, Int64(value)); r)
Base.append!(r::IntervalRecorder, values) = record_values!(r, values)

@inline record_value!(r::IntervalRecorder, value::Integer, count::Integer=1) =
    record_value!(r, Int64(value), Int64(count))
@inline record_corrected_value!(r::IntervalRecorder, value::Integer,
    expected_interval::Integer, count::Integer=1) =
    record_corrected_value!(r, Int64(value), Int64(expected_interval), Int64(count))

function interval_histogram(r::IntervalRecorder)
    reader_lock(r.phaser)
    try
        active = @atomic r.active
        inactive = @atomicswap r.active = similar(active)
        flip_phase(r.phaser)
        return inactive
    finally
        reader_unlock(r.phaser)
    end
end

function interval_histogram(r::IntervalRecorder{T}, inactive::T) where {T<:AbstractHistogram}
    reset!(inactive)

    reader_lock(r.phaser)
    try
        inactive = @atomicswap r.active = inactive
        flip_phase(r.phaser)
        return inactive
    finally
        reader_unlock(r.phaser)
    end
end
