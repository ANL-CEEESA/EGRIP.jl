
function solve_load_pickup(dir_case_network, network_data_format, dir_repair, dir_case_result, t_final, t_step, gap; solver="gurobi", load_priority=nothing)
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

    # read component repair time
    component_status = Dict()
    component_status = JSON.parsefile(dir_repair)

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

    # --------- load damage data --------------
    println("Loading component repairing information")
    for gen_key in keys(component_status["gen"])
        for t in 1:component_status["gen"][gen_key]["repair_time_days"]
            @constraint(model, model[:y][parse(Int, gen_key), t] == 0)
        end
    end

    for bus_key in keys(component_status["bus"])
        for t in 1:component_status["bus"][bus_key]["repair_time_days"]
            @constraint(model, model[:u][parse(Int, bus_key), t] == 0)
        end
    end

    for branch_key in keys(component_status["branch"])
        from_bus = component_status["branch"][branch_key]["source_id"][2]
        to_bus = component_status["branch"][branch_key]["source_id"][3]
        for t in 1:component_status["branch"][branch_key]["repair_time_days"]
            @constraint(model, model[:x][(from_bus, to_bus), t] == 0)
        end
    end

    # --------------- generator constraints ----------------
    println("Formulating generator dispatch constraints")
    for t in stages
        for g in keys(ref[:gen])
            @constraint(model, model[:pg][g,t] >= ref[:gen][g]["pmin"] * model[:y][g,t])
            @constraint(model, model[:pg][g,t] <= ref[:gen][g]["pmax"] * model[:y][g,t])
            @constraint(model, model[:qg][g,t] >= ref[:gen][g]["qmin"] * model[:y][g,t])
            @constraint(model, model[:qg][g,t] <= ref[:gen][g]["qmax"] * model[:y][g,t])
        end
    end

    # -------------- network constraints --------------------
    model = form_nodal(model, ref, stages)
    model = form_branch(model, ref, stages)

    # ------------ load constraints---------
    model = form_load_logic(model, ref, stages)

    # -------- objective----------
    if load_priority == nothing
        @objective(model, Max, sum(sum(model[:pl][d, t] for d in keys(ref[:load])) for t in stages))
    else
        @objective(model, Max, sum(sum(model[:pl][d, t] * load_priority[string(d)] for d in keys(ref[:load])) for t in stages))
    end

    # -------- solve problem ---------
    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))

    # ---- write the results -----
    # sort dict
    ordered_load = sort!(OrderedDict(ref[:load])) # order the dict based on the key
    ordered_gen = sort!(OrderedDict(ref[:gen])) # order the dict based on the key
    ordered_bus = sort!(OrderedDict(ref[:bus])) # order the dict based on the key
    ordered_branch = sort!(OrderedDict(ref[:branch])) # order the dict based on the key
    ordered_arcs = sort!(ref[:arcs])

    resultfile = open(string(dir_case_result, "load_value.csv"), "w")
    print(resultfile, "Load Index, Load Bus,")
    for t in stages
        if t < stages[end]
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, entry) in ordered_load
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, entry["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t < stages[end]
                        print(resultfile, value(model[:pl][i, t]))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        print(resultfile, value(model[:pl][i, t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    resultfile = open(string(dir_case_result, "load_ratio.csv"), "w")
    print(resultfile, "Load Index, Load Bus,")
    for t in stages
        if t < stages[end]
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, entry) in ordered_load
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, entry["load_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t < stages[end]
                        print(resultfile, value(model[:pl][i, t])/entry["pd"])
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        print(resultfile, value(model[:pl][i, t])/entry["pd"])
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    resultfile = open(string(dir_case_result, "gen_status.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t < stages[end]
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, entry) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, entry["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t < stages[end]
                        print(resultfile, value(model[:y][i, t]))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        print(resultfile, value(model[:y][i, t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    resultfile = open(string(dir_case_result, "gen_value.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t < stages[end]
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, entry) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, entry["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t < stages[end]
                        print(resultfile, value(model[:pg][i, t]))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        print(resultfile, value(model[:pg][i, t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    resultfile = open(string(dir_case_result, "gen_ratio.csv"), "w")
    print(resultfile, "Gen Index, Gen Bus,")
    for t in stages
        if t < stages[end]
            print(resultfile, t)
            print(resultfile, ", ")
        else
            println(resultfile, t)
        end
    end
    for (i, entry) in ordered_gen
                print(resultfile, i)
                print(resultfile, ", ")
                print(resultfile, entry["gen_bus"])
                print(resultfile, ", ")
                for t in stages
                    if t < stages[end]
                        print(resultfile, value(model[:pg][i, t])/entry["pmax"])
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        print(resultfile, value(model[:pg][i, t])/entry["pmax"])
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    # Write active power flow
    resultfile = open(string(dir_case_result, "line_p.csv"), "w")
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
                        print(resultfile, value(model[:p][i,t]))
                        print(resultfile, ",")
                    else
                        print(resultfile, value(model[:p][i,t]))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)


    return ref, model
end
