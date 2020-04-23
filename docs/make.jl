cd(@__DIR__)
push!(LOAD_PATH,"../src/")

using Documenter, EGRIP

makedocs(
    modules = [EGRIP],
    format = Documenter.HTML(analytics = "UA-367975-10", mathengine = Documenter.MathJax()),
    sitename = "EGRIP.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting Started" => "quickguide.md",
            "Problem Formulations" => "formulations.md"
        ],
        "Library" => "library.md"
    ]
)

# deploydocs(
#     repo = "github.com/lanl-ansi/PowerModels.jl.git",
# )
