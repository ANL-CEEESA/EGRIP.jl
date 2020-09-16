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
            "Installation" => "ch1_sec1_install.md",
            "Problem Formulations" => "ch1_sec2_formulations.md",
            "Advanced Algorithms" => "ch1_sec3_advanced_algorithm.md",
            "Restoration Workflow" => "ch1_sec4_workflow.md"
        ],
        "Library" => [
        "Public Library" =>"ch2_sec1_library_public.md"
        "Internal Library" =>"ch2_sec2_library_internal.md"
        ],
        "Developer" =>[
        "Development Overview"=>"ch3_sec1_development_overview.md",
        "Code Loading"=>"ch3_sec2_dev_code_loading.md",
        "Package Organization"=>"ch3_sec3_dev_package_org.md"
        ]
    ]
)

# deploydocs(
#     repo = "github.com/lanl-ansi/PowerModels.jl.git",
# )
