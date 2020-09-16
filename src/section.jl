# ----------------- Load modules from registered package----------------
using LinearAlgebra
using JuMP
using CPLEX
# using LightGraphs
# using LightGraphsFlows
# using Gurobi
using DataFrames
using CSV
using JSON
using PowerModels

@doc raw"""
Solve sectionalization problem for restoration preparedness
- Problem type: The sectionalization problem could assign all buses to certain sections or only critical buses.
- Inputs:
    - network data directory
    - restoration data directory
    - result storage directory
    - gap
- Output:
    - JSON file of network data of each section
- Constraints:
"""
function solve_section(dir_case_network, dir_case_blackstart, dir_case_result, gap)

    #----------------- Load system data ----------------
    # Load system data in PSSE format
    # Convert data from PSSE format to MPC format (MatPower format)
    # We can employ MatPower function to do this

    # Convert data from MPC format to Julia Dict (PowerModels format)
    data0 = PowerModels.parse_file(dir_case_network)
    ref = PowerModels.build_ref(data0)[:nw][0]
    println("system data built")

    # Count numbers and generate iterators
    n_gen = length(ref[:gen])
    n_load = length(ref[:load])
    n_bus = length(ref[:bus])
    n_line = length(ref[:branch])/2
    iter_gen = 1:n_gen
    iter_load = 1:n_load
    iter_bus = 1:n_bus
    iter_line = 1:n_line
    println("Number of generators: ", n_gen)
    println("Number of loads: ", n_load)
    println("Number of buses: ", n_bus)
    println("Number of lines: ", n_line)
    println("system iterator built")

    # get line set
    set_line = Set([])
    for i in keys(ref[:buspairs])
        push!(set_line,ref[:buspairs][i]["branch"])
    end
    println("set_line")
    println(set_line)
    println("")

    # split bus into different sets
    set_bus = Set([])
    set_bus_gen = Set([])
    set_bus_load = Set([])
    # loop all bus and split them into load and gen buses
    for i in keys(ref[:bus])
        push!(set_bus, i)
        if ref[:bus][i]["bus_type"]==1
            push!(set_bus_load, i)
        else
            push!(set_bus_gen, i)
        end
    end
    println("bus: ")
    println(set_bus)
    println("gen bus: ")
    println(set_bus_gen)
    println("load bus: ")
    println(set_bus_load)
    println("bus set built")
    println("")

    # read restoration data
    bs_data = CSV.read(dir_case_blackstart)
    println(bs_data)
    println("")

    # bus set with black-start generators
    ngen_bs = sum(bs_data[:, 6])
    idx = findall(x->x==1, bs_data[:, 6])
    # convert bs gen bus from array to set
    set_bus_J = Set(bs_data[idx, 2])
    num_J = length(set_bus_J)
    println("black start data built")
    println("")

    # get non-bs gen set
    set_bus_gen_nbs = setdiff(set_bus_gen, set_bus_J)
    println("non bs gen")
    println(set_bus_gen_nbs)
    println("")

    # union of nbs gen and load
    set_bus_I = union(set_bus_gen_nbs, set_bus_load)
    num_I = length(set_bus_I)
    println("set_bus_I")
    println(set_bus_I)
    println("")

    #----------------- Load solver ---------------
    #----JuMP 0.18----
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    #----JuMP 0.19----
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # # ------------Define decision variable ---------------------
    # z_vj represents the decision whether a bus v is assigned to BS generator j
    @variable(model, z[set_bus, set_bus_J], Bin)
    # f_lj represents the number of unit ﬂows on line l ﬂowing to section j
    @variable(model, f[set_line, set_bus_J], Int)
    # y_lj is a binary indicator variable, indicating
    # whether line l is assigned to section j
    @variable(model, y[set_line, set_bus_J], Bin)

    # # ------------Define constraints ---------------------
    # eq (1)
    for j in set_bus_J
        for i in set_bus_I
            # get lines that are connected to bus i
            sum_f = 0
            for l_i_j in ref[:bus_arcs][i]
                idx_line = l_i_j[1]
                sum_f = sum_f + f[idx_line, j]
            end
            @constraint(model, sum_f==z[i, j])
            println(sum_f)
        end
    end
    println("eq (1) added")

    # eq (2)
    # in our case: set_bus = set_bus_I + set_bus_J
    # so for now it is empyty

    # eq (3)
    for j in set_bus_J
        @constraint(model, sum(f[:,j]) == sum(z[k,j] for k in set_bus_I))
    end
    println("eq (3) added")

    # eq (4)
    for i in set_bus
        @constraint(model, sum(z[i,:])==1)
    end
    println("eq (4) added")

    # eq (5)
    for j in set_bus_J
        for jp in setdiff(set_bus_J,j)
            # get lines that are connected to bus jp
            delta_jp = Set([])
            for l_i_j in ref[:bus_arcs][jp]
                push!(delta_jp, l_i_j[1])
            end
            L_delta_jp = setdiff(set_line, delta_jp)

            for l in L_delta_jp
                @constraint(model, f[l, j] >= -y[l, j]*num_I)
                @constraint(model,  f[l, j] <= y[l, j]*num_I)
            end
        end
    end
    println("eq (5) added")

    # eq (6)
    for v in set_bus
        # get lines that are connected to bus v
        num_delta_v = length(ref[:bus_arcs][v])
        delta_v = Set([])
        for l_i_j in ref[:bus_arcs][v]
            push!(delta_v, l_i_j[1])
        end

        for j in set_bus_J
            @constraint(model, sum(y[l, j] for l in delta_v) <= z[v, j]*num_delta_v)
        end
    end
    println("eq (6) added")

    # eq (7)
    # in our case: set_bus = set_bus_I + set_bus_J
    # so for now it is empyty


    # eq (8)
    for j in set_bus_J
        p_sum = 0
        for i in set_bus_I
            # get all generator indices at bus i
            idx_gen = ref[:bus_gens][i]
            if !isempty(idx_gen)
                for id in idx_gen
                    p_sum = p_sum + ref[:gen][id]["pg"]*z[i, j]
                end
            end
            # get all load indices at bus i
            idx_load = ref[:bus_loads][i]
            if !isempty(idx_load)
                for id in idx_load
                    p_sum = p_sum - ref[:load][id]["pd"]*z[i, j]
                end
            end
        end
        @constraint(model, p_sum >= -5)
        @constraint(model, p_sum <= 5)
    end
    println("eq (8) added")

    # we can define an empty objective
    @objective(model, Min, 0)

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))

    # store and print the results
    network_section = Dict()   # dictionary to store sectionalization results
    for j in set_bus_J
        network_section[j]=[]
    end
    println("")
    for j in set_bus_J
        println("Islands: ", j)
        for i in set_bus_I
             if abs(value(z[i, j]) -1 ) < 1e-2
                 push!(network_section[j], i)
                 print("bus ", i, ", ")
             end
        end
        println("")
    end
    println("")

    z_val = Dict()
    for i in set_bus
        z_val[i] = Dict()
        for j in set_bus_J
            z_val[i][j] = Int(round(value(z[i, j])))
        end
    end

    f_val = Dict()
    for l in set_line
        f_val[l] = Dict()
        f_val[l]["line_to_buspairs"] = (ref[:branch][l]["f_bus"], ref[:branch][l]["t_bus"])
        for j in set_bus_J
            f_val[l][j] = Int(round(value(f[l, j])))
        end
    end
    for l in set_line
        f_val[(ref[:branch][l]["f_bus"], ref[:branch][l]["t_bus"])] = [[l], [f_val[l][j] for j in set_bus_J]]
    end


    return ref, network_section, z_val, f_val

end
