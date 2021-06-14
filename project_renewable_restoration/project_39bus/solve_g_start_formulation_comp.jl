# load registered package
using JuMP
using PowerModels

# get values from optimization variables with less or equal to two dimension
function get_value(A)
    n_dim = ndims(A)
    if n_dim == 1
        if axes(A)[1] isa Base.KeySet
            # Input variable use dict key as axis"
            solution_value = Dict()
            for i in axes(A)[1]
                solution_value[i] = value(A[i])
            end
        else
            # Input variable use time steps as axis"
            solution_value = []
            for i in axes(A)[1]
                push!(solution_value, value(A[i]))
            end
        end
    elseif n_dim == 2
        solution_value = Dict()
        for i in axes(A)[1]
            solution_value[i] = []
            for j in axes(A)[2]
                push!(solution_value[i], value(A[i,j]))
            end
        end
    else
        println("Currently does not support higher dimensional variables")
    end
    return solution_value
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
dir_case_network = "case39.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup_form_comp/"
t_final = 300
t_step = 10
gap = 0.0
nstage = t_final/t_step;
stages = 1:nstage;

# data0 = PowerModels.parse_file("case39.m")
# ref_org = PowerModels.build_ref(data0)[:nw][0]
# Pcr, Tcr, Krp = load_gen("BS_generator.csv", ref_org, t_step)

# plotting setup
line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
line_colors = ["b", "r", "m", "lime", "darkorange"]
line_markers = ["8", "s", "p", "*", "o"]
label_list = ["Form 1", "Form 2"]

# # ----------------- Solve the problem -------------------
test_from = 1
test_end = 2
formulation_type = [2, 3]
model = Dict()
ref = Dict()
pw_sp = Dict()
wind = Dict()
wind[1] = Dict("activation"=>0)
wind[2] = Dict("activation"=>0)
for i in test_from:test_end
    ref[i], model[i], pw_sp[i] = solve_startup(dir_case_network, network_data_format,
                                dir_case_blackstart, dir_case_result,
                                t_final, t_step, gap, formulation_type[i], wind[i])
end

# --------- retrieve results ---------
ys_seq = get_value(model[1][:ys])
zs_seq = get_value(model[1][:zs])
yg_seq = get_value(model[2][:yg])
zd_seq = get_value(model[2][:zd])

# look into the startup instant
for i in keys(ys_seq)
    startup_instant_form_1 = findall(x->x==1, ys_seq[i])[1]
    startup_instant_form_2 = round(Int64, yg_seq[i])
    println("Startup instant of generator ", i, ", Formulation 1: ", startup_instant_form_1, ", Formulation 2: ", startup_instant_form_2)
end
# look into the startup instant
for i in keys(zs_seq)
    startup_instant_form_1 = findall(x->x==1, zs_seq[i])[1]
    startup_instant_form_2 = round(Int64, zd_seq[i])
    println("Startup instant of load ", i, ", Formulation 1: ", startup_instant_form_1, ", Formulation 2: ", startup_instant_form_2)
end
Pg_seq = Dict()
Pg_seq[1] = get_value(model[1][:pg_total])
Pg_seq[2] = get_value(model[2][:pg_total])
Pd_seq = Dict()
Pd_seq[1] = get_value(model[1][:pd_total])
Pd_seq[2] = get_value(model[2][:pd_total])


# ------------ plot ------------
using PyPlot
# If true, return Python-based GUI; otherwise, return Julia backend

font_size = 20
fig_size=(12,5)

PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=fig_size)
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Generator Capacity", fontdict=Dict("fontsize"=>font_size))
ax.legend(loc="lower right", fontsize=font_size)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>font_size))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>font_size))
ax.xaxis.set_tick_params(labelsize=font_size)
ax.yaxis.set_tick_params(labelsize=font_size)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_form_comp_gen.png")
PyPlot.savefig(sav_dict)


PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
rcParams["font.family"] = "Arial"
fig, ax = PyPlot.subplots(figsize=fig_size)
for i in test_from:test_end
    ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
                color=line_colors[i],
                linestyle = line_style[i],
                marker=line_markers[i],
                linewidth=2,
                markersize=4,
                label=label_list[i])
end
ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>font_size))
ax.legend(loc="lower right", fontsize=font_size)
ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>font_size))
ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>font_size))
ax.xaxis.set_tick_params(labelsize=font_size)
ax.yaxis.set_tick_params(labelsize=font_size)
fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
PyPlot.show()
sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_form_comp_load.png")
PyPlot.savefig(sav_dict)

# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=fig_size)
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pg_seq[i] - Pd_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=4,
#                 label=label_list[i])
# end
# ax.set_title("System Capacity", fontdict=Dict("fontsize"=>font_size))
# ax.legend(loc="upper left", fontsize=font_size)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>font_size))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>font_size))
# ax.xaxis.set_tick_params(labelsize=font_size)
# ax.yaxis.set_tick_params(labelsize=font_size)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_cap.png")
# PyPlot.savefig(sav_dict)

# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=fig_size)
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pw_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=4,
#                 label=label_list[i])
# end
# ax.set_title("Wind Dispatch", fontdict=Dict("fontsize"=>font_size))
# ax.legend(loc="upper right", fontsize=font_size)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>font_size))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>font_size))
# ax.xaxis.set_tick_params(labelsize=font_size)
# ax.yaxis.set_tick_params(labelsize=font_size)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_wind_dispatch.png")
# PyPlot.savefig(sav_dict)

# if test_end > 2
#     PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
#     rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
#     rcParams["font.family"] = "Arial"
#     fig, ax = PyPlot.subplots(figsize=fig_size)
#     for i in 1:wind[2]["sample_number"]
#         ax.plot(t_step:t_step:t_final, (pw_sp[2][i])*100)
#     end
#     ax.set_title("Wind Sampled", fontdict=Dict("fontsize"=>font_size))
#     ax.legend(loc="upper right", fontsize=font_size)
#     ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>font_size))
#     ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>font_size))
#     ax.xaxis.set_tick_params(labelsize=font_size)
#     ax.yaxis.set_tick_params(labelsize=font_size)
#     fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
#     PyPlot.show()
#     sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_wind_sample.png")
#     PyPlot.savefig(sav_dict)
# end

# # save data into json
# using JSON
# json_string = JSON.json(Pw_seq)
# open("results_startup/data_gen_startup_fix_prob_wind.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pg_seq)
# open("results_startup/data_gen_startup_fix_prob_gen.json","w") do f
#   JSON.print(f, json_string)
# end
# json_string = JSON.json(Pd_seq)
# open("results_startup/data_gen_startup_fix_prob_load.json","w") do f
#   JSON.print(f, json_string)
# end
