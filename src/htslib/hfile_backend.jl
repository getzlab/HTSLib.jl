
# Implement a hFILE backend using arbitrary julia IO type

struct hFILE_julia
    base::hFILE_base
    ioptr::Ptr{Cvoid}
end

function _restore_hfile_io(fp)
    fp = convert(Ptr{hFILE_julia}, fp)
    unsafe_pointer_to_objref(unsafe_load(fp).ioptr)
end

function _debug_io(msg)
    # @async println(msg)
end

# As per read(2), returning the number of bytes read (possibly 0) or
# negative (and setting errno) on errors.  Front-end code will call this
# repeatedly if necessary to attempt to get the desired byte count.
function hfile_backend_read(fp, buffer, nbytes)
    _hfile_backend_read(_restore_hfile_io(fp), buffer, nbytes)
end
function _hfile_backend_read(io::IO, buffer::Ptr{Cvoid}, nbytes::Csize_t)::Cssize_t
    ## TODO: handle error, set errno and return negative value
    # TranscodingStreams.unsafe_read is different from Base.unsafe_read
    bytes_written = TranscodingStreams.unsafe_read(io, convert(Ptr{UInt8}, buffer), convert(Int, nbytes))
    _debug_io("hfile: read $bytes_written ($nbytes requested)")
    return bytes_written
end
# As per write(2), returning the number of bytes written or negative (and
# setting errno) on errors.  Front-end code will call this repeatedly if
# necessary until the desired block is written or an error occurs.
function hfile_backend_write(fp, buffer, nbytes)
    _hfile_backend_write(_restore_hfile_io(fp), buffer, nbytes)
end
function _hfile_backend_write(io::IO, buffer::Ptr{Cvoid}, nbytes::Csize_t)::Cssize_t
    ## TODO: handle error, set errno and return negative value
    bytes_written = unsafe_write(io, buffer, nbytes)
    _debug_io("hfile: write $bytes_written ($nbytes requested)")
    return bytes_written
end

# As per lseek(2), returning the resulting offset within the stream or
# negative (and setting errno) on errors.
function hfile_backend_seek(fp, offset, whence)
    ans = _hfile_backend_seek(_restore_hfile_io(fp), offset, whence)
    _debug_io("hfile: seek offset $offset with result $ans (whence $whence)")
    return ans
end
function _hfile_backend_seek(io::IO, offset::Coff_t, whence::Cint)::Coff_t
    SEEK_SET = Cint(0)
    SEEK_CUR = Cint(1)
    SEEK_END = Cint(2)
    origin::Coff_t = typemin(Coff_t)
    if whence == SEEK_SET
        origin = 0
    elseif whence == SEEK_CUR
        if !Core.applicable(position, io)
            Base.Libc.errno(Base.Libc.ESPIPE)
            return -1
        end
        origin = position(io)
    elseif whence == SEEK_END
        if !Core.applicable(seekend, io)
            Base.Libc.errno(Base.Libc.ESPIPE)
            return -1
        end
        # trick to get end position
        seekend(io)
        origin = position(io)
    else
        println("invalid whence argument: $whence")
        Base.Libc.errno(Base.Libc.EINVAL)
        return -1
    end
    realoffset = origin + offset

    if !Core.applicable(seek, io, realoffset)
        Base.Libc.errno(Base.Libc.ESPIPE)
        return -1
    end

    seek(io, realoffset)
    return realoffset
end

# Performs low-level flushing, if any, e.g., fsync(2); for writing streams
# only.  Returns 0 for success or negative (and sets errno) on errors.
function hfile_backend_flush(fp)
    _debug_io("hfile: flush")
    _hfile_backend_flush(_restore_hfile_io(fp))
end
function _hfile_backend_flush(io::IO)::Cint
    flush(io)
    return 0
end

# Closes the underlying stream (for output streams, the buffer will
# already have been flushed), returning 0 for success or negative (and
# setting errno) on errors, as per close(2).
function hfile_backend_close(fp)
    _debug_io("hfile: close")
    _hfile_backend_close(_restore_hfile_io(fp))
end
function _hfile_backend_close(io::IO)::Cint
    # if the io object didn't implement close, we shouldn't worry about it
    if !Core.applicable(close, io)
        return 0
    end
    close(io)
    return 0
end

function hfile_julia_backend()
    read_f  = @cfunction(hfile_backend_read,  Cssize_t, (Ptr{hFILE}, Ptr{Cvoid}, Csize_t))
    write_f = @cfunction(hfile_backend_write, Cssize_t, (Ptr{hFILE}, Ptr{Cvoid}, Csize_t))
    seek_f  = @cfunction(hfile_backend_seek,  Coff_t,   (Ptr{hFILE}, Coff_t, Cint))
    flush_f = @cfunction(hfile_backend_flush, Cint,     (Ptr{hFILE}, ))
    close_f = @cfunction(hfile_backend_close, Cint,     (Ptr{hFILE}, ))
    hFILE_backend(read_f, write_f, seek_f, flush_f, close_f)
end
