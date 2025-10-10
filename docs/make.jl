using Documenter
using JobSchedulers

makedocs(
    sitename = "JobSchedulers.jl",
    authors = "Dr. Jiacheng Chuan, and contributors.",
    pages = [
        "Home" => "index.md",
        "Manual" => "manual.md",
        "Use Cases" => "use_cases.md",
        "Best Practice" => "best_practice.md",
        "Overhead Benchmark" => "overhead.md",
        "API" => "API.md",
        "Change Log" => "changelog.md"
    ],
    format = Documenter.HTML(
        sidebar_sitename=false,
        assets = ["assets/favicon.ico"]
    )
)

if haskey(ENV, "GITHUB_TOKEN")
    deploydocs(
        repo = "github.com/cihga39871/JobSchedulers.jl.git",
        devbranch = "main"
    )
end