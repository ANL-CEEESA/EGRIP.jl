# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JSON
using CSV
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# ------------ load manually sectionalized data from JSON --------------
# load data for restoration
network_section = Dict()
network_section = JSON.parsefile("WECC_dataset/network_section.json")
# load network data
ref = load_network("WECC_BaseCase.raw", "psse")

# # ------------ Interactive --------------
dir_case_network = string("WECC_dataset/sec_N.json")
dir_case_blackstart = "WECC_dataset/WECC_Bus_gen.csv"
network_data_format = "json"
dir_case_result = "results_sec_N/"
t_final = 300
t_step = 50
gap = 0.25
solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)


# dir_case_network = string("WECC_dataset/sec_S.json")
# dir_case_blackstart = "WECC_dataset/WECC_Bus_gen.csv"
# network_data_format = "json"
# dir_case_result = "results_sec_S/"
# t_final = 300
# t_step = 15
# gap = 0.25
# solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

# # -------------- Command line --------------
# dir_case_network = ARGS[1]
# dir_case_blackstart = ARGS[2]
# dir_case_result = ARGS[3]
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])
# gap = parse(Float64, ARGS[6])
# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
