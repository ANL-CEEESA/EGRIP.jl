cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using PowerModels

# # ------------ solve refined restoration: Northern part--------------
dir_case_network = "WECC_dataset/WECC_noHVDC.raw"
network_data_format = "psse"
dir_case_blackstart = "WECC_dataset/WECC_generator_specs.csv"
dir_gen_plan = "results/Interpol_y.csv"
dir_case_result = "results_re/"
t_final = 300
t_step = 20
gap = 0.2
solve_refined_restoration(dir_case_network, network_data_format, dir_case_blackstart, dir_gen_plan, dir_case_result, t_final, t_step, gap)