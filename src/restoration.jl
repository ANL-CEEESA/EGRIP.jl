# # If we use fucntions from other un-registered modules, we need to declare them
# # ----------------- Load modules from un-registered modules-------------------
# # Option 1: We organize multiple scripts as a package and put include("file") in the main module
# # Option 2: We put include("file") in the scripts needed
# include("ReadMFile.jl")
# include("Form.jl")

# # relative or absolute import will depend on if the package is loaded in LOAD_PATH
# using ReadMFile
# using Form


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
- Problem type: The restoration problem could be partial or full restorations
- Inputs:
- Output:
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

    status = optimize!(model)
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


@doc raw"""
Solve restoration problem
- Problem type: The restoration problem could be partial or full restorations
- Inputs: A set of restoration data in csv format and original system data
    - restoration_gen: specify initial generator status, cranking specifications and black-start generators
    - restoration_bus: specify initial bus status and its load priority, from where the problem type (partial or full restorations) can be determined
    - restoration_line: specify initial line status, from where the problem type (partial or full restorations) can be determined
    - original system data in matpower or PSS/E format
- Output: Restoration plans
- Constraints:
    - linearized AC power flow constraint
    - steady-state voltage variation constraint
    - generator cranking constraint
    - generator status and output constraint
    - load pick-up constraint
"""
function solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)

    #----------------- Load system data ----------------
    # check network data format and load accordingly
    if network_data_format == "json"
        println("print dir_case_network")
        println(dir_case_network)
        ref = Dict()
        ref = JSON.parsefile(dir_case_network)  # parse and transform data
        println("convert key type from string to symbol and int")
        ref = Dict([Symbol(key) => val for (key, val) in pairs(ref)])
        ref[:gen] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:gen])])
        ref[:bus] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus])])
        ref[:bus_gens] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_gens])])
        ref[:bus_arcs] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_arcs])])
        ref[:bus_loads] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:bus_loads])])
        ref[:bus_shunts] = Dict([parse(Int, string(key)) => val for (key, val) in pairs(ref[:bus_shunts])])
        ref[:branch] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:branch])])
        ref[:load] = Dict([parse(Int,string(key)) => val for (key, val) in pairs(ref[:load])])
        ref[:buspairs] = Dict([ (parse(Int, split(key, ['(', ',', ')'])[2]),
            parse(Int, split(key, ['(', ',', ')'])[3]))=> val for (key, val) in pairs(ref[:buspairs])])
        println("complete loading network data in json format")
    elseif network_data_format == "matpower"
        # Convert data from matpower format to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:nw][0]
        println("complete loading network data in matpower format")
    elseif network_data_format == "psse"
        # Convert data from psse to Julia Dict (PowerModels format)
        data0 = PowerModels.parse_file(dir_case_network)
        ref = PowerModels.build_ref(data0)[:nw][0]
        println("complete loading network data in psse format")
    else
        println("un-supported network data format")
    end

    # check data
    println("")
    println("bus")
    println(keys(ref[:bus]))

    println("bus arcs")
    println(keys(ref[:bus_arcs]))

    println("bus gen")
    println(keys(ref[:bus_gens]))

    println("bus pairs")
    println(keys(ref[:buspairs]))

    println("gen")
    println(keys(ref[:gen]))

    println("arcs")
    println(keys(ref[:arcs]))

    # Count numbers and generate iterators
    ngen = length(keys(ref[:gen]));
    nload = length(keys(ref[:load]));
    # gen = 1:ngen;
    # load = 1:nload;

    # Load generation data
    # Generation data will be further adjusted based on the time and resolution specifications

    bs_data = CSV.read(dir_case_blackstart)

    # Define dictionary
    Tcr = Dict()
    Pcr = Dict()
    Krp = Dict()

    for g in keys(ref[:gen])
        Pcr[g] = bs_data[g,3]/100 # cranking power: power needed for the unit to be normally functional
        Tcr[g] = bs_data[g,4] # cranking time: time needed for the unit to be normally functional
        Krp[g] = bs_data[g,5]/100 # ramping rate
    end

    # --------------Set time and resolution specifications-----------------
    # The final time selection should be complied with restoration time requirement.
    time_final = t_final;
    time_series = 1:t_final;

    # Choicing different time steps is the key for testing multiple resolutions
    time_step = t_step;

    # calculate stages
    nstage = time_final/time_step;
    stages = 1:nstage;

    # Adjust generator data based on time step
    for g in keys(ref[:gen])
        Tcr[g] = ceil(bs_data[g,4]/time_step) # cranking time: time needed for the unit to be normally functional
        Krp[g] = bs_data[g,5]*time_step # ramping rate
    end


    #----------------- Load solver ---------------
    # JuMP 0.18
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # JuMP 0.19
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # ------------Define decision variable ---------------------
    @variable(model, x[keys(ref[:buspairs]),stages], Bin); # status of line at time t
    @variable(model, y[keys(ref[:gen]),stages], Bin); # status of gen at time t
    @variable(model, u[keys(ref[:bus]),stages], Bin); # status of bus at time t
    @variable(model, ref[:bus][i]["vmin"] <= v[i in keys(ref[:bus]),stages]
        <= ref[:bus][i]["vmax"]); # bus voltage with upper- and lower bounds
    @variable(model, a[keys(ref[:bus]),stages]); # bus angle

    # slack variables of voltage and angle on flow equations
    bp2 = collect(keys(ref[:buspairs]))
    for k in keys(ref[:buspairs])
        i,j = k
        push!(bp2, (j,i))
    end
    @variable(model, vl[bp2,stages]) # V_i^j
    @variable(model, al[bp2,stages]) # theta_i^j
    @variable(model, vb[keys(ref[:bus]),stages])

    # load variable
    @variable(model, pl[keys(ref[:load]),stages])
    @variable(model, ql[keys(ref[:load]),stages])

    # generation variable
    @variable(model, pg[keys(ref[:gen]),stages])
    @variable(model, qg[keys(ref[:gen]),stages])

    # line flow with the index rule (branch, from_bus, to_bus)
    # Note that we can only measure the line flow at the bus terminal
    @variable(model, -ref[:branch][l]["rate_a"] <= p[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])
    @variable(model, -ref[:branch][l]["rate_a"] <= q[(l,i,j) in ref[:arcs],stages] <= ref[:branch][l]["rate_a"])

    # nodal constraint
    model = form_nodal(ref, model, stages, vl, vb, v, x, y, a, al, u, p, q, pg, pl, qg, ql)

    # branch (power flow) constraints
    model = form_branch(ref, model, stages, vl, al, x, u, p, q)

    # generator control constraint
    model = form_gen_logic(ref, model, stages, nstage, pg, y, Krp, Pcr)

    # load control constraint
    model = form_load_logic(ref, model, stages, pl, ql, u)

    # generator cranking constraint
    model = form_bs_logic(ref, model, stages, pg, qg, y, Pcr, Tcr)

    #------------------- Define objectives--------------------
    # @objective(model, Min, sum( sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages ) + sum( sum(t*z[l,t] for l in keys(ref[:load])) for t in stages ) )
    # @objective(model, Min, sum( sum(-pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] >= 0)
    #         + sum(pl[l,t] for l in keys(ref[:load]) if ref[:load][l]["pd"] < 0) for t in stages ) )
    # @objective(model, Min, sum(10*sum(1 - y[g,t] for g in keys(ref[:gen])) + sum(x[a,t] for a in keys(ref[:buspairs])) for t in stages) )
    @objective(model, Min, sum(sum(1 - y[g,t] for g in keys(ref[:gen])) for t in stages) )

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    status = optimize!(model)
    println("The objective value is: ", objective_value(model))


    #------------- Record results ----------------
    # results in stages
    println("")
    adj_matrix = zeros(length(ref[:bus]), length(ref[:bus]))
    println("Line energization: ")
    for t in stages
        print("stage ", t, ": ")
        for (i,j) in keys(ref[:buspairs])
             if abs(value(x[(i,j),t]) - 1) < 1e-6 && adj_matrix[i,j] == 0
                print("(", i, ",", j, ") ")
                adj_matrix[i,j] = 1
             end
        end
        println("")
    end

    println("")
    println("Generator energization: ")
    for t in stages
        print("stage ", t, ": ")
        for g in keys(ref[:gen])
            if (abs(value(y[g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(y[g,t-1]) + value(y[g,t]) - 1) < 1e-6)
                print(ref[:gen][g]["gen_bus"], " ")
            end
        end
        println("")
    end

    println("")
    println("Bus energization: ")
    for t in stages
        print("stage ", t, ": ")
        for b in keys(ref[:bus])
            if (abs(value(u[b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(u[b,t-1]) + value(u[b,t]) - 1) < 1e-6)
                print(b, " ")
            end
        end
        println("")
    end

    #-----------Build a dictionary to store the changing point---------------
    CP = Dict();

    # Write branch energization solution
    CP[:x] = Dict();
    resultfile = open(string(dir_case_result, "res_x.csv"), "w")
    print(resultfile, "Branch Index, From Bus , To Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, branch) in ref[:branch]
            # if branch["b_fr"] == 0
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, branch["f_bus"])
                print(resultfile, ", ")
                print(resultfile, branch["t_bus"])
                print(resultfile, ",")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(x[(branch["f_bus"], branch["t_bus"]),t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(x[(branch["f_bus"], branch["t_bus"]),t])==0) & (value(x[(branch["f_bus"], branch["t_bus"]),t+1])==1)
                            CP[:x][i] = t
                        end
                    else
                        print(resultfile, round(value(x[(branch["f_bus"], branch["t_bus"]),t])))
                    end
                end
            println(resultfile, " ")
            #end
    end
    close(resultfile)

    # Write generator energization solution
    CP[:y] = Dict();
    resultfile = open(string(dir_case_result, "res_y.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(y[i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(y[i,t])==0) & (value(y[i,t+1])==1)
                            CP[:y][i] = t
                        end
                    else
                        print(resultfile, value(y[i,t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write bus energization solution
    CP[:u] = Dict();
    resultfile = open(string(dir_case_result, "res_u.csv"), "w")
    print(resultfile, "Bus Index,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, bus) in ref[:bus]
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(u[i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(u[i,t])==0) & (value(u[i,t+1])==1)
                            CP[:u][i] = t
                        end
                    else
                        print(resultfile, round(value(u[i,t])))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Write generator active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(pg[i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(pg[i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write generator rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_qg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(qg[i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(qg[i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pl.csv"), "w")
    print(resultfile, "Load Index, Bus Index, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ref[:load]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(pl[i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(pl[i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_ql.csv"), "w")
    print(resultfile, "Load Index, Bus Index, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ref[:load]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(ql[i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(ql[i,t])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    #---------------- Interpolate current plan to time series (one-minute based) data --------------------
    # Interpolate generator energization solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_y.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                       # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        # Determine if the current generator has a changing scenario
                        if i in keys(CP[:y])
                            # check if the current stage is the changing stage
                            # mark changing stage different from 0 or 1 (do not use string as it causes problems after reading from CSV)
                            if CP[:y][i] == stage_index
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else
                                print(resultfile, Int(round(value(y[i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(y[i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, Int(round(value(y[i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Interpolate generator dispatch solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_pg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ref[:gen]
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, round(value(pg[i,stage_index])*100))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, round(value(pg[i,stage_index])*100))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Interpolate bus energization solution to time series (one-minute based) data
    resultfile = open(string(dir_case_result, "Interpol_u.csv"), "w")
    print(resultfile, "Bus Index,")
    for t in time_series
        if t<time_final
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, bus) in ref[:bus]
                print(resultfile, i)
                print(resultfile, ", ")
                for t in time_series
                    if t<time_final
                       # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        if i in keys(CP[:u])
                            # check if the current stage is the changing stage
                            if CP[:u][i] == stage_index  # If yes, mark the time series data as "tbd"
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else                          # If no, use the previously calculated values
                                print(resultfile, Int(round(value(u[i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(u[i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
                        print(resultfile, Int(round(value(u[i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

end


@doc raw"""
form the nodal constraints:
- voltage constraint
    - voltage deviation should be limited
    - voltage constraints are only activated if the associated line is energized
```math
\begin{align*}
    & v^{\min}_{i} \leq v_{i,t} \leq v^{\max}_{i}\\
    & v^{\min}_{i}x_{ij,t} \leq vl_{ij,t} \leq v^{\max}_{i}x_{ij,t}\\
    & v^{\min}_{j}x_{ij,t} \leq vl_{ji,t} \leq v^{\max}_{j}x_{ij,t}\\
    & v_{i,t} - v^{\max}_{i}(1-x_{ij,t}) \leq vl_{ij,t} \leq v_{i,t} - v^{\min}_{i}(1-x_{ij,t})\\
    & v_{j,t} - v^{\max}_{j}(1-x_{ij,t}) \leq vl_{ij,t} \leq v_{j,t} - v^{\min}_{j}(1-x_{ij,t})
\end{align*}
```
- angle difference constraint
    - angle difference should be limited
     - angle difference constraints are only activated if the associated line is energized
```math
 \begin{align*}
     & a^{\min}_{ij} \leq a_{i,t}-a_{j,t} \leq a^{\max}_{ij}\\
     & a^{\min}_{ij}x_{ij,t} \leq al_{ij,t}-al_{ji,t} \leq a^{\max}_{ij}x_{ij,t}\\
     & a_{i,t}-a_{j,t}-a^{\max}_{ij}(1-x_{ij,t}) \leq al_{ij,t}-al_{ji,t} \leq a_{i,t}-a_{j,t}-a^{\min}_{ij}(1-x_{ij,t})
 \end{align*}
```
- generator and bus energizing logics
    - energized line cannot be shut down
    - bus should be energized before the connected genertor being on
```math
\begin{align*}
 & x_{ij,t} \geq x_{ij,t-1}\\
 & u_{i,t} \geq x_{ij,t}\\
 & u_{j,t} \geq x_{ij,t}
\end{align*}
```
- bus energized constraints
    - bus energized indicating generator energized
    - energized buses cannot be shut down
```math
\begin{align*}
& v^{\min}u_{i,t} \leq vb_{i,t} \leq v^{\max}u_{i,t} \\
& v_{i,t} - v^{\max}(1-u_{i,t}) \leq vb_{i,t} \leq v_{i,t} - v^{\min}(1-u_{i,t})\\
& u_{g,t} = y_{g,t}\\
& u_{i,t} \geq u_{i,t-1}
\end{align*}
```
- nodal power balance constraint
```math
\begin{align*}
& \sum_{b\in i}p_{b,t}=\sum_{g\in i}pg_{g,t}-\sum_{l\in i}pl_{l,t}-Gs(2vb_{i,t}-u_{i,t})\\
& \sum_{b\in i}q_{b,t}=\sum_{g\in i}qg_{g,t}-\sum_{l\in i}ql_{l,t}+Bs(2vb_{i,t}-u_{i,t})
\end{align*}
```
"""
function form_nodal(ref, model, stages, vl, vb, v, x, y, a, al, u, p, q, pg, pl, qg, ql)
    println("")
    println("formulating nodal constraints")

    for (i,j) in keys(ref[:buspairs])

        println("creating slack variables for nodal constraint for bus pair: ", i, ", ", j)

        for t in stages
            # voltage constraints
            # voltage constraints are only activated if the associated line is energized
            @constraint(model, vl[(i,j),t] >= ref[:bus][i]["vmin"]*x[(i,j),t])
            @constraint(model, vl[(i,j),t] <= ref[:bus][i]["vmax"]*x[(i,j),t])
            @constraint(model, vl[(j,i),t] >= ref[:bus][j]["vmin"]*x[(i,j),t])
            @constraint(model, vl[(j,i),t] <= ref[:bus][j]["vmax"]*x[(i,j),t])
            @constraint(model, vl[(i,j),t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-x[(i,j),t]))
            @constraint(model, vl[(i,j),t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-x[(i,j),t]))
            @constraint(model, vl[(j,i),t] >= v[j,t] - ref[:bus][j]["vmax"]*(1-x[(i,j),t]))
            @constraint(model, vl[(j,i),t] <= v[j,t] - ref[:bus][j]["vmin"]*(1-x[(i,j),t]))

            # angle difference constraints
            # angle difference constraints are only activated if the associated line is energized
            @constraint(model, a[i,t] - a[j,t] >= ref[:buspairs][(i,j)]["angmin"])
            @constraint(model, a[i,t] - a[j,t] <= ref[:buspairs][(i,j)]["angmax"])
            @constraint(model, al[(i,j),t] - al[(j,i),t] >= ref[:buspairs][(i,j)]["angmin"]*x[(i,j),t])
            @constraint(model, al[(i,j),t] - al[(j,i),t] <= ref[:buspairs][(i,j)]["angmax"]*x[(i,j),t])
            @constraint(model, al[(i,j),t] - al[(j,i),t] >= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmax"]*(1-x[(i,j),t]))
            @constraint(model, al[(i,j),t] - al[(j,i),t] <= a[i,t] - a[j,t] - ref[:buspairs][(i,j)]["angmin"]*(1-x[(i,j),t]))

            # energized line cannot be shut down
            if t > 1
                @constraint(model, x[(i,j), t] >= x[(i,j), t-1])
            end

            # bus should be energized before the connected genertor being on
            @constraint(model, u[i,t] >= x[(i,j),t])
            @constraint(model, u[j,t] >= x[(i,j),t])

        end
    end

    # nodal (bus) constraints
    for (i, bus) in ref[:bus]  # loop its keys and entries
        println("formulating nodal constraint for bus ", i)
        for t in stages
            bus_shunts = [ref[:shunt][s] for s in ref[:bus_shunts][i]]

            @constraint(model, vb[i,t] >= ref[:bus][i]["vmin"]*u[i,t])
            @constraint(model, vb[i,t] <= ref[:bus][i]["vmax"]*u[i,t])
            @constraint(model, vb[i,t] >= v[i,t] - ref[:bus][i]["vmax"]*(1-u[i,t]))
            @constraint(model, vb[i,t] <= v[i,t] - ref[:bus][i]["vmin"]*(1-u[i,t]))

            # u_i >= y_i & u_{i,t} >= u_{i,t-1}
            for g in ref[:bus_gens][i]
                @constraint(model, u[i,t] == y[g,t])  # bus on == generator on
            end
            if t > 1
                @constraint(model, u[i,t] >= u[i,t-1]) # on-line buses cannot be shut down
            end

            # Bus KCL
            # Nodal power balance constraint
            @constraint(model, sum(p[a,t] for a in ref[:bus_arcs][i]) ==
                sum(pg[g,t] for g in ref[:bus_gens][i]) -
                sum(pl[l,t] for l in ref[:bus_loads][i]) -
                sum(shunt["gs"] for shunt in bus_shunts)*(2*vb[i,t] - u[i,t]))
            @constraint(model, sum(q[a,t] for a in ref[:bus_arcs][i]) ==
                sum(qg[g,t] for g in ref[:bus_gens][i]) -
                sum(ql[l,t] for l in ref[:bus_loads][i]) +
                sum(shunt["bs"] for shunt in bus_shunts)*(2*vb[i,t] - u[i,t]))
        end
    end
    return model
end


@doc raw"""
branch (power flow) constraints
- linearized power flow
```math
\begin{align*}
p_{bij,t}=G_{ii}(2vl_{ij,t}-x_{ij,t}) + G_{ij}(vl_{ij,t} + vl_{ji,t}-x_{ij,t}) + B_{ij}(al_{ij,t}-al_{ij,t})\\
q_{bij,t}=-B_{ii}(2vl_{ij,t}-x_{ij,t}) - B_{ij}(vl_{ij,t} + vl_{ji,t}-x_{ij,t}) + G_{ij}(al_{ij,t}-al_{ij,t})\\
\end{align*}
```
"""
function form_branch(ref, model, stages, vl, al, x, u, p, q)

    for (i, branch) in ref[:branch]

        println("formulating branch constraint for branch ", i)

        for t in stages
            # create indices for variables
            f_idx = (i, branch["f_bus"], branch["t_bus"])
            t_idx = (i, branch["t_bus"], branch["f_bus"])
            bpf_idx = (branch["f_bus"], branch["t_bus"])
            bpt_idx = (branch["t_bus"], branch["f_bus"])
            # get indexed power flow
            p_fr = p[f_idx,t]
            q_fr = q[f_idx,t]
            p_to = p[t_idx,t]
            q_to = q[t_idx,t]
            # get indexed voltage
            v_fr = vl[bpf_idx,t]
            v_to = vl[bpt_idx,t]
            c_br = vl[bpf_idx,t] + vl[bpt_idx,t] - x[bpf_idx,t]
            s_br = al[bpt_idx,t] - al[bpf_idx,t]
            u_fr = u[branch["f_bus"],t]
            u_to = u[branch["t_bus"],t]

            # get line parameters
            ybus = pinv(branch["br_r"] + im * branch["br_x"])
            g, b = real(ybus), imag(ybus)
            g_fr = branch["g_fr"]
            b_fr = branch["b_fr"]
            g_to = branch["g_to"]
            b_to = branch["b_to"]
            # tap changer related computation
            tap_ratio = branch["tap"]
            angle_shift = branch["shift"]
            tr, ti = tap_ratio * cos(angle_shift), tap_ratio * sin(angle_shift)
            tm = tap_ratio^2

            ###### TEST ######
            # tr = 1; ti = 0; tm = 1
            # g_fr = 0
            # b_fr = 0
            # g_to = 0
            # b_to = 0

            # AC Line Flow Constraints
            @constraint(model, p_fr ==  (g+g_fr)/tm*(2*v_fr-x[bpf_idx,t]) + (-g*tr+b*ti)/tm*c_br + (-b*tr-g*ti)/tm*s_br)
            @constraint(model, q_fr == -(b+b_fr)/tm*(2*v_fr-x[bpf_idx,t]) - (-b*tr-g*ti)/tm*c_br + (-g*tr+b*ti)/tm*s_br)

            @constraint(model, p_to ==  (g+g_to)*(2*v_to-x[bpf_idx,t]) + (-g*tr-b*ti)/tm*c_br + (-b*tr+g*ti)/tm*(-s_br) )
            @constraint(model, q_to == -(b+b_to)*(2*v_to-x[bpf_idx,t]) - (-b*tr+g*ti)/tm*c_br + (-g*tr-b*ti)/tm*(-s_br) )
        end
    end
    return model
end


@doc raw"""
load pickup constraint
- restored load cannot exceed its maximum values
```math
\begin{align*}
& 0 \leq pl_{l,t} \leq pl^{\max}u_{l,t}\\
& 0 \leq ql_{l,t} \leq ql^{\max}u_{l,t}\\
\end{align*}
```
- restored load cannot be shed
```math
\begin{align*}
& pl_{l,t-1} \leq pl_{l,t}\\
& ql_{l,t-1} \leq ql_{l,t}\\
\end{align*}
```
"""
function form_load_logic(ref, model, stages, pl, ql, u)

    println("formulating load logic constraints")

    for t in stages
        for l in keys(ref[:load])

            # active power load
            if ref[:load][l]["pd"] >= 0  # The current bus has positive active power load
                @constraint(model, pl[l,t] >= 0)
                @constraint(model, pl[l,t] <= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, pl[l,t] >= pl[l,t-1]) # no load shedding
                end
            else
                @constraint(model, pl[l,t] <= 0) # The current bus has no positive active power load ?
                @constraint(model, pl[l,t] >= ref[:load][l]["pd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, pl[l,t] <= pl[l,t-1])
                end
            end

            # fix power factors
            if abs(ref[:load][l]["pd"]) >= exp(-8)
                @constraint(model, ql[l,t] == pl[l,t] * ref[:load][l]["qd"] / ref[:load][l]["pd"])
                continue
            end

            # reactive power load
            if ref[:load][l]["qd"] >= 0
                @constraint(model, ql[l,t] >= 0)
                @constraint(model, ql[l,t] <= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, ql[l,t] >= ql[l,t-1])
                end
            else
                @constraint(model, ql[l,t] <= 0)
                @constraint(model, ql[l,t] >= ref[:load][l]["qd"] * u[ref[:load][l]["load_bus"],t])
                if t > 1
                    @constraint(model, ql[l,t] <= ql[l,t-1])
                end
            end
        end
    end
    return model
end



@doc raw"""
generator status and output constraint
- generator ramping rate constraint
```math
\begin{align*}
-Krp_{g} \leq pg_{g,t}-pg_{g,t+1} \leq Krp_{g}
\end{align*}
```
- black-start unit is determined by the cranking power
```math
\begin{align*}
y_{g,t}=1 \text{  if  } Pcr_{g}=0
\end{align*}
```
- on-line generators cannot be shut down
```math
\begin{align*}
y_{g,t} <= y_{g,t+1}
\end{align*}
```
"""
function form_gen_logic(ref, model, stages, nstage, pg, y, Krp, Pcr)
    for g in keys(ref[:gen])
        # generator ramping rate constraint
        for t in 1:nstage-1
            @constraint(model, pg[g,t] - pg[g,t+1] >= -Krp[g])
            @constraint(model, pg[g,t] - pg[g,t+1] <= Krp[g])
        end
        # black-start unit is determined by the cranking power
        if Pcr[g] == 0
            for t in stages
                @constraint(model, y[g,t] == 1)
            end
        else
            for t in 1:nstage-1
                # on-line generators cannot be shut down
                @constraint(model, y[g,t] <= y[g,t+1])
            end
        end
    end
    return model
end

@doc raw"""
generator cranking constraint
- Once a non-black start generator is on, that is, $y_{g,t}=1$, then it needs to absorb the cranking power for its corresponding cranking time
- "After" the time step that this unit satisfies its cranking constraint, its power goes to zero; and from the next time step, it becomes a dispatchable generator
    - set non-black start unit generation limits based on "generator cranking constraint"
    - cranking constraint states if generator g has absorb the cranking power for its corresponding cranking time, it can produce power
- Mathematically if there exist enough 1 for $y_{g,t}=1$, then enable this generator's generating capability
- There will be the following scenarios
    - (1) generator is off, then $y_{g,t}-y_{g,t-Tcr_{g}} = 0$, then $pg_{g,t} = 0$
    - (2) generator is on but cranking time not satisfied, then $y_{g,t} - y_{g,t-Tcr_g} = 1$, then $pg_{g,t} = -Pcr_g$
    - (3) generator is on and just satisfies the cranking time, then $y_{g,t} - y_{g,t-Tcr_g} = 0$, $y_{g,t-Tcr_g-1}=0$, then $pg_{g,t} = 0$
    - (4) generator is on and bigger than satisfies the cranking time, then $y_{g,t} - y_{g,t-Tcr_g} = 0$, $y_{g,t-Tcr_g-1}=1$, then $0 <= pg_{g,t} <= pg^{\max}_{g}$
- All scenarios can be formulated as follows:
```math
\begin{align*}
& pg^{\min}_{g} \leq pg_{g,t} \leq pg^{\max}_{g}\\
& \text{ if }t > Tcr_{g}+1\\
& \quad\quad -Pcr_{g}(y_{g,t}-y_{g,Tcr_{g}}) \leq pg_{g,t} \leq pg^{\max}_{g}y_{g,t-Tcr_{g}-1}-Pcr_{g}(y_{g,t} - y_{g,t-Tcr_{g}}) \\
& \text{ elseif }t \leq Tcr_{g}\\
& \quad\quad pg_{g,t} = -Pcr_{g}y_{g,t}\\
& \text{else }\\
& \quad\quad pg_{g,t} = -Pcr_{g}(y_{g,t} - y_{g,1})
\end{align*}
```
"""
function form_bs_logic(ref, model, stages, pg, qg, y, Pcr, Tcr)

    println("formulating black-start constraints")

    for t in stages
        for g in keys(ref[:gen])
            if t > Tcr[g] + 1
                # scenario 1
                @constraint(model, pg[g,t] >= -Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
                @constraint(model, pg[g,t] <= ref[:gen][g]["pmax"] * y[g,t-Tcr[g]-1] - Pcr[g] * (y[g,t] - y[g,t-Tcr[g]]))
            elseif t <= Tcr[g]
                # determine the non-black start generator power by its cranking condition
                # with the time less than the cranking time, the generator power could only be zero or absorbing cranking power
                @constraint(model, pg[g,t] == -Pcr[g] * y[g,t])
            else
                # if the unit is on from the first time instant, it satisfies the cranking constraint and its power becomes zero
                # if not, it still absorbs the cranking power
                @constraint(model, pg[g,t] == -Pcr[g] * (y[g,t] - y[g,1]))
            end
            @constraint(model, qg[g,t] >= ref[:gen][g]["qmin"]*y[g,t])
            # @constraint(model, qg[g,t] >= -10*y[g,t])
            @constraint(model, qg[g,t] <= ref[:gen][g]["qmax"]*y[g,t])
        end
    end
    return model
end
