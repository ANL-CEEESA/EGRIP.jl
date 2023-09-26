
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

# try to modify network data
network_data = PowerModels.parse_file("case118.m")
for i in keys(network_data["bus"]["23"]) 
    println(i)
end

# PowerModel data after build
ref = load_network(dir_case_network, network_data_format)


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
         # loop all arcs connected to one bus
        for arc_bus_bus in all_arc_bus_bus
            # as long as one of the two terminal buses is not in this section, delete this arc 
            if isempty(findall(x->x==arc_bus_bus[2], network_section[i])) | isempty(findall(x->x==arc_bus_bus[3], network_section[i]))
                idx_delete = findall(x->x==arc_bus_bus, all_arc_bus_bus)
                deleteat!(all_arc_bus_bus, idx_delete)
                push!(arc_delete, arc_bus_bus)
            end
        end
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

section_ref[28]
# PowerModel data before build
# ["bus", "shunt", "load", "gen", "branch", "storage", "switch", "source_type", "name", "dcline", "source_version", "baseMVA", "per_unit"]
pf_data = Dict() 
pf_data = Dict([string(key) => val for (key, val) in pairs(section_ref[28])])
pf_data["bus"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:bus])])
pf_data["gen"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:gen])])
pf_data["load"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:load])])
pf_data["shunt"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:shunt])])
pf_data["storage"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:storage])])
pf_data["branch"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:branch])])
pf_data["switch"] = Dict([string(key) => val for (key, val) in pairs(section_ref[28][:switch])])
pf_data["name"] = section_ref[28][:name]
pf_data["source_type"] = section_ref[28][:source_type]
pf_data["dcline"] = section_ref[28][:dcline]
pf_data["source_version"] = section_ref[28][:source_version]
pf_data["baseMVA"] = section_ref[28][:baseMVA]
pf_data["per_unit"] = true

# # here we can change the status of devices
# # try to add new status component in the dict
# # "status Cannot work
# pf_data["bus"]["27"]["status"] = 0
# pf_data["branch"]["34"]["status"] = 0
pf_data_stages = pf_data
delete!(pf_data_stages["bus"], "27")
delete!(pf_data_stages["bus"], "10")
delete!(pf_data_stages["bus"], "1")
delete!(pf_data_stages["bus"], "2")
delete!(pf_data_stages["bus"], "3")
delete!(pf_data_stages["bus"], "14")
delete!(pf_data_stages["bus"], "117")
delete!(pf_data_stages["bus"], "113")

#TODO: load data in the restoration file is too small
for i in keys(pf_data_stages["load"])
    delete!(pf_data_stages["load"], i)
end

delete!(pf_data_stages["gen"], "6")
delete!(pf_data_stages["gen"], "3")
delete!(pf_data_stages["gen"], "17")

# bus 8
pf_data_stages["gen"]["4"]["pmax"] = -0.098
pf_data_stages["gen"]["4"]["pmin"] = -0.098

#TODO: Although the final generator output is 0.09, it is infeasible if I set the limit to be 0.15.
# We can obtain feasible solution if we set it to 1
pf_data_stages["gen"]["16"]["pmax"] = 1
pf_data_stages["gen"]["16"]["pmin"] = 0


# solve the power flow
pf_result = solve_ac_opf(pf_data_stages, Ipopt.Optimizer)

results_vm = Dict(name => data["vm"] for (name, data) in pf_result["solution"]["bus"])
results_va = Dict(name => data["va"] for (name, data) in pf_result["solution"]["bus"])
results_pg = Dict(name => data["pg"] for (name, data) in pf_result["solution"]["gen"])
results_qg = Dict(name => data["qg"] for (name, data) in pf_result["solution"]["gen"])
results_pt = Dict(name => data["pt"] for (name, data) in pf_result["solution"]["branch"])
results_qt = Dict(name => data["qt"] for (name, data) in pf_result["solution"]["branch"])

print_summary(pf_result["solution"])

println("             ")
println("bus voltage")
for i in keys(results_vm)
    println(i, ": ", results_vm[i])
end

println("             ")
println("generator active")
for i in keys(results_pg)
    println(i, ": ", results_pg[i])
end

println("             ")
println("generator reactive")
for i in keys(results_qg)
    println(i, ": ", results_qg[i])
end