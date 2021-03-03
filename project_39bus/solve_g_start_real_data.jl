# load registered package

function get_value(model, stages)
    Pg_seq = []
    for t in stages
        push!(Pg_seq, value(model[:pg_total][t]))
    end

    Pd_seq = []
    for t in stages
        push!(Pd_seq, value(model[:pd_total][t]))
    end

    return Pg_seq, Pd_seq

end

function check_load(ref)
    for k in keys(ref[:load])
        if ref[:load][k]["pd"] <= 0
            println("Load bus: ", ref[:load][k]["load_bus"], ", active power: ", ref[:load][k]["pd"])
        end
    end
end

# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# # ------------ Interactive --------------
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup/"
t_final = 500
t_step = 10
gap = 0.1
nstage = Int64(t_final/t_step)
stages = 1:nstage


# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Renewable", "W Renewable: Prob 0.05",
                            "W Renewable: Prob 0.10",
                            "W Renewable: Prob 0.15",
                            "W Renewable: Prob 0.20"]
fig_name = "fig_gen_startup_real_data.png"

# load real wind power data
wind_data = CSV.read("../ERCOT_wind/wind_power.csv", DataFrame)
pw_sp = Dict()
n_stages = length(stages)
n_wind_data = size(wind_data, 1)
sample_index = 1:n_stages:n_wind_data
n_sample = length(sample_index)
for s in 1:n_sample-1
    pw_sp[s] = wind_data[sample_index[s]:sample_index[s+1]-1, 1]
end


# solve the problem
test_from = 1
test_end = 5
model = Dict()
wind_activation = [0, 2, 2, 2, 2]
violation_probability = [0, 0.05, 0.10, 0.15, 0.50]
for i in test_from:test_end
ref, model[i] = solve_startup(dir_case_network, network_data_format,
                                dir_case_blackstart, dir_case_result,
                                t_final, t_step, gap, wind_activation[i], wind_data, violation_probability[i])
end

# # --------------- Validation functions -----------------
# # calculate total load
# Pd_bus = []
# for d in keys(ref[:load])
#     push!(Pd_bus, ref[:load][d]["pd"])
# end
# Pd_total = sum(Pd_bus)
#
# # calculate total generation
# Pg_bus = []
# for g in keys(ref[:gen])
#     push!(Pg_bus, ref[:gen][g]["pg"])
# end
# Pg_total = sum(Pg_bus)
#
# check load
# check_load(ref)


# --------- retrieve results ---------
Pg_seq = Dict()
Pd_seq = Dict()
for i in test_from:test_end
    Pg_seq[i], Pd_seq[i] = get_value(model[i], stages)
end

# plot
using PyPlot

# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(8, 5))
# ax.plot(t_step:t_step:t_final, (Pg_step_1)*100,  "b*-", linewidth=2, markersize=4, label="Generation")
# ax.plot(t_step:t_step:t_final, (Pd_step_1)*100,  "rs-.", linewidth=2, markersize=4, label="Load")
# ax.legend(loc="upper left", fontsize=16)
# ax.set_title("Generation and Load Trajectories", fontdict=Dict("fontsize"=>16))
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
# ax.xaxis.set_tick_params(labelsize=16)
# ax.yaxis.set_tick_params(labelsize=16)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_1.png")
# PyPlot.savefig(sav_dict)


PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(8, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>16))
ax.legend(loc="lower right", fontsize=10)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>16))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>16))
ax.xaxis.set_tick_params(labelsize=16)
ax.yaxis.set_tick_params(labelsize=16)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, fig_name)
PyPlot.savefig(sav_dict)

# # -------------- Command line --------------
# dir_case_network = ARGS[1]
# dir_case_blackstart = ARGS[2]
# dir_case_result = ARGS[3]
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])
# gap = parse(Float64, ARGS[6])
# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
