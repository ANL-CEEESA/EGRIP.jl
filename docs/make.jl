using Documenter, EGRIP

makedocs(
    modules = [EGRIP],
    format = Documenter.HTML(analytics = "UA-367975-10", mathengine = Documenter.MathJax()),
    sitename = "EGRIP Documentation",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting Started" => "quickguide.md",
            "Problem Formulations" => "formulations.md",
             "Mathematical Model" => "math-model.md",
        ]
    ]
)

# deploydocs(
#     repo = "github.com/lanl-ansi/PowerModels.jl.git",
# )
