# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JuMP

# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# # ------------ Interactive --------------
dir_case_network = "IEEE39_raw.raw"
dir_case_blackstart = "IEEE39_generator_specs_1.csv"
network_data_format = "psse"
dir_case_result = "results/"
t_final = 500  # we need at least five steps to model the entire process
t_step = 50
nstage = t_final/t_step;
stages = 1:nstage;
gap = 0.01
ref, model = solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)


# # ---------------- calculate restoration gaps ---------------------
total_load = sum(ref[:load][i]["pd"] for i in keys(ref[:load])) * ref[:baseMVA]
println("Total load: ", total_load)

restored_load = sum(value(model[:pl][d, end]) * ref[:baseMVA] for d in keys(ref[:load]))
println("Restored load: ", restored_load)

restored_energy = sum(sum(value(model[:pl][d, t]) * ref[:baseMVA] for d in keys(ref[:load])) for t in stages)
println("Restored energy: ", restored_energy)
