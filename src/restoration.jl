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
function solve_restoration_full(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
    #----------------- Data processing -------------------
    # load network data
    ref = load_network(dir_case_network, network_data_format)
    # Count numbers and generate iterators
    ngen = length(keys(ref[:gen]));
    nload = length(keys(ref[:load]));
    # Set time and resolution specifications
    # The final time selection should be complied with restoration time requirement.
    time_final = t_final;
    time_series = 1:t_final;
    # Choicing different time steps is the key for testing multiple resolutions
    time_step = t_step;
    # calculate stages
    nstage = time_final/time_step;
    stages = 1:nstage;
    # Load generation data
    Pcr, Tcr, Krp = load_gen(dir_case_blackstart, ref, time_step)


    #----------------- Load solver ---------------
    # JuMP 0.18
    # model = Model(solver=CplexSolver(CPX_PARAM_EPGAP = 0.05))
    # model = Model(solver=CplexSolver())
    # JuMP 0.19
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)

    # ------------Define decision variable ---------------------
    # define generator variables
    model = def_var_gen(model, ref, stages)
    # define load variable
    model = def_var_load(model, ref, stages)
    # define flow variable
    model = def_var_flow(model, ref, stages)

    # ------------Define constraints ---------------------
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



    #------------------- Define objectives--------------------
#     @objective(model, Min, sum(sum( - model[:y][g,t]*ref[:gen][g]["pg"] for g in keys(ref[:gen])) for t in stages)
#                                 + sum(sum( - model[:u][ref[:load][d]["load_bus"], t]*ref[:load][d]["pd"] for d in keys(ref[:load])) for t in stages) )
#     @objective(model, Min, sum(sum( - model[:pg][g,t] for g in keys(ref[:gen])) for t in stages)
#                                 + sum(sum( - model[:pl][d, t] for d in keys(ref[:load])) for t in stages) )
    @objective(model, Min, sum(sum( - model[:pl][d, t] for d in keys(ref[:load])) for t in stages) )
    
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
    for t in stages
        print("stage ", t, ": ")
        for b in keys(ref[:bus])
            if (abs(value(model[:u][b,t]) - 1) < 1e-6 && t == 1) || (t > 1 && abs(value(model[:u][b,t-1]) + value(model[:u][b,t]) - 1) < 1e-6)
                print(b, " ")
            end
        end
        println("")
    end

    # #-----------Build a dictionary to store the changing point---------------
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
    for (i, gen) in ref[:gen]
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
    for (i, bus) in ref[:bus]
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
                        print(resultfile, round(value(model[:pg][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pg][i,t])*100))
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
                        print(resultfile, round(value(model[:qg][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:qg][i,t])*100))
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
                        print(resultfile, round(value(model[:pl][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:pl][i,t])*100))
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
                        print(resultfile, round(value(model[:ql][i,t])*100))
                        print(resultfile, ",")
                    else
                        print(resultfile, round(value(model[:ql][i,t])*100))
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
                        stage_index = ceil(t/time_step)
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
                        stage_index = ceil(t/time_step)
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
                        stage_index = ceil(t/time_step)
                        print(resultfile, round(value(model[:pg][i,stage_index])*100))
                        print(resultfile, ", ")
                    else
                        # Determine which stages should the current time instant be
                        stage_index = ceil(t/time_step)
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
                        stage_index = ceil(t/time_step)
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
                        stage_index = ceil(t/time_step)
                        print(resultfile, Int(round(value(model[:u][i,stage_index]))))
                    end
                end
            println(resultfile, " ")
    end
    close(resultfile)

    return ref, model
end



@doc raw"""
Solve partial restoration problem (The restoration problem could be partial or full restorations)
- Partial restoration problem assumes that a part of the network is still functioning.
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
function solve_restoration_part(dir_case_network, network_data_format, dir_case_blackstart, dir_case_result, t_final, t_step, gap)
    println("under construction")
end
