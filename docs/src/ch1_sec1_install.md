# Installation

For now since `EGRIP.jl` has not been registered, we need to load the package locally by putting the following code at the beginning
of your test script:
```julia
cd(@__DIR__)
push!(LOAD_PATH,"../src/")
```
