# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JuMP
using PowerModels
using Random
using DataStructures
using JSON
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# -------------------- optimization setting -----------------
dir_case_network = "IEEE39_raw.raw"
dir_case_blackstart = "IEEE39_generator_specs_1.csv"
network_data_format = "psse"
dir_case_result = "results/"
t_final = 500  # we need at least five steps to model the entire process
t_step = 50
nstage = t_final/t_step;
stages = 1:nstage;
gap = 0.01

# load system data to sample branch damages
data0 = PowerModels.parse_file(dir_case_network)
ref = PowerModels.build_ref(data0)[:nw][0]

# -------------------------prepare for random line damages---------------------
gen_bus = [30,31,32,33,34,35,36,37,38,39]
disturbance_pool = []

for br in keys(ref[:buspairs])
    if issubset(br[1],gen_bus) || issubset(br[2],gen_bus)
        println(br)
    else
        push!(disturbance_pool, br)
    end
end

num_dis = 5

# starting the main sampling loop
num_sample = 100
samples = OrderedDict()
for s in 1:num_sample
    samples[s] = Dict()
    shuffle!(disturbance_pool)
    samples[s]["branch_damage"] = disturbance_pool[1:num_dis]

    # solve the restoration
    ref, model, bus_energization = solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap, disturbance_pool[1:num_dis])

    restored_load_t = []
    for t in stages
        load_t = sum(value(model[:pl][d, t]) * ref[:baseMVA] for d in keys(ref[:load]))
        push!(restored_load_t, load_t)
    end
    
    samples[s]["node_energization_sequence"] = bus_energization
    samples[s]["restored_load"] = restored_load_t
end

# save data
open("samples.json","w") do f
    JSON.print(f, samples)
end
