
@doc raw"""
Solve full restoration problem (The restoration problem could be partial or full restorations)
- Full restoration problem assumes that the entire network is broken down.
- Inputs: A set of restoration data in csv format and original system data
    - network data directory where data format could be json, matpower and psse
    - restoration data directory
        - restoration_gen: specify initial generator status, cranking specifications and black-start generators
        - restoration_bus: specify initial bus status and its load priority, from where the problem type (partial or full restorations) can be determined
        - restoration_line: specify initial line status, from where the problem type (partial or full restorations) can be determined
    - result storage directory
    - gap
- Output: Restoration plans
- Constraints:
    - linearized AC power flow constraint
    - steady-state voltage variation constraint
    - generator cranking constraint
    - generator status and output constraint
    - load pick-up constraint
"""
function solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap; solver="HiGHS", line_damage=nothing)
    #----------------- Data processing -------------------
    # load network data
    ref = load_network(dir_case_network, network_data_format)
    # Count numbers and generate iterators
    ngen = length(keys(ref[:gen]));
    nload = length(keys(ref[:load]));
    # Set time and resolution specifications
    # The final time selection should be complied with restoration time requirement.
    time_final = convert(Int, t_final);
    time_series = 1:t_final;
    # Choicing different time steps is the key for testing multiple resolutions
    time_step = convert(Int, t_step);
    # calculate stages
    nstage = convert(Int, time_final/time_step);
    stages = 1:nstage; # In Julia, key 1 and 1.0 has a difference
    # Load generation data
    Pcr, Tcr, Krp = load_gen(dir_case_blackstart, ref, time_step)

    #----------------- Load solver ---------------
    # ---JuMP 0.18 ---
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # ---JuMP 0.19 ---
    if solver == "cplex"
        model = Model(CPLEX.Optimizer)
        set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)
    elseif solver == "gurobi"
        model = Model(Gurobi.Optimizer)
        set_optimizer_attribute(model, "MIPGap", gap)
    elseif solver == "HiGHS"
        model = Model(HiGHS.Optimizer)
        set_optimizer_attribute(model, "presolve", "on")
        set_optimizer_attribute(model, "time_limit", 60.0)
        set_optimizer_attribute(model, "mip_rel_gap", gap)
    else
        println("Solver not avaliable")
    end

    # ------------Define decision variable ---------------------
    println("Defining restoration variables")
    # define generator variables
    model = def_var_gen(model, ref, stages; form=4)
    # define load variable
    model = def_var_load(model, ref, stages; form=4)
    # define flow variable
    model = def_var_flow(model, ref, stages)
    println("Complete defining restoration variables")

    # ------------Define constraints ---------------------
    println("Defining restoration constraints")
    # nodal constraint
    model = form_nodal(model, ref, stages)

    # branch (power flow) constraints
    model = form_branch(model, ref, stages)

    # generator control constraint
    model = form_gen_logic(model, ref, stages, nstage, Krp, Pcr)

    # generator cranking constraint
    model = form_gen_cranking(model, ref, stages, Pcr, Tcr)

    # load control constraint
    model = form_load_logic(model, ref, stages)

    # initial status of gen bus
    model = initial_gen_bus(model, ref, stages)

    # bus energization heuristic
    model = bus_energization_rule(model, ref, stages)

    # enforce the damaged branches to be off during the whole restoration process
    if line_damage == nothing
        println("No line damage data")
    else
        model = enforce_damage_branch(model, ref, stages, line_damage)
    end
    println("Complete defining restoration constraints")

    #------------------- Define objectives--------------------
    ## (1) maximize the generator status
    # @objective(model, Max, sum(sum(model[:y][g,t]*ref[:gen][g]["pg"] for g in keys(ref[:gen])) for t in stages))

    ## (2) maximize the total load
    # @objective(model, Max, sum(sum(model[:pl][d, t] for d in keys(ref[:load])) for t in stages))

    ## (3) maximize the total generator output
    # @objective(model, Max, sum(sum(model[:pg][g, t] for g in keys(ref[:gen])) for t in stages))

    ## (4) maximize both total load and generator output
    # @objective(model, Max, sum(sum(model[:pl][d, t] for d in keys(ref[:load])) for t in stages) + sum(sum(model[:pg][g, t] for g in keys(ref[:gen])) for t in stages))

     ## (5) maximize both total load and generator status
    @objective(model, Max, sum(sum(model[:pl][d, t] for d in keys(ref[:load])) for t in stages) +
                           sum(sum(model[:y][g,t]*ref[:gen][g]["pg"] for g in keys(ref[:gen])) for t in stages))

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))

    #
    # #------------- Record results ----------------
    # # results in stages
    println("")
    adj_matrix = Dict()
    for (i,j) in keys(ref[:buspairs])
        adj_matrix[(i,j)] = 0
    end
    println("Line energization: ")
    for t in stages
        print("stage ", t, ": ")
        for (i,j) in keys(ref[:buspairs])
             if (abs(value(model[:x][(i,j),t]) - 1) < 1e-6) && (adj_matrix[(i,j)] == 0)
                print("(", i, ",", j, ") ")
                adj_matrix[(i,j)] = 1
             end
        end
        println("")
    end

    println("")
    println("Generator energization: ")
    for t in stages
        print("stage ", t, ": ")
        for g in keys(ref[:gen])
            if (abs(value(model[:y][g,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:y][g,t-1]) + value(model[:y][g,t]) - 1) < 1e-6)
                print(ref[:gen][g]["gen_bus"], " ")
            end
        end
        println("")
    end

    println("")
    println("Bus energization: ")
    bus_energization = OrderedDict()
    for t in stages
        bus_energization[t] = []
        print("stage ", t, ": ")
        for b in keys(ref[:bus])
            if (abs(value(model[:u][b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:u][b,t-1]) + value(model[:u][b,t]) - 1) < 1e-6)
                print(b, " ")
                push!(bus_energization[t], b)
            end
        end
        println("")
    end

    # #-----------Build a dictionary to store the changing point---------------
    CP = Dict();

    # sort dict
    ordered_load = sort!(OrderedDict(ref[:load])) # order the dict based on the key
    ordered_gen = sort!(OrderedDict(ref[:gen])) # order the dict based on the key
    ordered_bus = sort!(OrderedDict(ref[:bus])) # order the dict based on the key
    ordered_branch = sort!(OrderedDict(ref[:branch])) # order the dict based on the key
    ordered_arcs = sort!(ref[:arcs])

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
    for (i, branch) in ordered_branch
            # if branch["b_fr"] == 0
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, branch["f_bus"])
                print(resultfile, ", ")
                print(resultfile, branch["t_bus"])
                print(resultfile, ",")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:x][(branch["f_bus"], branch["t_bus"]),t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:x][(branch["f_bus"], branch["t_bus"]),t])==0) & (value(model[:x][(branch["f_bus"], branch["t_bus"]),t+1])==1)
                            CP[:x][i] = t
                        end
                    else
                        print(resultfile, round(value(model[:x][(branch["f_bus"], branch["t_bus"]),t])))
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
    for (i, gen) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:y][i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:y][i,t])==0) & (value(model[:y][i,t+1])==1)
                            CP[:y][i] = t
                        end
                    else
                        print(resultfile, value(model[:y][i,t]))
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
    for (i, bus) in ordered_bus
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:u][i,t])))
                        print(resultfile, ",")
                        # detection of changing point
                        if (value(model[:u][i,t])==0) & (value(model[:u][i,t+1])==1)
                            CP[:u][i] = t
                        end
                    else
                        print(resultfile, round(value(model[:u][i,t])))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Write generator active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus, Upper Bound,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                print(resultfile, gen["pmax"]*ref[:baseMVA])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:pg][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pg][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write generator rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_qg.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus, Upper Bound,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, gen) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, gen["gen_bus"])
                print(resultfile, ", ")
                print(resultfile, gen["qmax"]*ref[:baseMVA])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:qg][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:qg][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load active power dispatch solution
    resultfile = open(string(dir_case_result, "res_pl.csv"), "w")
    print(resultfile, "Load Index, Bus Index, Nominal Value,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ordered_load
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                print(resultfile, load["pd"]*ref[:baseMVA])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:pl][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pl][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write load rective power dispatch solution
    resultfile = open(string(dir_case_result, "res_ql.csv"), "w")
    print(resultfile, "Load Index, Bus Index, Nominal Value,")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, load) in ordered_load
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, load["load_bus"])
                print(resultfile, ", ")
                print(resultfile, load["qd"]*ref[:baseMVA])
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:ql][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:ql][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write bus voltage solution
    resultfile = open(string(dir_case_result, "res_vb.csv"), "w")
    print(resultfile, "Bus Index, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, bus) in ordered_bus
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, value(model[:vb][i,t]))
                        print(resultfile, ",")
                    else
                        print(resultfile, value(model[:vb][i,t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # Write active power flow
    resultfile = open(string(dir_case_result, "res_p.csv"), "w")
    print(resultfile, "Branch Index, From/To, To/From, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for i in ordered_arcs
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:p][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:p][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Write reactive power flow
    resultfile = open(string(dir_case_result, "res_q.csv"), "w")
    print(resultfile, "Branch Index, From/To, To/From, ")
    for t in stages
        if t<nstage
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for i in ordered_arcs
                print(resultfile, i)
                print(resultfile, ", ")
                for t in stages
                    if t<nstage
                        print(resultfile, round(value(model[:q][i,t])*ref[:baseMVA]))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:q][i,t])*ref[:baseMVA]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    # #---------------- Interpolate current plan to time series (one-minute based) data --------------------
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
                        stage_index = convert(Int, ceil(t/time_step))
                        # Determine if the current generator has a changing scenario
                        if i in keys(CP[:y])
                            # check if the current stage is the changing stage
                            # mark changing stage different from 0 or 1 (do not use string as it causes problems after reading from CSV)
                            if CP[:y][i] == stage_index
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else
                                print(resultfile, Int(round(value(model[:y][i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(model[:y][i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = convert(Int, ceil(t/time_step))
                        print(resultfile, Int(round(value(model[:y][i,stage_index]))))
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
                        stage_index = convert(Int, ceil(t/time_step))
                        print(resultfile, round(value(model[:pg][i,stage_index])*100))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        stage_index = convert(Int, ceil(t/time_step))
                        print(resultfile, round(value(model[:pg][i,stage_index])*100))
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
                        stage_index = convert(Int, ceil(t/time_step))
                        if i in keys(CP[:u])
                            # check if the current stage is the changing stage
                            if CP[:u][i] == stage_index  # If yes, mark the time series data as "tbd"
                                print(resultfile, Int(2))
                                print(resultfile, ", ")
                            else                          # If no, use the previously calculated values
                                print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                                print(resultfile, ", ")
                            end
                        else
                            print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                            print(resultfile, ", ")
                        end
                    else
                        # Determine which stages should the current time instant be
                        stage_index = convert(Int, ceil(t/time_step))
                        print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    return ref, model, bus_energization
end



@doc raw"""
Solve partial restoration problem given generator startup plan
- Here the generator startup plan is given from the Parallel Power System Restoration (PPSR) module.
- Inputs:
    - network data directory where data format could be json, matpower and psse
    - restoration plan
    - result directory
    - gap
- Output: Rest part of the restoration plans
- Constraints:
    - linearized AC power flow constraint
    - steady-state voltage variation constraint
    - generator startup and load pickup should be consistent with the given plan
"""
function solve_restoration_part(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
    println("under construction")
end

