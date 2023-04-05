#!julia --color=yes
push!(LOAD_PATH,"../src/")

using Documenter

include("../src/JobSchedulers.jl")
using .JobSchedulers

makedocs(
    sitename="JobSchedulers.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => "manual.md",
        "API" => "API.md",
        "Change Log" => "changelog.md"
    ]
)
