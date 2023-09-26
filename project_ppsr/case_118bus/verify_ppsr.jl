
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
using Gurobi
using PowerModels
using Ipopt

# local functions
include("proj_utils.jl")

# # ------------ Load data --------------
dir_case_network = "case118.m"
dir_case_blackstart = "BS_generator.csv"
network_data_format = "matpower"
dir_case_result = "results_startup_density/"
gap = 0.0

ref = load_network(dir_case_network, network_data_format)

# t_final = 400
# t_step = 10
# nstage = Int64(t_final/t_step)
# stages = 1:nstage

# # plotting setup
# line_style = [(0,(3,5,1,5)), (0,(5,1)), (0,(5,5)), (0,(5,10)), (0,(1,1))]
# line_colors = ["b", "r", "m", "lime", "darkorange"]
# line_markers = ["8", "s", "p", "*", "o"]
# label_list = ["SAA 1", "SAA 40%"]


# load ppsr restoration plan 
dir_plan = "Restoration_plan_format_nodes_json_118_TL600_Rep1.csv"

plan = CSV.read(dir_plan, DataFrame)

# get the black start generator indices in each group
group_bs_bus_idx = unique(plan[:,end])

# get all buses in each group
network_section = Dict()
for i in group_bs_bus_idx
    idx_group = findall(x->x==i,plan[:,end])
    network_section[i] = plan[idx_group,1]
end

# we need to split ref data based on sectionalization
section_ref = Dict()
for i in keys(network_section)
    # build a dict to store sectionalized data
    section_ref[i] = Dict()

    # copy keys from standard ref
    for j in keys(ref)
        section_ref[i][j] = Dict()
    end
end

# for now we need to go through all keys. We will need to know the key strucutre of PowerModels and update accordingly.
# In total we have 31 keys.
# -----------------buses---------------
# bus
# bus_arcs
# bus_gens
# gen
# bus_loads
# load
# bus_shunts
# shunt
# bus_storage
# storage
# ----------------branches-----------------
# arcs
# buspairs
# branch
# arcs_dc
# arcs_to
# switch
# dcline
# arcs_to_dc
# arcs_to_sw
# arcs_from_sw
# arcs
# arcs_from
# bus_arcs_dc
# bus_arcs_sw
# arcs_from_dc
# arcs_sw
# -------------general information---------------
# baseMVA
# conductor_ids
# source_version
# ref_buses
# source_type
# name
# -------------- start splitting ref data structure--------
# general information
for i in keys(network_section)
    section_ref[i][:baseMVA] = ref[:baseMVA]
    section_ref[i][:name] = ref[:name]
    section_ref[i][:conductor_ids] = ref[:conductor_ids]
    section_ref[i][:source_type] = ref[:source_type]
    section_ref[i][:source_version] = ref[:source_version]
end

# assign bs gen bus as reference bus for each section
for i in keys(network_section)
    section_ref[i][:ref_buses] = i
end

# copy other bus related information for each section
for i in keys(network_section)
    for j in network_section[i]  # buses in each section
        section_ref[i][:bus][j] = ref[:bus][j]   # copy bus
        section_ref[i][:bus_arcs][j] = ref[:bus_arcs][j]   # copy bus_arcs
        section_ref[i][:bus_gens][j] = ref[:bus_gens][j]
        section_ref[i][:bus_loads][j] = ref[:bus_loads][j]
        section_ref[i][:bus_arcs][j] = ref[:bus_arcs][j]
        section_ref[i][:bus_shunts][j] = ref[:bus_shunts][j]
    end
end

# based on bus_xxx indices, copy other components
for i in keys(section_ref)
    # generator
    for j in keys(section_ref[i][:bus_gens])
        idx_set = section_ref[i][:bus_gens][j] # this is the generator index
        if !isempty(idx_set)  # this bus has generators
            for k in idx_set  # in case we have several generators in one bus
                section_ref[i][:gen][k] = ref[:gen][k]
            end
        end
    end

    # load
    for j in keys(section_ref[i][:bus_loads])
        idx_set = section_ref[i][:bus_loads][j] 
        if !isempty(idx_set)  
            for k in idx_set 
                section_ref[i][:load][k] = ref[:load][k]
            end
        end
    end

    # shunts
    for j in keys(section_ref[i][:bus_shunts])
        idx_set = section_ref[i][:bus_shunts][j] 
        if !isempty(idx_set)  
            for k in idx_set 
                section_ref[i][:shunt][k] = ref[:shunt][k]
            end
        end
    end

    # storage
    for j in keys(section_ref[i][:bus_storage])
        idx_set = section_ref[i][:bus_storage][j] 
        if !isempty(idx_set)  
            for k in idx_set 
                section_ref[i][:storage][k] = ref[:storage][k]
            end
        end
    end

end

# delete boundary arcs in bus_arcs
arc_delete = []
for i in keys(network_section)  # loop all sections
    for (idx_bus, all_arc_bus_bus) in section_ref[i][:bus_arcs]     # loop bus_arcs, data format (arc, bus, bus), no direction (5, 5, 6)=(5, 6, 5)

        # when we delete the arcs in a loop, the indices will change. We should store all indices and delete them at once
        idx_delete_store = []

        # loop all arcs connected to one bus
        for arc_bus_bus in all_arc_bus_bus
            # as long as one of the two terminal buses is not in this section, delete this arc 
            if isempty(findall(x->x==arc_bus_bus[2], network_section[i])) | isempty(findall(x->x==arc_bus_bus[3], network_section[i]))
                idx_delete = findall(x->x==arc_bus_bus, all_arc_bus_bus)
                push!(idx_delete_store, idx_delete[1])
            end
        end

        # record all deleted arcs
        for i in idx_delete_store
            push!(arc_delete, all_arc_bus_bus[i])
        end
        #commit the delete
        deleteat!(all_arc_bus_bus, idx_delete_store)

    end
end

# create buspairs for each section
for i in keys(network_section)
    for k in keys(ref[:buspairs])
        if !isempty(findall(x-> x==k[1],network_section[i])) & !isempty(findall(x-> x==k[2],network_section[i]))
            section_ref[i][:buspairs][k] = ref[:buspairs][k]
        end
    end
end

# use bus_arcs information to handle arcs, arcs_to, arcs_from
for i in keys(network_section)
    section_ref[i][:arcs] = []
    for (idx_bus, all_arc_bus_bus) in section_ref[i][:bus_arcs]
        for arc_bus_bus in all_arc_bus_bus
            push!(section_ref[i][:arcs], arc_bus_bus)
        end
    end
end

# branch
for (idx_br, info_br) in ref[:branch]
    f_bus = info_br["f_bus"]
    t_bus = info_br["t_bus"]
    skip_br_section = []
    for (idx_sec, bus_sec) in network_section
        if !isempty(findall(x->x==f_bus, bus_sec)) & !isempty(findall(x->x==t_bus, bus_sec))
            section_ref[idx_sec][:branch][idx_br] = info_br
        else
            push!(skip_br_section, idx_sec)
        end
    end

    if length(skip_br_section) == length(network_section)
        println("cut branch: ", idx_br, "  f_bus: ",f_bus, "  t_bus: ",t_bus)
    end
end
println("")

# process the restoration plan
plan_size = size(plan)
plan_gen = Dict()
plan_load = Dict()
plan_bus = Dict()
for i in 1:plan_size[1]
    bus_id = plan[i,1]
    bus_type = plan[i,2]
    bus_cap = plan[i,3]
    bus_crank_p = plan[i,4]
    bus_crank_t = plan[i,5]
    bus_ramp_t = plan[i,5]
    section_id = plan[i,end]
    ramp_traj = range(0, bus_cap, bus_ramp_t)

    # get bus plan
    plan_bus[bus_id] = Array(plan[i,7:end-1])

    # get generator plan
    # since PPSR does not consider power balance, we will focus on generator proccess
    if bus_type == "NBS"
        gen_id = section_ref[section_id][:bus_gens][bus_id]
        plan_gen[gen_id[1]] = []
        count_crank = 0
        count_ramp = 0
        for p in plan[i,7:end-1]
            if p == 0
                push!(plan_gen[gen_id[1]], 0)
            elseif (p == 1) & (count_crank < bus_crank_t)
                count_crank = count_crank + 1
                push!(plan_gen[gen_id[1]], -bus_crank_p/100)
            elseif (p == 1) & (count_crank >= bus_crank_t) & (count_ramp < bus_ramp_t)
                count_ramp = count_ramp + 1
                push!(plan_gen[gen_id[1]], ramp_traj[count_ramp]/100)
            elseif (p == 1) & (count_crank >= bus_crank_t) & (count_ramp >= bus_ramp_t)
                push!(plan_gen[gen_id[1]], bus_cap/100)
            else
                println("Impossible plan scenario")
            end
        end

    elseif bus_type == "BS"
        gen_id = section_ref[section_id][:bus_gens][bus_id]
        plan_gen[gen_id[1]] = Array(plan[i,7:end-1]) * bus_cap/100

    elseif bus_type == "CL"
        load_id = section_ref[section_id][:bus_loads][bus_id]
        plan_load[load_id[1]] = Array(plan[i,7:end-1]) * bus_cap/100
    end 
end

# define stages:
stages = 1: length(plan[1,7])

model = Model(Gurobi.Optimizer)
set_optimizer_attribute(model, "MIPGap", 0)

# ------------Define decision variable ---------------------
println("Defining restoration variables")
# define generator variables
model = def_var_gen(model, section_ref[28], stages; form=4)
# define load variable
model = def_var_load(model, section_ref[28], stages; form=4)
# define flow variable
model = def_var_flow(model, section_ref[28], stages)
println("Complete defining restoration variables")

# ------------Define constraints ---------------------
println("Defining restoration constraints")

# nodal constraint
model = form_nodal(model, section_ref[28], stages)

# branch (power flow) constraints
model = form_branch(model, section_ref[28], stages)

# # bus energization heuristic
# model = bus_energization_rule(model, section_ref[28], stages)

# single power balance constraints
for t in stages
    @constraint(model, model[:pg_total][t] == model[:pd_total][t])
end

# generator plan enforcement
model = form_gen_plan_enforce(model, section_ref[28], stages, plan_gen)

# load pickup constraints
model = form_load_plan_enforce(model, section_ref[28], stages, plan_load)

println("Complete defining restoration constraints")

#------------------- Define objectives--------------------
## (5) maximize both total load and generator status
@objective(model, Min, sum(model[:x][l, t] for l in keys(section_ref[28][:buspairs]) for t in stages))
optimize!(model) 
status = termination_status(model)
println("")
println("Termination status: ", status)
println("The objective value is: ", objective_value(model))

Pg_total_seq = get_value(model[:pg_total])
Pd_total_seq = get_value(model[:pd_total])
res_line_seq = get_value(model[:x])
res_vm = get_value(model[:v])
res_vl = get_value(model[:vl])
res_vb = get_value(model[:vb])
res_pl = get_value(model[:pl])
res_pg = get_value(model[:pg])
res_qg = get_value(model[:qg])
res_p = get_value(model[:p])
res_q = get_value(model[:q])

println("             ")
println("line sequence")
for i in keys(res_line_seq)
    println(i, ": ", res_line_seq[i])
end

println("             ")
println("bus voltage")
for i in keys(res_vm)
    println(i, ": ", res_vm[i])
end

println("             ")
println("bus voltage b")
for i in keys(res_vb)
    println(i, ": ", res_vb[i])
end

println("             ")
println("virtual bus voltage")
for i in keys(res_vl)
    println(i, ": ", res_vl[i])
end

println("             ")
println("active power flow")
for i in keys(res_p)
    println(i, ": ", res_p[i])
end

println("             ")
println("reactive power flow")
for i in keys(res_q)
    println(i, ": ", res_q[i])
end

println("             ")
println("load")
for i in keys(res_pl)
    println(i, ": ", res_pl[i])
end

println("             ")
println("generator active")
for i in keys(res_pg)
    println(i, ": ", res_pg[i])
end

println("             ")
println("generator reactive")
for i in keys(res_qg)
    println(i, ": ", res_qg[i])
end

println("end of plot")
# # --------- retrieve results and plotting ---------
# Pg_seq = Dict()
# Pd_seq = Dict()
# Pw_seq = Dict()
# w_seq = Dict()
# yg_seq = Dict()
# zd_seq = Dict()
# Pl_all_load = Dict()

# for i in 1:1
#     Pg_seq[i] = get_value(model[i][:pg_total])
#     Pd_seq[i] = get_value(model[i][:pd_total])
#     Pl_all_load[i] = get_value(model[i][:pl])
#     yg_seq[i] = get_value(model[i][:yg])
#     zd_seq[i] = get_value(model[i][:zd])
# end

# # look into the startup instant
# ordered_gen = sort!(OrderedDict(ref[1][:gen])) # order the dict based on the key
# for i in keys(ordered_gen)
#     gen_startup_instant_form_1 = findall(x->x==1, yg_seq[2][i])[1]
#     println("Startup instant of generator ", i,
#         ", Instant: ", gen_startup_instant_form_1
#         )
# end
# # look into the startup instant
# ordered_load = sort!(OrderedDict(ref[1][:load])) # order the dict based on the key
# for i in keys(ordered_load)
#     load_startup_instant_form_1 = findall(x->x==1, zd_seq[2][i])[1]
#     println("Startup instant of load ", i,
#         ", Instant: ", load_startup_instant_form_1,
#         ", Value: ", ref[1][:load][i]["pd"] * ref[1][:baseMVA]
#         )
# end

# # ===================================== plot ===================================
# # Pyplot generic setting
# using PyPlot
# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"

# # # -------------------------- generator and load in one plot --------------------
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
#                 color=line_colors[1],
#                 linestyle = line_style[1],
#                 marker=line_markers[1],
#                 linewidth=2,
#                 markersize=2,
#                 label="Generation")
# end
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
#                 color=line_colors[2],
#                 linestyle = line_style[2],
#                 marker=line_markers[2],
#                 linewidth=2,
#                 markersize=2,
#                 label="Load")
# end
# ax.set_title("Restoration Trajectory", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()

# # ----------------------------------- load status ------------------------------
# ordered_load = sort!(OrderedDict(ref[1][:load])) # order the dict based on the key
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# bin_position = 0
# bin_position_ticks = []
# bin_label_ticks = []
# for i in keys(ordered_load)
#     bin_position = bin_position + 0.1
#     for t in stages
#         if Pl_all_load[2][i][t] == 0
#             ax.scatter(t, bin_position, c=:red,alpha=0.5)
#         else
#             ax.scatter(t, bin_position, c=:green,alpha=0.5)
#         end
#     end
#     push!(bin_position_ticks,bin_position)
#     push!(bin_label_ticks, i)
# end
# ax.xaxis.set_label_text("Steps", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Load Index", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_ticks(bin_position_ticks)
# ax.yaxis.set_ticklabels(bin_label_ticks)
# ax.xaxis.set_tick_params(labelsize=14)
# ax.yaxis.set_tick_params(labelsize=14)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)

# # -------------------------------generator power-------------------------------
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pg_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("Generator Capacity", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# # sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_gen.png")
# # PyPlot.savefig(sav_dict)

# # -----------------------------load power--------------------------------------
# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(12,5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pd_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("Load Trajectory", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="lower right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# # sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_load.png")
# # PyPlot.savefig(sav_dict)

# # plot system available capacity
# PyPlot.pygui(true) # If true, return Python-based GUI; otherwise, return Julia backend
# rcParams = PyPlot.PyDict(PyPlot.matplotlib."rcParams")
# rcParams["font.family"] = "Arial"
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pg_seq[i] + Pw_seq[i] - Pd_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("System Capacity", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="upper left", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# # sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_cap.png")
# # PyPlot.savefig(sav_dict)

# # ----------------------------wind dispatch command---------------------------
# wind_data_POE_WF3 = CSV.read("../../ERCOT_wind/wind_farm3_POE.csv", DataFrame)
# wind_data_POE_WF3 = convert(Matrix, wind_data)
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     if saa_mode_option[i] == 1
#         for st in 1:wind[i]["sample_number"]
#             if value(model[i][:w][st]) > 0
#                 ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=3, alpha=0.4)
#             else
#                 ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=1.0, alpha=0.3)
#             end
#         end
#     elseif saa_mode_option[i] == 2
#         for st in 1:wind[i]["sample_number"]
#             ax.plot(t_step:t_step:t_final, (pw_sp[i][st])*100, linewidth=1.0, alpha=0.3)
#         end
#     end
# end
# for i in test_from:size(wind_data_POE_WF3)[2]
#     ax.plot(t_step:t_step:t_final, wind_data_POE_WF3[1:1:40, i], color="k", linewidth=0.5)
# end
# for i in test_from:test_end
#     ax.plot(t_step:t_step:t_final, (Pw_seq[i])*100,
#                 color=line_colors[i],
#                 linestyle = line_style[i],
#                 marker=line_markers[i],
#                 linewidth=2,
#                 markersize=2,
#                 label=label_list[i])
# end
# ax.set_title("Wind Dispatch", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="upper right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Power (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()
# # sav_dict = string(pwd(), "/", dir_case_result, "fig_gen_startup_fix_prob_wind_dispatch_10.png")
# # PyPlot.savefig(sav_dict)

# # ------------------------------SAA violation scenarios-------------------------
# fig, ax = PyPlot.subplots(figsize=(12, 5))
# for i in test_from:test_end
#     if i >= 2
#         for t in stages
#             ax.scatter(t, sum(w_seq[i][st][t] for st in 1:wind[i]["sample_number"]))
#         end
#     end
# end
# ax.set_title("SAA violation scenarios", fontdict=Dict("fontsize"=>20))
# ax.legend(loc="upper right", fontsize=20)
# ax.xaxis.set_label_text("Time (min)", fontdict=Dict("fontsize"=>20))
# ax.yaxis.set_label_text("Number of violations (MW)", fontdict=Dict("fontsize"=>20))
# ax.xaxis.set_tick_params(labelsize=20)
# ax.yaxis.set_tick_params(labelsize=20)
# fig.tight_layout(pad=0.2, w_pad=0.2, h_pad=0.2)
# PyPlot.show()

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
