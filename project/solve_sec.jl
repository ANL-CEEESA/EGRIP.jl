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
dir_case_blackstart = "BS_generator_2.csv"
dir_case_result = "results_sec/"
gap = 0
ref, network_section, z_val, f_val, set_bus, set_line = solve_section(dir_case_network, dir_case_blackstart, dir_case_result, gap)


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

# for now we need to manually go through all keys
# :arcs_to, :arcs, :arcs_from,
# :branch,
# :gen,
# :load,
# :ref_buses,

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
    # add bs gen bus in the bus list
    push!(network_section[i], i)

    # copy bs gen bus
    section_ref[i][:bus][i] = ref[:bus][i]
    section_ref[i][:bus_gens][i] = ref[:bus_gens][i]
    section_ref[i][:bus_loads][i] = ref[:bus_loads][i]
    section_ref[i][:bus_arcs][i] = ref[:bus_arcs][i]
    section_ref[i][:bus_shunts][i] = ref[:bus_shunts][i]

    # assign bs gen bus as reference bus for each section
    section_ref[i][:ref_buses] = i

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
for i in keys(network_section)
    for (idx_bus, all_arc_bus_bus) in section_ref[i][:bus_arcs]
        for arc_bus_bus in all_arc_bus_bus
            if isempty(findall(x-> x==arc_bus_bus[3], network_section[i]))
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
        if !isempty(findall(x-> x==k[1],network_section[i])) && !isempty(findall(x-> x==k[2],network_section[i]))
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
        if !isempty(findall(x->x==f_bus, bus_sec)) && !isempty(findall(x->x==t_bus, bus_sec))
            section_ref[idx_sec][:branch][idx_br] = info_br
        else
            push!(skip_br_section, idx_sec)
        end
    end

    if length(skip_br_section) == length(network_section)
        println("skip branch: ", idx_br, "  f_bus: ",f_bus, "  t_bus: ",t_bus)
    end
end




zval = Dict()
for i in set_bus
    zval[i] = (z_val[38][i], z_val[39][i])
end

fval = Dict()
for br in set_line
    fval[(ref[:branch][br]["f_bus"], ref[:branch][br]["t_bus"])] = (br, f_val[38][br], f_val[39][br])
    println(br, " (", ref[:branch][br]["f_bus"], ", ",
        ref[:branch][br]["t_bus"], ") =>", f_val[38][br], ", ", f_val[39][br])
end

# # -------------- Command line --------------
# dir_case_network = ARGS[1]
# dir_case_blackstart = ARGS[2]
# dir_case_result = ARGS[3]
# t_final = parse(Int64, ARGS[4])
# t_step = parse(Int64, ARGS[5])
# gap = parse(Float64, ARGS[6])
# solve_restoration(dir_case_network, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
