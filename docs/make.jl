using Documenter
using JobSchedulers

makedocs(
    sitename="JobSchedulers.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => "manual.md",
        "Use Cases" => "use_cases.md",
        "Best Practice" => "best_practice.md",
        "Overhead Benchmark" => "overhead.md",
        "API" => "API.md",
        "Change Log" => "changelog.md"
    ]
)

deploydocs(
    repo = "github.com/cihga39871/JobSchedulers.jl.git",
    devbranch = "main"
)
