# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP

# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# # ------------ Interactive --------------
dir_case_network = "/Users/whoiszyc/Github/EGRIP.jl/src/cases/ieee_39bus/case39.m"
dir_case_blackstart = "/Users/whoiszyc/Github/EGRIP.jl/src/cases/ieee_39bus/BS_generator.csv"
dir_case_result = "/Users/whoiszyc/Github/EGRIP.jl/src/cases/ieee_39bus/results/"
t_final = 500
t_step = 250

solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step)


# -------------- Command line --------------
# Arguments
# dir_case_network = parse(String, ARGS[1])
# dir_case_blackstart = parse(String, ARGS[2])
# dir_case_result = parse(String, ARGS[3])
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])

# println(dir_case_network)
# println(dir_case_blackstart)
# println(dir_case_result)
# println(t_final)
# println(t_step)

# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step)
