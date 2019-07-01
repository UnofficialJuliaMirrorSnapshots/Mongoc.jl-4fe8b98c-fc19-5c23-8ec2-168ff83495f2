
# API Reference

## BSON

```@docs
Mongoc.BSON
Mongoc.BSONObjectId
Mongoc.BSONCode
Mongoc.as_json
Mongoc.as_dict
Mongoc.read_bson
Mongoc.write_bson
Mongoc.read_next_bson
Mongoc.BSONError
Mongoc.BSONValue
Mongoc.get_as_bson_value
```

## Client

```@docs
Mongoc.Client
Mongoc.set_appname!
Mongoc.ping
Mongoc.get_server_mongodb_version
Mongoc.find_databases
Mongoc.get_database_names
Mongoc.has_database
```

## ClientPool

```@docs
Mongoc.ClientPool
Mongoc.set_max_size
```

## Database

```@docs
Mongoc.command_simple
Mongoc.add_user
Mongoc.remove_user
Mongoc.has_user
Mongoc.find_collections
Mongoc.get_collection_names
Mongoc.read_command
Mongoc.write_command
```

## Collection

```@docs
Mongoc.find
Mongoc.find_one
Mongoc.count_documents
Mongoc.drop
Mongoc.find_and_modify
Mongoc.FindAndModifyFlags
```

## Aggregation

```@docs
Mongoc.aggregate
Mongoc.QueryFlags
```

## Session

```@docs
Mongoc.transaction
```

## GridFS

```@docs
Mongoc.MongoStreamFile
Mongoc.upload
Mongoc.download
Mongoc.delete
Mongoc.open_download_stream
Mongoc.open_upload_stream
Mongoc.abort_upload
```
