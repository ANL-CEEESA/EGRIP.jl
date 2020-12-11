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

# # ------------ solve refined restoration: Northern part--------------
dir_case_network = "WECC_dataset/WECC_noHVDC.raw"
network_data_format = "psse"
dir_case_blackstart = "WECC_dataset/WECC_generator_specs.csv"
dir_gen_plan = "results_startup/Interpol_ys.csv"
dir_case_result = "results_startup_re/"
t_final = 300
t_step = 10
gap = 0.2
solve_refined_restoration(dir_case_network, network_data_format, dir_case_blackstart, dir_gen_plan, dir_case_result, t_final, t_step, gap)

# # ------------ solve refined restoration: Southern part--------------
# dir_case_network = string("WECC_dataset/sec_S.json")
# dir_case_blackstart = "WECC_dataset/WECC_Bus_gen.csv"
# network_data_format = "json"
# dir_case_result = "results_sec_S/"
# dir_gen_plan = ""
# t_final = 300
# t_step = 50
# gap = 0.25
# solve_refined_restoration(dir_case_network, network_data_format, dir_case_blackstart, dir_gen_plan, dir_case_result, t_final, t_step, gap)
