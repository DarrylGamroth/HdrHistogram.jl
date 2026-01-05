using CodecZlib

const ENCODING_HEADER_SIZE = 40
const V0_ENCODING_HEADER_SIZE = 32

const V0_ENCODING_COOKIE_BASE = 0x1c849308
const V0_COMPRESSED_ENCODING_COOKIE_BASE = 0x1c849309

const V1_ENCODING_COOKIE_BASE = 0x1c849301
const V1_COMPRESSED_ENCODING_COOKIE_BASE = 0x1c849302

const V2_ENCODING_COOKIE_BASE = 0x1c849303
const V2_COMPRESSED_ENCODING_COOKIE_BASE = 0x1c849304

const V2_MAX_WORD_SIZE_IN_BYTES = 9

const ENCODING_COOKIE_BASE = V2_ENCODING_COOKIE_BASE
const COMPRESSED_ENCODING_COOKIE_BASE = V2_COMPRESSED_ENCODING_COOKIE_BASE

mutable struct BufferWriter
    data::Vector{UInt8}
    pos::Int
end

BufferWriter(capacity::Int) = BufferWriter(Vector{UInt8}(undef, capacity), 1)

@inline function write_u8!(w::BufferWriter, v::UInt8)
    w.data[w.pos] = v
    w.pos += 1
end

@inline function write_be_i32!(w::BufferWriter, v::Int32)
    write_u8!(w, UInt8((v >> 24) & 0xff))
    write_u8!(w, UInt8((v >> 16) & 0xff))
    write_u8!(w, UInt8((v >> 8) & 0xff))
    write_u8!(w, UInt8(v & 0xff))
end

@inline function write_be_i64!(w::BufferWriter, v::Int64)
    write_u8!(w, UInt8((v >> 56) & 0xff))
    write_u8!(w, UInt8((v >> 48) & 0xff))
    write_u8!(w, UInt8((v >> 40) & 0xff))
    write_u8!(w, UInt8((v >> 32) & 0xff))
    write_u8!(w, UInt8((v >> 24) & 0xff))
    write_u8!(w, UInt8((v >> 16) & 0xff))
    write_u8!(w, UInt8((v >> 8) & 0xff))
    write_u8!(w, UInt8(v & 0xff))
end

@inline function write_be_f64!(w::BufferWriter, v::Float64)
    write_be_i64!(w, reinterpret(Int64, v))
end

@inline function write_at_be_i32!(w::BufferWriter, pos::Int, v::Int32)
    w.data[pos] = UInt8((v >> 24) & 0xff)
    w.data[pos + 1] = UInt8((v >> 16) & 0xff)
    w.data[pos + 2] = UInt8((v >> 8) & 0xff)
    w.data[pos + 3] = UInt8(v & 0xff)
end

mutable struct BufferReader
    data::Vector{UInt8}
    pos::Int
end

BufferReader(data::Vector{UInt8}) = BufferReader(data, 1)

@inline function read_u8!(r::BufferReader)
    v = r.data[r.pos]
    r.pos += 1
    return v
end

@inline function read_be_i32!(r::BufferReader)
    b1 = read_u8!(r)
    b2 = read_u8!(r)
    b3 = read_u8!(r)
    b4 = read_u8!(r)
    return Int32((UInt32(b1) << 24) | (UInt32(b2) << 16) | (UInt32(b3) << 8) | UInt32(b4))
end

@inline function read_be_i16!(r::BufferReader)
    b1 = read_u8!(r)
    b2 = read_u8!(r)
    return Int16((UInt16(b1) << 8) | UInt16(b2))
end

@inline function read_be_i64!(r::BufferReader)
    b1 = read_u8!(r)
    b2 = read_u8!(r)
    b3 = read_u8!(r)
    b4 = read_u8!(r)
    b5 = read_u8!(r)
    b6 = read_u8!(r)
    b7 = read_u8!(r)
    b8 = read_u8!(r)
    return Int64((UInt64(b1) << 56) | (UInt64(b2) << 48) | (UInt64(b3) << 40) | (UInt64(b4) << 32) |
                 (UInt64(b5) << 24) | (UInt64(b6) << 16) | (UInt64(b7) << 8) | UInt64(b8))
end

@inline function read_be_f64!(r::BufferReader)
    return reinterpret(Float64, read_be_i64!(r))
end

@inline function encoding_cookie()
    return Int32(ENCODING_COOKIE_BASE | 0x10)
end

@inline function compressed_encoding_cookie()
    return Int32(COMPRESSED_ENCODING_COOKIE_BASE | 0x10)
end

@inline function cookie_base(cookie::Int32)
    return Int32(UInt32(cookie) & UInt32(0xffffff0f))
end

@inline function word_size_in_bytes_from_cookie(cookie::Int32)
    base = cookie_base(cookie)
    if base == V2_ENCODING_COOKIE_BASE || base == V2_COMPRESSED_ENCODING_COOKIE_BASE
        return V2_MAX_WORD_SIZE_IN_BYTES
    end
    size_byte = (UInt32(cookie) & UInt32(0xf0)) >> 4
    return Int(Int32(size_byte & UInt32(0x0e)))
end

@inline function zigzag_put_long!(w::BufferWriter, value::Int64)
    v = (value << 1) ⊻ (value >> 63)
    if (UInt64(v) >>> 7) == 0
        write_u8!(w, UInt8(v))
        return
    end
    write_u8!(w, UInt8((v & 0x7f) | 0x80))
    if (UInt64(v) >>> 14) == 0
        write_u8!(w, UInt8(v >>> 7))
        return
    end
    write_u8!(w, UInt8((v >>> 7) | 0x80))
    if (UInt64(v) >>> 21) == 0
        write_u8!(w, UInt8(v >>> 14))
        return
    end
    write_u8!(w, UInt8((v >>> 14) | 0x80))
    if (UInt64(v) >>> 28) == 0
        write_u8!(w, UInt8(v >>> 21))
        return
    end
    write_u8!(w, UInt8((v >>> 21) | 0x80))
    if (UInt64(v) >>> 35) == 0
        write_u8!(w, UInt8(v >>> 28))
        return
    end
    write_u8!(w, UInt8((v >>> 28) | 0x80))
    if (UInt64(v) >>> 42) == 0
        write_u8!(w, UInt8(v >>> 35))
        return
    end
    write_u8!(w, UInt8((v >>> 35) | 0x80))
    if (UInt64(v) >>> 49) == 0
        write_u8!(w, UInt8(v >>> 42))
        return
    end
    write_u8!(w, UInt8((v >>> 42) | 0x80))
    if (UInt64(v) >>> 56) == 0
        write_u8!(w, UInt8(v >>> 49))
        return
    end
    write_u8!(w, UInt8((v >>> 49) | 0x80))
    write_u8!(w, UInt8(v >>> 56))
end

@inline function zigzag_get_long!(r::BufferReader)
    v = Int64(read_u8!(r))
    value = v & 0x7f
    if (v & 0x80) != 0
        v = Int64(read_u8!(r))
        value |= (v & 0x7f) << 7
        if (v & 0x80) != 0
            v = Int64(read_u8!(r))
            value |= (v & 0x7f) << 14
            if (v & 0x80) != 0
                v = Int64(read_u8!(r))
                value |= (v & 0x7f) << 21
                if (v & 0x80) != 0
                    v = Int64(read_u8!(r))
                    value |= (v & 0x7f) << 28
                    if (v & 0x80) != 0
                        v = Int64(read_u8!(r))
                        value |= (v & 0x7f) << 35
                        if (v & 0x80) != 0
                            v = Int64(read_u8!(r))
                            value |= (v & 0x7f) << 42
                            if (v & 0x80) != 0
                                v = Int64(read_u8!(r))
                                value |= (v & 0x7f) << 49
                                if (v & 0x80) != 0
                                    v = Int64(read_u8!(r))
                                    value |= v << 56
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return (value >>> 1) ⊻ (-(value & 1))
end

function get_needed_payload_byte_buffer_capacity(relevant_length::Int)
    return relevant_length * V2_MAX_WORD_SIZE_IN_BYTES
end

function get_needed_byte_buffer_capacity(relevant_length::Int)
    return get_needed_payload_byte_buffer_capacity(relevant_length) + ENCODING_HEADER_SIZE
end

function get_needed_byte_buffer_capacity(h::AbstractHistogram)
    return get_needed_byte_buffer_capacity(counts_length(h))
end

function encode_into_byte_buffer(h::AbstractHistogram)
    relevant_length = counts_index_for(h, max_value(h)) + 1
    capacity = get_needed_byte_buffer_capacity(relevant_length)
    buf = BufferWriter(capacity)
    bytes_written = encode_into_byte_buffer!(buf, h, relevant_length)
    return buf.data[1:bytes_written]
end

function encode_into_compressed_byte_buffer(h::AbstractHistogram; compression_level::Integer=CodecZlib.Z_DEFAULT_COMPRESSION)
    uncompressed = encode_into_byte_buffer(h)
    compressed = transcode(CodecZlib.ZlibCompressor(level=Int(compression_level)), uncompressed)
    writer = BufferWriter(8 + length(compressed))
    write_be_i32!(writer, compressed_encoding_cookie())
    write_be_i32!(writer, Int32(length(compressed)))
    for b in compressed
        write_u8!(writer, b)
    end
    return writer.data[1:writer.pos-1]
end

function encode_into_byte_buffer!(w::BufferWriter, h::AbstractHistogram, relevant_length::Int)
    initial_pos = w.pos
    write_be_i32!(w, encoding_cookie())
    payload_len_pos = w.pos
    write_be_i32!(w, Int32(0))
    write_be_i32!(w, Int32(normalizing_index_offset(h)))
    write_be_i32!(w, Int32(significant_figures(h)))
    write_be_i64!(w, lowest_discernible_value(h))
    write_be_i64!(w, highest_trackable_value(h))
    write_be_f64!(w, conversion_ratio(h))

    payload_start = w.pos
    fill_buffer_from_counts_array!(w, h, relevant_length)
    payload_len = w.pos - payload_start
    write_at_be_i32!(w, payload_len_pos, Int32(payload_len))
    return w.pos - initial_pos
end

function fill_buffer_from_counts_array!(w::BufferWriter, h::AbstractHistogram, counts_limit::Int)
    src_index = 0
    while src_index < counts_limit
        count = count_at_index(h, src_index)
        count >= 0 || error("Cannot encode histogram containing negative counts ($count) at index $src_index")
        src_index += 1
        zeros_count = 0
        if count == 0
            zeros_count = 1
            while src_index < counts_limit && count_at_index(h, src_index) == 0
                zeros_count += 1
                src_index += 1
            end
        end
        if zeros_count > 1
            zigzag_put_long!(w, -zeros_count)
        else
            zigzag_put_long!(w, count)
        end
    end
end

function decode_from_byte_buffer(data::Vector{UInt8}, min_bar_for_highest_trackable_value::Int64=0)
    reader = BufferReader(data)
    cookie = read_be_i32!(reader)
    base = cookie_base(cookie)

    if base != ENCODING_COOKIE_BASE && base != V1_ENCODING_COOKIE_BASE && base != V0_ENCODING_COOKIE_BASE
        throw(ArgumentError("The buffer does not contain a Histogram (no valid cookie found)"))
    end

    payload_length = 0
    normalizing_offset = Int32(0)
    sigfigs = Int32(0)
    lowest = Int64(0)
    highest = Int64(0)
    conversion_ratio = 1.0

    if base == V0_ENCODING_COOKIE_BASE
        sigfigs = read_be_i32!(reader)
        lowest = read_be_i64!(reader)
        highest = read_be_i64!(reader)
        _ = read_be_i64!(reader)
        payload_length = typemax(Int32)
        conversion_ratio = 1.0
        normalizing_offset = 0
    else
        payload_length = Int(read_be_i32!(reader))
        normalizing_offset = read_be_i32!(reader)
        sigfigs = read_be_i32!(reader)
        lowest = read_be_i64!(reader)
        highest = read_be_i64!(reader)
        conversion_ratio = read_be_f64!(reader)
    end

    highest = max(highest, min_bar_for_highest_trackable_value)
    histogram = _init_with_config(Histogram{Int64}, lowest, highest, Int64(sigfigs), true,
        conversion_ratio, Int64(normalizing_offset))

    word_size = word_size_in_bytes_from_cookie(cookie)
    payload_end = min(reader.pos + payload_length, length(data) + 1)
    fill_counts_array_from_source_buffer!(histogram, reader, payload_end, word_size)
    reset_internal_counters!(histogram)
    return histogram
end

function decode_from_compressed_byte_buffer(data::Vector{UInt8}, min_bar_for_highest_trackable_value::Int64=0)
    reader = BufferReader(data)
    cookie = read_be_i32!(reader)
    base = cookie_base(cookie)
    if base != COMPRESSED_ENCODING_COOKIE_BASE && base != V1_COMPRESSED_ENCODING_COOKIE_BASE &&
       base != V0_COMPRESSED_ENCODING_COOKIE_BASE
        throw(ArgumentError("The buffer does not contain a compressed Histogram"))
    end
    compressed_length = Int(read_be_i32!(reader))
    start_pos = reader.pos
    end_pos = start_pos + compressed_length - 1
    end_pos > length(data) && throw(ArgumentError("The buffer does not contain the indicated payload amount"))
    compressed = data[start_pos:end_pos]
    uncompressed = transcode(CodecZlib.ZlibDecompressor(), compressed)
    return decode_from_byte_buffer(uncompressed, min_bar_for_highest_trackable_value)
end

function fill_counts_array_from_source_buffer!(h::AbstractHistogram, r::BufferReader, end_pos::Int, word_size::Int)
    (word_size == 2 || word_size == 4 || word_size == 8 || word_size == V2_MAX_WORD_SIZE_IN_BYTES) ||
        throw(ArgumentError("word size must be 2, 4, 8, or $V2_MAX_WORD_SIZE_IN_BYTES"))
    dst_index = 0
    while r.pos < end_pos
        count = Int64(0)
        zeros_count = 0
        if word_size == V2_MAX_WORD_SIZE_IN_BYTES
            count = zigzag_get_long!(r)
            if count < 0
                zc = -count
                zc > typemax(Int32) && throw(ArgumentError("An encoded zero count of > Int32 max was encountered"))
                zeros_count = Int(zc)
            end
        else
            if word_size == 2
                count = Int64(read_be_i16!(r))
            elseif word_size == 4
                count = Int64(read_be_i32!(r))
            else
                count = read_be_i64!(r)
            end
        end
        if zeros_count > 0
            dst_index += zeros_count
        else
            counts_set_direct!(h, dst_index, count)
            dst_index += 1
        end
    end
end
