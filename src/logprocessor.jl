mutable struct LazyHistogramReader
    payload::String
    used::Bool
end

function Base.read(reader::LazyHistogramReader)
    reader.used && throw(ArgumentError("histogram payload already read"))
    reader.used = true
    compressed = base64decode(reader.payload)
    return decode_from_compressed_byte_buffer(compressed, 0)
end

mutable struct HistogramLogScanner{I<:IO}
    io::I
    start_time_sec::Float64
    base_time_sec::Float64
    observed_start_time::Bool
    observed_base_time::Bool
    function HistogramLogScanner(io::I) where {I<:IO}
        new{I}(io, 0.0, 0.0, false, false)
    end
end

start_time_sec(scanner::HistogramLogScanner) = scanner.start_time_sec
base_time_sec(scanner::HistogramLogScanner) = scanner.base_time_sec

function _next_line!(scanner::HistogramLogScanner)
    eof(scanner.io) && return nothing
    return readline(scanner.io)
end

function _scan_comment_times!(scanner::HistogramLogScanner, line::AbstractString)
    if startswith(line, "#[StartTime:")
        m = match(r"#\[StartTime:\s*([0-9eE.+-]+)", line)
        if m !== nothing
            scanner.start_time_sec = parse(Float64, m.captures[1])
            scanner.observed_start_time = true
        end
        return :start
    elseif startswith(line, "#[BaseTime:")
        m = match(r"#\[BaseTime:\s*([0-9eE.+-]+)", line)
        if m !== nothing
            scanner.base_time_sec = parse(Float64, m.captures[1])
            scanner.observed_base_time = true
        end
        return :base
    end
    return :comment
end

function process!(scanner::HistogramLogScanner;
    on_comment::Function=(line)->false,
    on_start_time::Function=(t)->false,
    on_base_time::Function=(t)->false,
    on_histogram::Function=(tag, timestamp, length, reader)->false,
    on_exception::Function=(err)->false)
    while true
        line = _next_line!(scanner)
        line === nothing && return
        line = strip(line)
        isempty(line) && continue
        try
            if startswith(line, "#")
                kind = _scan_comment_times!(scanner, line)
                if kind === :start
                    on_start_time(scanner.start_time_sec) && return
                elseif kind === :base
                    on_base_time(scanner.base_time_sec) && return
                else
                    on_comment(line) && return
                end
                continue
            end

            parsed = parse_interval_line(line)
            parsed === nothing && continue
            tag_value, timestamp_sec, length_sec, payload = parsed

            if !scanner.observed_start_time
                scanner.start_time_sec = timestamp_sec
                scanner.observed_start_time = true
            end
            if !scanner.observed_base_time
                if timestamp_sec < scanner.start_time_sec - (365 * 24 * 3600.0)
                    scanner.base_time_sec = scanner.start_time_sec
                else
                    scanner.base_time_sec = 0.0
                end
                scanner.observed_base_time = true
            end

            lazy_reader = LazyHistogramReader(payload, false)
            on_histogram(tag_value, timestamp_sec, length_sec, lazy_reader) && return
        catch err
            on_exception(err) && return
        end
    end
end

mutable struct HistogramLogProcessor{S<:HistogramLogScanner}
    scanner::S
    tag::Union{Nothing,String}
    range_start_sec::Float64
    range_end_sec::Float64
    absolute::Bool
    expected_interval::Float64
    output_value_unit_ratio::Float64
    percentiles_output_ticks_per_half::Int
end

HistogramLogProcessor(io::IO; tag=nothing, range_start_sec=0.0, range_end_sec=Inf, absolute=false,
    expected_interval=0.0, output_value_unit_ratio=1_000_000.0, percentiles_output_ticks_per_half=5) =
    HistogramLogProcessor(HistogramLogScanner(io), tag, range_start_sec, range_end_sec, absolute,
        expected_interval, output_value_unit_ratio, percentiles_output_ticks_per_half)

function _write_interval_header(io::IO, csv::Bool)
    if csv
        println(io, "\"StartTimestamp\",\"Interval_Length\",\"TotalCount\",\"Mean\",\"99%'ile\",\"Max\"")
    else
        println(io, "StartTimestamp Interval_Length TotalCount Mean 99%'ile Max")
    end
end

function _write_interval_summary(io::IO, histogram::AbstractHistogram, start_sec::Float64, length_sec::Float64,
    value_unit_ratio::Float64, csv::Bool)
    mean_value = mean(histogram) / value_unit_ratio
    max_value = max(histogram) / value_unit_ratio
    p99_value = value_at_percentile(histogram, 99.0) / value_unit_ratio
    total = total_count(histogram)
    if csv
        @printf(io, "%.3f,%.3f,%d,%.3f,%.3f,%.3f\n", start_sec, length_sec, total, mean_value, p99_value, max_value)
    else
        @printf(io, "%.3f %.3f %d %.3f %.3f %.3f\n", start_sec, length_sec, total, mean_value, p99_value, max_value)
    end
end

function process!(processor::HistogramLogProcessor;
    interval_io::Union{Nothing,IO}=nothing,
    percentiles_io::Union{Nothing,IO}=stdout,
    csv::Bool=false,
    list_tags::Bool=false,
    all_tags::Bool=false)
    tags = Set{Union{Nothing,String}}()
    accumulated = nothing
    wrote_interval_header = false

    process!(processor.scanner,
        on_histogram = (tag_value, timestamp_sec, length_sec, lazy_reader) -> begin
            push!(tags, tag_value)
            if list_tags
                return false
            end
            if !all_tags
                if processor.tag === nothing
                    tag_value === nothing || return false
                else
                    tag_value == processor.tag || return false
                end
            elseif processor.tag !== nothing
                tag_value == processor.tag || return false
            end

            absolute_start_sec = timestamp_sec + base_time_sec(processor.scanner)
            offset_start_sec = absolute_start_sec - start_time_sec(processor.scanner)
            absolute_end_sec = absolute_start_sec + length_sec
            start_to_check = processor.absolute ? absolute_start_sec : offset_start_sec

            if start_to_check < processor.range_start_sec
                return false
            end
            if start_to_check > processor.range_end_sec
                return true
            end

            histogram = read(lazy_reader)
            if processor.expected_interval > 0
                corrected = similar(histogram)
                add_while_correcting_for_coordinated_omission(corrected, histogram, Int64(processor.expected_interval))
                histogram = corrected
            end
            if accumulated === nothing
                accumulated = similar(histogram)
            end
            add(accumulated, histogram)

            if interval_io !== nothing
                if !wrote_interval_header
                    _write_interval_header(interval_io, csv)
                    wrote_interval_header = true
                end
                output_start = processor.absolute ? absolute_start_sec : offset_start_sec
                _write_interval_summary(interval_io, histogram, output_start, length_sec,
                    processor.output_value_unit_ratio, csv)
            end
            return false
        end)

    if list_tags
        return nothing, tags
    end

    if percentiles_io !== nothing && accumulated !== nothing
        percentile_print(percentiles_io, accumulated, processor.percentiles_output_ticks_per_half,
            processor.output_value_unit_ratio)
    end
    return accumulated, tags
end
