using Base64

const HISTOGRAM_LOG_FORMAT_VERSION = "1.3"

mutable struct HistogramLogWriter{I<:IO}
    io::I
    base_time_msec::Int64
    encoding_workspace::EncodingWorkspace
    base64_pipe::Base64EncodePipe
    function HistogramLogWriter(io::I) where {I<:IO}
        new{I}(io, 0, EncodingWorkspace(), Base64EncodePipe(io))
    end
end

function output_start_time(writer::HistogramLogWriter, start_time_msec::Int64)
    @printf(writer.io, "#[StartTime: %.3f (seconds since epoch)]\n", start_time_msec / 1000.0)
end

function output_base_time(writer::HistogramLogWriter, base_time_msec::Int64)
    @printf(writer.io, "#[BaseTime: %.3f (seconds since epoch)]\n", base_time_msec / 1000.0)
end

function output_comment(writer::HistogramLogWriter, comment::AbstractString)
    @printf(writer.io, "#%s\n", comment)
end

function output_legend(writer::HistogramLogWriter)
    println(writer.io, "\"StartTimestamp\",\"Interval_Length\",\"Interval_Max\",\"Interval_Compressed_Histogram\"")
end

function output_log_format_version(writer::HistogramLogWriter)
    output_comment(writer, "[Histogram log format version $(HISTOGRAM_LOG_FORMAT_VERSION)]")
end

function set_base_time!(writer::HistogramLogWriter, base_time_msec::Int64)
    writer.base_time_msec = base_time_msec
end

base_time(writer::HistogramLogWriter) = writer.base_time_msec

function output_interval_histogram(writer::HistogramLogWriter,
    start_time_sec::Float64,
    end_time_sec::Float64,
    histogram::AbstractHistogram,
    max_value_unit_ratio::Float64=1_000_000.0)
    compressed = encode_into_compressed_byte_buffer!(writer.encoding_workspace, histogram)
    tag_value = tag(histogram)
    max_value = max_value_as_double(histogram) / max_value_unit_ratio
    if tag_value === nothing
        @printf(writer.io, "%.3f,%.3f,%.3f,",
            start_time_sec,
            end_time_sec - start_time_sec,
            max_value)
    else
        occursin(r"[,\s]", tag_value) &&
            throw(ArgumentError("Tag string cannot contain commas, spaces, or line breaks"))
        @printf(writer.io, "Tag=%s,%.3f,%.3f,%.3f,",
            tag_value,
            start_time_sec,
            end_time_sec - start_time_sec,
            max_value)
    end
    write(writer.base64_pipe, compressed)
    close(writer.base64_pipe)
    write(writer.io, '\n')
end

function output_interval_histogram(writer::HistogramLogWriter, histogram::AbstractHistogram)
    output_interval_histogram(writer,
        (start_time_stamp(histogram) - writer.base_time_msec) / 1000.0,
        (end_time_stamp(histogram) - writer.base_time_msec) / 1000.0,
        histogram)
end

mutable struct HistogramLogReader{I<:IO}
    io::I
    start_time_sec::Float64
    base_time_sec::Float64
    observed_start_time::Bool
    observed_base_time::Bool
    function HistogramLogReader(io::I) where {I<:IO}
        new{I}(io, 0.0, 0.0, false, false)
    end
end

start_time_sec(reader::HistogramLogReader) = reader.start_time_sec

function next_line!(reader::HistogramLogReader)
    eof(reader.io) && return nothing
    return readline(reader.io)
end

function parse_comment_times!(reader::HistogramLogReader, line::AbstractString)
    if startswith(line, "#[StartTime:")
        m = match(r"#\[StartTime:\s*([0-9eE.+-]+)", line)
        if m !== nothing
            reader.start_time_sec = parse(Float64, m.captures[1])
            reader.observed_start_time = true
        end
        return true
    elseif startswith(line, "#[BaseTime:")
        m = match(r"#\[BaseTime:\s*([0-9eE.+-]+)", line)
        if m !== nothing
            reader.base_time_sec = parse(Float64, m.captures[1])
            reader.observed_base_time = true
        end
        return true
    end
    return false
end

function parse_interval_line(line::AbstractString)
    line = strip(line)
    isempty(line) && return nothing
    startswith(line, "#") && return nothing
    startswith(line, "\"StartTimestamp\"") && return nothing
    startswith(line, "StartTimestamp") && return nothing
    startswith(line, "Timestamp") && return nothing

    tag_value = nothing
    if startswith(line, "Tag=")
        comma = findfirst(',', line)
        comma === nothing && return nothing
        tag_value = line[5:comma-1]
        line = line[comma+1:end]
    end

    fields = split(line, [',', ' '], keepempty=false)
    length(fields) < 4 && return nothing
    start_sec = parse(Float64, fields[1])
    length_sec = parse(Float64, fields[2])
    _ = fields[3] # interval max is informational
    payload = fields[4]
    return tag_value, start_sec, length_sec, payload
end

function next_interval_histogram(reader::HistogramLogReader;
    range_start_sec::Float64=-Inf,
    range_end_sec::Float64=Inf,
    absolute::Bool=false)
    while true
        line = next_line!(reader)
        line === nothing && return nothing
        line = strip(line)
        isempty(line) && continue
        startswith(line, "#") && (parse_comment_times!(reader, line); continue)

        parsed = parse_interval_line(line)
        parsed === nothing && continue
        tag_value, timestamp_sec, length_sec, payload = parsed

        if !reader.observed_start_time
            reader.start_time_sec = timestamp_sec
            reader.observed_start_time = true
        end
        if !reader.observed_base_time
            if timestamp_sec < reader.start_time_sec - (365 * 24 * 3600.0)
                reader.base_time_sec = reader.start_time_sec
            else
                reader.base_time_sec = 0.0
            end
            reader.observed_base_time = true
        end

        absolute_start_sec = timestamp_sec + reader.base_time_sec
        offset_start_sec = absolute_start_sec - reader.start_time_sec
        absolute_end_sec = absolute_start_sec + length_sec
        start_to_check = absolute ? absolute_start_sec : offset_start_sec

        if start_to_check < range_start_sec
            continue
        end
        if start_to_check > range_end_sec
            return nothing
        end

        compressed = base64decode(payload)
        histogram = decode_from_compressed_byte_buffer(compressed, 0)
        start_time_stamp!(histogram, trunc(Int64, absolute_start_sec * 1000.0))
        end_time_stamp!(histogram, trunc(Int64, absolute_end_sec * 1000.0))
        tag!(histogram, tag_value)
        return histogram
    end
end
