# ----------------- Load modules from registered package----------------
# using LinearAlgebra
# using JuMP
# # using CPLEX
# # using Gurobi
# using DataFrames
# using CSV
# using JSON
# using PowerModels

@doc raw"""
Load network data
"""
function load_network(dir_case_network, network_data_format)
    #----------------- Load system data ----------------
    # check network data format and load accordingly
    # we are currently relying on PowerModels's IO functions
    if network_data_format == "json"
        println("Print dir_case_network")
        println(dir_case_network)
        ref = Dict()
        ref = JSON.parsefile(dir_case_network)  # parse and transform data
        println("Reconstruct data loaded from json")
        ref = Dict([Symbol(key) => val for (key, val) in pairs(ref)])
        ref[:gen] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:gen])])
        ref[:bus] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus])])
        ref[:bus_gens] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_gens])])
        ref[:bus_arcs] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_arcs])])
        ref[:bus_loads] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_loads])])
        ref[:bus_shunts] = Dict([parse(Int, string(key)) => val for (key, val) in pairs(ref[:bus_shunts])])
        ref[:branch] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:branch])])
        ref[:shunt] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:shunt])])
        ref[:load] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:load])])
        ref[:buspairs] = Dict([ (parse(Int, split(key, ['(', ',', ')'])[2]),
            parse(Int, split(key, ['(', ',', ')'])[3]))=> val for (key, val) in pairs(ref[:buspairs])])
        ref[:arcs] = [Tuple(val) for (key, val) in pairs(ref[:arcs])]
        ref[:bus_arcs] = Dict([key=>[Tuple(arc) for arc in val] for (key,val) in pairs(ref[:bus_arcs])])
        println("Complete loading network data in json format")
    elseif network_data_format == "matpower"
        println("Loading network data in matpower format")
        # Convert data from matpower format to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:it][:pm][:nw][0]
        println("Complete loading network data in matpower format")
    elseif network_data_format == "psse"
        println("Loading network data in psse format")
        # Convert data from psse to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:it][:pm][:nw][0]
        println("Complete loading network data in psse format")
    else
        println("Un-supported network data format")
    end

    return ref
end

@doc raw"""
Load generator data with respect to restoration
"""
function load_gen(dir_case_blackstart, ref, time_step)
    println("Loading generator black start data")
    # time step is in section
    # Generation data will be further adjusted based on the time and resolution specifications
    bs_data = CSV.read(dir_case_blackstart, DataFrame)

    # Define dictionary
    Pcr = Dict()    # cranking power
    Tcr = Dict()    # cranking time
    Krp = Dict()    # ramping rate

    for g in keys(ref[:gen])
        # This find index is added in case the genertor key is not from 1
        index = findall(x->x==g,bs_data[:,1])
        # cranking power: power needed for the unit to be normally functional, unit converted into pu
        Pcr[g] = bs_data[index[1],3] / ref[:baseMVA]
        # cranking time: time needed for the unit to be normally functional
        Tcr[g] = bs_data[index[1],4]  # in minutes
        # ramping rate: the unit in BS data is MW/min and converted into pu/min
        Krp[g] = bs_data[index[1],5] / ref[:baseMVA]   # originally in minutes/MW and now in minutes/pu
    end

    # Adjust generator data based on time step from minute to per time step
    for g in keys(ref[:gen])
        Tcr[g] = convert(Int, ceil(Tcr[g][1] / time_step)) # cranking time: time needed for the unit to be normally functional
        Krp[g] = Krp[g] * time_step # ramping rate in pu/each step
    end
    println("Complete loading generator black start data")
    return Pcr, Tcr, Krp
end


@doc raw"""
Load restoration plan from parallel power system restoration (PPSR) module
"""
function load_gen(dir_restoration_plan)
    println("Loading restoration plan from parallel power system restoration (PPSR) modulea")
    plan = CSV.read(dir_case_blackstart, DataFrame)
end