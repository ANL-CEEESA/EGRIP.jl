# load registered package
using JuMP
using JSON
using CSV
using JuMP
using DataFrames

# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.
# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"/Users/yichenzhang/GitHub/EGRIP.jl/src/")
using EGRIP
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# local functions
include("utils.jl")

# # ------------ Interactive --------------
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup/"
t_final = 300
t_step = 10
gap = 0.0
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
 
# load real wind power data
# note that we ignore the ERCOT wind data in the version control for security
# Each time we may need to add the data folder manually
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
wind = Dict()
wind[1] = Dict("activation"=>0, "violation_probability"=>0.00)
wind[2] = Dict("activation"=>2, "violation_probability"=>0.05)
wind[3] = Dict("activation"=>2, "violation_probability"=>0.1)
wind[4] = Dict("activation"=>2, "violation_probability"=>0.15)
wind[5] = Dict("activation"=>2, "violation_probability"=>0.2)
wind_activation = [0, 2, 2, 2, 2]
violation_probability = [0, 0.05, 0.10, 0.15, 0.20]
for i in test_from:test_end
ref, model[i] = solve_startup(dir_case_network, network_data_format,
                                dir_case_blackstart, dir_case_result,
                                t_final, t_step, gap, wind[i], wind_data)
end


# --------- retrieve results ---------
Pg_seq = Dict()
Pd_seq = Dict()
Pw_seq = Dict()
for i in test_from:test_end
    Pg_seq[i], Pd_seq[i], Pw_seq[i] = get_value(model[i], stages)
end

# plot
using PyPlot
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Generator Capacity", fontdict=Dict("fontsize"=>20))
ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_real_data_gen.png")
PyPlot.savefig(sav_dict)


PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12,5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>20))
ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_real_data_load.png")
PyPlot.savefig(sav_dict)

PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i] - Pd_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("System Capacity", fontdict=Dict("fontsize"=>20))
ax.legend(loc="upper left", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_real_data_cap.png")
PyPlot.savefig(sav_dict)

PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pw_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Wind Dispatch", fontdict=Dict("fontsize"=>20))
ax.legend(loc="upper right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_real_data_wind_dispatch.png")
PyPlot.savefig(sav_dict)


# save data into json
using JSON
json_string = JSON.json(Pw_seq)
open("results_startup/data_gen_startup_real_data_wind.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pg_seq)
open("results_startup/data_gen_startup_real_data_gen.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pd_seq)
open("results_startup/data_gen_startup_real_data_load.json","w") do f
  JSON.print(f, json_string)
end
