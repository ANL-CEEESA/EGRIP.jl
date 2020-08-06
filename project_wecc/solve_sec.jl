# The "current working directory" is very important for correctly loading modules.
# One should refer to "Section 40 Code Loading" in Julia Manual for more details.

# change the current working directory to the one containing the file
# It seems Julia will not automatically change directory based on the operating file.
cd(@__DIR__)

# We can either add EGRIP to the Julia LOAD_PATH.
push!(LOAD_PATH,"../src/")
using EGRIP
using JSON
using CSV
# Or we use EGRIP as a module.
# include("../src/EGRIP.jl")
# using .EGRIP

# ------------ load manually sectionalized data from JSON --------------
# load data for restoration
network_section = Dict()
network_section = JSON.parsefile("WECC_dataset/network_section.json")
# load network data
ref = load_network("WECC_BaseCase.raw", "psse")

# ------------ processing ref data structure --------------
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

# TODO: manually assign bs gen bus as reference bus for each section
section_ref["1"][:ref_buses] = 78
section_ref["2"][:ref_buses] = 147

# for now we need to manually go through all keys
# :arcs_to, :arcs, :arcs_from,
# general information
for i in keys(network_section)
    section_ref[i][:baseMVA] = ref[:baseMVA]
    section_ref[i][:name] = ref[:name]
    section_ref[i][:conductor_ids] = ref[:conductor_ids]
    section_ref[i][:source_type] = ref[:source_type]
    section_ref[i][:source_version] = ref[:source_version]
    section_ref[i][:shunt] = ref[:shunt]
end

# bus name as keys
for i in keys(network_section)
    # copy other bus related information for each section
    for j in network_section[i]  # buses in each section
        section_ref[i][:bus][j] = ref[:bus][j]
        section_ref[i][:bus_gens][j] = ref[:bus_gens][j]
        section_ref[i][:bus_loads][j] = ref[:bus_loads][j]
        section_ref[i][:bus_arcs][j] = ref[:bus_arcs][j]
        section_ref[i][:bus_shunts][j] = ref[:bus_shunts][j]
    end
end

# delete boundary arcs in bus_arcs
arc_delete = []
# loop all sections
for i in keys(network_section)
    # loop bus_arcs
    for (idx_bus, all_arc_bus_bus) in section_ref[i][:bus_arcs]
         # loop all arcs connected to one bus
        for arc_bus_bus in all_arc_bus_bus
            # as long as one of the two terminal buses is not in this section
            # delete this arc
            if isempty(findall(x->x==arc_bus_bus[2], network_section[i])) | isempty(findall(x->x==arc_bus_bus[3], network_section[i]))
                idx_delete = findall(x->x==arc_bus_bus, all_arc_bus_bus)
                deleteat!(all_arc_bus_bus, idx_delete)
                push!(arc_delete, arc_bus_bus)
            end
        end
    end
end

# buspairs
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

# load
for (idx_load, info_load) in ref[:load]
    for i in keys(network_section)
        if !isempty(findall(x->x==info_load["load_bus"], network_section[i]))
            section_ref[i][:load][idx_load] = info_load
        end
    end
end

# gen
for (idx_gen, info_gen) in ref[:gen]
    for i in keys(network_section)
        if !isempty(findall(x->x==info_gen["gen_bus"], network_section[i]))
            section_ref[i][:gen][idx_gen] = info_gen
        end
    end
end

# save sectionalized data
a=["sec_1","sec_2"]
open(string("WECC_dataset/", a[1], ".json"), "w") do f
    JSON.print(f, section_ref["1"])
end
open(string("WECC_dataset/", a[2], ".json"), "w") do f
    JSON.print(f, section_ref["2"])
end

# testing: load data for restoration
function data_process(ref)
    println("print dir_case_network")
    ref = Dict([Symbol(key) => val for (key, val) in pairs(ref)])
    ref[:gen] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:gen])])
    ref[:bus] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus])])
    ref[:bus_gens] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_gens])])
    ref[:bus_arcs] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_arcs])])
    ref[:bus_loads] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_loads])])
    ref[:bus_shunts] = Dict([parse(Int, string(key)) => val for (key, val) in pairs(ref[:bus_shunts])])
    ref[:branch] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:branch])])
    ref[:load] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:load])])
    ref[:shunt] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:shunt])])
    ref[:buspairs] = Dict([ (parse(Int, split(key, ['(', ',', ')'])[2]),
        parse(Int, split(key, ['(', ',', ')'])[3]))=> val for (key, val) in pairs(ref[:buspairs])])
    ref[:arcs] = [Tuple(val) for (key, val) in pairs(ref[:arcs])]
    ref[:bus_arcs] = Dict([key=>[Tuple(arc) for arc in val] for (key,val) in pairs(ref[:bus_arcs])])
    println("complete loading network data in json format")
    return ref
end

dict_1 = Dict()
dict_2 = Dict()
dict_1 = JSON.parsefile(string("WECC_dataset/", a[1], ".json"))
dict_2 = JSON.parsefile(string("WECC_dataset/", a[2], ".json"))

dict_1 = data_process(dict_1)


# # ------------ Interactive --------------
dir_case_network = string("WECC_dataset/", a[1], ".json")
dir_case_blackstart = "WECC_dataset/WECC_Bus_gen.csv"
network_data_format = "json"
dir_case_result = "results_sec_1/"
t_final = 500
t_step = 250
gap = 1
solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

dir_case_network = string("WECC_dataset/", a[2], ".json")
dir_case_blackstart = "WECC_dataset/WECC_Bus_gen.csv"
network_data_format = "json"
dir_case_result = "results_sec_2/"
t_final = 500
t_step = 250
gap = 1
solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

# # -------------- Command line --------------
# dir_case_network = ARGS[1]
# dir_case_blackstart = ARGS[2]
# dir_case_result = ARGS[3]
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])
# gap = parse(Float64, ARGS[6])
# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
