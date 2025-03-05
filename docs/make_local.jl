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
        "Use Cases" => "use_cases.md",
        "Overhead Benchmark" => "overhead.md",
        "Best Practice (Please Read)" => "best_practice.md",
        "API" => "API.md",
        "Change Log" => "changelog.md"
    ]
)
