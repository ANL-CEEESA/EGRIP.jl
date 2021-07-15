
# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../../src/")
using EGRIP
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# registered packages
using JuMP
using JSON
using CSV
using JuMP
using DataFrames
using Interpolations
using Distributions

# local functions
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup_density/"
t_final = 400
t_step = 10
gap = 0.0
nstage = Int64(t_final/t_step)
stages = 1:nstage

# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["SAA 1", "SAA 40%"]

# ------------------- obtain approximated density function (histogram) from historical data-------------
# load real wind power data
# note that we ignore the ERCOT wind data in the version control for security
# Each time we may need to add the data folder manually
wind_data = CSV.read("../../ERCOT_wind/wind_farm3_POE.csv", DataFrame)
wind_data = convert(Matrix, wind_data)
prob = 1.0:-0.1:0.1
# construct estimated density function
wind_density = Dict()
for i in 1:size(wind_data)[1]
    wind_density[i] = density_est_from_risk(wind_data[i,:], 1.0:-0.1:0.1, 1000)
end

# # ----------------- Solve the problem -------------------
test_from = 2
test_end = 2
formulation_type = 2
saa_mode_option = [1, 2]
model = Dict()
wind = Dict()
pw_sp = Dict()
wind[1] = Dict("activation"=>3, "violation_probability"=>0.40, "sample_number"=>10, "seed"=>1)
wind[2] = Dict("activation"=>3, "violation_probability"=>0.40, "sample_number"=>10, "seed"=>1)
# here we use keyword arguments
for i in test_from:test_end
ref, model[i], pw_sp[i] = solve_startup(dir_case_network, network_data_format,
                                dir_case_blackstart, dir_case_result,
                                t_final, t_step, gap, formulation_type, wind[i], wind_density; saa_mode=saa_mode_option[i])
end

# --------- retrieve results and plotting ---------
Pg_seq = Dict()
Pd_seq = Dict()
Pw_seq = Dict()
w_seq = Dict()
yg_seq = Dict()
zd_seq = Dict()
Pl_all_load = Dict()
for i in test_from:test_end
    Pg_seq[i] = get_value(model[i][:pg_total])
    Pd_seq[i] = get_value(model[i][:pd_total])
    Pw_seq[i] = get_value(model[i][:pw])
    w_seq[i] = get_value(model[i][:w])
    Pl_all_load[i] = get_value(model[i][:pl])
    yg_seq[i] = get_value(model[i][:yg])
    zd_seq[i] = get_value(model[i][:zd])

end

# look into the startup instant
ordered_gen = sort!(OrderedDict(ref[1][:gen])) # order the dict based on the key
for i in keys(ordered_gen)
    gen_startup_instant_form_1 = findall(x->x==1, yg_seq[2][i])[1]
    println("Startup instant of generator ", i,
        ", Instant: ", gen_startup_instant_form_1
        )
end
# look into the startup instant
ordered_load = sort!(OrderedDict(ref[1][:load])) # order the dict based on the key
for i in keys(ordered_load)
    load_startup_instant_form_1 = findall(x->x==1, zd_seq[2][i])[1]
    println("Startup instant of load ", i,
        ", Instant: ", load_startup_instant_form_1,
        ", Value: ", ref[1][:load][i]["pd"] * ref[1][:baseMVA]
        )
end

# ------------ plot ------------
# # Pyplot generic setting
using PyPlot
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"

# plot generator and load in one plot
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
                color=line_colors[1],
                linestyle = line_style[1],
                marker=line_markers[1],
                linewidth=2,
                markersize=2,
                label="Generation")
end
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
                color=line_colors[2],
                linestyle = line_style[2],
                marker=line_markers[2],
                linewidth=2,
                markersize=2,
                label="Load")
end
ax.set_title("Restoration Trajectory", fontdict=Dict("fontsize"=>20))
ax.legend(loc="lower right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()

# plot load status
ordered_load = sort!(OrderedDict(ref[1][:load])) # order the dict based on the key
fig, ax = PyPlot.subplots(figsize=(12, 5))
bin_position = 0
bin_position_ticks = []
bin_label_ticks = []
for i in keys(ordered_load)
    bin_position = bin_position + 0.1
    for t in stages
        if Pl_all_load[2][i][t] == 0
            ax.scatter(t, bin_position, c=:red,alpha=0.5)
        else
            ax.scatter(t, bin_position, c=:green,alpha=0.5)
        end
    end
    push!(bin_position_ticks,bin_position)
    push!(bin_label_ticks, i)
end
ax.xaxis.set_label_text("Steps", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Load Index", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_ticks(bin_position_ticks)
ax.yaxis.set_ticklabels(bin_label_ticks)
ax.xaxis.set_tick_params(labelsize=14)
ax.yaxis.set_tick_params(labelsize=14)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)

# plot generator power
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=2,
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
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_gen.png")
PyPlot.savefig(sav_dict)

# plot load power
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
                markersize=2,
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
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_load.png")
# PyPlot.savefig(sav_dict)

# plot system available capacity
PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i] + Pw_seq[i] - Pd_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=2,
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
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_cap.png")
# PyPlot.savefig(sav_dict)

# wind dispatch command
wind_data_POE_WF3 = CSV.read("../../ERCOT_wind/wind_farm3_POE.csv", DataFrame)
wind_data_POE_WF3 = convert(Matrix, wind_data)
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    if saa_mode_option[i] == 1
        for st in 1:wind[i]["sample_number"]
            if value(model[i][:w][st]) > 0
                ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=3, alpha=0.4)
            else
                ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=1.0, alpha=0.3)
            end
        end
    elseif saa_mode_option[i] == 2
        for st in 1:wind[i]["sample_number"]
            ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=1.0, alpha=0.3)
        end
    end
end
for i in test_from:size(wind_data_POE_WF3)[2]
    ax.plot(t_step:t_step:t_final, wind_data_POE_WF3[1:1:40, i], color="k", linewidth=0.5)
end
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pw_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=2,
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
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_wind_dispatch_10.png")
# PyPlot.savefig(sav_dict)

# plot SAA violation scenarios
fig, ax = PyPlot.subplots(figsize=(12, 5))
for i in test_from:test_end
    if i >= 2
        for t in stages
            ax.scatter(t, sum(w_seq[i][st][t] for st in 1:wind[i]["sample_number"]))
        end
    end
end
ax.set_title("SAA violation scenarios", fontdict=Dict("fontsize"=>20))
ax.legend(loc="upper right", fontsize=20)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
ax.yaxis.set_label_text("Number of violations (MW)", fontdict=Dict("fontsize"=>20))
ax.xaxis.set_tick_params(labelsize=20)
ax.yaxis.set_tick_params(labelsize=20)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()

# # ------------------- save data into json --------------------
# using JSON
# json_string = JSON.json(Pw_seq)
# open("results_startup/data_gen_startup_real_data_wind.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pg_seq)
# open("results_startup/data_gen_startup_real_data_gen.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pd_seq)
# open("results_startup/data_gen_startup_real_data_load.json","w") do f
#   JSON.print(f, json_string)
# end
