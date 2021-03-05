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
gap = 0.0
nstage = t_final/t_step;
stages = 1:nstage;

# solve the problem
test_from = 1
test_end = 5
# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["W/O Wind", "Wind: Sample 1000, Prob 0.05",
                            "Wind: Sample 1000, Prob 0.10",
                            "Wind: Sample 1000, Prob 0.15",
                            "Wind: Sample 1000, Prob 0.20"]


model = Dict()
ref = Dict()
pw_sp = Dict()
wind = Dict()
wind[1] = Dict("activation"=>0)
wind[2] = Dict("activation"=>1, "sample_number"=>1000, "violation_probability"=>0.05, "mean"=>0.4, "var"=>0.2) # power is in MVA base
wind[3] = Dict("activation"=>1, "sample_number"=>1000, "violation_probability"=>0.1, "mean"=>0.4, "var"=>0.2)
wind[4] = Dict("activation"=>1, "sample_number"=>1000, "violation_probability"=>0.15, "mean"=>0.4, "var"=>0.2)
wind[5] = Dict("activation"=>1, "sample_number"=>1000, "violation_probability"=>0.2, "mean"=>0.4, "var"=>0.2)
for i in test_from:test_end
    ref[i], model[i], pw_sp[i] = solve_startup(dir_case_network, network_data_format,
                                dir_case_blackstart, dir_case_result,
                                t_final, t_step, gap, wind[i])
end

# --------- retrieve results ---------
Pg_seq = Dict()
Pd_seq = Dict()
Pw_seq = Dict()
for i in test_from:test_end
    Pg_seq[i], Pd_seq[i], Pw_seq[i] = get_value(model[i], stages)
end

# calculate the violation integer numbers
vol_num = []
for i in 1:wind[2]["sample_number"]
    push!(vol_num,value(model[2][:w][i]))
end

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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_gen.png")
PyPlot.savefig(sav_dict)


PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12,5)))
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_load.png")
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_cap.png")
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_wind_dispatch.png")
PyPlot.savefig(sav_dict)


PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in 1:wind[2]["sample_number"]
    ax.plot(t_step:t_step:t_final, (pw_sp[2][i])*100)
end
ax.set_title("Wind Sampled", fontdict=Dict("fontsize"=>20))
ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_sample_wind_sample.png")
PyPlot.savefig(sav_dict)


# save data into json
using JSON
json_string = JSON.json(Pw_seq)
open("results_startup/data_gen_startup_fix_sample_wind.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pg_seq)
open("results_startup/data_gen_startup_fix_sample_gen.json","w") do f
  JSON.print(f, json_string)
end
json_string = JSON.json(Pd_seq)
open("results_startup/data_gen_startup_fix_sample_load.json","w") do f
  JSON.print(f, json_string)
end
