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
Solve restoration problem
- Problem type: The restoration problem could be partial or full restorations
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

    #----------------- Load system data ----------------
    # check network data format and load accordingly
    # we are currently relying on PowerModels's IO functions
    if network_data_format == "json"
        println("print dir_case_network")
        println(dir_case_network)
        ref = Dict()
        ref = JSON.parsefile(dir_case_network)  # parse and transform data
        println("reconstruct data loaded from json")
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
        ref[:arcs] = [Tuple(val) for (key, val) in pairs(ref[:arcs])]
        ref[:bus_arcs] = Dict([key=>[Tuple(arc) for arc in val] for (key,val) in pairs(ref[:bus_arcs])])
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

    println("number of arcs")
    println(length(ref[:arcs]))

    println("arcs")
    println(ref[:arcs])

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

    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
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
