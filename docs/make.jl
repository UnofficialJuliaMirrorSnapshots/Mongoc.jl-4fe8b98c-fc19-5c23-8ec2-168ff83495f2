
using Documenter, Mongoc

makedocs(
    sitename = "Mongoc.jl",
    modules = [ Mongoc ],
    pages = [ "Home" => "index.md",
              "Tutorial" => "tutorial.md",
              "CRUD Operations" => "crud.md",
              "Authentication" => "authentication.md",
              "Transactions" => "transaction.md",
              "Connection Pool" => "connection_pool.md",
              "GridFS" => "gridfs.md",
              "API Reference" => "api.md" ]
)

deploydocs(
    repo = "github.com/felipenoris/Mongoc.jl.git",
    target = "build",
)
