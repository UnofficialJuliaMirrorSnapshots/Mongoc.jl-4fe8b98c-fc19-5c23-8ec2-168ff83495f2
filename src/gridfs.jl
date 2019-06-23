
"""
    upload(bucket::Bucket, filename::AbstractString, source::AbstractMongoStream;
        options::Union{Nothing, BSON}=nothing,
        file_id=BSONObjectId())

Uploads data from `source` to a GridFS file `filename`.

`bson_file_id` is a BSON document with a `_id` field.
If `_id` field is not present, a `BSONObjectId` will be generated.
"""
function upload(bucket::Bucket, filename::AbstractString, source::AbstractMongoStream;
        file_id=BSONObjectId(),
        chunk_size::Union{Nothing, Integer}=nothing,
        metadata::Union{Nothing, BSON}=nothing)

    # Julia does not support C unions.
    # libmongoc represents bson_value_t as a C union.
    # To make things work, here we construct a BSON document
    # and set the id. Later, we retrieve a bson_value_t
    # using get_as_bson_value, which uses bson_iter_value.
    # new_bson_with_id returns a tuple with the BSON doc
    # along with the id to ensure that the lifetime of the BSON
    # doc exceeds the lifetime of the bson_value_t
    # that we'll pass to mongoc_gridfs_bucket_upload_from_stream_with_id.

    function new_bson_with_id(id)
        doc = BSON("_id" => id)
        return doc, get_as_bson_value(doc, "_id")
    end
    doc, file_id_as_bson_value = new_bson_with_id(file_id)

    function new_bson_upload_opts(chunk_size::Union{Nothing, Integer}, metadata::Union{Nothing, BSON}) :: Union{Nothing, BSON}
        if chunk_size == nothing && metadata == nothing
            return nothing
        else
            result = BSON()

            if chunk_size != nothing
                result["chunkSizeBytes"] = Int32(chunk_size)
            end

            if metadata != nothing
                result["metadata"] = metadata
            end

            return result
        end
    end
    options = new_bson_upload_opts(chunk_size, metadata)
    options_handle = options == nothing ? C_NULL : options.handle

    err_ref = Ref{BSONError}()

    ok = mongoc_gridfs_bucket_upload_from_stream_with_id(
            bucket.handle,
            file_id_as_bson_value.handle,
            filename,
            source.handle,
            options_handle,
            err_ref
        )

    if !ok
        throw(err_ref[])
    end

    nothing
end

"""
    upload(bucket::Bucket, remote_filename::AbstractString, local_source_filepath::AbstractString;
        options::Union{Nothing, BSON}=nothing,
        file_id=BSONObjectId())

High-level interface to upload a local file to a GridFS bucket.
"""
function upload(bucket::Bucket, remote_filename::AbstractString, local_source_filepath::AbstractString;
        file_id=BSONObjectId(),
        chunk_size::Union{Nothing, Integer}=nothing,
        metadata::Union{Nothing, BSON}=nothing)

    @assert isfile(local_source_filepath) "Couldn't find $local_source_filepath."
    source_stream = MongoStreamFile(local_source_filepath)

    try
        upload(bucket, remote_filename, source_stream,
            file_id=file_id, chunk_size=chunk_size, metadata=metadata)
    finally
        close(source_stream)
    end
end

"""
    download(bucket::Bucket, file_id::BSONValue, target::AbstractMongoStream)

Download a GridFS file identified by `file_id` to `target` stream.
"""
function download(bucket::Bucket, file_id::BSONValue, target::AbstractMongoStream)
    err_ref = Ref{BSONError}()
    ok = mongoc_gridfs_bucket_download_to_stream(
            bucket.handle, file_id.handle, target.handle, err_ref
        )

    if !ok
        throw(err_ref[])
    end
    nothing
end

function download(bucket::Bucket, file_info::BSON, target::AbstractMongoStream)
    @assert haskey(file_info, "_id")
    download(bucket, get_as_bson_value(file_info, "_id"), target)
end

function find_file_info(bucket::Bucket, filename::AbstractString) :: BSON
    bson_filter = BSON()
    bson_filter["filename"] = String(filename)

    local found::Bool=false
    local result::BSON

    for doc in find(bucket, bson_filter)
        @assert !found "More than 1 file was found with name $filename."
        found = true

        result = doc
    end
    @assert found "Coudln't find file with name $filename."

    return result
end

"""
    download(bucket::Bucket, filename::AbstractString, target::AbstractMongoStream)

Download a GridFS file named `filename` to `target` stream.
"""
function download(bucket::Bucket, filename::AbstractString, target::AbstractMongoStream)
    file_info = find_file_info(bucket, filename)
    download(bucket, file_info, target)
end

"""
    download(bucket::Bucket, remote_filename::AbstractString, local_filepath::AbstractString;
        flags::Integer=(Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_RDWR), mode::Integer=0o600

Downloads a GridFS file named `remote_filename` to `local_filepath`.
"""
function download(bucket::Bucket, remote_filename::AbstractString, local_filepath::AbstractString;
        flags::Integer=(Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_RDWR), mode::Integer=0o600)

    download_file_stream = Mongoc.MongoStreamFile(local_filepath, flags=(Base.Filesystem.JL_O_CREAT | Base.Filesystem.JL_O_RDWR), mode=0o600)

    try
        Mongoc.download(bucket, remote_filename, download_file_stream)
    finally
        Mongoc.close(download_file_stream)
    end
end

"""
    find(bucket::Bucket, bson_filter::BSON=BSON();
        options::BSON=BSON()) :: Cursor

Looks for files in GridFS bucket.
"""
function find(bucket::Bucket, bson_filter::BSON=BSON();
        options::BSON=BSON()) :: Cursor

    cursor_handle = mongoc_gridfs_bucket_find(bucket.handle, bson_filter.handle, options.handle)

    if cursor_handle == C_NULL
        error("Couldn't execute query.")
    end
    return Cursor(bucket, cursor_handle)
end

"""
    delete(bucket::Bucket, file_id)
    delete(bucket::Bucket, file_metadata::BSON)

Deletes a file from a GridFS Bucket.
"""
function delete(bucket::Bucket, file_id::BSONValue)
    err_ref = Ref{BSONError}()
    ok = mongoc_gridfs_bucket_delete_by_id(bucket.handle, file_id.handle, err_ref)
    if !ok
        throw(err_ref[])
    end
    nothing
end

function delete(bucket::Bucket, file_metadata::BSON)
    oid_as_bson_value = get_as_bson_value(file_metadata, "_id")
    delete(bucket, oid_as_bson_value)
end

function delete(bucket::Bucket, file_id)
    file_metadata = BSON("_id" => file_id)
    delete(bucket, file_metadata)
end

function Base.empty!(bucket::Bucket)
    for doc in find(bucket)
        delete(bucket, doc)
    end
end

function Base.isempty(bucket::Bucket)
    for _ in find(bucket)
        return false
    end
    return true
end

function open_download_stream(bucket::Bucket, file_id::BSONValue;
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    err_ref = Ref{BSONError}()
    stream_handle = mongoc_gridfs_bucket_open_download_stream(bucket.handle, file_id.handle, err_ref)
    if stream_handle == C_NULL
        throw(err_ref[])
    end
    return MongoIOStream(bucket, stream_handle; timeout_msec=timeout_msec, chunk_size=chunk_size)
end

function open_download_stream(bucket::Bucket, filename::AbstractString) :: MongoIOStream
    local result::MongoIOStream
    file_info = find_file_info(bucket, filename)
    return open_download_stream(bucket, file_info)
end

function open_download_stream(bucket::Bucket, file_info::BSON;
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    @assert haskey(file_info, "_id")
    return open_download_stream(bucket, get_as_bson_value(file_info, "_id"),
                timeout_msec=timeout_msec,
                chunk_size=chunk_size)
end

"""
    open_download_stream(f, bucket, filename)
    open_download_stream(bucket, filename) :: MongoIOStream

Opens a stream for reading a remote file identified by `filename`.

# Example

```julia
Mongoc.open_download_stream(bucket, remote_filename) do io
    @test isopen(io)
    tmp_str = read(io, String)
    @test original_str == tmp_str
end
```
"""
function open_download_stream(f::Function, bucket::Bucket, file::Union{BSONValue, AbstractString})
    stream = open_download_stream(bucket, file)
    try
        f(stream)
    finally
        close(stream)
    end
end

function open_upload_stream(bucket::Bucket, file_id::BSONValue, filename::AbstractString;
        options::Union{Nothing, BSON}=nothing,
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    err_ref = Ref{BSONError}()
    options_handle = options == nothing ? C_NULL : options.handle

    stream_handle = mongoc_gridfs_bucket_open_upload_stream_with_id(
            bucket.handle, file_id.handle, filename, options_handle,
            err_ref)

    if stream_handle == C_NULL
        throw(err_ref[])
    end

    return MongoIOStream(
            bucket,
            stream_handle,
            timeout_msec=timeout_msec,
            chunk_size=chunk_size
        )
end

function open_upload_stream(bucket::Bucket, file_info::BSON;
        options::Union{Nothing, BSON}=nothing,
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    @assert haskey(file_info, "filename") "`file_info` must have a `filename` field."

    # generates a new _id if not present in `file_info`
    if !haskey(file_info, "_id")
        file_info["_id"] = BSONObjectId()
    end

    return open_upload_stream(
            bucket, get_as_bson_value(file_info, "_id"), file_info["filename"],
            options=options, timeout_msec=timeout_msec, chunk_size=chunk_size
        )
end

"""
    open_upload_stream(bucket, file_id, filename; [options], [timeout_msec], [chunk_size]) :: MongoIOStream
    open_upload_stream(bucket, filename; [options], [timeout_msec], [chunk_size]) :: MongoIOStream
    open_upload_stream(bucket, file_info; [options], [timeout_msec], [chunk_size]) :: MongoIOStream

Opens a stream to upload a file to a GridFS Bucket.

`file_info` is a BSON document with the following fields:

* `_id` as an optional identifier.

* `filename` as the name of the file in the remote bucket.

If `_id` is not provided, a `BSONObjectId` will be generated.

# Example

```julia
data = rand(UInt8, 3_000_000)
remote_filename = "uploaded.data"
io = Mongoc.open_upload_stream(bucket, remote_filename)
write(io, data)
close(io)
```
"""
function open_upload_stream(bucket::Bucket, file_id, filename::AbstractString;
        options::Union{Nothing, BSON}=nothing,
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    file_info = BSON("_id" => file_id, "filename" => filename)
    return open_upload_stream(bucket, file_info,
            options=options, timeout_msec=timeout_msec, chunk_size=chunk_size)
end

function open_upload_stream(bucket::Bucket, filename::AbstractString;
        options::Union{Nothing, BSON}=nothing,
        timeout_msec::Integer=DEFAULT_TIMEOUT_MSEC,
        chunk_size::Integer=DEFAULT_CHUNK_SIZE) :: MongoIOStream

    file_info = BSON("filename" => filename)
    return open_upload_stream(bucket, file_info,
            options=options, timeout_msec=timeout_msec, chunk_size=chunk_size)
end
