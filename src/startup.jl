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
Solve generator start-up problem
- Inputs: A set of restoration data in csv format and original system data
    - network data directory where data format could be json, matpower and psse
    - restoration data directory
        - restoration_gen: specify initial generator status, cranking specifications and black-start generators
        - restoration_bus: specify initial bus status and its load priority, from where the problem type (partial or full restorations) can be determined
        - restoration_line: specify initial line status, from where the problem type (partial or full restorations) can be determined
    - result storage directory
    - gap
    - formulation types
    - specifications of wind power
        - wind activation 0 denotes no wind will support the restoration
        - wind activation 1 denotes wind will support the restoration with its distribution as normal
        - wind activation 2 denotes wind will support the restoration with time seires wind data
        - wind activation 3 denotes wind will support the restoration with real quantile and interpolation (linear, cubic, or spline)
    - if wind activation = 3, then real wind power density will be specified in wind_data
    - The followings are the keyword arguments
        - wind_data: time series wind data
        - saa_mode: different chance constraints enforcement in sample average approximations
- Output: Generator start-up sequence
- Constraints:
    - generato cranking
    - load pickup
    - power balance
"""
function solve_startup(dir_case_network,
    network_data_format,
    dir_case_blackstart,
    dir_case_result,
    t_final,
    t_step,
    gap,
    form,
    wind,
    wind_data=nothing;
    saa_mode=1)
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
    # # CPLEX
    # model = Model(CPLEX.Optimizer)
    # set_optimizer_attribute(model, "CPX_PARAM_EPGAP", gap)
    # # Gurobi
    model = Model(Gurobi.Optimizer)

    # ------------Define decision variable ---------------------
    # define generator variables
    model = def_var_gen(model, ref, stages; form=form)

    # define load variables
    model = def_var_load(model, ref, stages; form=form)

    # if wind power option is activated, define the variable
    # #TODO: load wind data from csv or raw
    if wind["activation"] != 0
        model = def_var_wind(model, ref, stages)
    end

    # ------------Define constraints ---------------------
    if form == 1
        # generator cranking constraint
        model, Trp = form_gen_cranking_1(model, ref, stages, Pcr, Tcr, Krp)
        # load pickup logic
        model = form_load_logic_1(model, ref, stages)
    elseif form == 2
        # generator cranking constraint
        model, Trp = form_gen_cranking_2(model, ref, stages, Pcr, Tcr, Krp)
        # load pickup logic
        model = form_load_logic_2(model, ref, stages)
    elseif form == 3
        # generator cranking constraint
        model, Trp = form_gen_cranking_3(model, ref, stages, Pcr, Tcr, Krp)
        # load pickup logic
        model = form_load_logic_3(model, ref, stages)
    elseif form == 4
        println("Formulation 4 is under construction.")
    end

    # wind power dispatch chance constraint
    if wind["activation"] == 1
        model, pw_sp = form_wind_saa_1(model, ref, stages, wind)
    elseif wind["activation"] == 2
        model, pw_sp = form_wind_saa_2(model, ref, stages, wind_data, wind["violation_probability"])
    elseif wind["activation"] == 3
        model, pw_sp = form_wind_saa_3(model, ref, stages, wind, wind_data; mode=saa_mode)
    else
        pw_sp = 0
    end

    # generator capacity is greater than load for all time
    if wind["activation"] != 0
        println("Generation start-up with wind power")
        for t in stages
            @constraint(model, model[:pw][t] + model[:pg_total][t] >= model[:pd_total][t])
        end
    else
        println("Generation start-up without wind power")
        for t in stages
            @constraint(model, model[:pg_total][t] >= model[:pd_total][t])
        end
    end

    #-----------------Define objectives--------------------
    println("Formulating objective")
    if form == 1
        @objective(model, Min, sum(sum(t * model[:ys][g,t] for t in stages) for g in keys(ref[:gen])) +
                            sum(sum(t * model[:zs][d,t] for t in stages) for d in keys(ref[:load])))
    elseif form == 2
        @objective(model, Min, sum(sum(t * model[:yg][g,t] for t in stages) for g in keys(ref[:gen])) +
                            sum(sum(t * model[:zd][d,t] for t in stages) for d in keys(ref[:load])))
                            #  - sum(model[:pw][t] for t in stages)
    elseif form == 3
        # # option 1: min startup instant + max active power
        # # option 1 should be used with larger M (step: 1000, power: 1000)
        # # option 1 Gurobi 0.7s, CPLEX 4s
        # @objective(model, Min, sum(model[:yg][g] for g in keys(ref[:gen])) +
        #     sum(model[:zd][d] for d in keys(ref[:load])) -
        #     sum(sum(model[:pg][g,t] for g in keys(ref[:gen])) for t in stages) -
        #     sum(sum(model[:pl][d,t] for d in keys(ref[:load])) for t in stages))
        # option 2: min startup instant
        # # option 2 should be used with smaller M (step: 30-50, power: 100)
        # # option 2 Gurobi 35s, CPLEX ~~s
        # # option 2 should be used with tighter M (step: 30-50, power: pmax + 5)
        # # option 2 Gurobi 13s (optimal found in 1s), CPLEX 2578s (optimal found in 4s)
        # # The experience is the solver can quickly found the optimal solution within 2-4s,
        # # but took long time to find the optimal certificates.
        @objective(model, Min, sum(model[:yg][g] for g in keys(ref[:gen])) +
            sum(model[:zd][d] for d in keys(ref[:load])))
    end

    #------------- Build and solve model----------------
    # buildInternalModel(model)
    # m = model.internalModel.inner
    # CPLEX.set_logfile(m.env, string(dir, "log.txt"))

    # optimize the model
    optimize!(model)
    status = termination_status(model)
    println("")
    println("Termination status: ", status)
    println("The objective value is: ", objective_value(model))


    # #------------- Record results ----------------
    # results in stages
    println("")
    println("Generation total capacity: ")
    for t in stages
        println("stage ", t, ": ", value(model[:pg_total][t]) * ref[:baseMVA])
    end

    println("Load total capacity: ")
    for t in stages
        println("stage ", t, ": ", value(model[:pd_total][t])* ref[:baseMVA])
    end

    # if form == 1
    #     # #----------- Write generation data ----------------------
    #     CP = Dict();
    #     ## Build a dictionary to store the changing point
    #     CP[:ys] = Dict();
    #     resultfile = open(string(dir_case_result, "res_ys.csv"), "w")
    #     print(resultfile, "Gen Index, Gen Bus,")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, gen) in ref[:gen]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, gen["gen_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if abs(value(model[:ys][i,t]) - 1) < 0.1
    #                         CP[:ys][i] = t
    #                         println("CP: ", t)
    #                     end
    #                     if t< nstage
    #                         print(resultfile, round(value(model[:ys][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, value(model[:ys][i,t]))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #     resultfile = open(string(dir_case_result, "res_yc.csv"), "w")
    #     print(resultfile, "Gen Index, Gen Bus,")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, gen) in ref[:gen]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, gen["gen_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if t<nstage
    #                         print(resultfile, round(value(model[:yc][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, value(model[:yc][i,t]))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #     resultfile = open(string(dir_case_result, "res_yr.csv"), "w")
    #     print(resultfile, "Gen Index, Gen Bus,")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, gen) in ref[:gen]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, gen["gen_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if t<nstage
    #                         print(resultfile, round(value(model[:yr][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, value(model[:yr][i,t]))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #     resultfile = open(string(dir_case_result, "res_yd.csv"), "w")
    #     print(resultfile, "Gen Index, Gen Bus,")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, gen) in ref[:gen]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, gen["gen_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if t<nstage
    #                         print(resultfile, round(value(model[:yd][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, value(model[:yd][i,t]))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #
    #      # #----------- Write load data ----------------------
    #     resultfile = open(string(dir_case_result, "res_zs.csv"), "w")
    #     print(resultfile, "Load Index, Bus Index, ")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, load) in ref[:load]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, load["load_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if t<nstage
    #                         print(resultfile, round(value(model[:zs][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, round(value(model[:zs][i,t])))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #     resultfile = open(string(dir_case_result, "res_z.csv"), "w")
    #     print(resultfile, "Load Index, Bus Index, ")
    #     for t in stages
    #         if t<nstage
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, load) in ref[:load]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, load["load_bus"])
    #                 print(resultfile, ", ")
    #                 for t in stages
    #                     if t<nstage
    #                         print(resultfile, round(value(model[:z][i,t])))
    #                         print(resultfile, ",")
    #                     else
    #                         print(resultfile, round(value(model[:z][i,t])))
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    #     # #---------------- Interpolate current plan to time series (one-minute based) data --------------------
    #     # Interpolate generator energization solution to time series (one-minute based) data
    #     resultfile = open(string(dir_case_result, "Interpol_ys.csv"), "w")
    #     print(resultfile, "Gen Index, Gen Bus,")
    #     for t in time_series
    #         if t<time_final
    #             print(resultfile, t)
    #             print(resultfile, ", ")
    #         else
    #             println(resultfile, t)
    #         end
    #     end
    #     for (i, gen) in ref[:gen]
    #                 print(resultfile, i)
    #                 print(resultfile, ", ")
    #                 print(resultfile, gen["gen_bus"])
    #                 print(resultfile, ", ")
    #                 for t in time_series
    #                     if t<time_final
    #                        # Determine which stages should the current time instant be
    #                         stage_index = ceil(t/time_step)
    #                         # Determine if the current generator has a changing scenario
    #                         if i in keys(CP[:ys])
    #                             # check if the current stage is the changing stage
    #                             # mark changing stage different from 0 or 1 (do not use string as it causes problems after reading from CSV)
    #                             if CP[:ys][i] == stage_index
    #                                 print(resultfile, Int(2))
    #                                 print(resultfile, ", ")
    #                             end
    #                             if CP[:ys][i] < stage_index
    #                                 print(resultfile, 1)
    #                                 print(resultfile, ", ")
    #                             end
    #                             if CP[:ys][i] > stage_index
    #                                 print(resultfile, 0)
    #                                 print(resultfile, ", ")
    #                             end
    #                         else
    #                             print(resultfile, Int(round(value(model[:ys][i,stage_index]))))
    #                             print(resultfile, ", ")
    #                         end
    #                     else
    #                         print(resultfile, 1)
    #                     end
    #                 end
    #             println(resultfile, " ")
    #     end
    #     close(resultfile)
    #
    # end

    return ref, model, pw_sp, Pcr, Tcr, Krp, Trp
end
