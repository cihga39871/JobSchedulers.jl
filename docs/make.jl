#!julia --color=yes
push!(LOAD_PATH,"../src/")

using Documenter, JobSchedulers

makedocs(
    sitename="JobSchedulers.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "command_program.md",
            "julia_program.md",
            "command_dependency.md",
        ],
        "API.md"
    ]
)

deploydocs(
    repo = "github.com/cihga39871/JobSchedulers.jl.git",
    devbranch = "main"
)
