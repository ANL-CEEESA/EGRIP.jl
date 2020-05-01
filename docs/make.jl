cd(@__DIR__)
push!(LOAD_PATH,"../src/")

using Documenter, EGRIP

makedocs(
    modules = [EGRIP],
    # format = Documenter.HTML(analytics = "UA-367975-10", mathengine = Documenter.MathJax(), prettyurls = false),
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true", mathengine = Documenter.MathJax(),analytics = "UA-367975-10"),
    sitename = "EGRIP.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting Started" => "quickguide.md",
            "Problem Formulations" => "formulations.md"
        ],
        "Library" => [
        "Public Library" =>"library_public.md"
        "Internal Library" =>"library_internal.md"
        ],
        "Developer" =>[
        "Development Notes"=>"development_notes.md",
        "Code Loading"=>"dev_code_loading.md",
        "Package Organization"=>"dev_package_org.md"
        ],
        "Research" =>[
        "Literature Review"=>"literature.md",
        "Benchmark Testing"=>"benchmark.md",
        ]
    ]
)

# deploydocs(
#     repo = "github.com/lanl-ansi/PowerModels.jl.git",
# )
