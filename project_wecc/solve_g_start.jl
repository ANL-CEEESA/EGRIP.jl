# load registered package
using Plots
using JuMP
gr()
Plots.GRBackend()

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
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup/"
t_final = 300
t_step = 10
gap = 0.1
nstage = t_final/t_step;
stages = 1:nstage;

# solve the problem
ref, model = solve_startup(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

# calculate total load
Pd_bus = []
for d in keys(ref[:load])
    push!(Pd_bus, ref[:load][d]["pd"])
end
Pd_total = sum(Pd_bus)

# calculate total generation
Pg_bus = []
for g in keys(ref[:gen])
    push!(Pg_bus, ref[:gen][g]["pg"])
end
Pg_total = sum(Pg_bus)

# retrieve results
Pg_step = []
for t in stages
    push!(Pg_step, value(model[:pg_total][t]))
end
Pd_step = []
for t in stages
    push!(Pd_step, value(model[:pd_total][t]))
end

# plot
plot(t_step:t_step:t_final, (Pg_step)*100, w=2)
xaxis!("Time (Min)")
yaxis!("Total generation capacity (MW)")

plot(t_step:t_step:t_final, (Pd_step)*100, w=2)
xaxis!("Time (Min)")
yaxis!("Total load (MW)")

plot(t_step:t_step:t_final, (Pg_step - Pd_step)*100, w=2)
xaxis!("Time (Min)")
yaxis!("Net generation capacity (MW)")



# # -------------- Command line --------------
# dir_case_network = ARGS[1]
# dir_case_blackstart = ARGS[2]
# dir_case_result = ARGS[3]
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])
# gap = parse(Float64, ARGS[6])
# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step, gap)