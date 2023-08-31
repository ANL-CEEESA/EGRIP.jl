cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using PowerModels
using DataFrames
# # ------------ solve refined restoration: Northern part--------------
dir_case_network = "IEEE39_raw.raw"
dir_case_blackstart = "IEEE39_generator_specs_1.csv"
network_data_format = "psse"
t_final = 500  # we need at least five steps to model the entire process
t_step = 50
nstage = t_final/t_step;
stages = 1:nstage;
gap = 0.01
dir_gen_plan = "results/Interpol_ys.csv"
dir_case_result = "results_re/"
solve_refined_restoration(dir_case_network, network_data_format, dir_case_blackstart, dir_gen_plan, dir_case_result, t_final, t_step, gap)
