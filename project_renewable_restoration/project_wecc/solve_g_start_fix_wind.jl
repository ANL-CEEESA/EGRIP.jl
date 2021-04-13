# load registered package
using JuMP

function get_value(model, stages)
    Pg_seq = []
    for t in stages
        push!(Pg_seq, value(model[:pg_total][t]))
    end

    Pd_seq = []
    for t in stages
        push!(Pd_seq, value(model[:pd_total][t]))
    end

    Pw_seq = []
    for t in stages
        try
            push!(Pw_seq, value(model[:pw][t]))
        catch e
            push!(Pw_seq, 0)
        end
    end

    return Pg_seq, Pd_seq, Pw_seq
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
push!(LOAD_PATH,"/Users/yichenzhang/GitHub/EGRIP.jl/src/")
using EGRIP

# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# # ------------ Interactive --------------
dir_case_network = "WECC_dataset/WECC_noHVDC.raw"
dir_case_blackstart = "WECC_dataset/WECC_generator_specs.csv"
network_data_format = "psse"
dir_case_result = "results_startup/"
t_final = 300
t_step = 10
gap = 0.01
nstage = t_final/t_step;
stages = 1:nstage;

# solve the problem
test_from = 1
test_end = 5
# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Wind", "Wind: Prob 0.05",
                            "Wind: Prob 0.10",
                            "Wind: Prob 0.15",
                            "Wind: Prob 0.20"]

model = Dict()
ref = Dict()
pw_sp = Dict()
wind = Dict()
wind[1] = Dict("activation"=>0)
wind[2] = Dict("activation"=>1, "sample_number"=>500, "violation_probability"=>0.05, "mean"=>10, "var"=>5) # power is in MVA base
wind[3] = Dict("activation"=>1, "sample_number"=>500, "violation_probability"=>0.1, "mean"=>10, "var"=>5)
wind[4] = Dict("activation"=>1, "sample_number"=>500, "violation_probability"=>0.15, "mean"=>10, "var"=>5)
wind[5] = Dict("activation"=>1, "sample_number"=>500, "violation_probability"=>0.2, "mean"=>10, "var"=>5)
# # run optimization
# for i in test_from:test_end
#     ref[i], model[i], pw_sp[i] = solve_startup(dir_case_network, network_data_format,
#                                 dir_case_blackstart, dir_case_result,
#                                 t_final, t_step, gap, wind[i])
# end

# # --------- retrieve results ---------
# Pg_seq = Dict()
# Pd_seq = Dict()
# Pw_seq = Dict()
# for i in test_from:test_end
#     Pg_seq[i], Pd_seq[i], Pw_seq[i] = get_value(model[i], stages)
# end

# # ----------- read non-black-start generator that are cranked by wind at the first step ---------
# using CSV
# using DataFrames
# black_start_seq = CSV.read("results_startup/res_ys.csv", DataFrame)
# gen_start_idx = findall(x->x==1, black_start_seq[:,3])
# gen_start_id = black_start_seq[gen_start_idx, 2]
# gen_bs_id = [12, 34, 39, 76, 78, 147]
# gen_nbs_start_id = setdiff(Set(gen_start_id),Set(gen_bs_id))
# print(sort!(collect(gen_nbs_start_id)))

# --------------load case data---------------
using JSON
Pg_seq = Dict()
Pd_seq = Dict()
Pw_seq = Dict()
Pg_seq = JSON.parsefile("results_startup/data_gen_startup_wecc_fix_wind_gen.json")
Pg_seq = JSON.parse(Pg_seq)
Pg_seq = Dict([parse(Int,string(key)) => val for (key, val) in pairs(Pg_seq)])
Pd_seq = JSON.parsefile("results_startup/data_gen_startup_wecc_fix_wind_load.json")
Pd_seq = JSON.parse(Pd_seq)
Pd_seq = Dict([parse(Int,string(key)) => val for (key, val) in pairs(Pd_seq)])
Pw_seq = JSON.parsefile("results_startup/data_gen_startup_wecc_fix_wind_wind.json")
Pw_seq = JSON.parse(Pw_seq)
Pw_seq = Dict([parse(Int,string(key)) => val for (key, val) in pairs(Pw_seq)])

# # ------------------- plot -----------------------
# # calculate the violation integer numbers
# vol_num = []
# for i in 1:wind[2]["sample_number"]
#     push!(vol_num,value(model[2][:w][i]))
# end

# plot
using PyPlot
# If true, return Python-based GUI; otherwise, return Julia backend
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_wecc_fix_wind_gen.png")
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_wecc_fix_wind_load.png")
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_wecc_fix_wind_cap.png")
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_wecc_fix_wind_wind_dispatch.png")
PyPlot.savefig(sav_dict)


# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in 1:wind[2]["sample_number"]
#     ax.plot(t_step:t_step:t_final, (pw_sp[2][i])*100)
# end
# ax.set_title("Wind Sampled", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_wecc_fix_wind_wind_sample.png")
# PyPlot.savefig(sav_dict)


# save data into json
using JSON
json_string = JSON.json(Pw_seq)
open("results_startup/data_gen_startup_wecc_fix_wind_wind.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pg_seq)
open("results_startup/data_gen_startup_wecc_fix_wind_gen.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pd_seq)
open("results_startup/data_gen_startup_wecc_fix_wind_load.json","w") do f
  JSON.print(f, json_string)
end
