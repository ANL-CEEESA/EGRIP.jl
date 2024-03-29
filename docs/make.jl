cd(@__DIR__)
push!(LOAD_PATH,"../src/")

using Documenter, EGRIP

# prettyurls = get(ENV, "CI", nothing) == "true",

makedocs(
    modules = [EGRIP],
    format = Documenter.HTML(edit_link = "master", mathengine = Documenter.MathJax()),
    sitename = "EGRIP.jl",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Installation" => "ch1_sec1_install.md",
            "Tutorials" => "ch1_sec2_tutorials.md",
            "Mathematical Model" => "ch1_sec3_formulations.md",
            "Advanced Algorithms" => "ch1_sec4_advanced_algorithm.md",

        ],
        "Library" => [
        "Public Library" =>"ch2_sec1_library_public.md"
        "Internal Library" =>"ch2_sec2_library_internal.md"
        ]
    ]
)

deploydocs(repo = "github.com/ANL-CEEESA/EGRIP.jl.git",
           )